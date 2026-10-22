/**
 * Recojo y entrega a domicilio — Guardería y Hospedaje.
 *
 * El cuidador (independiente o empresa) lo activa con un precio fijo por viaje
 * (recojo / entrega, 0 = gratis) y una distancia máxima en línea recta desde su
 * dirección. El dueño elige recojo, entrega, ambos o ninguno al reservar.
 *
 * DINERO: el transporte va 100% al cuidador — sin comisión de GARDEN. Se suma a
 * totalAmount (con su impuesto, si los impuestos están activos) y queda en
 * Booking.transportAmount; caregiverNetOf() (total − comisión − impuesto) ya lo incluye.
 * Si se cancela un viaje después de pagar, se devuelve precio + su impuesto a la
 * billetera del dueño y se descuenta de totalAmount / taxAmount / transportAmount, así
 * todos los cálculos de pago y de reembolso que parten de totalAmount siguen bien.
 *
 * VIAJE (BookingTransportLeg): SCHEDULED → EN_ROUTE → ARRIVED → DONE, o CANCELLED.
 *  - Recojo: "voy en camino" → "llegué a tu casa" → "recogí a X" (= inicia el servicio,
 *    ver booking.service.ts pickUpPet) → "ya llegamos" (cierra el mapa en vivo).
 *  - Entrega: con el servicio en curso, "salí a devolver a X" → "llegué" → al finalizar el
 *    servicio (concludeService) el viaje queda DONE. Con entrega a domicilio no hay cargo
 *    por tiempo extra al dueño: la hora de devolución la maneja el cuidador.
 *
 * La fecha de cada viaje no se guarda: se deriva de la reserva (recojo = día de entrada /
 * de la guardería; entrega = día de salida / de la guardería), así extender o cambiar
 * fechas mueve los viajes solos.
 */
import { Prisma, ServiceType, BookingStatus } from '@prisma/client';
import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';
import { BadRequestError, ForbiddenError, NotFoundError } from '../../shared/errors.js';
import { getCache, delByPrefix } from '../../shared/cache.js';
import { sendPushToUser, notifyAdmins } from '../../services/firebase.service.js';
import { getIO, emitWalletUpdated } from '../../services/socket.service.js';
import {
  LEG_STATUS, ACTIVE_LEG_STATUSES, EN_ROUTE_OPENS_MIN, ARRIVE_OPENS_MIN, PICKUP_TRACKING_MAX_MS, TIME_RE,
  round2, minutesOf, fmtHHmm, legScheduledMs, isLegLive, type ScheduleShape, type LegKind,
} from './transport.view.js';

export * from './transport.view.js';

export const LEG_KINDS: LegKind[] = ['PICKUP', 'DROPOFF'];
export const TRANSPORT_SERVICES: ServiceType[] = [ServiceType.GUARDERIA, ServiceType.HOSPEDAJE];

export const MAX_TRANSPORT_FEE = 500;
export const MIN_TRANSPORT_KM = 1;
export const MAX_TRANSPORT_KM = 30;
/** Rango de horas que se puede elegir en hospedaje. */
const HOSPEDAJE_MIN_TIME = '06:00';
const HOSPEDAJE_MAX_TIME = '21:00';
/** Al reservar, el recojo tiene que quedar al menos este tiempo en el futuro. */
const MIN_LEAD_MIN = 45;
const GPS_MAX_POINTS = 1500;


// ── Utilidades ───────────────────────────────────────────────────────────────

export function haversineKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

const fmtDayHHmm = (ms: number) => {
  const b = new Date(ms - 4 * 60 * 60 * 1000);
  return `${String(b.getUTCDate()).padStart(2, '0')}/${String(b.getUTCMonth() + 1).padStart(2, '0')} a las ${fmtHHmm(ms)}`;
};

function caregiverDisplayName(p: { isCompany?: boolean | null; companyName?: string | null; user?: { firstName?: string | null } | null }): string {
  if (p.isCompany && p.companyName) return p.companyName;
  return p.user?.firstName?.trim() || 'Tu cuidador';
}

async function invalidateCaregiverCaches(profileId: string): Promise<void> {
  try {
    await getCache().del(`caregivers:detail:${profileId}`);
    await delByPrefix('caregivers:list:');
  } catch (err) {
    logger.warn('[TRANSPORT] no se pudo invalidar cache', { profileId, err });
  }
}

async function notify(userId: string, bookingId: string, title: string, message: string, pushType: string): Promise<void> {
  try {
    await prisma.notification.create({ data: { userId, bookingId, title, message, type: 'SYSTEM' } });
  } catch (err) {
    logger.warn('[TRANSPORT] no se pudo crear la notificación', { userId, bookingId, err });
  }
  sendPushToUser(userId, title, message, { type: pushType, bookingId }).catch(() => {});
}

/** Dueño de la empresa + empleado asignado (si hay) — a quién avisarle de un viaje. */
async function caregiverRecipients(booking: { caregiverId: string; assignedStaffMemberId?: string | null }): Promise<string[]> {
  const profile = await prisma.caregiverProfile.findUnique({ where: { id: booking.caregiverId }, select: { userId: true } });
  const ids = new Set<string>();
  if (profile) ids.add(profile.userId);
  if (booking.assignedStaffMemberId) {
    const m = await prisma.caregiverStaffMember.findUnique({ where: { id: booking.assignedStaffMemberId }, select: { userId: true } });
    if (m) ids.add(m.userId);
  }
  return [...ids];
}

// ── Ajustes del cuidador ─────────────────────────────────────────────────────

const SETTINGS_SELECT = {
  id: true, servicesOffered: true, addressLat: true, addressLng: true, address: true,
  transportEnabled: true, transportPickupFee: true, transportDropoffFee: true, transportMaxKm: true,
} as const;

function settingsView(p: {
  servicesOffered: ServiceType[]; addressLat: number | null; addressLng: number | null; address?: string | null;
  transportEnabled: boolean; transportPickupFee: unknown; transportDropoffFee: unknown; transportMaxKm: unknown;
}) {
  const eligibleServices = p.servicesOffered.filter((s) => TRANSPORT_SERVICES.includes(s));
  return {
    enabled: p.transportEnabled,
    pickupFee: Number(p.transportPickupFee),
    dropoffFee: Number(p.transportDropoffFee),
    maxKm: Number(p.transportMaxKm),
    services: eligibleServices,
    eligible: eligibleServices.length > 0,
    hasLocation: p.addressLat != null && p.addressLng != null,
    limits: { maxFee: MAX_TRANSPORT_FEE, minKm: MIN_TRANSPORT_KM, maxKm: MAX_TRANSPORT_KM },
  };
}

async function ownerProfile(userId: string) {
  const p = await prisma.caregiverProfile.findUnique({ where: { userId }, select: SETTINGS_SELECT });
  if (!p) throw new ForbiddenError('Solo el titular del perfil de cuidador o empresa puede configurar esto.');
  return p;
}

/** GET /api/caregiver/transport */
export async function getMyTransport(userId: string) {
  return settingsView(await ownerProfile(userId));
}

function parseFee(v: unknown, label: string): number {
  const n = typeof v === 'string' && v.trim() !== '' ? Number(v) : v;
  if (typeof n !== 'number' || !Number.isFinite(n)) throw new BadRequestError(`Escribe el precio de ${label} (0 si es gratis).`);
  if (n < 0) throw new BadRequestError(`El precio de ${label} no puede ser negativo.`);
  if (!Number.isInteger(n)) throw new BadRequestError(`El precio de ${label} debe ser en bolivianos enteros.`);
  if (n > MAX_TRANSPORT_FEE) throw new BadRequestError(`El precio de ${label} no puede pasar de Bs ${MAX_TRANSPORT_FEE}.`);
  return n;
}

/** PUT /api/caregiver/transport — vale para reservas nuevas; las existentes conservan su precio. */
export async function setMyTransport(userId: string, body: { enabled?: unknown; pickupFee?: unknown; dropoffFee?: unknown; maxKm?: unknown }) {
  const p = await ownerProfile(userId);
  if (typeof body.enabled !== 'boolean') throw new BadRequestError('Indica si ofreces recojo y entrega.');
  const pickupFee = parseFee(body.pickupFee, 'recojo');
  const dropoffFee = parseFee(body.dropoffFee, 'entrega');
  const km = typeof body.maxKm === 'string' ? Number(body.maxKm) : body.maxKm;
  if (typeof km !== 'number' || !Number.isFinite(km) || km < MIN_TRANSPORT_KM || km > MAX_TRANSPORT_KM) {
    throw new BadRequestError(`La distancia máxima debe ser de ${MIN_TRANSPORT_KM} a ${MAX_TRANSPORT_KM} km.`);
  }
  const maxKm = Math.round(km * 10) / 10;
  if (body.enabled) {
    if (!p.servicesOffered.some((s) => TRANSPORT_SERVICES.includes(s))) {
      throw new BadRequestError('El recojo y la entrega son para guardería u hospedaje. Activa uno de esos servicios primero.', 'TRANSPORT_NOT_ELIGIBLE');
    }
    if (p.addressLat == null || p.addressLng == null) {
      throw new BadRequestError('Marca tu dirección en el mapa (Editar perfil) para calcular hasta dónde recoges.', 'TRANSPORT_LOCATION_REQUIRED');
    }
  }
  const updated = await prisma.caregiverProfile.update({
    where: { id: p.id },
    data: {
      transportEnabled: body.enabled,
      transportPickupFee: new Prisma.Decimal(pickupFee),
      transportDropoffFee: new Prisma.Decimal(dropoffFee),
      transportMaxKm: new Prisma.Decimal(maxKm),
    },
    select: SETTINGS_SELECT,
  });
  await invalidateCaregiverCaches(p.id);
  logger.info('[TRANSPORT] ajustes del cuidador', { profileId: p.id, enabled: body.enabled, pickupFee, dropoffFee, maxKm });
  return settingsView(updated);
}

/** Lo que ve el dueño en el perfil/listado (null si no ofrece transporte). */
export function publicTransportOf(p: {
  transportEnabled?: boolean | null; transportPickupFee?: unknown; transportDropoffFee?: unknown; transportMaxKm?: unknown;
  servicesOffered?: ServiceType[] | null; addressLat?: number | null; addressLng?: number | null;
}): { pickupFee: number; dropoffFee: number; maxKm: number; services: ServiceType[] } | null {
  if (!p.transportEnabled || p.addressLat == null || p.addressLng == null) return null;
  const services = (p.servicesOffered ?? []).filter((s) => TRANSPORT_SERVICES.includes(s));
  if (services.length === 0) return null;
  return {
    pickupFee: Number(p.transportPickupFee ?? 0),
    dropoffFee: Number(p.transportDropoffFee ?? 0),
    maxKm: Number(p.transportMaxKm ?? 0),
    services,
  };
}

// ── Cotización y armado al reservar ──────────────────────────────────────────

type CaregiverForTransport = {
  id: string;
  servicesOffered: ServiceType[];
  addressLat: number | null;
  addressLng: number | null;
  transportEnabled: boolean;
  transportPickupFee: unknown;
  transportDropoffFee: unknown;
  transportMaxKm: unknown;
};
type ClientAddress = {
  address: string | null;
  addressLat: number | null;
  addressLng: number | null;
  addressReference?: string | null;
  addressStreet?: string | null;
  addressNumber?: string | null;
  addressApartment?: string | null;
  addressCondominio?: string | null;
};

export const TRANSPORT_CAREGIVER_SELECT = {
  id: true, servicesOffered: true, addressLat: true, addressLng: true,
  transportEnabled: true, transportPickupFee: true, transportDropoffFee: true, transportMaxKm: true,
} as const;
export const TRANSPORT_CLIENT_SELECT = {
  address: true, addressLat: true, addressLng: true, addressReference: true,
  addressStreet: true, addressNumber: true, addressApartment: true, addressCondominio: true,
} as const;

// Un solo tipo (no unión discriminada): el build de producción compila sin
// strictNullChecks (tsconfig.build.json) y ahí no se estrecha `available`.
type Availability = { available: boolean; distanceKm?: number; code?: string; message?: string };

function availabilityFor(cg: CaregiverForTransport, client: ClientAddress | null, serviceType?: string): Availability {
  const pub = publicTransportOf(cg);
  if (!pub) return { available: false, code: 'TRANSPORT_NOT_OFFERED', message: 'Este cuidador no ofrece recojo ni entrega.' };
  if (serviceType && !pub.services.includes(serviceType as ServiceType)) {
    return { available: false, code: 'TRANSPORT_NOT_OFFERED', message: 'El recojo y la entrega son solo para guardería u hospedaje.' };
  }
  if (!client || client.addressLat == null || client.addressLng == null) {
    return {
      available: false,
      code: 'TRANSPORT_ADDRESS_REQUIRED',
      message: 'Para pedir recojo o entrega, guarda tu dirección con la ubicación en el mapa (Perfil > Mi dirección).',
    };
  }
  const distanceKm = round2(haversineKm({ lat: client.addressLat, lng: client.addressLng }, { lat: cg.addressLat!, lng: cg.addressLng! }));
  if (distanceKm > pub.maxKm) {
    // Sin la distancia exacta: cambiando su dirección y consultando, alguien podría
    // triangular dónde vive el cuidador.
    return {
      available: false,
      code: 'TRANSPORT_OUT_OF_RANGE',
      message: `Tu dirección está fuera del área donde este cuidador recoge (hasta ${pub.maxKm} km).`,
    };
  }
  return { available: true, distanceKm };
}

/** GET /api/caregivers/:id/transport-quote — lo que puede pedir este dueño a este cuidador. */
export async function quoteForClient(clientUserId: string, caregiverId: string, serviceType?: string) {
  const cg = await prisma.caregiverProfile.findFirst({
    where: { id: caregiverId, status: 'APPROVED', suspended: false },
    select: TRANSPORT_CAREGIVER_SELECT,
  });
  if (!cg) throw new NotFoundError('Cuidador no encontrado');
  const client = await prisma.clientProfile.findUnique({ where: { userId: clientUserId }, select: TRANSPORT_CLIENT_SELECT });
  const pub = publicTransportOf(cg);
  const a = availabilityFor(cg, client, serviceType);
  return {
    offered: !!pub,
    available: a.available,
    code: a.available ? null : a.code,
    message: a.available ? null : a.message,
    // Nunca la distancia: ni exacta ni redondeada (permitiría triangular la casa del
    // cuidador cambiando la dirección propia). Solo si está dentro del área o no.
    distanceKm: null,
    maxKm: pub?.maxKm ?? null,
    pickupFee: pub?.pickupFee ?? null,
    dropoffFee: pub?.dropoffFee ?? null,
    address: client?.address ?? null,
    hospedajeTimeRange: { min: HOSPEDAJE_MIN_TIME, max: HOSPEDAJE_MAX_TIME },
  };
}

export type TransportRequest = { pickup?: { time?: string | null } | null; dropoff?: { time?: string | null } | null } | null | undefined;

export interface PlannedLeg {
  kind: LegKind;
  fee: number;
  tax: number;
  time: string | null;
  address: string | null;
  addressLat: number;
  addressLng: number;
  addressReference: string | null;
  distanceKm: number;
}

function addressLine(c: ClientAddress): string | null {
  const parts = [
    c.addressStreet && c.addressNumber ? `${c.addressStreet} #${c.addressNumber}` : c.addressStreet,
    c.addressCondominio ? `Cond. ${c.addressCondominio}` : null,
    c.addressApartment ? `Dep. ${c.addressApartment}` : null,
  ].filter(Boolean);
  const line = parts.length > 0 ? parts.join(', ') : c.address;
  return line ? line.slice(0, 500) : null;
}

/**
 * Valida y arma los viajes pedidos al reservar. Lanza un error claro ante cualquier
 * pedido imposible (cuidador que no lo ofrece, fuera de radio, sin dirección, hora rara).
 */
export function planTransport(
  input: TransportRequest,
  ctx: { caregiver: CaregiverForTransport; client: ClientAddress | null; booking: ScheduleShape; taxRate?: number; nowMs?: number }
): { legs: PlannedLeg[]; amount: number; tax: number } {
  const wantPickup = !!input?.pickup;
  const wantDropoff = !!input?.dropoff;
  if (!wantPickup && !wantDropoff) return { legs: [], amount: 0, tax: 0 };

  const st = ctx.booking.serviceType;
  if (st !== ServiceType.GUARDERIA && st !== ServiceType.HOSPEDAJE) {
    throw new BadRequestError('El recojo y la entrega son solo para guardería u hospedaje.', 'TRANSPORT_NOT_OFFERED');
  }
  const a = availabilityFor(ctx.caregiver, ctx.client, st);
  if (!a.available) throw new BadRequestError(a.message ?? 'Recojo no disponible.', a.code);
  const client = ctx.client!;
  const now = ctx.nowMs ?? Date.now();

  const legs: PlannedLeg[] = [];
  for (const kind of LEG_KINDS) {
    const req = kind === 'PICKUP' ? input?.pickup : input?.dropoff;
    if (!req) continue;
    let time: string | null = null;
    if (st === ServiceType.HOSPEDAJE) {
      const t = typeof req.time === 'string' ? req.time.trim() : '';
      const label = kind === 'PICKUP' ? 'recojo' : 'entrega';
      if (!TIME_RE.test(t)) throw new BadRequestError(`Elige la hora de ${label}.`, 'TRANSPORT_TIME_REQUIRED');
      if (minutesOf(t) < minutesOf(HOSPEDAJE_MIN_TIME) || minutesOf(t) > minutesOf(HOSPEDAJE_MAX_TIME)) {
        throw new BadRequestError(`La hora de ${label} debe estar entre las ${HOSPEDAJE_MIN_TIME} y las ${HOSPEDAJE_MAX_TIME}.`, 'TRANSPORT_TIME_RANGE');
      }
      time = t;
    }
    const scheduled = legScheduledMs(ctx.booking, { kind, time });
    if (scheduled == null) throw new BadRequestError('No pudimos calcular la hora del viaje. Revisa la fecha y la hora.', 'TRANSPORT_TIME_REQUIRED');
    if (kind === 'PICKUP' && scheduled < now + MIN_LEAD_MIN * 60_000) {
      throw new BadRequestError(
        `El recojo tiene que ser al menos ${MIN_LEAD_MIN} minutos desde ahora. Elige una hora más tarde o lleva tú a tu mascota.`,
        'TRANSPORT_TOO_SOON'
      );
    }
    const fee = Number(kind === 'PICKUP' ? ctx.caregiver.transportPickupFee : ctx.caregiver.transportDropoffFee);
    legs.push({
      kind,
      fee,
      // Mismo redondeo que el impuesto de la reserva (computeClientCharge: Bs enteros).
      tax: Math.round(fee * Math.max(0, ctx.taxRate ?? 0)),
      time,
      address: addressLine(client),
      addressLat: client.addressLat!,
      addressLng: client.addressLng!,
      addressReference: client.addressReference?.slice(0, 300) ?? null,
      distanceKm: a.distanceKm ?? 0,
    });
  }
  const pickup = legs.find((l) => l.kind === 'PICKUP');
  const dropoff = legs.find((l) => l.kind === 'DROPOFF');
  if (pickup && dropoff) {
    const p = legScheduledMs(ctx.booking, pickup)!;
    const d = legScheduledMs(ctx.booking, dropoff)!;
    if (d <= p) throw new BadRequestError('La entrega tiene que ser después del recojo.', 'TRANSPORT_TIME_ORDER');
  }
  return { legs, amount: legs.reduce((s, l) => s + l.fee, 0), tax: legs.reduce((s, l) => s + l.tax, 0) };
}

// ── Acciones del cuidador sobre un viaje ─────────────────────────────────────

export function parseLegKind(raw: unknown): LegKind {
  const k = typeof raw === 'string' ? raw.toUpperCase() : '';
  if (k === 'PICKUP' || k === 'RECOJO') return 'PICKUP';
  if (k === 'DROPOFF' || k === 'ENTREGA') return 'DROPOFF';
  throw new BadRequestError('Viaje inválido: usa pickup o dropoff.');
}

function assertWindow(scheduled: number | null, minutesBefore: number, action: string, now = Date.now()) {
  if (scheduled == null) return;
  const opens = scheduled - minutesBefore * 60_000;
  if (now >= opens) return;
  throw new BadRequestError(`Todavía es pronto para ${action}. Podrás hacerlo el ${fmtDayHHmm(opens)}.`, 'TRANSPORT_TOO_EARLY');
}

async function lockForCaregiver(tx: Prisma.TransactionClient, caregiverUserId: string, bookingId: string) {
  const profile = await tx.caregiverProfile.findFirst({
    where: { userId: caregiverUserId },
    select: { id: true, userId: true, isCompany: true, companyName: true, user: { select: { firstName: true } } },
  });
  if (!profile) throw new ForbiddenError('Perfil de cuidador no encontrado');
  await tx.$queryRaw`SELECT id FROM "bookings" WHERE id = ${bookingId} FOR UPDATE`;
  const booking = await tx.booking.findFirst({ where: { id: bookingId, caregiverId: profile.id }, include: { transportLegs: true } });
  if (!booking) throw new NotFoundError('Reserva no encontrada');
  return { profile, booking };
}

function legOf(booking: { transportLegs: any[] }, kind: LegKind) {
  return booking.transportLegs.find((l) => l.kind === kind) ?? null;
}

const petOf = (b: { petName?: string | null }) => b.petName || 'tu mascota';
const placeOf = (b: { serviceType: string }) => (b.serviceType === ServiceType.HOSPEDAJE ? 'el hospedaje' : 'la guardería');

/** "Voy en camino" (recojo, antes de iniciar) / "salí a devolverlo" (entrega, servicio en curso). */
export async function markLegEnRoute(bookingId: string, caregiverUserId: string, kind: LegKind) {
  const r = await prisma.$transaction(async (tx) => {
    const { profile, booking } = await lockForCaregiver(tx, caregiverUserId, bookingId);
    const leg = legOf(booking, kind);
    if (!leg || leg.status === LEG_STATUS.CANCELLED) {
      throw new BadRequestError(kind === 'PICKUP' ? 'Esta reserva no tiene recojo a domicilio.' : 'Esta reserva no tiene entrega a domicilio.', 'TRANSPORT_LEG_NOT_FOUND');
    }
    if (leg.status !== LEG_STATUS.SCHEDULED) return { booking, notify: false, profile };
    if (kind === 'PICKUP' && booking.status !== BookingStatus.CONFIRMED) {
      throw new BadRequestError('El recojo se avisa antes de iniciar el servicio, con la reserva confirmada.');
    }
    if (kind === 'DROPOFF') {
      if (booking.status !== BookingStatus.IN_PROGRESS) throw new BadRequestError('La entrega se avisa con el servicio en curso.');
      if (booking.pausedAt) throw new BadRequestError('Hay una emergencia activa sin resolver. Resuélvela antes de salir con la mascota.');
    }
    assertWindow(legScheduledMs(booking, leg), EN_ROUTE_OPENS_MIN, kind === 'PICKUP' ? 'salir a recogerlo' : 'salir a devolverlo');
    const now = new Date();
    const res = await tx.bookingTransportLeg.updateMany({
      where: { id: leg.id, status: LEG_STATUS.SCHEDULED },
      data: { status: LEG_STATUS.EN_ROUTE, enRouteAt: now },
    });
    if (res.count === 0) return { booking, notify: false, profile };
    // El aviso general "en camino" de la reserva también queda marcado (pantallas viejas).
    if (kind === 'PICKUP' && !booking.enRouteAt) {
      await tx.booking.update({ where: { id: bookingId }, data: { enRouteAt: now } });
    }
    return { booking, notify: true, profile };
  });
  if (r.notify) {
    const who = caregiverDisplayName(r.profile);
    if (kind === 'PICKUP') {
      await notify(r.booking.clientId, bookingId, `🚗 ${who} va en camino a recoger a ${petOf(r.booking)}`,
        `Ten lista a ${petOf(r.booking)}. Puedes seguir el viaje en vivo desde "Mis reservas".`, 'TRANSPORT_PICKUP_EN_ROUTE');
    } else {
      await notify(r.booking.clientId, bookingId, `🚗 ${petOf(r.booking)} va de regreso a casa`,
        `${who} salió de ${placeOf(r.booking)} para devolverte a ${petOf(r.booking)}. Síguelo en vivo desde "Mis reservas".`, 'TRANSPORT_DROPOFF_EN_ROUTE');
    }
  }
  return reloadResponse(bookingId);
}

/** "Llegué a tu casa" (recojo o entrega). */
export async function markLegArrived(bookingId: string, caregiverUserId: string, kind: LegKind) {
  const r = await prisma.$transaction(async (tx) => {
    const { profile, booking } = await lockForCaregiver(tx, caregiverUserId, bookingId);
    const leg = legOf(booking, kind);
    if (!leg || leg.status === LEG_STATUS.CANCELLED) throw new BadRequestError('Este viaje no existe o fue cancelado.', 'TRANSPORT_LEG_NOT_FOUND');
    if (leg.status === LEG_STATUS.ARRIVED || leg.status === LEG_STATUS.DONE) return { booking, notify: false, profile };
    if (kind === 'PICKUP') {
      if (booking.status !== BookingStatus.CONFIRMED) throw new BadRequestError('El recojo se hace antes de iniciar el servicio.');
      assertWindow(legScheduledMs(booking, leg), ARRIVE_OPENS_MIN, 'marcar que llegaste');
    } else {
      if (booking.status !== BookingStatus.IN_PROGRESS) throw new BadRequestError('La entrega se hace con el servicio en curso.');
      if (leg.status === LEG_STATUS.SCHEDULED) {
        throw new BadRequestError('Primero marca que saliste a devolverlo.', 'TRANSPORT_NOT_EN_ROUTE');
      }
    }
    const now = new Date();
    const res = await tx.bookingTransportLeg.updateMany({
      where: { id: leg.id, status: { in: [LEG_STATUS.SCHEDULED, LEG_STATUS.EN_ROUTE] } },
      data: { status: LEG_STATUS.ARRIVED, arrivedAt: now, ...(leg.enRouteAt ? {} : { enRouteAt: now }) },
    });
    return { booking, notify: res.count > 0, profile };
  });
  if (r.notify) {
    const who = caregiverDisplayName(r.profile);
    if (kind === 'PICKUP') {
      await notify(r.booking.clientId, bookingId, `📍 ${who} llegó a tu casa`,
        `Llegó a recoger a ${petOf(r.booking)}. Sal a entregárselo.`, 'TRANSPORT_PICKUP_ARRIVED');
    } else {
      await notify(r.booking.clientId, bookingId, `📍 ${petOf(r.booking)} llegó a casa`,
        `${who} está en tu puerta con ${petOf(r.booking)}. Sal a recibirlo.`, 'TRANSPORT_DROPOFF_ARRIVED');
    }
  }
  return reloadResponse(bookingId);
}

/** Recojo: "ya llegamos a la guardería / al hospedaje" — cierra el mapa en vivo. */
export async function markPickupAtBase(bookingId: string, caregiverUserId: string) {
  const r = await prisma.$transaction(async (tx) => {
    const { profile, booking } = await lockForCaregiver(tx, caregiverUserId, bookingId);
    const leg = legOf(booking, 'PICKUP');
    if (!leg || leg.status !== LEG_STATUS.DONE) throw new BadRequestError('Primero marca que recogiste a la mascota.', 'TRANSPORT_NOT_PICKED_UP');
    if (leg.atBaseAt) return { booking, notify: false, profile };
    const res = await tx.bookingTransportLeg.updateMany({ where: { id: leg.id, atBaseAt: null }, data: { atBaseAt: new Date() } });
    return { booking, notify: res.count > 0, profile };
  });
  if (r.notify) {
    await notify(r.booking.clientId, bookingId, `🏠 ${petOf(r.booking)} ya llegó a ${placeOf(r.booking)}`,
      `Llegaron bien. Desde aquí te llegan fotos y novedades.`, 'TRANSPORT_PICKUP_AT_BASE');
  }
  return reloadResponse(bookingId);
}

/**
 * Cancelar un viaje (solo antes de que el cuidador salga; el cuidador también puede
 * mientras va en camino si surge un imprevisto). Devuelve precio + impuesto a la
 * billetera del dueño si la reserva ya estaba pagada.
 */
export async function cancelLeg(
  bookingId: string,
  actor: { userId: string; role: 'CLIENT' | 'CAREGIVER' | 'ADMIN' },
  kind: LegKind,
  reasonRaw?: unknown
) {
  const reason = typeof reasonRaw === 'string' ? reasonRaw.trim().slice(0, 300) : '';
  const r = await prisma.$transaction(async (tx) => {
    let booking: any;
    let profileForName: any = null;
    if (actor.role === 'CAREGIVER') {
      const l = await lockForCaregiver(tx, actor.userId, bookingId);
      booking = l.booking;
      profileForName = l.profile;
    } else {
      await tx.$queryRaw`SELECT id FROM "bookings" WHERE id = ${bookingId} FOR UPDATE`;
      booking = await tx.booking.findFirst({
        where: actor.role === 'CLIENT' ? { id: bookingId, clientId: actor.userId } : { id: bookingId },
        include: { transportLegs: true },
      });
      if (!booking) throw new NotFoundError('Reserva no encontrada');
    }
    const leg = legOf(booking, kind);
    if (!leg) throw new BadRequestError('Esta reserva no tiene ese viaje.', 'TRANSPORT_LEG_NOT_FOUND');
    if (leg.status === LEG_STATUS.CANCELLED) return { booking, leg, refund: 0, already: true, profileForName };
    const allowed: string[] = actor.role === 'CLIENT' ? [LEG_STATUS.SCHEDULED] : [LEG_STATUS.SCHEDULED, LEG_STATUS.EN_ROUTE];
    if (!allowed.includes(leg.status)) {
      throw new BadRequestError(
        leg.status === LEG_STATUS.DONE
          ? 'Este viaje ya se hizo.'
          : actor.role === 'CLIENT'
            ? 'El cuidador ya salió hacia tu casa; ya no se puede cancelar este viaje. Escríbele por el chat.'
            : 'Ya llegaste a la casa del dueño; termina el viaje.',
        'TRANSPORT_LEG_LOCKED'
      );
    }
    const st = booking.status as BookingStatus;
    const paidStates: BookingStatus[] = [BookingStatus.WAITING_CAREGIVER_APPROVAL, BookingStatus.CONFIRMED, BookingStatus.IN_PROGRESS];
    if (!paidStates.includes(st)) {
      throw new BadRequestError(
        st === BookingStatus.PAYMENT_PENDING_APPROVAL
          ? 'Estamos verificando el pago de esta reserva. Podrás cambiar el viaje cuando se confirme.'
          : 'Esta reserva ya no admite cambios en el recojo o la entrega.',
        'TRANSPORT_LEG_LOCKED'
      );
    }
    if (kind === 'PICKUP' && st === BookingStatus.IN_PROGRESS) throw new BadRequestError('El servicio ya empezó.', 'TRANSPORT_LEG_LOCKED');
    if (booking.paymentAutoApprovedAt && !booking.paymentReviewedAt) {
      throw new BadRequestError('Estamos verificando el pago de esta reserva. Podrás cambiar el viaje cuando se confirme.', 'TRANSPORT_LEG_LOCKED');
    }

    const fee = Number(leg.fee);
    const feeTax = Number(leg.tax ?? 0);
    // Nunca más de lo que queda pagado en la reserva (defensa ante descuentos raros).
    const refund = Math.min(round2(fee + feeTax), Math.max(0, round2(Number(booking.totalAmount))));
    const now = new Date();
    const claimed = await tx.bookingTransportLeg.updateMany({
      where: { id: leg.id, status: { in: allowed } },
      data: {
        status: LEG_STATUS.CANCELLED,
        cancelledAt: now,
        cancelledBy: actor.role,
        cancelReason: reason || null,
        refundedAmount: new Prisma.Decimal(refund),
      },
    });
    if (claimed.count === 0) return { booking, leg, refund: 0, already: true, profileForName };

    if (refund > 0) {
      await tx.booking.update({
        where: { id: bookingId },
        data: {
          totalAmount: { decrement: refund },
          taxAmount: { decrement: feeTax },
          transportAmount: { decrement: fee },
          transportTaxAmount: { decrement: feeTax },
          transportRefundAmount: { increment: refund },
        },
      });
      await tx.$queryRaw`SELECT id FROM "users" WHERE id = ${booking.clientId} FOR UPDATE`;
      const u = await tx.user.update({
        where: { id: booking.clientId },
        data: { balance: { increment: refund } },
        select: { balance: true },
      });
      await tx.walletTransaction.create({
        data: {
          userId: booking.clientId,
          type: 'REFUND',
          amount: refund,
          balance: Number(u.balance),
          description: `Devolución del ${kind === 'PICKUP' ? 'recojo' : 'la entrega'} cancelado (${bookingId.slice(0, 8)})`,
          bookingId,
          status: 'COMPLETED',
        },
      });
    }
    return { booking, leg, refund, already: false, profileForName };
  });

  if (!r.already) {
    if (r.refund > 0) emitWalletUpdated(r.booking.clientId);
    const what = kind === 'PICKUP' ? 'recojo' : 'entrega';
    const money = r.refund > 0 ? ` Te devolvimos Bs ${r.refund.toFixed(2)} a tu billetera Garden.` : '';
    const pet = petOf(r.booking);
    if (actor.role === 'CLIENT') {
      for (const uid of await caregiverRecipients(r.booking)) {
        await notify(uid, bookingId, `El dueño canceló el ${what} de ${pet}`,
          kind === 'PICKUP'
            ? `Ya no vas a recogerlo: el dueño lo lleva a ${placeOf(r.booking)}.`
            : `Ya no vas a devolverlo: el dueño lo recoge en ${placeOf(r.booking)}.`,
          'TRANSPORT_LEG_CANCELLED');
      }
      await notify(r.booking.clientId, bookingId, `Cancelaste el ${what} de ${pet}`,
        (kind === 'PICKUP' ? `Lleva tú a ${pet} a ${placeOf(r.booking)}.` : `Recoge tú a ${pet} en ${placeOf(r.booking)}.`) + money,
        'TRANSPORT_LEG_CANCELLED');
    } else {
      const who = r.profileForName ? caregiverDisplayName(r.profileForName) : 'El cuidador';
      await notify(r.booking.clientId, bookingId, `⚠️ ${actor.role === 'ADMIN' ? 'Garden' : who} canceló el ${what} de ${pet}`,
        (kind === 'PICKUP'
          ? `No podrán recogerlo en tu casa: llévalo tú a ${placeOf(r.booking)}${reason ? `. Motivo: ${reason}` : ''}.`
          : `No podrán devolverlo a tu casa: recógelo en ${placeOf(r.booking)}${reason ? `. Motivo: ${reason}` : ''}.`) + money,
        'TRANSPORT_LEG_CANCELLED');
      if (actor.role === 'CAREGIVER') {
        notifyAdmins('Un cuidador canceló un viaje', `Canceló el ${what} de la reserva ${bookingId.slice(0, 8)}${reason ? ` (motivo: ${reason})` : ''}.`, { type: 'TRANSPORT_LEG_CANCELLED', bookingId }).catch(() => {});
      }
    }
    logger.info('[TRANSPORT] viaje cancelado', { bookingId, kind, by: actor.role, refund: r.refund });
  }
  return reloadResponse(bookingId);
}

// ── GPS durante los viajes ───────────────────────────────────────────────────

/** Punto GPS del cuidador mientras hace un viaje de Guardería/Hospedaje. */
export async function trackLegLocation(booking: { id: string; transportLegs?: any[] }, lat: number, lng: number, accuracy?: number) {
  const legs = booking.transportLegs ?? (await prisma.bookingTransportLeg.findMany({ where: { bookingId: booking.id } }));
  const live = legs.find((l) => isLegLive(l));
  if (!live) throw new BadRequestError('No hay un viaje en curso para seguir en el mapa.', 'TRANSPORT_NOT_LIVE');
  const punto = { lat, lng, timestamp: new Date().toISOString(), accuracy: accuracy ?? 0, leg: live.kind };
  const json = JSON.stringify(punto);
  await prisma.$executeRaw`
    UPDATE "booking_transport_legs"
    SET "trackingData" = COALESCE("trackingData", '[]'::jsonb) || ${json}::jsonb
    WHERE id = ${live.id}
  `;
  const cur = await prisma.bookingTransportLeg.findUnique({ where: { id: live.id }, select: { trackingData: true } });
  const pts = (cur?.trackingData as any[]) || [];
  if (pts.length > GPS_MAX_POINTS) {
    await prisma.bookingTransportLeg.update({ where: { id: live.id }, data: { trackingData: pts.slice(-1000) } });
  }
  getIO()?.to(`booking:${booking.id}`).emit('gps_update', punto);
}

/** Ruta del viaje en curso (o del último hecho) para el mapa del dueño. */
export async function legTrack(bookingId: string): Promise<any[]> {
  const legs = await prisma.bookingTransportLeg.findMany({ where: { bookingId }, orderBy: { createdAt: 'asc' } });
  const live = legs.find((l) => isLegLive(l));
  const pick = live ?? [...legs].reverse().find((l) => Array.isArray(l.trackingData) && (l.trackingData as any[]).length > 0);
  return ((pick?.trackingData as any[]) ?? []).map((p) => ({ ...p, leg: pick!.kind }));
}

// ── Job: recordatorios, atrasos y cierre del mapa ────────────────────────────

export async function runTransportMaintenance(now = new Date()): Promise<{ reminded: number; late: number; alerted: number; closed: number }> {
  const legs = await prisma.bookingTransportLeg.findMany({
    where: {
      OR: [
        { status: { in: ACTIVE_LEG_STATUSES } },
        { kind: 'PICKUP', status: LEG_STATUS.DONE, atBaseAt: null },
      ],
      booking: { status: { in: [BookingStatus.CONFIRMED, BookingStatus.IN_PROGRESS] } },
    },
    include: {
      booking: {
        select: {
          id: true, status: true, serviceType: true, startDate: true, endDate: true, walkDate: true, startTime: true,
          timeSlot: true, duration: true, clientId: true, caregiverId: true, assignedStaffMemberId: true, petName: true,
        },
      },
    },
  });
  const t = now.getTime();
  let reminded = 0, late = 0, alerted = 0, closed = 0;
  for (const leg of legs) {
    const b = leg.booking;
    try {
      if (leg.kind === 'PICKUP' && leg.status === LEG_STATUS.DONE) {
        if (leg.doneAt && t - leg.doneAt.getTime() >= PICKUP_TRACKING_MAX_MS) {
          await prisma.bookingTransportLeg.updateMany({ where: { id: leg.id, atBaseAt: null }, data: { atBaseAt: now } });
          closed++;
        }
        continue;
      }
      // El recojo solo cuenta con la reserva confirmada; la entrega, con el servicio en curso.
      if (leg.kind === 'PICKUP' && b.status !== BookingStatus.CONFIRMED) continue;
      if (leg.kind === 'DROPOFF' && b.status !== BookingStatus.IN_PROGRESS) continue;
      const scheduled = legScheduledMs(b, leg);
      if (scheduled == null) continue;
      const pet = b.petName || 'la mascota';
      const what = leg.kind === 'PICKUP' ? 'Recojo' : 'Entrega';

      if (leg.status === LEG_STATUS.SCHEDULED && !leg.reminderSentAt && t >= scheduled - 60 * 60_000 && t < scheduled + 60 * 60_000) {
        const res = await prisma.bookingTransportLeg.updateMany({ where: { id: leg.id, reminderSentAt: null }, data: { reminderSentAt: now } });
        if (res.count > 0) {
          reminded++;
          for (const uid of await caregiverRecipients(b)) {
            await notify(uid, b.id, `⏰ ${what} de ${pet} a las ${fmtHHmm(scheduled)}`,
              leg.kind === 'PICKUP'
                ? `Cuando salgas, toca "Voy en camino" para que el dueño te siga en el mapa. Dirección: ${leg.address ?? 'ver en la reserva'}.`
                : `Cuando salgas, toca "Salí a devolverlo" para que el dueño te siga en el mapa.`,
              'TRANSPORT_REMINDER');
          }
        }
      }
      if (leg.status === LEG_STATUS.SCHEDULED && !leg.lateNoticeAt && t > scheduled + 15 * 60_000) {
        const res = await prisma.bookingTransportLeg.updateMany({ where: { id: leg.id, lateNoticeAt: null }, data: { lateNoticeAt: now } });
        if (res.count > 0) {
          late++;
          for (const uid of await caregiverRecipients(b)) {
            await notify(uid, b.id, `⚠️ Vas tarde con el ${what.toLowerCase()} de ${pet}`,
              `Era a las ${fmtHHmm(scheduled)}. Avísale al dueño por el chat y toca "Voy en camino" al salir. Si no puedes hacerlo, cancela el viaje para que lo sepa.`,
              'TRANSPORT_LATE');
          }
          await notify(b.clientId, b.id, `El ${what.toLowerCase()} de ${pet} viene con retraso`,
            `Era a las ${fmtHHmm(scheduled)} y el cuidador todavía no salió. Ya le avisamos; puedes escribirle por el chat.`,
            'TRANSPORT_LATE');
        }
      }
      if (leg.status !== LEG_STATUS.DONE && !leg.adminAlertAt && t > scheduled + 60 * 60_000) {
        const res = await prisma.bookingTransportLeg.updateMany({ where: { id: leg.id, adminAlertAt: null }, data: { adminAlertAt: now } });
        if (res.count > 0) {
          alerted++;
          notifyAdmins(`${what} atrasado más de 1 hora`,
            `${what} de ${pet} (reserva ${b.id.slice(0, 8)}) era a las ${fmtHHmm(scheduled)} y sigue en "${leg.status}". Revisa con el cuidador.`,
            { type: 'TRANSPORT_LATE', bookingId: b.id }).catch(() => {});
        }
      }
    } catch (err) {
      logger.error('[TRANSPORT] job: error en un viaje', { legId: leg.id, err });
    }
  }
  return { reminded, late, alerted, closed };
}

async function reloadResponse(bookingId: string) {
  const { bookingToResponse } = await import('../booking-service/booking.types.js');
  const b = await prisma.booking.findUniqueOrThrow({ where: { id: bookingId }, include: { transportLegs: true } });
  return bookingToResponse(b as any);
}

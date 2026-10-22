/**
 * Cálculos puros del recojo / entrega (sin base de datos) — los usan la respuesta de la
 * reserva (booking.types.ts), transport.service.ts y booking.service.ts.
 */
import { ServiceType } from '@prisma/client';
import { boliviaDateAndTimeToMs } from '../../utils/bolivia-time.js';

export type LegKind = 'PICKUP' | 'DROPOFF';

export const LEG_STATUS = {
  SCHEDULED: 'SCHEDULED',
  EN_ROUTE: 'EN_ROUTE',
  ARRIVED: 'ARRIVED',
  DONE: 'DONE',
  CANCELLED: 'CANCELLED',
} as const;
export const ACTIVE_LEG_STATUSES: string[] = [LEG_STATUS.SCHEDULED, LEG_STATUS.EN_ROUTE, LEG_STATUS.ARRIVED];

/** Ventanas de aviso (igual que paseo, ver utils/service-window.ts). */
export const EN_ROUTE_OPENS_MIN = 60;
export const ARRIVE_OPENS_MIN = 30;
export const SLOT_START: Record<string, string> = { MANANA: '08:00', TARDE: '14:00', NOCHE: '19:00' };

export const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/;
/** Si nadie marca "ya llegamos", el mapa en vivo del recojo se cierra solo. */
export const PICKUP_TRACKING_MAX_MS = 3 * 60 * 60 * 1000;

export const round2 = (n: number) => Math.round(n * 100) / 100;
export const minutesOf = (hhmm: string) => {
  const [h, m] = hhmm.split(':').map(Number);
  return (h as number) * 60 + (m as number);
};
export const fmtHHmm = (ms: number) => {
  const b = new Date(ms - 4 * 60 * 60 * 1000);
  return `${String(b.getUTCHours()).padStart(2, '0')}:${String(b.getUTCMinutes()).padStart(2, '0')}`;
};
/** Lo que el dueño paga por el transporte vigente (precios + su impuesto). */
export function transportGrossOf(b: { transportAmount?: unknown; transportTaxAmount?: unknown }): number {
  return round2(Number(b.transportAmount ?? 0) + Number(b.transportTaxAmount ?? 0));
}

export type ScheduleShape = {
  serviceType: ServiceType | string;
  startDate: Date | null;
  endDate: Date | null;
  walkDate: Date | null;
  startTime: string | null;
  timeSlot: string | null;
  duration: number | null;
};

/** Instante (ms UTC) acordado para un viaje, derivado de la reserva. null = desconocido. */
export function legScheduledMs(b: ScheduleShape, leg: { kind: string; time: string | null }): number | null {
  if (b.serviceType === ServiceType.HOSPEDAJE) {
    const day = leg.kind === 'PICKUP' ? b.startDate : b.endDate;
    if (!day || !leg.time) return null;
    return boliviaDateAndTimeToMs(day, leg.time);
  }
  if (!b.walkDate) return null;
  if (leg.time) return boliviaDateAndTimeToMs(b.walkDate, leg.time);
  const start = b.startTime && TIME_RE.test(b.startTime) ? b.startTime : b.timeSlot ? SLOT_START[b.timeSlot] : undefined;
  if (!start) return null;
  const startMs = boliviaDateAndTimeToMs(b.walkDate, start);
  return leg.kind === 'PICKUP' ? startMs : startMs + (b.duration ?? 0) * 60_000;
}

// ── Vista en la respuesta de la reserva ──────────────────────────────────────

/**
 * Vista de un viaje para la respuesta de la reserva. La dirección exacta del dueño solo
 * viaja con la reserva confirmada o en curso (igual que en paseo): antes basta la distancia.
 */
export function legView(leg: any, booking: ScheduleShape & { status?: string }) {
  const scheduled = legScheduledMs(booking, leg);
  const exposeAddress = booking.status === undefined || booking.status === 'CONFIRMED' || booking.status === 'IN_PROGRESS';
  return {
    kind: leg.kind as LegKind,
    fee: Number(leg.fee),
    status: leg.status as string,
    scheduledAt: scheduled != null ? new Date(scheduled).toISOString() : null,
    time: scheduled != null ? fmtHHmm(scheduled) : leg.time ?? null,
    address: exposeAddress ? leg.address ?? null : null,
    addressLat: exposeAddress ? leg.addressLat : null,
    addressLng: exposeAddress ? leg.addressLng : null,
    addressReference: exposeAddress ? leg.addressReference ?? null : null,
    distanceKm: exposeAddress ? Number(leg.distanceKm) : null,
    enRouteAt: leg.enRouteAt?.toISOString?.() ?? null,
    arrivedAt: leg.arrivedAt?.toISOString?.() ?? null,
    doneAt: leg.doneAt?.toISOString?.() ?? null,
    atBaseAt: leg.atBaseAt?.toISOString?.() ?? null,
    cancelledAt: leg.cancelledAt?.toISOString?.() ?? null,
    cancelledBy: leg.cancelledBy ?? null,
    cancelReason: leg.cancelReason ?? null,
    refundedAmount: Number(leg.refundedAmount ?? 0),
    /** El mapa en vivo tiene sentido ahora (viaje en curso). */
    live: isLegLive(leg),
    enRouteOpensAt: scheduled != null ? new Date(scheduled - EN_ROUTE_OPENS_MIN * 60_000).toISOString() : null,
    arrivalOpensAt: scheduled != null ? new Date(scheduled - ARRIVE_OPENS_MIN * 60_000).toISOString() : null,
  };
}

export function isLegLive(leg: { kind: string; status: string; doneAt?: Date | null; atBaseAt?: Date | null }, now = Date.now()): boolean {
  if (leg.status === LEG_STATUS.EN_ROUTE || leg.status === LEG_STATUS.ARRIVED) return true;
  return (
    leg.kind === 'PICKUP' &&
    leg.status === LEG_STATUS.DONE &&
    !leg.atBaseAt &&
    !!leg.doneAt &&
    now - leg.doneAt.getTime() < PICKUP_TRACKING_MAX_MS
  );
}


/**
 * CRM de mascotas walk-in + dashboard de ocupación para cuentas EMPRESA.
 * Puro registro interno — sin dinero, sin reserva real de Garden de por
 * medio. Dueño y staff (ver caregiver-staff module) pueden operarlo por
 * igual; cada función toma `ownerUserId` y resuelve el perfil, mismo
 * patrón que getBookingsByCaregiverUserId y todo caregiver-staff.service.ts.
 */
import { BookingStatus, ServiceType } from '@prisma/client';
import prisma from '../../config/database.js';
import { BadRequestError, ConflictError, ForbiddenError, NotFoundError } from '../../shared/errors.js';
import { combinedHospedajeGuarderiaMax } from '../../utils/caregiver-capacity.js';
import { sendTransactionalEmail } from '../auth/email.service.js';
import logger from '../../shared/logger.js';
import type { z } from 'zod';
import type {
  createWalkInClientBodySchema,
  patchWalkInClientBodySchema,
  createWalkInPetBodySchema,
  patchWalkInPetBodySchema,
  addVisitEventBodySchema,
  patchWalkInVisitBodySchema,
} from './caregiver-crm.validation.js';

type CreateWalkInClientBody = z.infer<typeof createWalkInClientBodySchema>;
type PatchWalkInClientBody = z.infer<typeof patchWalkInClientBodySchema>;
type CreateWalkInPetBody = z.infer<typeof createWalkInPetBodySchema>;
type PatchWalkInPetBody = z.infer<typeof patchWalkInPetBodySchema>;
type AddVisitEventBody = z.infer<typeof addVisitEventBodySchema>;
type PatchWalkInVisitBody = z.infer<typeof patchWalkInVisitBodySchema>;

/** Mismo patrón que ALLOWED_EVENT_TYPES en booking.service.ts — bitácora de
 * cuidado (FEEDING/WALK/MEDICATION/BATH/NOTE, nunca dispara email) +
 * comunicación con el dueño (PHOTO/INCIDENT/INCIDENT_RESOLVED, si hay email). */
const ALLOWED_VISIT_EVENT_TYPES = ['FEEDING', 'WALK', 'MEDICATION', 'BATH', 'NOTE', 'PHOTO', 'INCIDENT', 'INCIDENT_RESOLVED'] as const;

interface WalkInVisitEvent {
  type: (typeof ALLOWED_VISIT_EVENT_TYPES)[number];
  note: string | null;
  photoUrl: string | null;
  at: string;
  byUserId: string;
}

/** No debe tumbar la operación principal (check-in/check-out/bitácora) si el
 * email falla — mismo criterio que sendPushToUser en notification.service.ts. */
async function notifyWalkInClientEmail(email: string, subject: string, html: string) {
  try {
    await sendTransactionalEmail(email, subject, html);
  } catch (err) {
    logger.error('No se pudo notificar por email a cliente walk-in', { email, subject, error: (err as Error).message });
  }
}

async function resolveCompanyProfile(ownerUserId: string) {
  const profile = await prisma.caregiverProfile.findFirst({ where: { userId: ownerUserId } });
  if (!profile) throw new NotFoundError('No tenés un perfil de cuidador');
  if (!profile.isCompany) {
    throw new ForbiddenError('El CRM de mascotas walk-in es solo para cuentas empresa');
  }
  return profile;
}

// ── Clientes walk-in ─────────────────────────────────────────────────────────

export async function listWalkInClients(ownerUserId: string, search?: string) {
  const profile = await resolveCompanyProfile(ownerUserId);
  return prisma.walkInClient.findMany({
    where: {
      caregiverProfileId: profile.id,
      ...(search ? { name: { contains: search, mode: 'insensitive' as const } } : {}),
    },
    orderBy: { name: 'asc' },
    include: { pets: { select: { id: true, name: true, photoUrl: true } } },
  });
}

export async function getWalkInClient(ownerUserId: string, clientId: string) {
  const profile = await resolveCompanyProfile(ownerUserId);
  const client = await prisma.walkInClient.findUnique({
    where: { id: clientId },
    include: { pets: true },
  });
  if (!client || client.caregiverProfileId !== profile.id) {
    throw new NotFoundError('Cliente walk-in no encontrado');
  }
  return client;
}

export async function createWalkInClient(ownerUserId: string, actingUserId: string, body: CreateWalkInClientBody) {
  const profile = await resolveCompanyProfile(ownerUserId);
  return prisma.walkInClient.create({
    data: {
      caregiverProfileId: profile.id,
      name: body.name.trim(),
      phone: body.phone ?? null,
      email: body.email ?? null,
      notes: body.notes ?? null,
      createdByUserId: actingUserId,
    },
  });
}

export async function updateWalkInClient(ownerUserId: string, clientId: string, body: PatchWalkInClientBody) {
  const profile = await resolveCompanyProfile(ownerUserId);
  const existing = await prisma.walkInClient.findUnique({ where: { id: clientId } });
  if (!existing || existing.caregiverProfileId !== profile.id) {
    throw new NotFoundError('Cliente walk-in no encontrado');
  }
  return prisma.walkInClient.update({
    where: { id: clientId },
    data: {
      ...(body.name !== undefined ? { name: body.name.trim() } : {}),
      ...(body.phone !== undefined ? { phone: body.phone } : {}),
      ...(body.email !== undefined ? { email: body.email } : {}),
      ...(body.notes !== undefined ? { notes: body.notes } : {}),
    },
  });
}

export async function deleteWalkInClient(ownerUserId: string, clientId: string): Promise<void> {
  const profile = await resolveCompanyProfile(ownerUserId);
  const existing = await prisma.walkInClient.findUnique({
    where: { id: clientId },
    include: { pets: { select: { id: true, _count: { select: { visits: true } } } } },
  });
  if (!existing || existing.caregiverProfileId !== profile.id) {
    throw new NotFoundError('Cliente walk-in no encontrado');
  }
  const hasHistory = existing.pets.some((p) => p._count.visits > 0);
  if (hasHistory) {
    throw new ConflictError('No se puede borrar: alguna de sus mascotas tiene historial de visitas', 'WALKIN_HAS_HISTORY');
  }
  await prisma.walkInClient.delete({ where: { id: clientId } });
}

// ── Mascotas walk-in ─────────────────────────────────────────────────────────

export async function createWalkInPet(ownerUserId: string, clientId: string, body: CreateWalkInPetBody) {
  const profile = await resolveCompanyProfile(ownerUserId);
  const client = await prisma.walkInClient.findUnique({ where: { id: clientId } });
  if (!client || client.caregiverProfileId !== profile.id) {
    throw new NotFoundError('Cliente walk-in no encontrado');
  }
  return prisma.walkInPet.create({
    data: { walkInClientId: clientId, ...body, name: body.name.trim() },
  });
}

async function findOwnedPet(profileId: string, petId: string) {
  const pet = await prisma.walkInPet.findUnique({
    where: { id: petId },
    include: { walkInClient: { select: { caregiverProfileId: true } } },
  });
  if (!pet || pet.walkInClient.caregiverProfileId !== profileId) {
    throw new NotFoundError('Mascota walk-in no encontrada');
  }
  return pet;
}

export async function getWalkInPet(ownerUserId: string, petId: string) {
  const profile = await resolveCompanyProfile(ownerUserId);
  const pet = await prisma.walkInPet.findUnique({
    where: { id: petId },
    include: {
      walkInClient: { select: { id: true, name: true, phone: true, email: true, caregiverProfileId: true } },
      visits: { orderBy: { checkedInAt: 'desc' } },
    },
  });
  if (!pet || pet.walkInClient.caregiverProfileId !== profile.id) {
    throw new NotFoundError('Mascota walk-in no encontrada');
  }
  return pet;
}

export async function updateWalkInPet(ownerUserId: string, petId: string, body: PatchWalkInPetBody) {
  const profile = await resolveCompanyProfile(ownerUserId);
  await findOwnedPet(profile.id, petId);
  return prisma.walkInPet.update({
    where: { id: petId },
    data: { ...body, ...(body.name !== undefined ? { name: body.name.trim() } : {}) },
  });
}

export async function deleteWalkInPet(ownerUserId: string, petId: string): Promise<void> {
  const profile = await resolveCompanyProfile(ownerUserId);
  const pet = await prisma.walkInPet.findUnique({ where: { id: petId }, include: { walkInClient: true, _count: { select: { visits: true } } } });
  if (!pet || pet.walkInClient.caregiverProfileId !== profile.id) {
    throw new NotFoundError('Mascota walk-in no encontrada');
  }
  if (pet._count.visits > 0) {
    throw new ConflictError('No se puede borrar una mascota con historial de visitas', 'WALKIN_HAS_HISTORY');
  }
  await prisma.walkInPet.delete({ where: { id: petId } });
}

// ── Check-in / check-out ─────────────────────────────────────────────────────

export async function checkInWalkInPet(
  ownerUserId: string,
  actingUserId: string,
  petId: string,
  serviceType: ServiceType,
  notes?: string,
  spaceLabel?: string
) {
  const profile = await resolveCompanyProfile(ownerUserId);
  await findOwnedPet(profile.id, petId);

  const openVisit = await prisma.walkInVisit.findFirst({ where: { walkInPetId: petId, checkedOutAt: null } });
  if (openVisit) {
    throw new ConflictError('Esta mascota ya está registrada como presente', 'ALREADY_CHECKED_IN');
  }

  return prisma.walkInVisit.create({
    data: {
      caregiverProfileId: profile.id,
      walkInPetId: petId,
      serviceType,
      notes: notes ?? null,
      spaceLabel: spaceLabel ?? null,
      checkedInByUserId: actingUserId,
    },
    include: { walkInPet: { select: { name: true } } },
  });
}

export async function getWalkInVisit(ownerUserId: string, visitId: string) {
  const profile = await resolveCompanyProfile(ownerUserId);
  const visit = await prisma.walkInVisit.findUnique({
    where: { id: visitId },
    include: { walkInPet: { include: { walkInClient: { select: { id: true, name: true, phone: true, email: true } } } } },
  });
  if (!visit || visit.caregiverProfileId !== profile.id) {
    throw new NotFoundError('Visita no encontrada');
  }
  return visit;
}

function eventEmoji(type: string): string {
  switch (type) {
    case 'FEEDING': return '🍽️';
    case 'WALK': return '🚶';
    case 'MEDICATION': return '💊';
    case 'BATH': return '🛁';
    case 'PHOTO': return '📷';
    case 'INCIDENT': return '⚠️';
    case 'INCIDENT_RESOLVED': return '✅';
    default: return '📝';
  }
}

const EVENT_LABEL_ES: Record<string, string> = {
  FEEDING: 'Alimentación', WALK: 'Paseo interno', MEDICATION: 'Medicación', BATH: 'Baño',
  NOTE: 'Nota', PHOTO: 'Foto', INCIDENT: 'Incidente', INCIDENT_RESOLVED: 'Incidente resuelto',
};

export async function checkOutWalkInVisit(ownerUserId: string, actingUserId: string, visitId: string, amountCollected?: number) {
  const profile = await resolveCompanyProfile(ownerUserId);
  const visit = await prisma.walkInVisit.findUnique({
    where: { id: visitId },
    include: { walkInPet: { include: { walkInClient: true } } },
  });
  if (!visit || visit.caregiverProfileId !== profile.id) {
    throw new NotFoundError('Visita no encontrada');
  }
  if (visit.checkedOutAt !== null) {
    throw new BadRequestError('Esta visita ya tiene check-out registrado', 'ALREADY_CHECKED_OUT');
  }
  const checkedOutAt = new Date();
  const updated = await prisma.walkInVisit.update({
    where: { id: visitId },
    data: {
      checkedOutAt,
      checkedOutByUserId: actingUserId,
      ...(amountCollected !== undefined ? { amountCollected } : {}),
    },
    include: { walkInPet: { select: { name: true } } },
  });

  const client = visit.walkInPet.walkInClient;
  if (client.email) {
    const events = (visit.events as unknown as WalkInVisitEvent[] | null) ?? [];
    const durationMin = Math.round((checkedOutAt.getTime() - visit.checkedInAt.getTime()) / 60000);
    const durationTxt = durationMin >= 60 ? `${Math.floor(durationMin / 60)}h ${durationMin % 60}min` : `${durationMin} min`;
    const eventsHtml = events.length
      ? `<ul>${events.map((e) => `<li>${eventEmoji(e.type)} ${EVENT_LABEL_ES[e.type] ?? e.type}${e.note ? `: ${e.note}` : ''}</li>`).join('')}</ul>`
      : '<p>Sin registros adicionales durante la estadía.</p>';
    const html = `
      <p>Hola ${client.name},</p>
      <p><strong>${visit.walkInPet.name}</strong> ya salió de <strong>${profile.companyName ?? 'nuestro local'}</strong>.</p>
      <p>Servicio: ${visit.serviceType} · Duración: ${durationTxt}</p>
      ${eventsHtml}
      ${updated.amountCollected !== null ? `<p>Monto cobrado: Bs ${updated.amountCollected.toFixed(2)}</p>` : ''}
      <p>¡Gracias por confiarnos a ${visit.walkInPet.name}!</p>
    `;
    await notifyWalkInClientEmail(client.email, `${visit.walkInPet.name} ya está de vuelta con vos 🐾`, html);
  }

  return updated;
}

export async function updateWalkInVisit(ownerUserId: string, visitId: string, body: PatchWalkInVisitBody) {
  const profile = await resolveCompanyProfile(ownerUserId);
  const visit = await prisma.walkInVisit.findUnique({ where: { id: visitId } });
  if (!visit || visit.caregiverProfileId !== profile.id) {
    throw new NotFoundError('Visita no encontrada');
  }
  // El espacio físico solo tiene sentido mientras la mascota sigue en el
  // local; el monto cobrado, en cambio, se puede corregir después del
  // check-out (ej. el staff se olvidó de cargarlo en el momento).
  if (body.spaceLabel !== undefined && visit.checkedOutAt !== null) {
    throw new BadRequestError('Esta visita ya finalizó — no se puede reasignar el espacio', 'VISIT_ALREADY_CHECKED_OUT');
  }
  return prisma.walkInVisit.update({
    where: { id: visitId },
    data: {
      ...(body.spaceLabel !== undefined ? { spaceLabel: body.spaceLabel } : {}),
      ...(body.amountCollected !== undefined ? { amountCollected: body.amountCollected } : {}),
    },
  });
}

export async function addVisitEvent(ownerUserId: string, actingUserId: string, visitId: string, body: AddVisitEventBody) {
  const profile = await resolveCompanyProfile(ownerUserId);
  const visit = await prisma.walkInVisit.findUnique({
    where: { id: visitId },
    include: { walkInPet: { include: { walkInClient: true } } },
  });
  if (!visit || visit.caregiverProfileId !== profile.id) {
    throw new NotFoundError('Visita no encontrada');
  }
  if (visit.checkedOutAt !== null) {
    throw new BadRequestError('Esta visita ya finalizó — no se pueden agregar más registros', 'VISIT_ALREADY_CHECKED_OUT');
  }
  if (!ALLOWED_VISIT_EVENT_TYPES.includes(body.type as any)) {
    throw new BadRequestError(`Tipo de evento inválido: ${body.type}`);
  }

  const events = ((visit.events as unknown as WalkInVisitEvent[] | null) ?? []).slice();
  const entry: WalkInVisitEvent = {
    type: body.type,
    note: body.note ?? null,
    photoUrl: body.photoUrl ?? null,
    at: new Date().toISOString(),
    byUserId: actingUserId,
  };
  events.push(entry);

  const updated = await prisma.walkInVisit.update({
    where: { id: visitId },
    data: { events: events as any },
    include: { walkInPet: { include: { walkInClient: true } } },
  });

  const client = updated.walkInPet.walkInClient;
  const petName = updated.walkInPet.name;

  if (body.type === 'PHOTO' && client.email) {
    await notifyWalkInClientEmail(
      client.email,
      `📷 Nueva foto de ${petName}`,
      `<p>Hola ${client.name},</p><p>Tu cuidador subió una foto nueva de <strong>${petName}</strong> durante su estadía en ${profile.companyName ?? 'nuestro local'}.</p>${body.note ? `<p>${body.note}</p>` : ''}${body.photoUrl ? `<p><img src="${body.photoUrl}" alt="${petName}" style="max-width:400px;border-radius:8px" /></p>` : ''}`
    );
  }

  if (body.type === 'INCIDENT') {
    if (client.email) {
      await notifyWalkInClientEmail(
        client.email,
        `🐾 Novedad con ${petName}`,
        `<p>Hola ${client.name},</p><p>Durante la estadía de <strong>${petName}</strong> en ${profile.companyName ?? 'nuestro local'} hubo una novedad. El equipo ya está al tanto y acompañando la situación.</p>${body.note ? `<p>${body.note}</p>` : ''}`
      );
    }
    await prisma.adminNotification.create({
      data: { type: 'WALKIN_INCIDENT', caregiverId: profile.id, bookingId: null },
    }).catch((err) => logger.error('No se pudo crear AdminNotification de incidente walk-in', { error: (err as Error).message }));
  }

  if (body.type === 'INCIDENT_RESOLVED' && client.email) {
    await notifyWalkInClientEmail(
      client.email,
      `✅ ${petName} está bien`,
      `<p>Hola ${client.name},</p><p>La novedad reportada durante la estadía de <strong>${petName}</strong> ya quedó resuelta.</p>`
    );
  }

  return updated;
}

// ── Dashboard de ocupación ────────────────────────────────────────────────────

export interface OccupancyEntry {
  kind: 'BOOKING' | 'WALK_IN';
  id: string;
  petName: string;
  serviceType: 'HOSPEDAJE' | 'GUARDERIA';
  clientName: string;
  since: Date;
  photoUrl: string | null;
}

export interface OccupancyDashboard {
  occupied: number;
  capacity: number;
  overCapacity: boolean;
  entries: OccupancyEntry[];
}

export async function getOccupancyDashboard(ownerUserId: string): Promise<OccupancyDashboard> {
  const profile = await resolveCompanyProfile(ownerUserId);
  const inPremisesTypes: ServiceType[] = [ServiceType.HOSPEDAJE, ServiceType.GUARDERIA];

  const [inProgressBookings, openVisits] = await Promise.all([
    prisma.booking.findMany({
      where: { caregiverId: profile.id, status: BookingStatus.IN_PROGRESS, serviceType: { in: inPremisesTypes } },
      include: { client: { select: { firstName: true, lastName: true } } },
      orderBy: { serviceStartedAt: 'asc' },
    }),
    prisma.walkInVisit.findMany({
      where: { caregiverProfileId: profile.id, checkedOutAt: null, serviceType: { in: inPremisesTypes } },
      include: { walkInPet: { include: { walkInClient: { select: { name: true } } } } },
      orderBy: { checkedInAt: 'asc' },
    }),
  ]);

  const bookingEntries: OccupancyEntry[] = inProgressBookings.map((b) => ({
    kind: 'BOOKING',
    id: b.id,
    petName: b.petName,
    serviceType: b.serviceType as 'HOSPEDAJE' | 'GUARDERIA',
    clientName: `${b.client.firstName} ${b.client.lastName}`,
    since: b.serviceStartedAt ?? b.createdAt,
    photoUrl: b.serviceStartPhoto,
  }));
  const walkInEntries: OccupancyEntry[] = openVisits.map((v) => ({
    kind: 'WALK_IN',
    id: v.id,
    petName: v.walkInPet.name,
    serviceType: v.serviceType as 'HOSPEDAJE' | 'GUARDERIA',
    clientName: v.walkInPet.walkInClient.name,
    since: v.checkedInAt,
    photoUrl: v.walkInPet.photoUrl,
  }));

  const entries = [...bookingEntries, ...walkInEntries].sort((a, b) => a.since.getTime() - b.since.getTime());
  const capacity = combinedHospedajeGuarderiaMax(profile);
  return { occupied: entries.length, capacity, overCapacity: entries.length > capacity, entries };
}

// ── Reportes (solo dueño) ─────────────────────────────────────────────────────

const MAX_REPORT_RANGE_DAYS = 180;

function parseDateRange(from?: string, to?: string): { from: Date; to: Date } {
  const to_ = to ? new Date(to) : new Date();
  const from_ = from ? new Date(from) : new Date(to_.getTime() - 30 * 24 * 60 * 60 * 1000);
  if (isNaN(from_.getTime()) || isNaN(to_.getTime())) {
    throw new BadRequestError('Rango de fechas inválido');
  }
  if (from_ > to_) throw new BadRequestError('"from" no puede ser posterior a "to"');
  // getWalkInOccupancyReport hace un loop día por día — sin tope, un rango de
  // años dispararía cientos de queries secuenciales.
  const rangeDays = (to_.getTime() - from_.getTime()) / (24 * 60 * 60 * 1000);
  if (rangeDays > MAX_REPORT_RANGE_DAYS) {
    throw new BadRequestError(`El rango no puede superar ${MAX_REPORT_RANGE_DAYS} días`);
  }
  return { from: from_, to: to_ };
}

export interface OccupancyReportDay {
  date: string;
  count: number;
}

/** Mismo patrón que el trend de 6 meses en admin.service.ts getFinancialStats:
 * loop por período + conteos vía Prisma (no SQL crudo). Cuenta, por día, cuántas
 * estadías (reservas reales + visitas walk-in) se solapan con ese día — mismo
 * criterio de "quién está en el local" que getOccupancyDashboard. */
export async function getWalkInOccupancyReport(ownerUserId: string, fromStr?: string, toStr?: string) {
  const profile = await resolveCompanyProfile(ownerUserId);
  const { from, to } = parseDateRange(fromStr, toStr);
  const inPremisesTypes: ServiceType[] = [ServiceType.HOSPEDAJE, ServiceType.GUARDERIA];

  const days: OccupancyReportDay[] = [];
  const cursor = new Date(from);
  cursor.setHours(0, 0, 0, 0);
  while (cursor <= to) {
    const dayStart = new Date(cursor);
    const dayEnd = new Date(cursor);
    dayEnd.setHours(23, 59, 59, 999);

    const [visitsCount, bookingsCount] = await Promise.all([
      prisma.walkInVisit.count({
        where: {
          caregiverProfileId: profile.id,
          serviceType: { in: inPremisesTypes },
          checkedInAt: { lte: dayEnd },
          OR: [{ checkedOutAt: null }, { checkedOutAt: { gte: dayStart } }],
        },
      }),
      prisma.booking.count({
        where: {
          caregiverId: profile.id,
          serviceType: { in: inPremisesTypes },
          status: { in: [BookingStatus.IN_PROGRESS, BookingStatus.COMPLETED] },
          serviceStartedAt: { lte: dayEnd },
          OR: [{ serviceEndedAt: null }, { serviceEndedAt: { gte: dayStart } }],
        },
      }),
    ]);

    days.push({ date: dayStart.toISOString().slice(0, 10), count: visitsCount + bookingsCount });
    cursor.setDate(cursor.getDate() + 1);
  }

  const counts = days.map((d) => d.count);
  const peak = days.reduce((best, d) => (d.count > (best?.count ?? -1) ? d : best), null as OccupancyReportDay | null);
  const avg = counts.length ? counts.reduce((a, b) => a + b, 0) / counts.length : 0;
  const capacity = combinedHospedajeGuarderiaMax(profile);

  return { from: from.toISOString().slice(0, 10), to: to.toISOString().slice(0, 10), capacity, avgOccupancy: Math.round(avg * 10) / 10, peakDay: peak, days };
}

/** Cierre de caja walk-in — solo informativo, nunca pasa por User.balance ni
 * comisión Garden (ver doc del módulo). */
export async function getWalkInCashReport(ownerUserId: string, fromStr?: string, toStr?: string) {
  const profile = await resolveCompanyProfile(ownerUserId);
  const { from, to } = parseDateRange(fromStr, toStr);

  const [agg, visits] = await Promise.all([
    prisma.walkInVisit.aggregate({
      where: { caregiverProfileId: profile.id, checkedOutAt: { gte: from, lte: to }, amountCollected: { not: null } },
      _sum: { amountCollected: true },
      _avg: { amountCollected: true },
      _count: { amountCollected: true },
    }),
    prisma.walkInVisit.count({ where: { caregiverProfileId: profile.id, checkedOutAt: { gte: from, lte: to } } }),
  ]);

  return {
    from: from.toISOString().slice(0, 10),
    to: to.toISOString().slice(0, 10),
    totalCollected: agg._sum.amountCollected ?? 0,
    avgCollected: agg._avg.amountCollected ?? 0,
    visitsWithAmount: agg._count.amountCollected,
    totalCheckedOutVisits: visits,
  };
}

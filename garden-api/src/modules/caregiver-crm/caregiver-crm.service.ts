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
import type { z } from 'zod';
import type {
  createWalkInClientBodySchema,
  patchWalkInClientBodySchema,
  createWalkInPetBodySchema,
  patchWalkInPetBodySchema,
} from './caregiver-crm.validation.js';

type CreateWalkInClientBody = z.infer<typeof createWalkInClientBodySchema>;
type PatchWalkInClientBody = z.infer<typeof patchWalkInClientBodySchema>;
type CreateWalkInPetBody = z.infer<typeof createWalkInPetBodySchema>;
type PatchWalkInPetBody = z.infer<typeof patchWalkInPetBodySchema>;

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
  notes?: string
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
      checkedInByUserId: actingUserId,
    },
    include: { walkInPet: { select: { name: true } } },
  });
}

export async function checkOutWalkInVisit(ownerUserId: string, actingUserId: string, visitId: string) {
  const profile = await resolveCompanyProfile(ownerUserId);
  const visit = await prisma.walkInVisit.findUnique({ where: { id: visitId } });
  if (!visit || visit.caregiverProfileId !== profile.id) {
    throw new NotFoundError('Visita no encontrada');
  }
  if (visit.checkedOutAt !== null) {
    throw new BadRequestError('Esta visita ya tiene check-out registrado', 'ALREADY_CHECKED_OUT');
  }
  return prisma.walkInVisit.update({
    where: { id: visitId },
    data: { checkedOutAt: new Date(), checkedOutByUserId: actingUserId },
    include: { walkInPet: { select: { name: true } } },
  });
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

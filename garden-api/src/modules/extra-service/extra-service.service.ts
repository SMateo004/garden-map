/**
 * Servicio: CRUD de servicios extra (ExtraService) para cuidadores tipo empresa.
 * - Solo empresas (CaregiverProfile.isCompany === true) pueden crear/editar por ahora
 *   (validado aquí, no en rutas/modelo, para poder abrirlo a cuidadores individuales después).
 * - Se cobran siempre por día. Editables en cualquier momento.
 */

import prisma from '../../config/database.js';
import { ServiceType } from '@prisma/client';
import { BadRequestError, ForbiddenError, NotFoundError } from '../../shared/errors.js';
import { getCache } from '../../shared/cache.js';
import type { CreateExtraServiceBody, PatchExtraServiceBody } from './extra-service.validation.js';

/** Resuelve el CaregiverProfile del usuario autenticado (o lanza 404). */
async function getCaregiverProfileOrThrow(userId: string) {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { userId },
    select: { id: true, isCompany: true },
  });
  if (!profile) throw new NotFoundError('No tienes perfil de cuidador', 'CAREGIVER_PROFILE_NOT_FOUND');
  return profile;
}

function serializeExtraService(extra: {
  id: string;
  caregiverId: string;
  name: string;
  pricePerDay: unknown;
  appliesTo: ServiceType[];
  active: boolean;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: extra.id,
    caregiverId: extra.caregiverId,
    name: extra.name,
    pricePerDay: Number(extra.pricePerDay),
    appliesTo: extra.appliesTo,
    active: extra.active,
    createdAt: extra.createdAt,
    updatedAt: extra.updatedAt,
  };
}

/** GET / — lista TODOS los extras del cuidador autenticado (activos e inactivos). */
export async function listMyExtraServices(userId: string) {
  const profile = await getCaregiverProfileOrThrow(userId);
  const extras = await prisma.extraService.findMany({
    where: { caregiverId: profile.id },
    orderBy: { createdAt: 'desc' },
  });
  return extras.map(serializeExtraService);
}

/** POST / — crea un ExtraService. Solo empresas. */
export async function createExtraService(userId: string, body: CreateExtraServiceBody) {
  const profile = await getCaregiverProfileOrThrow(userId);
  if (!profile.isCompany) {
    throw new ForbiddenError('Solo las empresas pueden crear servicios extra por ahora', 'EXTRA_SERVICE_COMPANY_ONLY');
  }

  const created = await prisma.extraService.create({
    data: {
      caregiverId: profile.id,
      name: body.name,
      pricePerDay: body.pricePerDay,
      appliesTo: body.appliesTo,
    },
  });

  await getCache().del(`caregivers:detail:${profile.id}`);

  return serializeExtraService(created);
}

/** PATCH /:id — edita name/pricePerDay/appliesTo/active. Valida ownership + isCompany. */
export async function patchExtraService(userId: string, id: string, body: PatchExtraServiceBody) {
  const profile = await getCaregiverProfileOrThrow(userId);
  if (!profile.isCompany) {
    throw new ForbiddenError('Solo las empresas pueden editar servicios extra por ahora', 'EXTRA_SERVICE_COMPANY_ONLY');
  }

  const existing = await prisma.extraService.findUnique({ where: { id } });
  if (!existing || existing.caregiverId !== profile.id) {
    throw new NotFoundError('Servicio extra no encontrado', 'EXTRA_SERVICE_NOT_FOUND');
  }

  const data: {
    name?: string;
    pricePerDay?: number;
    appliesTo?: ServiceType[];
    active?: boolean;
  } = {};
  if (body.name !== undefined) data.name = body.name;
  if (body.pricePerDay !== undefined) data.pricePerDay = body.pricePerDay;
  if (body.appliesTo !== undefined) data.appliesTo = body.appliesTo;
  if (body.active !== undefined) data.active = body.active;

  const updated = await prisma.extraService.update({
    where: { id },
    data,
  });

  await getCache().del(`caregivers:detail:${profile.id}`);

  return serializeExtraService(updated);
}

/** DELETE /:id — valida ownership. Si ya fue usado en una reserva, rechaza (sugiere desactivar). */
export async function deleteExtraService(userId: string, id: string) {
  const profile = await getCaregiverProfileOrThrow(userId);

  const existing = await prisma.extraService.findUnique({ where: { id } });
  if (!existing || existing.caregiverId !== profile.id) {
    throw new NotFoundError('Servicio extra no encontrado', 'EXTRA_SERVICE_NOT_FOUND');
  }

  const usageCount = await prisma.bookingExtra.count({ where: { extraServiceId: id } });
  if (usageCount > 0) {
    throw new BadRequestError(
      'Este servicio ya fue usado en una reserva — desactívalo en vez de eliminarlo',
      'EXTRA_SERVICE_IN_USE'
    );
  }

  await prisma.extraService.delete({ where: { id } });

  await getCache().del(`caregivers:detail:${profile.id}`);

  return { deleted: true };
}

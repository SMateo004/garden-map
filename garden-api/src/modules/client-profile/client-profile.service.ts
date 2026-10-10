import type { Prisma } from '@prisma/client';
import prisma from '../../config/database.js';
import { BadRequestError } from '../../shared/errors.js';
import type { PatchClientProfileBody } from './client-profile.validation.js';
import logger from '../../shared/logger.js';
import { getPricingConfig, resolveCommissionPct, walk30BasePrice } from '../pricing/pricing.service.js';

/**
 * GET /api/client/my-profile - Perfil del cliente con sus mascotas (Pet[]).
 */
export async function getMyProfile(userId: string) {
  const profile = await prisma.clientProfile.findUnique({
    where: { userId },
    include: {
      user: {
        select: {
          id: true,
          email: true,
          firstName: true,
          lastName: true,
          phone: true,
        },
      },
      pets: { orderBy: { createdAt: 'desc' } },
    },
  });

  if (!profile) {
    return null;
  }

  // Respuesta explícita: asegurar que petPhoto y pets[].photoUrl sean strings o null (nunca undefined) para el frontend
  const pets = profile.pets.map((p) => ({
    ...p,
    photoUrl: p.photoUrl ?? null,
  }));
  const out = {
    ...profile,
    petPhoto: profile.petPhoto ?? null,
    pets,
  };
  return out;
}

/**
 * PATCH /api/client/profile - Actualización solo de datos del dueño (address, phone).
 * Las mascotas se gestionan con POST/PATCH /api/client/pets.
 */
export async function patchProfile(userId: string, body: PatchClientProfileBody) {
  const profile = await prisma.clientProfile.findUnique({ where: { userId } });
  if (!profile) {
    throw new BadRequestError('No tienes perfil de cliente', 'CLIENT_PROFILE_NOT_FOUND');
  }

  const data: Prisma.ClientProfileUpdateInput = {
    ...(body.address !== undefined && { address: body.address }),
    // `phone` del body se ignora a propósito: el teléfono real es User.phone, que
    // solo cambia por PATCH /auth/me (si no está verificado) o por el cambio
    // autorizado por soporte. Escribir acá un campo legacy dejaba dos números
    // distintos y sin pasar por la guarda de teléfono verificado.
    // String vacío se guarda como null — permite borrar un NIT/razón social cargado antes.
    ...(body.nit !== undefined && { nit: body.nit.trim() || null }),
    ...(body.nitRazonSocial !== undefined && { nitRazonSocial: body.nitRazonSocial.trim() || null }),
  };

  const updated = await prisma.clientProfile.update({
    where: { id: profile.id },
    data,
  });

  logger.info('ClientProfile actualizado', { userId, profileId: updated.id });

  return {
    profileId: updated.id,
    updatedAt: updated.updatedAt,
  };
}

/**
 * Toggle favorite caregiver status for a client.
 */
export async function toggleFavorite(userId: string, caregiverId: string) {
  const profile = await prisma.clientProfile.findUnique({ where: { userId } });
  if (!profile) {
    throw new BadRequestError('No tienes perfil de cliente', 'CLIENT_PROFILE_NOT_FOUND');
  }

  const isFavorite = profile.favoriteCaregiverIds.includes(caregiverId);
  const newFavorites = isFavorite
    ? profile.favoriteCaregiverIds.filter((id: string) => id !== caregiverId)
    : [...profile.favoriteCaregiverIds, caregiverId];

  await prisma.clientProfile.update({
    where: { id: profile.id },
    data: { favoriteCaregiverIds: newFavorites },
  });

  return { isFavorite: !isFavorite, favoriteCaregiverIds: newFavorites };
}

/**
 * Get the list of favorite caregivers for a client.
 */
export async function getFavorites(userId: string) {
  const profile = await prisma.clientProfile.findUnique({ where: { userId } });
  if (!profile || profile.favoriteCaregiverIds.length === 0) {
    return [];
  }

  const caregivers = await prisma.caregiverProfile.findMany({
    where: {
      id: { in: profile.favoriteCaregiverIds },
      suspended: false,
    },
    include: {
      user: {
        select: {
          firstName: true,
          lastName: true,
          profilePicture: true,
        },
      },
    },
  });

  // Mismo precio que el listado: comisión de Admin > Comisiones por servicio y cuidador.
  const pricing = await getPricingConfig();
  const priced = (price: number | null, service: 'PASEO' | 'HOSPEDAJE' | 'GUARDERIA', caregiverId: string) =>
    price ? Math.round(price * (1 + resolveCommissionPct(pricing, service, caregiverId) / 100)) : null;

  // Map to CaregiverListItem-like format
  return caregivers.map(c => ({
    id: c.id,
    firstName: c.user?.firstName ?? '',
    lastName: c.user?.lastName ?? '',
    profilePicture: c.profilePhoto ?? c.user?.profilePicture ?? null,
    zone: c.zone ?? '',
    rating: c.rating,
    reviewCount: c.reviewCount,
    pricePerDay: priced(c.pricePerDay, 'HOSPEDAJE', c.id),
    pricePerWalk30: priced(walk30BasePrice(c.pricePerWalk30, c.pricePerWalk60), 'PASEO', c.id),
    // Lo mismo que trae el listado del marketplace, para que la app muestre
    // la misma tarjeta (antes faltaban guardería, antecedentes y empresa).
    pricePerWalk60: priced(c.pricePerWalk60, 'PASEO', c.id),
    pricePerGuarderia: priced(c.pricePerGuarderia, 'GUARDERIA', c.id),
    services: c.servicesOffered,
    verified: c.verified,
    antecedentesVerified: (c as any).antecedentesStatus === 'LIMPIO',
    experienceYears: c.experienceYears,
    isCompany: (c as any).isCompany ?? false,
    companyName: (c as any).companyName ?? null,
  }));
}

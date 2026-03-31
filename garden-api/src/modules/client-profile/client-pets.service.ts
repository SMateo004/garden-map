import { PetSize } from '@prisma/client';
import prisma from '../../config/database.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';
import { ensureAbsoluteUrl } from '../../shared/upload-utils.js';
import logger from '../../shared/logger.js';
import type { CreatePetBody, PatchPetBody } from './client-pets.validation.js';
import { blockchainService } from '../../services/blockchain.service.js';

function isPetComplete(p: { name: string; size: PetSize | null; photoUrl: string | null }) {
  return Boolean(p.name && p.size && p.photoUrl);
}

async function recalcProfileIsComplete(
  db: Pick<typeof prisma, 'clientProfile'>,
  profileId: string,
  pets: { name: string; size: PetSize | null; photoUrl: string | null }[]
) {
  const complete = pets.some(isPetComplete);
  const petPhoto = pets.length > 0 ? (pets[0]?.photoUrl ?? null) : null;
  await db.clientProfile.update({
    where: { id: profileId },
    data: { isComplete: complete, petPhoto },
  });
}

export type PetListItem = {
  id: string;
  name: string;
  breed: string | null;
  age: number | null;
  size: PetSize | null;
  photoUrl: string | null;
  specialNeeds: string | null;
  notes: string | null;
  gender: string | null;
  weight: number | null;
  color: string | null;
  sterilized: boolean | null;
  microchipNumber: string | null;
  extraPhotos: string[];
  vaccinePhotos: string[];
  documents: string[];
};

/**
 * Lista todas las mascotas del cliente logueado. Orden: createdAt DESC.
 */
export async function getPetsByUserId(userId: string): Promise<PetListItem[]> {
  const profile = await prisma.clientProfile.findUnique({
    where: { userId },
    select: {
      id: true,
      pets: {
        orderBy: { createdAt: 'desc' },
        select: {
          id: true,
          name: true,
          breed: true,
          age: true,
          size: true,
          photoUrl: true,
          specialNeeds: true,
          notes: true,
          gender: true,
          weight: true,
          color: true,
          sterilized: true,
          microchipNumber: true,
          extraPhotos: true,
          vaccinePhotos: true,
          documents: true,
        },
      },
    },
  });

  if (!profile) return [];
  return profile.pets as PetListItem[];
}

/**
 * Crea una mascota para el cliente. Actualiza isComplete del perfil si la mascota tiene name, size, photoUrl.
 */
export async function createPet(userId: string, body: CreatePetBody): Promise<PetListItem> {
  const profile = await prisma.clientProfile.findUnique({
    where: { userId },
    select: { id: true },
  });
  if (!profile) {
    throw new NotFoundError('No tienes perfil de cliente');
  }

  const photoUrl = ensureAbsoluteUrl(body.photoUrl) ?? null;
  const pet = await prisma.pet.create({
    data: {
      clientProfileId: profile.id,
      name: body.name,
      breed: body.breed ?? null,
      age: body.age ?? null,
      size: body.size ?? null,
      photoUrl,
      specialNeeds: body.specialNeeds ?? null,
      notes: body.notes ?? null,
      gender: body.gender ?? null,
      weight: body.weight ?? null,
      color: body.color ?? null,
      sterilized: body.sterilized ?? null,
      microchipNumber: body.microchipNumber ?? null,
      extraPhotos: body.extraPhotos ?? [],
      vaccinePhotos: body.vaccinePhotos ?? [],
      documents: body.documents ?? [],
    },
  });

  const allPets = await prisma.pet.findMany({
    where: { clientProfileId: profile.id },
    orderBy: { createdAt: 'desc' },
    select: { name: true, size: true, photoUrl: true },
  });
  await recalcProfileIsComplete(prisma, profile.id, allPets);

  // Sync pet to Blockchain (Creative touch)
  blockchainService.addPetOnChain(
    userId,
    pet.name,
    pet.breed || 'Mestizo'
  ).catch(err => logger.error('Blockchain pet sync failed', { userId, petName: pet.name, err }));

  if (photoUrl) {
    logger.info('Foto subida y guardada', { url: photoUrl, field: 'petPhoto', userId });
  }
  logger.info('Perfil actualizado con mascota (crear)', {
    userId,
    petId: pet.id,
    hasPhotoUrl: Boolean(pet.photoUrl),
  });
  return {
    id: pet.id,
    name: pet.name,
    breed: pet.breed,
    age: pet.age,
    size: pet.size,
    photoUrl: pet.photoUrl,
    specialNeeds: pet.specialNeeds,
    notes: pet.notes ?? null,
    gender: pet.gender ?? null,
    weight: pet.weight ?? null,
    color: pet.color ?? null,
    sterilized: pet.sterilized ?? null,
    microchipNumber: pet.microchipNumber ?? null,
    extraPhotos: pet.extraPhotos ?? [],
    vaccinePhotos: pet.vaccinePhotos ?? [],
    documents: pet.documents ?? [],
  };
}

/**
 * Actualiza una mascota. Valida que pertenezca al cliente. Recalcula isComplete del perfil.
 */
export async function updatePet(
  userId: string,
  petId: string,
  body: PatchPetBody
): Promise<PetListItem> {
  const profile = await prisma.clientProfile.findUnique({
    where: { userId },
    select: { id: true },
  });
  if (!profile) {
    throw new NotFoundError('No tienes perfil de cliente');
  }

  const pet = await prisma.pet.findFirst({
    where: { id: petId, clientProfileId: profile.id },
  });
  if (!pet) {
    throw new BadRequestError('Mascota no pertenece al usuario', 'PET_NOT_OWNED');
  }

  const photoUrlValue =
    body.photoUrl !== undefined ? ensureAbsoluteUrl(body.photoUrl) ?? null : undefined;
  const updated = await prisma.pet.update({
    where: { id: petId },
    data: {
      ...(body.name !== undefined && { name: body.name }),
      ...(body.breed !== undefined && { breed: body.breed }),
      ...(body.age !== undefined && { age: body.age }),
      ...(body.size !== undefined && { size: body.size }),
      ...(photoUrlValue !== undefined && { photoUrl: photoUrlValue }),
      ...(body.specialNeeds !== undefined && { specialNeeds: body.specialNeeds }),
      ...(body.notes !== undefined && { notes: body.notes }),
      ...(body.gender !== undefined && { gender: body.gender }),
      ...(body.weight !== undefined && { weight: body.weight }),
      ...(body.color !== undefined && { color: body.color }),
      ...(body.sterilized !== undefined && { sterilized: body.sterilized }),
      ...(body.microchipNumber !== undefined && { microchipNumber: body.microchipNumber }),
      ...(body.extraPhotos !== undefined && { extraPhotos: body.extraPhotos }),
      ...(body.vaccinePhotos !== undefined && { vaccinePhotos: body.vaccinePhotos }),
      ...(body.documents !== undefined && { documents: body.documents }),
    },
  });

  const allPets = await prisma.pet.findMany({
    where: { clientProfileId: profile.id },
    orderBy: { createdAt: 'desc' },
    select: { name: true, size: true, photoUrl: true },
  });
  await recalcProfileIsComplete(prisma, profile.id, allPets);

  if (photoUrlValue !== undefined && photoUrlValue) {
    logger.info('Foto subida y guardada', { url: photoUrlValue, field: 'petPhoto', userId });
  }
  logger.info('Perfil actualizado con mascota (editar)', {
    userId,
    petId,
    hasPhotoUrl: body.photoUrl !== undefined,
  });

  return {
    id: updated.id,
    name: updated.name,
    breed: updated.breed,
    age: updated.age,
    size: updated.size,
    photoUrl: updated.photoUrl,
    specialNeeds: updated.specialNeeds,
    notes: updated.notes,
    gender: updated.gender ?? null,
    weight: updated.weight ?? null,
    color: updated.color ?? null,
    sterilized: updated.sterilized ?? null,
    microchipNumber: updated.microchipNumber ?? null,
    extraPhotos: updated.extraPhotos ?? [],
    vaccinePhotos: updated.vaccinePhotos ?? [],
    documents: updated.documents ?? [],
  };
}

/**
 * Elimina una mascota. Valida que pertenezca al cliente. Recalcula isComplete del perfil.
 */
export async function deletePet(userId: string, petId: string): Promise<void> {
  const profile = await prisma.clientProfile.findUnique({
    where: { userId },
    select: { id: true },
  });
  if (!profile) throw new NotFoundError('No tienes perfil de cliente');

  const pet = await prisma.pet.findFirst({
    where: { id: petId, clientProfileId: profile.id },
  });
  if (!pet) throw new BadRequestError('Mascota no pertenece al usuario', 'PET_NOT_OWNED');

  await prisma.pet.delete({ where: { id: petId } });

  const allPets = await prisma.pet.findMany({
    where: { clientProfileId: profile.id },
    orderBy: { createdAt: 'desc' },
    select: { name: true, size: true, photoUrl: true },
  });
  await recalcProfileIsComplete(prisma, profile.id, allPets);
}

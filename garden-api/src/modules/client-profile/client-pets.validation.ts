import { z } from 'zod';
import { PetSize } from '@prisma/client';

const petGender = z.enum(['MALE', 'FEMALE']).optional();
// Solo DOGS/CATS tienen sentido como especie de una mascota — el enum
// AnimalType de Prisma también incluye valores usados por CaregiverProfile
// (PUPPIES, SENIORS, LARGE, SMALL, SPECIAL) que no aplican aquí.
const petAnimalType = z.enum(['DOGS', 'CATS']).optional();

export const createPetBodySchema = z
  .object({
    name: z.string().min(1, 'Nombre requerido').max(200),
    breed: z.string().max(100).optional(),
    age: z.number().int().min(0).max(30).optional(),
    size: z.nativeEnum(PetSize).optional(),
    animalType: petAnimalType,
    isAggressive: z.boolean().optional(),
    photoUrl: z.string().url().optional(),
    specialNeeds: z.string().max(2000).optional(),
    notes: z.string().max(2000).optional(),
    gender: petGender,
    weight: z.number().min(0).max(200).optional(),
    color: z.string().max(100).optional(),
    sterilized: z.boolean().optional(),
    microchipNumber: z.string().max(50).optional(),
    extraPhotos: z.array(z.string().url()).max(6).optional(),
    vaccinePhotos: z.array(z.string().url()).max(6).optional(),
    documents: z.array(z.string().url()).max(6).optional(),
  })
  .strict();

export type CreatePetBody = z.infer<typeof createPetBodySchema>;

export const patchPetBodySchema = z
  .object({
    name: z.string().min(1).max(200).optional(),
    breed: z.string().max(100).optional(),
    age: z.number().int().min(0).max(30).optional(),
    size: z.nativeEnum(PetSize).optional(),
    animalType: petAnimalType,
    isAggressive: z.boolean().optional(),
    photoUrl: z.string().url().optional(),
    specialNeeds: z.string().max(2000).optional(),
    notes: z.string().max(2000).optional(),
    gender: petGender,
    weight: z.number().min(0).max(200).optional(),
    color: z.string().max(100).optional(),
    sterilized: z.boolean().optional(),
    microchipNumber: z.string().max(50).optional(),
    extraPhotos: z.array(z.string().url()).max(6).optional(),
    vaccinePhotos: z.array(z.string().url()).max(6).optional(),
    documents: z.array(z.string().url()).max(6).optional(),
  })
  .strict();

export type PatchPetBody = z.infer<typeof patchPetBodySchema>;

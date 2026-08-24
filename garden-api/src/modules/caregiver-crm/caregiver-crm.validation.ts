import { z } from 'zod';
import { PetSize, ServiceType } from '@prisma/client';

export const createWalkInClientBodySchema = z.object({
  name: z.string().min(1, 'Nombre requerido').max(200),
  // Sin regex estricto a propósito — un walk-in puede traer un fijo, un
  // número extranjero, o nada.
  phone: z.string().max(30).optional(),
  email: z.string().email('Email inválido').optional(),
  notes: z.string().max(2000).optional(),
}).strict();

export const patchWalkInClientBodySchema = createWalkInClientBodySchema.partial();

const petGender = z.enum(['MALE', 'FEMALE']).optional();
const petAnimalType = z.enum(['DOGS', 'CATS']).optional();

// Copiado literal de createPetBodySchema (client-pets.validation.ts) — mismo
// set de campos, mismas constraints; solo cambia el FK (viene del :clientId
// de la URL, no del body).
export const createWalkInPetBodySchema = z.object({
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
}).strict();

export const patchWalkInPetBodySchema = createWalkInPetBodySchema.partial().strict();

export const checkInBodySchema = z.object({
  // Requerido — decide si la visita cuenta para el cupo combinado
  // Hospedaje+Guardería (Paseo es fuera del local, no cuenta).
  serviceType: z.nativeEnum(ServiceType),
  notes: z.string().max(500).optional(),
}).strict();

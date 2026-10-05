import { z } from 'zod';
import { PetSize, ServiceType } from '@prisma/client';

// Vacío = sin dato (null). Antes la app mandaba email: '' al editar un
// cliente sin correo y el servidor respondía "Email inválido": ninguna
// edición de esos clientes se podía guardar, y borrar un dato era imposible.
const blankToNull = (v: unknown) => (typeof v === 'string' ? v.trim() || null : v);

export const createWalkInClientBodySchema = z.object({
  name: z.string().trim().min(1, 'Escribe el nombre del cliente').max(200),
  // Sin regex estricto a propósito — un walk-in puede traer un fijo, un
  // número extranjero, o nada.
  phone: z.preprocess(blankToNull, z.string().max(30, 'Revisa el teléfono: es demasiado largo').nullable().optional()),
  email: z.preprocess(blankToNull, z.string().email('Revisa el correo del cliente').max(200).nullable().optional()),
  notes: z.preprocess(blankToNull, z.string().max(2000, 'Las notas pueden tener hasta 2000 caracteres').nullable().optional()),
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

// Al editar, los datos opcionales aceptan null para poder BORRARLOS (con
// .partial() la app no tenía forma de quitar una raza o un peso ya cargado).
export const patchWalkInPetBodySchema = z.object({
  name: z.string().trim().min(1, 'Nombre requerido').max(200).optional(),
  breed: z.string().max(100).nullable().optional(),
  age: z.number().int().min(0).max(30).nullable().optional(),
  size: z.nativeEnum(PetSize).nullable().optional(),
  animalType: z.enum(['DOGS', 'CATS']).nullable().optional(),
  isAggressive: z.boolean().optional(),
  photoUrl: z.string().url().nullable().optional(),
  specialNeeds: z.string().max(2000).nullable().optional(),
  notes: z.string().max(2000).nullable().optional(),
  gender: z.enum(['MALE', 'FEMALE']).nullable().optional(),
  weight: z.number().positive().max(200).nullable().optional(),
  color: z.string().max(100).nullable().optional(),
  sterilized: z.boolean().nullable().optional(),
  microchipNumber: z.string().max(50).nullable().optional(),
  extraPhotos: z.array(z.string().url()).max(6).optional(),
  vaccinePhotos: z.array(z.string().url()).max(6).optional(),
  documents: z.array(z.string().url()).max(6).optional(),
}).strict();

export const checkInBodySchema = z.object({
  // Requerido — decide si la visita cuenta para el cupo combinado
  // Hospedaje+Guardería (Paseo es fuera del local, no cuenta).
  serviceType: z.nativeEnum(ServiceType),
  notes: z.string().max(500).optional(),
  spaceLabel: z.string().max(50).optional(),
}).strict();

export const checkOutBodySchema = z.object({
  amountCollected: z.number().min(0).max(100000).optional(),
}).strict();

export const patchWalkInVisitBodySchema = z.object({
  spaceLabel: z.string().max(50).optional(),
  amountCollected: z.number().min(0).max(100000).optional(),
}).strict();

const visitEventType = z.enum(['FEEDING', 'WALK', 'MEDICATION', 'BATH', 'NOTE', 'PHOTO', 'INCIDENT', 'INCIDENT_RESOLVED']);

// INCIDENT sin descripción no sirve de nada — es lo único que ve el dueño y
// el admin. PHOTO sin foto tampoco tiene sentido (para eso está NOTE). El
// resto de la bitácora (FEEDING/WALK/MEDICATION/BATH/NOTE) puede quedar sin
// nota — a veces solo importa marcar que pasó.
export const addVisitEventBodySchema = z.object({
  type: visitEventType,
  note: z.string().max(1000).optional(),
  photoUrl: z.string().url().optional(),
}).strict()
  .refine((data) => data.type !== 'INCIDENT' || !!data.note?.trim(), { message: 'Describí qué pasó', path: ['note'] })
  .refine((data) => data.type !== 'PHOTO' || !!data.photoUrl, { message: 'Se requiere una foto', path: ['photoUrl'] });

export const occupancyReportQuerySchema = z.object({
  from: z.string().optional(),
  to: z.string().optional(),
}).strict();

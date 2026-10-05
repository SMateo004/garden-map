import { z } from 'zod';
import { PetSize } from '@prisma/client';

const petGender = z.enum(['MALE', 'FEMALE']).optional();
// Solo DOGS/CATS tienen sentido como especie de una mascota — el enum
// AnimalType de Prisma también incluye valores usados por CaregiverProfile
// (PUPPIES, SENIORS, LARGE, SMALL, SPECIAL) que no aplican aquí.

// Especie y tamaño son obligatorios al crear: la reserva los compara con lo
// que acepta cada cuidador (animalTypes / sizesAccepted). Antes eran
// opcionales y una mascota sin especie pasaba ese filtro sin validarse.
const name = z.string().trim().min(1, 'Escribe el nombre de tu mascota').max(200);
const age = z.number().int().min(0, 'La edad no puede ser negativa').max(30, 'Revisa la edad: máximo 30 años');
const weight = z.number().positive('El peso debe ser mayor a 0').max(200, 'Revisa el peso: máximo 200 kg');

const createFields = {
  name,
  breed: z.string().trim().max(100).optional(),
  age: age.optional(),
  size: z.nativeEnum(PetSize, { errorMap: () => ({ message: 'Elige el tamaño de tu mascota' }) }),
  animalType: z.enum(['DOGS', 'CATS'], { errorMap: () => ({ message: 'Elige si es perro o gato' }) }),
  isAggressive: z.boolean().optional(),
  photoUrl: z.string().url().optional(),
  specialNeeds: z.string().max(2000).optional(),
  notes: z.string().max(2000).optional(),
  gender: petGender,
  weight: weight.optional(),
  color: z.string().max(100).optional(),
  sterilized: z.boolean().optional(),
  microchipNumber: z.string().max(50).optional(),
  extraPhotos: z.array(z.string().url()).max(6).optional(),
  vaccinePhotos: z.array(z.string().url()).max(6).optional(),
  documents: z.array(z.string().url()).max(6).optional(),
};

export const createPetBodySchema = z.object(createFields).strict();

export type CreatePetBody = z.infer<typeof createPetBodySchema>;

// Al editar, los datos opcionales aceptan null: así el dueño puede BORRAR un
// dato (antes la app no lo mandaba y quedaba el valor viejo). Nombre,
// especie y tamaño no se pueden borrar, solo cambiar.
export const patchPetBodySchema = z
  .object({
    name: name.optional(),
    breed: z.string().trim().max(100).nullable().optional(),
    age: age.nullable().optional(),
    size: z.nativeEnum(PetSize).optional(),
    animalType: z.enum(['DOGS', 'CATS']).optional(),
    isAggressive: z.boolean().optional(),
    photoUrl: z.string().url().nullable().optional(),
    specialNeeds: z.string().max(2000).nullable().optional(),
    notes: z.string().max(2000).nullable().optional(),
    gender: z.enum(['MALE', 'FEMALE']).nullable().optional(),
    weight: weight.nullable().optional(),
    color: z.string().max(100).nullable().optional(),
    sterilized: z.boolean().nullable().optional(),
    microchipNumber: z.string().max(50).nullable().optional(),
    extraPhotos: z.array(z.string().url()).max(6).optional(),
    vaccinePhotos: z.array(z.string().url()).max(6).optional(),
    documents: z.array(z.string().url()).max(6).optional(),
  })
  .strict();

export type PatchPetBody = z.infer<typeof patchPetBodySchema>;

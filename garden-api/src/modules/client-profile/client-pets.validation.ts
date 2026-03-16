import { z } from 'zod';
import { PetSize } from '@prisma/client';

export const createPetBodySchema = z
  .object({
    name: z.string().min(1, 'Nombre requerido').max(200),
    breed: z.string().max(100).optional(),
    age: z.number().int().min(0).max(30).optional(),
    size: z.nativeEnum(PetSize).optional(),
    photoUrl: z.string().url().optional(),
    specialNeeds: z.string().max(2000).optional(),
    notes: z.string().max(2000).optional(),
  })
  .strict();

export type CreatePetBody = z.infer<typeof createPetBodySchema>;

export const patchPetBodySchema = z
  .object({
    name: z.string().min(1).max(200).optional(),
    breed: z.string().max(100).optional(),
    age: z.number().int().min(0).max(30).optional(),
    size: z.nativeEnum(PetSize).optional(),
    photoUrl: z.string().url().optional(),
    specialNeeds: z.string().max(2000).optional(),
    notes: z.string().max(2000).optional(),
  })
  .strict();

export type PatchPetBody = z.infer<typeof patchPetBodySchema>;

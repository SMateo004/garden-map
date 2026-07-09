/**
 * Validación (Zod) para el CRUD de servicios extra (ExtraService).
 * - create: name, pricePerDay, appliesTo obligatorios.
 * - patch: todos los campos opcionales (allowlist manual en el controller).
 */

import { z } from 'zod';
import { ServiceType } from '@prisma/client';

export const createExtraServiceSchema = z.object({
  name: z.string().trim().min(1, 'El nombre es requerido').max(100, 'Máximo 100 caracteres'),
  pricePerDay: z.number({ invalid_type_error: 'pricePerDay debe ser un número' }).positive('pricePerDay debe ser mayor a 0'),
  appliesTo: z.array(z.nativeEnum(ServiceType), { invalid_type_error: 'appliesTo debe ser un array de ServiceType' })
    .min(1, 'appliesTo no puede estar vacío'),
});

export type CreateExtraServiceBody = z.infer<typeof createExtraServiceSchema>;

export const patchExtraServiceSchema = z.object({
  name: z.string().trim().min(1, 'El nombre es requerido').max(100, 'Máximo 100 caracteres').optional(),
  pricePerDay: z.number({ invalid_type_error: 'pricePerDay debe ser un número' }).positive('pricePerDay debe ser mayor a 0').optional(),
  appliesTo: z.array(z.nativeEnum(ServiceType)).min(1, 'appliesTo no puede estar vacío').optional(),
  active: z.boolean().optional(),
});

export type PatchExtraServiceBody = z.infer<typeof patchExtraServiceSchema>;

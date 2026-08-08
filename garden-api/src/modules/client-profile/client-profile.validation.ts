import { z } from 'zod';

/**
 * Validación para actualización de perfil de cliente (solo datos del dueño).
 * Las mascotas se gestionan en /api/client/pets.
 */
export const patchClientProfileSchema = z
  .object({
    address: z.string().max(500).optional(),
    phone: z.string().max(20).optional(),
    // NIT boliviano — solo dígitos. String vacío se acepta y se guarda como
    // null (permite borrar un NIT cargado antes).
    nit: z
      .string()
      .max(20)
      .regex(/^\d*$/, 'El NIT solo puede contener números')
      .optional(),
    nitRazonSocial: z.string().max(200).optional(),
  })
  .strict();

export type PatchClientProfileBody = z.infer<typeof patchClientProfileSchema>;

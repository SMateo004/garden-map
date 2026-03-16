import { z } from 'zod';

/**
 * Validación para actualización de perfil de cliente (solo datos del dueño).
 * Las mascotas se gestionan en /api/client/pets.
 */
export const patchClientProfileSchema = z
  .object({
    address: z.string().max(500).optional(),
    phone: z.string().max(20).optional(),
  })
  .strict();

export type PatchClientProfileBody = z.infer<typeof patchClientProfileSchema>;

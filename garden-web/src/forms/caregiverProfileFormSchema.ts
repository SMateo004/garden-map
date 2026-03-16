import { z } from 'zod';
import { ZONES } from '@/types/caregiver';

const MAX_BIO = 500;

export const caregiverProfileFormSchema = z.object({
  bio: z
    .string()
    .min(1, 'La descripción es obligatoria')
    .max(MAX_BIO, `Máximo ${MAX_BIO} caracteres`),
  zone: z
    .union([z.enum(ZONES as [string, ...string[]]), z.literal('')])
    .refine((v) => v !== '', { message: 'Elige una zona' }),
  spaceType: z
    .array(z.enum(['Casa con patio', 'Casa sin patio', 'Departamento pequeño', 'Departamento amplio']))
    .optional(),
  servicesOffered: z
    .array(z.enum(['HOSPEDAJE', 'PASEO']))
    .min(1, 'Elige al menos un servicio'),
  pricePerDay: z.number().int().min(0).optional().nullable(),
  pricePerWalk30: z.number().int().min(0).optional().nullable(),
  pricePerWalk60: z.number().int().min(0).optional().nullable(),
});

export type CaregiverProfileFormValues = z.infer<typeof caregiverProfileFormSchema>;

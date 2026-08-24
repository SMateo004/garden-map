import { z } from 'zod';
import { strongPasswordSchema, phoneCaregiverSchema } from '../auth/auth.validation.js';

export const createInviteBodySchema = z.object({
  label: z.string().max(100).optional(),
  /** Días de vigencia del código — default 7, tope 30 para no dejar códigos eternos sueltos. */
  expiresInDays: z.number().int().min(1).max(30).optional(),
});

export const registerStaffBodySchema = z.object({
  code: z.string().min(1, 'Código de invitación requerido'),
  email: z.string().email('Email inválido'),
  password: strongPasswordSchema,
  phone: phoneCaregiverSchema,
  firstName: z.string().min(1, 'Nombre requerido').max(100),
  lastName: z.string().min(1, 'Apellido requerido').max(100),
});

export const removalReasonBodySchema = z.object({
  reason: z.string().max(300).optional(),
});

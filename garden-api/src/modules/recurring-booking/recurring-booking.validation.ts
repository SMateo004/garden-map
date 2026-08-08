import { z } from 'zod';

/** POST /api/recurring-bookings — crear serie de paseos recurrentes.
 * v1: solo PASEO (ver comentario en el schema de Prisma). */
export const createRecurringSeriesSchema = z
  .object({
    caregiverId: z.string().uuid('caregiverId inválido'),
    petIds: z
      .array(z.string().uuid('petId inválido'))
      .min(1, 'Debes seleccionar al menos una mascota')
      .max(3, 'Máximo 3 mascotas por reserva'),
    daysOfWeek: z
      .array(z.number().int().min(1).max(7))
      .min(1, 'Elegí al menos un día de la semana')
      .max(7)
      .transform((arr) => [...new Set(arr)].sort((a, b) => a - b)),
    timeSlot: z
      .enum(['MANANA', 'TARDE', 'NOCHE'], {
        errorMap: () => ({ message: 'timeSlot debe ser MANANA, TARDE o NOCHE' }),
      })
      .optional(),
    startTime: z.string().regex(/^\d{2}:\d{2}$/, 'startTime formato HH:mm').optional(),
    duration: z.coerce
      .number()
      .int()
      .min(30)
      .max(240)
      .refine((n) => n % 30 === 0, { message: 'La duración debe ser múltiplo de 30 minutos' }),
  })
  .refine((data) => !!data.timeSlot || !!data.startTime, {
    message: 'Debes indicar timeSlot o startTime',
    path: ['timeSlot'],
  });

export type CreateRecurringSeriesBody = z.infer<typeof createRecurringSeriesSchema>;

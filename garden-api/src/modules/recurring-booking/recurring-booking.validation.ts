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
      .min(1, 'Elige al menos un día de la semana')
      .max(7)
      .transform((arr) => [...new Set(arr)].sort((a, b) => a - b)),
    timeSlot: z
      .enum(['MANANA', 'TARDE', 'NOCHE'], {
        errorMap: () => ({ message: 'timeSlot debe ser MANANA, TARDE o NOCHE' }),
      })
      .optional(),
    startTime: z.string().regex(/^\d{2}:\d{2}$/, 'startTime formato HH:mm').optional(),
    // Solo 30 o 60 min: son los dos precios que fija el cuidador (walk30BasePrice / pricePerWalk60).
    // Antes se aceptaba hasta 240 min y todo lo que no era 30 se cobraba al precio de 60.
    duration: z.coerce
      .number()
      .int()
      .refine((n): boolean => n === 30 || n === 60, { message: 'El paseo dura 30 o 60 minutos' }),
  })
  .refine((data) => !!data.timeSlot || !!data.startTime, {
    message: 'Debes indicar timeSlot o startTime',
    path: ['timeSlot'],
  });

export type CreateRecurringSeriesBody = z.infer<typeof createRecurringSeriesSchema>;

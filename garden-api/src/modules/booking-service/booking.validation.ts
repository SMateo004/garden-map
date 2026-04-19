import { z } from 'zod';

const dateOnlyRegex = /^\d{4}-\d{2}-\d{2}$/;

/** Solo serviceType para el primer paso: errores claros en el discriminador. */
const serviceTypeSchema = z.object({
  serviceType: z.enum(['HOSPEDAJE', 'PASEO'], {
    required_error: 'Debes seleccionar HOSPEDAJE o PASEO como tipo de servicio',
    invalid_type_error: 'serviceType debe ser HOSPEDAJE o PASEO',
  }),
});

/** Schema completo para hospedaje. */
export const hospedajeSchema = z.object({
  serviceType: z.literal('HOSPEDAJE'),
  caregiverId: z.string().uuid('caregiverId inválido'),
  petId: z.string().uuid('petId inválido'),
  startDate: z.string().regex(dateOnlyRegex, 'startDate: formato YYYY-MM-DD'),
  endDate: z.string().regex(dateOnlyRegex, 'endDate: formato YYYY-MM-DD'),
  totalDays: z.coerce.number().int().min(1).max(90),
});

/** Schema completo para paseo. duration se coerce para aceptar "30" / "60" etc. del form. */
export const paseoSchema = z.object({
  serviceType: z.literal('PASEO'),
  caregiverId: z.string().uuid('caregiverId inválido'),
  petId: z.string().uuid('petId inválido'),
  walkDate: z.string().regex(dateOnlyRegex, 'walkDate: formato YYYY-MM-DD'),
  timeSlot: z.enum(['MANANA', 'TARDE', 'NOCHE'], {
    errorMap: () => ({ message: 'timeSlot debe ser MANANA, TARDE o NOCHE' }),
  }),
  startTime: z.string().regex(/^\d{2}:\d{2}$/, 'startTime formato HH:mm').optional(),
  duration: z.coerce.number().int().min(30).max(240).refine(n => n % 30 === 0, {
    message: 'La duración debe ser múltiplo de 30 minutos',
  }),
});

export type CreateBookingBody = z.infer<typeof hospedajeSchema> | z.infer<typeof paseoSchema>;

/**
 * Validación en dos pasos: primero serviceType, luego el subesquema correspondiente.
 * Así siempre obtenemos errores por campo (duration, walkDate, timeSlot, petId, etc.)
 * y nunca el mensaje genérico del union.
 */
export function parseCreateBookingBody(data: unknown): CreateBookingBody {
  const first = serviceTypeSchema.safeParse(data);
  if (!first.success) {
    throw first.error;
  }

  const { serviceType } = first.data;

  if (serviceType === 'HOSPEDAJE') {
    const result = hospedajeSchema.safeParse(data);
    if (!result.success) {
      throw result.error;
    }
    return result.data;
  }

  const result = paseoSchema.safeParse(data);
  if (!result.success) {
    throw result.error;
  }
  return result.data;
}

/** POST /api/bookings/:id/cancel — motivo opcional. */
export const cancelBookingBodySchema = z.object({
  reason: z.string().max(2000).optional(),
});

/** POST /api/bookings/:id/extend — nueva fecha de salida (hospedaje). */
export const extendBookingBodySchema = z.object({
  newEndDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'newEndDate formato YYYY-MM-DD'),
});

/** POST /api/bookings/:id/change-dates — nuevas fechas (hospedaje). Mín 48h. */
export const changeDatesBookingBodySchema = z
  .object({
    newStartDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'newStartDate formato YYYY-MM-DD'),
    newEndDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'newEndDate formato YYYY-MM-DD'),
  })
  .refine(
    (data) => {
      const start = new Date(data.newStartDate);
      const end = new Date(data.newEndDate);
      return end > start && (end.getTime() - start.getTime()) >= 2 * 24 * 60 * 60 * 1000;
    },
    { message: 'Hospedaje: mínimo 48 horas entre check-in y check-out', path: ['newEndDate'] }
  );

/** POST /api/bookings/:id/payment — iniciar pago. */
export const initPaymentBodySchema = z.object({
  method: z.enum(['qr', 'manual'], {
    required_error: 'method es requerido (qr | manual)',
    invalid_type_error: 'method debe ser "qr" o "manual"',
  }),
});

export type InitPaymentBody = z.infer<typeof initPaymentBodySchema>;

/** POST /api/bookings/:id/cancellation-request — cuidador solicita cancelación. */
export const cancellationRequestBodySchema = z.object({
  reason: z.string().min(1, 'El motivo es obligatorio').max(2000, 'Máximo 2000 caracteres'),
});

export type CancellationRequestBody = z.infer<typeof cancellationRequestBodySchema>;

/** POST /api/bookings/:id/request-extension-payment — inicia pago de extensión de paseo. */
export const requestExtensionPaymentBodySchema = z.object({
  additionalMinutes: z.number().int().refine((n) => [15, 30, 60].includes(n), {
    message: 'additionalMinutes debe ser 15, 30 o 60',
  }),
  method: z.enum(['qr', 'manual'], { required_error: 'method es requerido (qr | manual)' }),
});

/** POST /api/bookings/:id/confirm-extension-qr — confirma pago QR de extensión. */
export const confirmExtensionQrBodySchema = z.object({
  qrId: z.string().min(1, 'qrId requerido'),
});

/** POST /api/bookings/:id/extend-paseo — cliente solicita extensión de paseo en curso. */
export const extendPaseoBodySchema = z.object({
  additionalMinutes: z.number().int().refine((n) => [15, 30, 60].includes(n), {
    message: 'additionalMinutes debe ser 15, 30 o 60',
  }),
});

export type ExtendPaseoBody = z.infer<typeof extendPaseoBodySchema>;

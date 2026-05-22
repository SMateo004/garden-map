import { z } from 'zod';

const dateOnlyRegex = /^\d{4}-\d{2}-\d{2}$/;

/** Solo serviceType para el primer paso: errores claros en el discriminador. */
const serviceTypeSchema = z.object({
  serviceType: z.enum(['HOSPEDAJE', 'PASEO', 'GUARDERIA'], {
    required_error: 'Debes seleccionar HOSPEDAJE, PASEO o GUARDERIA como tipo de servicio',
    invalid_type_error: 'serviceType debe ser HOSPEDAJE, PASEO o GUARDERIA',
  }),
});

/** Schema completo para hospedaje. */
export const hospedajeSchema = z
  .object({
    serviceType: z.literal('HOSPEDAJE'),
    caregiverId: z.string().uuid('caregiverId inválido'),
    petId: z.string().uuid('petId inválido'),
    startDate: z.string().regex(dateOnlyRegex, 'startDate: formato YYYY-MM-DD'),
    endDate: z.string().regex(dateOnlyRegex, 'endDate: formato YYYY-MM-DD'),
    // totalDays is accepted from the client for UX purposes but ALWAYS recomputed
    // server-side in booking.service.ts — never trusted for pricing.
    totalDays: z.coerce.number().int().min(1).max(90).optional(),
  })
  .refine(
    (data) => {
      const start = new Date(data.startDate);
      const end = new Date(data.endDate);
      const diffMs = end.getTime() - start.getTime();
      // Minimum 2 full days (48h) between check-in and check-out
      return diffMs >= 2 * 24 * 60 * 60 * 1000;
    },
    {
      message: 'La fecha de salida debe ser al menos 2 días después del check-in (mínimo 48 horas)',
      path: ['endDate'],
    }
  );

/** Schema para un día individual dentro de una reserva multi-día de paseo. */
const walkDaySchema = z.object({
  date: z.string().regex(dateOnlyRegex, 'date: formato YYYY-MM-DD'),
  timeSlot: z.enum(['MANANA', 'TARDE', 'NOCHE'], {
    errorMap: () => ({ message: 'timeSlot debe ser MANANA, TARDE o NOCHE' }),
  }),
  startTime: z.string().regex(/^\d{2}:\d{2}$/, 'startTime formato HH:mm').optional(),
});

export type WalkDay = z.infer<typeof walkDaySchema>;

/**
 * Schema completo para paseo. Acepta dos modos:
 * - Single day: walkDate + timeSlot (comportamiento original)
 * - Multi-day: walkDays (array de días con sus slots)
 */
export const paseoSchema = z
  .object({
    serviceType: z.literal('PASEO'),
    caregiverId: z.string().uuid('caregiverId inválido'),
    petId: z.string().uuid('petId inválido'),
    // Single-day fields (opcionales cuando se usa walkDays)
    walkDate: z.string().regex(dateOnlyRegex, 'walkDate: formato YYYY-MM-DD').optional(),
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
    // Multi-day field
    walkDays: z
      .array(walkDaySchema)
      .min(1, 'walkDays debe tener al menos 1 día')
      .max(30, 'Máximo 30 días por reserva')
      .optional(),
  })
  .refine(
    (data) => {
      // Debe tener walkDate+timeSlot (single) O walkDays (multi), no puede ser ambos ausentes
      const hasSingle = !!data.walkDate && !!data.timeSlot;
      const hasMulti = !!data.walkDays && data.walkDays.length > 0;
      return hasSingle || hasMulti;
    },
    {
      message:
        'Debes proporcionar walkDate+timeSlot para reserva de un día, o walkDays para múltiples días',
      path: ['walkDate'],
    }
  );

/** Schema completo para guardería (igual que paseo single-day pero con duración fija). */
export const guarderiaSchema = z.object({
  serviceType: z.literal('GUARDERIA'),
  caregiverId: z.string().uuid('caregiverId inválido'),
  petId: z.string().uuid('petId inválido'),
  walkDate: z.string().regex(dateOnlyRegex, 'walkDate: formato YYYY-MM-DD'),
  timeSlot: z.enum(['MANANA', 'TARDE'], {
    errorMap: () => ({ message: 'timeSlot debe ser MANANA o TARDE' }),
  }),
  startTime: z.string().regex(/^\d{2}:\d{2}$/, 'startTime formato HH:mm').optional(),
  duration: z.coerce
    .number()
    .int()
    .refine((n) => [180, 240, 360, 480, 600].includes(n), {
      message: 'Duración debe ser 180, 240, 360, 480 o 600 minutos',
    }),
});

export type CreateBookingBody =
  | z.infer<typeof hospedajeSchema>
  | z.infer<typeof paseoSchema>
  | z.infer<typeof guarderiaSchema>;

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

  if (serviceType === 'GUARDERIA') {
    const result = guarderiaSchema.safeParse(data);
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

/** POST /api/bookings/:id/request-hospedaje-extension-payment — inicia pago de noches adicionales. */
export const requestHospedajeExtensionPaymentBodySchema = z.object({
  additionalDays: z.number().int().min(1).max(30),
  method: z.enum(['qr', 'manual'], { required_error: 'method es requerido (qr | manual)' }),
});

/** POST /api/bookings/:id/confirm-hospedaje-extension-qr — confirma pago QR de extensión de hospedaje. */
export const confirmHospedajeExtensionQrBodySchema = z.object({
  qrId: z.string().min(1, 'qrId requerido'),
});

/** POST /api/bookings/:id/extend-paseo — cliente solicita extensión de paseo en curso. */
export const extendPaseoBodySchema = z.object({
  additionalMinutes: z.number().int().refine((n) => [15, 30, 60].includes(n), {
    message: 'additionalMinutes debe ser 15, 30 o 60',
  }),
});

export type ExtendPaseoBody = z.infer<typeof extendPaseoBodySchema>;

// ── Service execution ─────────────────────────────────────────────────────────

/** POST /api/bookings/:id/start — cuidador inicia el servicio (foto obligatoria). */
export const startServiceBodySchema = z.object({
  photo: z.string().optional().default(''),
});
export type StartServiceBody = z.infer<typeof startServiceBodySchema>;

/** POST /api/bookings/:id/track — cuidador envía coordenada GPS. */
export const trackLocationBodySchema = z.object({
  lat: z
    .number({ invalid_type_error: 'lat debe ser un número' })
    .min(-90, 'lat debe estar entre -90 y 90')
    .max(90, 'lat debe estar entre -90 y 90'),
  lng: z
    .number({ invalid_type_error: 'lng debe ser un número' })
    .min(-180, 'lng debe estar entre -180 y 180')
    .max(180, 'lng debe estar entre -180 y 180'),
  accuracy: z
    .number({ invalid_type_error: 'accuracy debe ser un número' })
    .min(0, 'accuracy no puede ser negativa')
    .optional(),
});
export type TrackLocationBody = z.infer<typeof trackLocationBodySchema>;

/** POST /api/bookings/:id/conclude — cuidador finaliza el servicio. */
export const concludeServiceBodySchema = z.object({
  photo: z.string().optional().default(''),
  lat: z
    .number({ invalid_type_error: 'lat debe ser un número' })
    .min(-90, 'lat debe estar entre -90 y 90')
    .max(90, 'lat debe estar entre -90 y 90')
    .optional(),
  lng: z
    .number({ invalid_type_error: 'lng debe ser un número' })
    .min(-180, 'lng debe estar entre -180 y 180')
    .max(180, 'lng debe estar entre -180 y 180')
    .optional(),
});
export type ConcludeServiceBody = z.infer<typeof concludeServiceBodySchema>;

/** POST /api/bookings/:id/confirm-receipt — cliente confirma y califica el servicio. */
export const confirmReceiptBodySchema = z.object({
  rating: z
    .number({ invalid_type_error: 'rating debe ser un número' })
    .int('rating debe ser un entero')
    .min(1, 'rating mínimo es 1')
    .max(5, 'rating máximo es 5'),
  comment: z.string().max(1000, 'El comentario no puede superar 1000 caracteres').optional(),
});
export type ConfirmReceiptBody = z.infer<typeof confirmReceiptBodySchema>;

/** POST /api/bookings/:id/event — cuidador registra evento durante el servicio. */
export const addEventBodySchema = z.object({
  type: z.enum(
    ['INCIDENT', 'ACCIDENT', 'ILLNESS', 'COMPLICATION', 'NOTE', 'PHOTO', 'WALK_UPDATE'],
    { errorMap: () => ({ message: 'Tipo de evento inválido' }) }
  ),
  description: z
    .string()
    .min(1, 'La descripción es obligatoria')
    .max(1000, 'La descripción no puede superar 1000 caracteres'),
  photoUrl: z.string().url('photoUrl debe ser una URL válida').optional(),
});
export type AddEventBody = z.infer<typeof addEventBodySchema>;

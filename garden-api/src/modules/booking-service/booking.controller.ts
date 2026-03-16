import { Request, Response } from 'express';
import { ZodError } from 'zod';
import { asyncHandler } from '../../shared/async-handler.js';
import { AppError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';
import {
  parseCreateBookingBody,
  cancelBookingBodySchema,
  extendBookingBodySchema,
  changeDatesBookingBodySchema,
  initPaymentBodySchema,
  cancellationRequestBodySchema,
} from './booking.validation.js';
import * as bookingService from './booking.service.js';

/**
 * POST /api/bookings
 * Crea reserva (hospedaje o paseo). Requiere auth (cliente).
 * Body validado con Zod; 409 si no hay disponibilidad, 400 si datos inválidos.
 * Devuelve 400 con errors[] por campo cuando falla validación.
 */
export const create = asyncHandler(async (req: Request, res: Response) => {
  const clientId = req.user!.userId;
  let body: ReturnType<typeof parseCreateBookingBody>;
  try {
    body = parseCreateBookingBody(req.body);
  } catch (error) {
    if (error instanceof ZodError) {
      const issues = error.issues.map((issue) => {
        const rawMessage = issue.message;
        let message = rawMessage;
        if (rawMessage === 'Invalid input' || rawMessage.includes('Invalid input')) {
          message =
            'Selecciona tipo de servicio (HOSPEDAJE o PASEO) y completa todos los campos requeridos';
        } else if (rawMessage.includes('union') || rawMessage.includes('discriminator')) {
          message = 'Debes seleccionar HOSPEDAJE o PASEO como tipo de servicio';
        }
        const field =
          (issue.path && issue.path[0] === 'serviceType'
            ? 'serviceType'
            : (issue.path.join('.') || 'serviceType')) as string;
        return { field: field === 'body' || field === '' ? 'serviceType' : field, message };
      });
      const errors =
        issues.length > 0 ? issues : [{ field: 'serviceType', message: 'Datos inválidos para la reserva' }];
      logger.warn('Respuesta 400 en creación de reserva', {
        errors,
        zodIssues: error.issues,
        body: req.body,
        userId: (req.user as { userId?: string })?.userId,
      });
      return res.status(400).json({
        message: 'Datos inválidos para la reserva',
        errors,
      });
    }
    throw error;
  }

  try {
    const booking = await bookingService.createBooking(clientId, body);
    res.status(201).json({ success: true, data: booking });
  } catch (err) {
    if (err instanceof AppError && (err.statusCode === 400 || err.statusCode === 409)) {
      const errors = [{ field: err.field ?? 'general', message: err.message }];
      logger.warn('Respuesta 400 en creación de reserva', {
        errors,
        body: req.body,
        userId: (req.user as { userId?: string })?.userId,
      });
      return res.status(err.statusCode).json({
        message: 'Datos inválidos para la reserva',
        errors,
      });
    }
    throw err;
  }
});

/**
 * POST /api/bookings/:id/cancel
 * Cancela la reserva y aplica política de reembolso (MVP: 48h/12h). Solo cliente titular.
 */
export const cancel = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const clientId = req.user!.userId;
  const body = cancelBookingBodySchema.parse(req.body ?? {});
  const booking = await bookingService.cancelBooking(
    bookingId,
    clientId,
    body.reason
  );
  res.json({ success: true, data: booking });
});

/**
 * POST /api/bookings/:id/extend
 * Extiende hospedaje (nueva endDate). Solo CONFIRMED; cliente titular.
 */
export const extend = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const clientId = req.user!.userId;
  const body = extendBookingBodySchema.parse(req.body);
  const newEndDate = new Date(body.newEndDate);
  const booking = await bookingService.extendBooking(bookingId, clientId, newEndDate);
  res.json({ success: true, data: booking });
});

/**
 * POST /api/bookings/:id/change-dates
 * Cambia fechas de hospedaje (newStartDate, newEndDate). Solo CONFIRMED; mín 48h.
 */
export const changeDates = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const clientId = req.user!.userId;
  const body = changeDatesBookingBodySchema.parse(req.body);
  const newStartDate = new Date(body.newStartDate);
  const newEndDate = new Date(body.newEndDate);
  const booking = await bookingService.changeDatesBooking(
    bookingId,
    clientId,
    newStartDate,
    newEndDate
  );
  res.json({ success: true, data: booking });
});

/**
 * GET /api/bookings/my
 * Obtiene todas las reservas del cliente autenticado.
 */
export const getMyBookings = asyncHandler(async (req: Request, res: Response) => {
  const clientId = req.user!.userId;
  const bookings = await bookingService.getMyBookings(clientId);
  res.json({ success: true, data: bookings });
});

/**
 * GET /api/bookings/:id
 * Obtiene una reserva por ID. Solo el cliente titular puede acceder.
 */
export const getById = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const clientId = req.user!.userId;
  const booking = await bookingService.getBookingById(bookingId, clientId);
  res.json({ success: true, data: booking });
});

/**
 * GET /api/bookings/:id/confirm
 * Datos de la reserva para la página de confirmación (fechas, horario, mascota). Solo cliente titular.
 */
export const getConfirm = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const clientId = req.user!.userId;
  const booking = await bookingService.getBookingById(bookingId, clientId);
  res.json({ success: true, data: booking });
});

/**
 * POST /api/bookings/:id/payment
 * Inicia pago: genera QR (placeholder) o solicita aprobación manual. Solo cliente titular; reserva PENDING_PAYMENT.
 */
export const initPayment = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const clientId = req.user!.userId;
  const body = initPaymentBodySchema.parse(req.body);
  const result = await bookingService.initPayment(bookingId, clientId, body.method);
  res.json({ success: true, data: result });
});

/**
 * POST /api/bookings/:id/request-cancellation
 * Cuidador cancela la reserva (flujo automático).
 */
export const requestCancellationByCaregiver = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const caregiverUserId = req.user!.userId;
  const body = cancellationRequestBodySchema.parse(req.body);
  const booking = await bookingService.requestCancellationByCaregiver(
    bookingId,
    caregiverUserId,
    body.reason
  );
  res.json({ success: true, data: booking });
});

/**
 * POST /api/bookings/:id/accept
 * Cuidador acepta una reserva pagada.
 */
export const accept = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const caregiverUserId = req.user!.userId;
  const booking = await bookingService.acceptBooking(bookingId, caregiverUserId);
  res.json({ success: true, data: booking });
});

/**
 * POST /api/bookings/:id/reject
 * Cuidador rechaza una reserva pagada.
 */
export const reject = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const caregiverUserId = req.user!.userId;
  const body = cancellationRequestBodySchema.parse(req.body); // use the same schema as cancellation
  const booking = await bookingService.rejectBooking(bookingId, caregiverUserId, body.reason);
  res.json({ success: true, data: booking });
});

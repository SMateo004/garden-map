/**
 * Controlador: flujo de registro cuidador con guardado progresivo.
 * - GET /api/caregiver/my-profile
 * - PATCH /api/caregiver/profile
 * - POST /api/caregiver/submit
 */

import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as caregiverProfileService from './caregiver-profile.service.js';
import * as bookingService from '../booking-service/booking.service.js';
import {
  patchCaregiverProfileSchema,
  patchAvailabilityBodySchema,
} from './caregiver-profile.validation.js';

/** GET /api/caregiver/my-profile - Perfil del cuidador logueado (para cargar wizard). */
export const getMyProfile = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const profile = await caregiverProfileService.getMyProfile(userId);
  if (!profile) {
    res.status(404).json({
      success: false,
      error: { code: 'CAREGIVER_PROFILE_NOT_FOUND', message: 'No tienes perfil de cuidador' },
    });
    return;
  }
  res.json({ success: true, data: profile });
});

/** PATCH /api/caregiver/profile - Actualización parcial. 403 si status APPROVED. */
export const patchProfile = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const body = patchCaregiverProfileSchema.parse(req.body);
  const result = await caregiverProfileService.patchProfile(userId, body);
  res.json({ success: true, data: result });
});

/** POST /api/caregiver/submit - Enviar solicitud (campos obligatorios, status → PENDING_REVIEW). */
export const submit = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const result = await caregiverProfileService.submitProfile(userId);
  res.json(result);
});

/** PATCH /api/caregiver/user-info - Actualiza nombre, email, teléfono. Si cambia email → emailVerified = false. */
export const patchUserInfo = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const { firstName, lastName, phone, email } = req.body as {
    firstName?: string;
    lastName?: string;
    phone?: string;
    email?: string;
  };
  const result = await caregiverProfileService.patchUserInfo(userId, { firstName, lastName, phone, email });
  res.json({ success: true, data: result });
});

/** GET /api/caregiver/availability - Disponibilidad del cuidador logueado para editar (defaultSchedule + overrides por fecha). Query: from/to o start/end (YYYY-MM-DD). */
export const getMyAvailability = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const from =
    (req.query.from as string) || (req.query.start as string) ||
    new Date().toISOString().slice(0, 10);
  const to =
    (req.query.to as string) ||
    (req.query.end as string) ||
    (() => {
      const d = new Date();
      d.setDate(d.getDate() + 90);
      return d.toISOString().slice(0, 10);
    })();
  const data = await caregiverProfileService.getMyAvailabilityForEdit(userId, from, to);
  res.json({ success: true, data });
});

/** PATCH /api/caregiver/availability - Guardar horario predeterminado y/o sobrescrituras por día. */
export const patchAvailability = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const body = patchAvailabilityBodySchema.parse(req.body);
  const result = await caregiverProfileService.patchAvailability(userId, body);
  res.json(result);
});

/** POST /api/caregiver/send-verify-email - Genera y envía código de verificación.破 */
export const sendVerifyEmail = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const result = await caregiverProfileService.sendEmailVerificationCode(userId);
  res.json(result);
});

/** POST /api/caregiver/verify-email - Valida código de verificación.破 */
export const verifyEmail = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const { code } = req.body as { code: string };
  if (!code) {
    return res.status(400).json({
      success: false,
      error: { code: 'MISSING_CODE', message: 'Código requerido' },
    });
  }
  const result = await caregiverProfileService.verifyEmailCode(userId, code);
  res.json(result);
});

/** GET /api/caregiver/bookings - Reservas asignadas al cuidador logueado. */
export const getMyBookingsAsCaregiver = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const bookings = await bookingService.getBookingsByCaregiverUserId(userId);
  res.json({ success: true, data: bookings });
});

/** GET /api/caregiver/notifications - Bandeja de notificaciones (APPROVED, REJECTED, REVIEW). */
export const getNotifications = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const list = await caregiverProfileService.getNotifications(userId);
  res.json({ success: true, data: list });
});

/** PATCH /api/caregiver/notifications/:id/read - Marcar notificación como leída. */
export const markNotificationRead = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const notificationId = req.params.id!;
  const result = await caregiverProfileService.markNotificationRead(userId, notificationId);
  res.json(result);
});

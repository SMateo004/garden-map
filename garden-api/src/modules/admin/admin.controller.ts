/**
 * Controlador admin: revisión de cuidadores (approve / reject / request_revision).
 * - GET /api/admin/caregivers/pending
 * - PATCH /api/admin/caregivers/:id/review
 */

import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as adminService from './admin.service.js';
import {
  reviewCaregiverBodySchema,
  pendingCaregiversQuerySchema,
  listCaregiversQuerySchema,
  suspendCaregiverSchema,
  activateCaregiverSchema,
  deleteCaregiverSchema,
} from './admin.validation.js';

/** GET /api/admin/caregivers — listado de todos los cuidadores (paginado, filtro status opcional). */
export const getCaregiversList = asyncHandler(async (req: Request, res: Response) => {
  const query = listCaregiversQuerySchema.parse(req.query);
  const result = await adminService.listCaregivers(query.page, query.limit, query.status);
  res.json({ success: true, data: result });
});

/** GET /api/admin/caregivers/pending — listado paginado PENDING_REVIEW y NEEDS_REVISION. */
export const getPendingCaregivers = asyncHandler(async (req: Request, res: Response) => {
  const query = pendingCaregiversQuerySchema.parse(req.query);
  const result = await adminService.listPendingCaregivers(query.page, query.limit);
  res.json({ success: true, data: result });
});

/** GET /api/admin/caregivers/:id/detail — todos los datos de la solicitud para revisión. 404 si no existe. */
export const getCaregiverDetail = asyncHandler(async (req: Request, res: Response) => {
  const profileId = req.params.id!;
  const data = await adminService.getCaregiverDetailForAdmin(profileId);
  res.json({ success: true, data });
});

/** PATCH /api/admin/caregivers/:id/review — approve | reject | request_revision. */
export const reviewCaregiver = asyncHandler(async (req: Request, res: Response) => {
  const profileId = req.params.id!;
  const body = reviewCaregiverBodySchema.parse(req.body);
  const adminId = req.user!.userId;
  const result = await adminService.reviewCaregiver(profileId, adminId, body);
  res.json({ success: true, data: result });
});

/** PATCH /api/admin/caregivers/:id/suspend — suspend profile. */
export const suspendCaregiver = asyncHandler(async (req: Request, res: Response) => {
  const profileId = req.params.id!;
  const { reason } = suspendCaregiverSchema.parse(req.body);
  const adminId = req.user!.userId;
  const result = await adminService.suspendCaregiver(profileId, adminId, reason);
  res.json({ success: true, data: result });
});

/** PATCH /api/admin/caregivers/:id/activate — restore profile. */
export const activateCaregiver = asyncHandler(async (req: Request, res: Response) => {
  const profileId = req.params.id!;
  const { notes } = activateCaregiverSchema.parse(req.body);
  const adminId = req.user!.userId;
  const result = await adminService.activateCaregiver(profileId, adminId, notes);
  res.json({ success: true, data: result });
});

/** DELETE /api/admin/caregivers/:id — permanent delete. */
export const deleteCaregiver = asyncHandler(async (req: Request, res: Response) => {
  const profileId = req.params.id!;
  const body = deleteCaregiverSchema.parse(req.body);
  const adminId = req.user!.userId;
  const result = await adminService.deleteCaregiver(profileId, adminId, body);
  res.json({ success: true, data: result });
});

/** PATCH /api/admin/caregivers/:id/verify-email — manually verify caregiver email. */
export const verifyEmail = asyncHandler(async (req: Request, res: Response) => {
  const result = await adminService.verifyEmail(req.params.id!);
  res.json({ success: true, data: result });
});

/** PATCH /api/admin/caregivers/:id/verify — legacy toggle verify badge. */
export const toggleVerify = asyncHandler(async (req: Request, res: Response) => {
  const result = await adminService.toggleVerify(req.params.id!, req.user!.userId);
  res.json({ success: true, data: { caregiver: result } });
});

/** GET /api/admin/payments-pending — reservas en PAYMENT_PENDING_APPROVAL. */
export const getPaymentsPending = asyncHandler(async (_req: Request, res: Response) => {
  const result = await adminService.getPaymentsPending();
  res.json({ success: true, data: result });
});

/** POST /api/admin/bookings/:id/reject-payment — rechazar pago manual (vuelve a PENDING_PAYMENT). */
export const rejectPayment = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const adminId = req.user!.userId;
  const result = await adminService.rejectPayment(bookingId, adminId);
  res.json({ success: true, data: result });
});

/** GET /api/admin/reservations — listado de reservas, opcional ?status= */
export const getReservations = asyncHandler(async (req: Request, res: Response) => {
  const status = typeof req.query.status === 'string' ? req.query.status : undefined;
  const result = await adminService.getReservations(status);
  res.json({ success: true, data: result });
});


/** GET /api/admin/identity-reviews — lista sesiones en REVIEW. */
export const listIdentityReviews = asyncHandler(async (_req: Request, res: Response) => {
  const result = await adminService.listIdentityReviews();
  res.json({ success: true, data: result });
});

/** GET /api/admin/verifications/:id o identity-reviews/:id — detalles sesión identidad. */
export const getIdentityVerificationDetail = asyncHandler(async (req: Request, res: Response) => {
  const result = await adminService.getIdentityVerificationDetail(req.params.id!);
  res.json({ success: true, data: result });
});

/** POST /api/admin/verifications/:id/approve — aprobar manualmente. */
export const approveIdentityVerification = asyncHandler(async (req: Request, res: Response) => {
  const adminId = req.user!.userId;
  const result = await adminService.approveIdentityVerification(req.params.id!, adminId);
  res.json({ success: true, data: result });
});

/** POST /api/admin/verifications/:id/reject — rechazar manualmente. */
export const rejectIdentityVerification = asyncHandler(async (req: Request, res: Response) => {
  const adminId = req.user!.userId;
  const result = await adminService.rejectIdentityVerification(req.params.id!, adminId);
  res.json({ success: true, data: result });
});

import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as adminController from './admin.controller.js';

const router = Router();

router.use(authMiddleware);
router.use(requireRole('ADMIN'));

/** GET /api/admin/caregivers — todos los cuidadores, paginado, ?status=pendientes|APPROVED|... */
router.get('/caregivers', adminController.getCaregiversList);

/** GET /api/admin/caregivers/pending — status IN [PENDING_REVIEW, NEEDS_REVISION], paginado. */
router.get('/caregivers/pending', adminController.getPendingCaregivers);

/** GET /api/admin/caregivers/:id/detail — todos los datos de la solicitud para revisión (solo ADMIN). */
router.get('/caregivers/:id/detail', adminController.getCaregiverDetail);

/** PATCH /api/admin/caregivers/:id/review — approve | reject | request_revision. */
router.patch('/caregivers/:id/review', adminController.reviewCaregiver);

/** PATCH /api/admin/caregivers/:id/suspend — suspend profile. */
router.patch('/caregivers/:id/suspend', adminController.suspendCaregiver);

/** PATCH /api/admin/caregivers/:id/activate — restore profile. */
router.patch('/caregivers/:id/activate', adminController.activateCaregiver);

/** DELETE /api/admin/caregivers/:id — absolute delete (removes User + Profile + all). */
router.delete('/caregivers/:id', adminController.deleteCaregiver);

/** Manually verify caregiver email. */
router.patch('/caregivers/:id/verify-email', adminController.verifyEmail);

/** Legacy: toggle verify badge (mantener compatibilidad). */
router.patch('/caregivers/:id/verify', adminController.toggleVerify);

/** GET /api/admin/payments-pending — reservas pendientes de aprobación de pago manual. */
router.get('/payments-pending', adminController.getPaymentsPending);

/** GET /api/admin/payments-history — pagos ya procesados (historial). */
router.get('/payments-history', adminController.getPaymentsHistory);

/** POST /api/admin/bookings/:id/reject-payment — rechazar pago manual. */
router.post('/bookings/:id/reject-payment', adminController.rejectPayment);

/** POST /api/admin/bookings/:id/approve-payment — aprobar pago manual. */
router.post('/bookings/:id/approve-payment', adminController.approvePayment);

/** GET /api/admin/reservations — listado de reservas, ?status= opcional. */
router.get('/reservations', adminController.getReservations);

/** GET /api/admin/reservations/:id — detalle completo de una reserva. */
router.get('/reservations/:id', adminController.getReservationDetail);


/** GET /api/admin/identity-reviews — lista sesiones en REVIEW. */
router.get('/identity-reviews', adminController.listIdentityReviews);

/** GET /api/admin/identity-reviews/:id — detalles con imágenes para revisión. */
router.get('/identity-reviews/:id', adminController.getIdentityVerificationDetail);

/** GET /api/admin/verifications/:id — alias para compatibilidad. */
router.get('/verifications/:id', adminController.getIdentityVerificationDetail);

/** POST /api/admin/verifications/:id/approve — aprobar manualmente. */
router.post('/verifications/:id/approve', adminController.approveIdentityVerification);

/** POST /api/admin/identity-reviews/:id/approve — aprobar (alias). */
router.post('/identity-reviews/:id/approve', adminController.approveIdentityVerification);

/** POST /api/admin/verifications/:id/reject — rechazar manualmente. */
router.post('/verifications/:id/reject', adminController.rejectIdentityVerification);

/** POST /api/admin/identity-reviews/:id/reject — rechazar (alias). */
router.post('/identity-reviews/:id/reject', adminController.rejectIdentityVerification);

/** GET /api/admin/withdrawals — listar retiros pendientes */
router.get('/withdrawals', adminController.getWithdrawals);

/** PATCH /api/admin/withdrawals/:id/process — marcar en proceso */
router.patch('/withdrawals/:id/process', adminController.processWithdrawal);

/** PATCH /api/admin/withdrawals/:id/complete — marcar completado y descontar saldo */
router.patch('/withdrawals/:id/complete', adminController.completeWithdrawal);

/** PATCH /api/admin/withdrawals/:id/reject — rechazar retiro */
router.patch('/withdrawals/:id/reject', adminController.rejectWithdrawal);

/** GET /api/admin/gift-codes — listar todos los códigos de regalo */
router.get('/gift-codes', adminController.listGiftCodes);

/** POST /api/admin/gift-codes — crear nuevo código de regalo */
router.post('/gift-codes', adminController.createGiftCode);

/** PATCH /api/admin/gift-codes/:id/toggle — activar/desactivar */
router.patch('/gift-codes/:id/toggle', adminController.toggleGiftCode);

/** GET /api/admin/disputes — listar todas las disputas */
router.get('/disputes', adminController.getDisputes);

// ── Owners ────────────────────────────────────────────────────────────────
router.get('/owners', adminController.getOwnersList);
router.get('/owners/:id', adminController.getOwnerDetail);

// ── Stats ─────────────────────────────────────────────────────────────────
router.get('/stats/live', adminController.getLiveStats);
router.get('/stats/financial', adminController.getFinancialStats);

// ── Zones ─────────────────────────────────────────────────────────────────
router.get('/zones', adminController.getZones);
router.patch('/zones/:zone/toggle', adminController.toggleZone);

// ── App Settings ──────────────────────────────────────────────────────────
/** GET /api/admin/settings — get all app settings */
router.get('/settings', adminController.getSettings);
/** PATCH /api/admin/settings/:key — update a setting value */
router.patch('/settings/:key', adminController.updateSetting);
/** GET /api/admin/agent-logs — get recent agent logs */
router.get('/agent-logs', adminController.getAgentLogs);
/** POST /api/admin/agent-logs — post a custom agent instruction */
router.post('/agent-logs', adminController.postAgentInstruction);

export default router;

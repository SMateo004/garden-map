import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as adminController from './admin.controller.js';
import { asyncHandler } from '../../shared/async-handler.js';
import { exportMonthAsTxt } from '../../services/audit.service.js';
import prisma from '../../config/database.js';

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

/** PATCH /api/admin/caregivers/:id/flag-review — poner bajo revisión por actividad sospechosa. */
router.patch('/caregivers/:id/flag-review', adminController.flagCaregiverForReview);

/** DELETE /api/admin/caregivers/:id — absolute delete (removes User + Profile + all). */
router.delete('/caregivers/:id', adminController.deleteCaregiver);

/** PATCH /api/admin/caregivers/:id/toggle-professional — assign/remove professional flag. */
router.patch('/caregivers/:id/toggle-professional', adminController.toggleProfessional);

/** Manually verify caregiver email. */
router.patch('/caregivers/:id/verify-email', adminController.verifyEmail);

/** Legacy: toggle verify badge (mantener compatibilidad). */
router.patch('/caregivers/:id/verify', adminController.toggleVerify);

/** Reset identity verification lockout. */
router.patch('/caregivers/:id/unlock-verification', adminController.unlockVerification);

/** GET /api/admin/payments-pending — reservas pendientes de aprobación de pago manual. */
router.get('/payments-pending', adminController.getPaymentsPending);

/** GET /api/admin/payments-history — pagos ya procesados (historial). */
router.get('/payments-history', adminController.getPaymentsHistory);

/** POST /api/admin/bookings/:id/reject-payment — rechazar pago manual. */
router.post('/bookings/:id/reject-payment', adminController.rejectPayment);

/** POST /api/admin/bookings/:id/approve-payment — aprobar pago manual. */
router.post('/bookings/:id/approve-payment', adminController.approvePayment);

/** GET /api/admin/extension-payments-pending — extensiones de paseo pendientes de aprobación. */
router.get('/extension-payments-pending', adminController.getExtensionPaymentsPending);

/** POST /api/admin/bookings/:id/approve-extension-payment — aprobar extensión manual. */
router.post('/bookings/:id/approve-extension-payment', adminController.approveExtensionPayment);

/** POST /api/admin/bookings/:id/reject-extension-payment — rechazar extensión manual. */
router.post('/bookings/:id/reject-extension-payment', adminController.rejectExtensionPayment);

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
/** GET /api/admin/agent-logs — get recent agent logs (?type=PRECIO|...) */
router.get('/agent-logs', adminController.getAgentLogs);
/** GET /api/admin/agent-stats — conteo por tipo y estado */
router.get('/agent-stats', adminController.getAgentStats);
/** POST /api/admin/agent-logs — post a custom agent instruction */
router.post('/agent-logs', adminController.postAgentInstruction);

// ── Notificaciones Admin ───────────────────────────────────────────────────
/** POST /api/admin/notifications/send — broadcast inmediato */
router.post('/notifications/send', adminController.sendAdminNotification);
/** POST /api/admin/notifications/schedule — programar */
router.post('/notifications/schedule', adminController.scheduleAdminNotification);
/** GET /api/admin/notifications/scheduled — listar programadas */
router.get('/notifications/scheduled', adminController.getScheduledNotifications);
/** DELETE /api/admin/notifications/scheduled/:id — cancelar programada */
router.delete('/notifications/scheduled/:id', adminController.cancelScheduledNotification);
/** GET /api/admin/notifications/history — historial de enviadas */
router.get('/notifications/history', adminController.getNotificationHistory);

// ── Audit log ─────────────────────────────────────────────────────────────
/**
 * GET /api/admin/audit-log/export?month=YYYY-MM
 * Descarga el registro mensual como archivo TXT.
 * Si no se especifica month, usa el mes actual.
 */
router.get('/audit-log/export', asyncHandler(async (req, res) => {
  const month = typeof req.query.month === 'string' && /^\d{4}-\d{2}$/.test(req.query.month)
    ? req.query.month
    : new Date().toISOString().substring(0, 7);

  const txt = await exportMonthAsTxt(month);
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="garden-audit-${month}.txt"`);
  res.send(txt);
}));

// ── Diagnóstico temporal — filtros de mascota ─────────────────────────────
// GET /api/admin/debug/animal-types — muestra animalTypes real en DB para todos los cuidadores aprobados
router.get('/debug/animal-types', asyncHandler(async (_req, res) => {
  const profiles = await prisma.caregiverProfile.findMany({
    where: { status: 'APPROVED' },
    select: {
      id: true,
      animalTypes: true,
      sizesAccepted: true,
      serviceDetails: true,
      user: { select: { firstName: true, lastName: true } },
    },
  });
  res.json({
    success: true,
    data: profiles.map((p) => ({
      id: p.id,
      name: `${p.user?.firstName} ${p.user?.lastName}`,
      animalTypes: p.animalTypes,
      sizesAccepted: p.sizesAccepted,
      serviceDetailsAcceptedPetTypes: (p.serviceDetails as any)?.acceptedPetTypes ?? null,
      serviceDetailsAcceptedSizes: (p.serviceDetails as any)?.acceptedSizes ?? null,
    })),
  });
}));

/** GET /api/admin/vets — listar veterinarias */
router.get('/vets', asyncHandler(async (_req, res) => {
  const vets = await (prisma as any).vetClinic.findMany({ orderBy: { createdAt: 'desc' } });
  res.json({ success: true, data: vets });
}));

/** POST /api/admin/vets — crear veterinaria */
router.post('/vets', asyncHandler(async (req, res) => {
  const { name, address, phone, lat, lng } = req.body;
  if (!name || !phone || lat == null || lng == null) {
    res.status(400).json({ success: false, error: { message: 'name, phone, lat, lng son requeridos' } });
    return;
  }
  const vet = await (prisma as any).vetClinic.create({
    data: { name, address: address ?? null, phone, lat: parseFloat(lat), lng: parseFloat(lng) },
  });
  res.json({ success: true, data: vet });
}));

/** PATCH /api/admin/vets/:id — actualizar veterinaria */
router.patch('/vets/:id', asyncHandler(async (req, res) => {
  const { name, address, phone, lat, lng, isActive } = req.body;
  const vet = await (prisma as any).vetClinic.update({
    where: { id: req.params.id },
    data: {
      ...(name !== undefined && { name }),
      ...(address !== undefined && { address }),
      ...(phone !== undefined && { phone }),
      ...(lat !== undefined && { lat: parseFloat(lat) }),
      ...(lng !== undefined && { lng: parseFloat(lng) }),
      ...(isActive !== undefined && { isActive }),
    },
  });
  res.json({ success: true, data: vet });
}));

/** DELETE /api/admin/vets/:id — desactivar veterinaria */
router.delete('/vets/:id', asyncHandler(async (req, res) => {
  await (prisma as any).vetClinic.update({
    where: { id: req.params.id },
    data: { isActive: false },
  });
  res.json({ success: true });
}));

// ── Donaciones ────────────────────────────────────────────────────────────────

/** GET /api/admin/donations — resumen + historial de donaciones para hogares de perros. */
router.get('/donations', asyncHandler(async (_req, res) => {
  const [donations, summary] = await Promise.all([
    prisma.donation.findMany({
      orderBy: { createdAt: 'desc' },
      take: 200,
      include: {
        client: { select: { firstName: true, lastName: true, email: true } },
        booking: { select: { serviceType: true, petName: true } },
      },
    }),
    prisma.donation.aggregate({
      _sum: { amount: true },
      where: { disbursedAt: null },
    }),
  ]);
  const pendingTotal = Number(summary._sum.amount ?? 0);
  res.json({ success: true, data: { pendingTotal, donations } });
}));

/** POST /api/admin/donations/:id/disburse — marcar donación como enviada al hogar. */
router.post('/donations/:id/disburse', asyncHandler(async (req, res) => {
  const { note } = req.body as { note?: string };
  const donation = await prisma.donation.update({
    where: { id: req.params.id },
    data: { disbursedAt: new Date(), disbursementNote: note ?? null },
  });
  res.json({ success: true, data: donation });
}));

export default router;

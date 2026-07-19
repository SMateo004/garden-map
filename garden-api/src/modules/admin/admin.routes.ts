import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as adminController from './admin.controller.js';
import * as trainingController from '../training/training.controller.js';
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

/** GET /api/admin/caregivers/:id/audit-log — historial visible de suspensiones/reactivaciones. */
router.get('/caregivers/:id/audit-log', adminController.getCaregiverAuditLog);

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

/** POST /api/admin/bookings/:id/approve-payment-secure — igual, con contraseña + ventana 24h. */
router.post('/bookings/:id/approve-payment-secure', adminController.approvePaymentSecure);

/** POST /api/admin/bookings/:id/refund — reembolsa el servicio y cancela la reserva. */
router.post('/bookings/:id/refund', adminController.refundBooking);

/** POST /api/admin/bookings/test — crea una reserva de prueba a mano, directo a
 *  WAITING_CAREGIVER_APPROVAL, sin restricciones normales del flujo real. */
router.post('/bookings/test', adminController.createTestBooking);

/** DELETE /api/admin/bookings/:id/test — borra una reserva de prueba (createdByAdmin=true). */
router.delete('/bookings/:id/test', adminController.deleteTestBooking);

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


// ── Capacitaciones ─────────────────────────────────────────────────────────

/** GET /api/admin/trainings — todos los temas (Amateur + Experiencia), con preguntas. */
router.get('/trainings', trainingController.adminListTopics);

/** POST /api/admin/trainings — crear tema (video + intro + 3 preguntas). */
router.post('/trainings', trainingController.adminCreateTopic);

/** PATCH /api/admin/trainings/:topicId — editar tema (parcial). */
router.patch('/trainings/:topicId', trainingController.adminUpdateTopic);

/** DELETE /api/admin/trainings/:topicId */
router.delete('/trainings/:topicId', trainingController.adminDeleteTopic);

/** GET /api/admin/caregivers/:caregiverId/trainings — progreso de un cuidador puntual. */
router.get('/caregivers/:caregiverId/trainings', trainingController.adminGetCaregiverTopics);

/** PATCH /api/admin/caregivers/:caregiverId/trainings/:topicId/exempt — Body: { exempted } */
router.patch('/caregivers/:caregiverId/trainings/:topicId/exempt', trainingController.adminSetExemption);

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

/** POST /api/admin/disputes/:bookingId/resolve-manual — resolución forzada, con contraseña. */
router.post('/disputes/:bookingId/resolve-manual', adminController.resolveDisputeManual);

/** GET /api/admin/disputes/appeals — disputas apeladas, pendientes de revisión humana. */
router.get('/disputes/appeals', adminController.getDisputeAppeals);

/** POST /api/admin/disputes/:bookingId/resolve-appeal — decisión final de un admin humano sobre una apelación. */
router.post('/disputes/:bookingId/resolve-appeal', adminController.resolveDisputeAppeal);

/** GET /api/admin/chat-reports — listar reportes de chat, ?status= opcional. */
router.get('/chat-reports', adminController.getChatReports);

/** POST /api/admin/chat-reports/:id/resolve — resolver reporte de chat (ACTION_TAKEN | DISMISSED). */
router.post('/chat-reports/:id/resolve', adminController.resolveChatReport);

/** GET /api/admin/phone-otp-requests — cuidadores que pidieron código de teléfono y aún no verifican. */
router.get('/phone-otp-requests', adminController.getPendingPhoneOtpRequests);

/** POST /api/admin/phone-otp-requests/:userId/message — (re)genera el código y el mensaje listo para copiar/enviar. */
router.post('/phone-otp-requests/:userId/message', adminController.generatePhoneOtpMessage);

/** GET /api/admin/email-otp-requests — usuarios a los que Resend no pudo enviarles el código de email. */
router.get('/email-otp-requests', adminController.getPendingEmailOtpRequests);

/** POST /api/admin/email-otp-requests/:userId/message — genera el código y el mensaje listo para copiar/enviar. */
router.post('/email-otp-requests/:userId/message', adminController.generateEmailOtpMessage);

/** POST /api/admin/bookings/:id/resolve-incident — reanuda el reloj tras una emergencia. */
router.post('/bookings/:id/resolve-incident', adminController.resolveIncidentAdmin);

/** GET /api/admin/bookings/:id/track — track GPS del paseo, sin restricción de ownership. */
router.get('/bookings/:id/track', adminController.getBookingGpsTrackAdmin);

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

/** GET /api/admin/icon-schedule — reglas de icono estacional + variante activa hoy.
 * IMPORTANTE: solo elige entre variantes ya empaquetadas en el build actual — ver nota
 * de plataforma en admin.controller.ts / admin.service.ts. */
router.get('/icon-schedule', adminController.getIconSchedule);
/** POST /api/admin/icon-schedule — crear regla { variant, startDate, endDate, label? } */
router.post('/icon-schedule', adminController.createIconScheduleRule);
/** PATCH /api/admin/icon-schedule/:id — editar regla */
router.patch('/icon-schedule/:id', adminController.updateIconScheduleRule);
/** DELETE /api/admin/icon-schedule/:id — eliminar regla */
router.delete('/icon-schedule/:id', adminController.deleteIconScheduleRule);
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

// ── Ciudades y zonas (multi-ciudad) ─────────────────────────────────────────

/** GET /api/admin/cities — listar todas las ciudades (incl. inactivas) */
router.get('/cities', asyncHandler(async (_req, res) => {
  const cities = await prisma.city.findMany({ orderBy: { name: 'asc' }, include: { _count: { select: { zones: true } } } });
  res.json({ success: true, data: cities });
}));

/** POST /api/admin/cities — crear ciudad nueva */
router.post('/cities', asyncHandler(async (req, res) => {
  const { name, slug, centerLat, centerLng, defaultZoom } = req.body;
  if (!name || !slug || centerLat == null || centerLng == null) {
    res.status(400).json({ success: false, error: { message: 'name, slug, centerLat, centerLng son requeridos' } });
    return;
  }
  const city = await prisma.city.create({
    data: {
      name, slug,
      centerLat: parseFloat(centerLat), centerLng: parseFloat(centerLng),
      defaultZoom: defaultZoom != null ? parseFloat(defaultZoom) : 13,
    },
  });
  res.json({ success: true, data: city });
}));

/** PATCH /api/admin/cities/:id — editar ciudad (nombre, centro del mapa, activar/desactivar) */
router.patch('/cities/:id', asyncHandler(async (req, res) => {
  const { name, centerLat, centerLng, defaultZoom, active } = req.body;
  const city = await prisma.city.update({
    where: { id: req.params.id },
    data: {
      ...(name !== undefined && { name }),
      ...(centerLat !== undefined && { centerLat: parseFloat(centerLat) }),
      ...(centerLng !== undefined && { centerLng: parseFloat(centerLng) }),
      ...(defaultZoom !== undefined && { defaultZoom: parseFloat(defaultZoom) }),
      ...(active !== undefined && { active }),
    },
  });
  res.json({ success: true, data: city });
}));

/** GET /api/admin/city-zones?cityId= — listar zonas de una ciudad (incl. inactivas) */
router.get('/city-zones', asyncHandler(async (req, res) => {
  const cityId = req.query.cityId as string | undefined;
  const zones = await prisma.cityZone.findMany({
    where: cityId ? { cityId } : undefined,
    orderBy: [{ cityId: 'asc' }, { label: 'asc' }],
    include: { city: { select: { name: true, slug: true } } },
  });
  res.json({ success: true, data: zones });
}));

/** Valida que `points` (si viene) sea un array de 4+ {lat,lng} numéricos. */
function validatePoints(points: unknown): { lat: number; lng: number }[] | undefined {
  if (points == null) return undefined;
  if (!Array.isArray(points) || points.length < 4) {
    throw new Error('points debe ser un array de al menos 4 puntos [{lat, lng}, ...]');
  }
  return points.map((p) => {
    const lat = parseFloat(p?.lat);
    const lng = parseFloat(p?.lng);
    if (isNaN(lat) || isNaN(lng)) throw new Error('Cada punto necesita lat y lng numéricos');
    return { lat, lng };
  });
}

/** POST /api/admin/city-zones — crear zona nueva dentro de una ciudad */
router.post('/city-zones', asyncHandler(async (req, res) => {
  const { cityId, key, label, color, lat, lng, points } = req.body;
  if (!cityId || !key || !label || !color || lat == null || lng == null) {
    res.status(400).json({ success: false, error: { message: 'cityId, key, label, color, lat, lng son requeridos' } });
    return;
  }
  let validatedPoints: { lat: number; lng: number }[] | undefined;
  try {
    validatedPoints = validatePoints(points);
  } catch (e) {
    res.status(400).json({ success: false, error: { message: (e as Error).message } });
    return;
  }
  const zone = await prisma.cityZone.create({
    data: {
      cityId,
      key: String(key).trim().toUpperCase().replace(/\s+/g, '_'),
      label, color,
      lat: parseFloat(lat), lng: parseFloat(lng),
      points: validatedPoints ?? undefined,
    },
  });
  res.json({ success: true, data: zone });
}));

/** PATCH /api/admin/city-zones/:id — editar zona (label, color, coords, polígono, activar/desactivar) */
router.patch('/city-zones/:id', asyncHandler(async (req, res) => {
  const { label, color, lat, lng, points, active } = req.body;
  let validatedPoints: { lat: number; lng: number }[] | undefined;
  try {
    validatedPoints = validatePoints(points);
  } catch (e) {
    res.status(400).json({ success: false, error: { message: (e as Error).message } });
    return;
  }
  const zone = await prisma.cityZone.update({
    where: { id: req.params.id },
    data: {
      ...(label !== undefined && { label }),
      ...(color !== undefined && { color }),
      ...(lat !== undefined && { lat: parseFloat(lat) }),
      ...(lng !== undefined && { lng: parseFloat(lng) }),
      ...(validatedPoints !== undefined && { points: validatedPoints }),
      ...(active !== undefined && { active }),
    },
  });
  res.json({ success: true, data: zone });
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

// ── Tarjeta de donador — canjes en negocios asociados ───────────────────────
// El negocio no tiene cuenta ni valida nada por su cuenta: anota el uso a
// mano y se lo comunica a Garden; el admin lo carga acá con el código del
// cliente. Puramente informativo, sin ningún efecto monetario.

/** GET /api/admin/donor-redemptions — historial completo de canjes. */
router.get('/donor-redemptions', asyncHandler(async (_req, res) => {
  const redemptions = await prisma.donorCodeRedemption.findMany({
    orderBy: { redeemedAt: 'desc' },
    take: 200,
    include: { user: { select: { firstName: true, lastName: true, email: true, donorCode: true } } },
  });
  res.json({ success: true, data: redemptions });
}));

/** POST /api/admin/donor-redemptions — registrar un canje por código de donador. */
router.post('/donor-redemptions', asyncHandler(async (req, res) => {
  const { donorCode, businessName, redeemedAt } = req.body;
  if (!donorCode || !businessName || !redeemedAt) {
    res.status(400).json({ success: false, error: { message: 'donorCode, businessName y redeemedAt son requeridos' } });
    return;
  }
  const user = await prisma.user.findUnique({
    where: { donorCode: String(donorCode).trim().toUpperCase() },
    select: { id: true, firstName: true, lastName: true },
  });
  if (!user) {
    res.status(404).json({ success: false, error: { message: 'Código de donador no encontrado' } });
    return;
  }
  const adminId = (req.user as { userId?: string })?.userId;
  const redemption = await prisma.donorCodeRedemption.create({
    data: {
      userId: user.id,
      businessName: String(businessName).trim(),
      redeemedAt: new Date(redeemedAt),
      loggedByAdminId: adminId ?? null,
    },
  });
  res.json({ success: true, data: { ...redemption, userName: `${user.firstName} ${user.lastName}` } });
}));

// ── Donaciones (trazabilidad completa — separada del área financiera) ──────
// El monto (`amount`) de cada donación es INTOCABLE desde este módulo: no
// existe ningún endpoint que lo modifique. Lo único que el admin puede
// registrar es que ya se hizo la transferencia real y hacia qué beneficiario
// (hogar de mascotas / refugio) — nunca cambiar cuánto se donó.

/** GET /api/admin/donations — historial completo de donaciones, ?status=pending|disbursed opcional. */
router.get('/donations', asyncHandler(async (req, res) => {
  const status = req.query.status as string | undefined;
  const where = status === 'pending' ? { disbursedAt: null }
    : status === 'disbursed' ? { disbursedAt: { not: null } }
    : {};

  const [donations, pendingSummary, totalSummary] = await Promise.all([
    prisma.donation.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: 500,
      include: {
        client: { select: { firstName: true, lastName: true, email: true } },
        booking: { select: { serviceType: true, petName: true } },
        beneficiary: { select: { id: true, name: true } },
      },
    }),
    prisma.donation.aggregate({ _sum: { amount: true }, _count: { _all: true }, where: { disbursedAt: null } }),
    prisma.donation.aggregate({ _sum: { amount: true }, _count: { _all: true } }),
  ]);

  res.json({
    success: true,
    data: {
      pendingTotal: Number(pendingSummary._sum.amount ?? 0),
      pendingCount: pendingSummary._count._all,
      grandTotal: Number(totalSummary._sum.amount ?? 0),
      totalCount: totalSummary._count._all,
      donations,
    },
  });
}));

/** GET /api/admin/donation-beneficiaries — hogares/refugios registrados (activos primero). */
router.get('/donation-beneficiaries', asyncHandler(async (_req, res) => {
  const beneficiaries = await prisma.donationBeneficiary.findMany({
    orderBy: [{ active: 'desc' }, { name: 'asc' }],
  });
  res.json({ success: true, data: beneficiaries });
}));

/** POST /api/admin/donation-beneficiaries — registra un nuevo hogar/refugio. */
router.post('/donation-beneficiaries', asyncHandler(async (req, res) => {
  const { name, contactInfo } = req.body as { name?: string; contactInfo?: string };
  if (!name || typeof name !== 'string' || name.trim().length < 2) {
    return res.status(400).json({ success: false, error: { message: 'Escribe el nombre del beneficiario.' } });
  }
  const beneficiary = await prisma.donationBeneficiary.create({
    data: { name: name.trim(), contactInfo: contactInfo?.trim() || null },
  });
  res.json({ success: true, data: beneficiary });
}));

/**
 * POST /api/admin/donations/disburse — marca una o varias donaciones como
 * transferidas a un beneficiario. Body: { donationIds: string[], beneficiaryId: string, note?: string }.
 * Solo toca disbursedAt/disbursementNote/beneficiaryId/disbursedByAdminId —
 * el campo `amount` nunca se incluye en el update, es imposible editarlo desde aquí.
 */
router.post('/donations/disburse', asyncHandler(async (req, res) => {
  const { donationIds, beneficiaryId, note } = req.body as { donationIds?: string[]; beneficiaryId?: string; note?: string };
  if (!Array.isArray(donationIds) || donationIds.length === 0) {
    return res.status(400).json({ success: false, error: { message: 'Selecciona al menos una donación.' } });
  }
  if (!beneficiaryId || typeof beneficiaryId !== 'string') {
    return res.status(400).json({ success: false, error: { message: 'Selecciona un beneficiario.' } });
  }
  const beneficiary = await prisma.donationBeneficiary.findUnique({ where: { id: beneficiaryId } });
  if (!beneficiary) {
    return res.status(404).json({ success: false, error: { message: 'Beneficiario no encontrado.' } });
  }

  const result = await prisma.donation.updateMany({
    where: { id: { in: donationIds }, disbursedAt: null },
    data: {
      disbursedAt: new Date(),
      disbursementNote: note?.trim() || null,
      beneficiaryId,
      disbursedByAdminId: req.user!.userId,
    },
  });

  res.json({ success: true, data: { updated: result.count, beneficiary: beneficiary.name } });
}));

// ═══════════════════════════════════════════════════════════════════════════
// MARKETPLACE BANNERS
// ═══════════════════════════════════════════════════════════════════════════

/** GET /api/admin/banners */
router.get('/banners', asyncHandler(async (_req, res) => {
  const banners = await prisma.marketplaceBanner.findMany({ orderBy: [{ position: 'asc' }, { sortOrder: 'asc' }] });
  res.json({ success: true, data: banners });
}));

/** POST /api/admin/banners */
router.post('/banners', asyncHandler(async (req, res) => {
  const body = req.body as {
    title: string; subtitle?: string; imageUrl?: string;
    position?: number; sortOrder?: number; active?: boolean;
    buttonText?: string; actionType?: string; actionValue?: string;
  };
  const banner = await prisma.marketplaceBanner.create({
    data: {
      title: body.title,
      subtitle: body.subtitle ?? null,
      imageUrl: body.imageUrl ?? null,
      position: body.position ?? 0,
      sortOrder: body.sortOrder ?? 0,
      active: body.active ?? false,
      buttonText: body.buttonText ?? null,
      actionType: body.actionType ?? 'none',
      actionValue: body.actionValue ?? null,
    },
  });
  res.status(201).json({ success: true, data: banner });
}));

/** PATCH /api/admin/banners/:id */
router.patch('/banners/:id', asyncHandler(async (req, res) => {
  const b = req.body as Record<string, unknown>;
  // Filtrar solo campos editables — nunca permitir id, createdAt, updatedAt
  const data: Record<string, unknown> = {};
  const allowed = ['active','position','sortOrder','imageUrl','title','subtitle','buttonText','actionType','actionValue'];
  for (const k of allowed) {
    if (k in b) data[k] = b[k] ?? null;
  }
  const banner = await prisma.marketplaceBanner.update({ where: { id: req.params.id }, data: data as any });
  res.json({ success: true, data: banner });
}));

/** DELETE /api/admin/banners/:id */
router.delete('/banners/:id', asyncHandler(async (req, res) => {
  await prisma.marketplaceBanner.delete({ where: { id: req.params.id } });
  res.json({ success: true });
}));

// ═══════════════════════════════════════════════════════════════════════════
// MASS NOTIFICATIONS
// ═══════════════════════════════════════════════════════════════════════════

/** GET /api/admin/mass-notifications */
router.get('/mass-notifications', asyncHandler(async (_req, res) => {
  const list = await prisma.massNotification.findMany({ orderBy: { createdAt: 'desc' }, take: 100 });
  res.json({ success: true, data: list });
}));

/** POST /api/admin/mass-notifications — crear y opcionalmente enviar inmediatamente */
router.post('/mass-notifications', asyncHandler(async (req, res) => {
  const { title, message, targetType = 'all', targetZone, scheduledAt } = req.body as {
    title: string; message: string; targetType?: string; targetZone?: string; scheduledAt?: string;
  };
  const adminId = (req.user as any)?.userId ?? 'admin';
  const isImmediate = !scheduledAt;

  const notif = await prisma.massNotification.create({
    data: {
      title, message, targetType,
      targetZone: targetZone ?? null,
      scheduledAt: scheduledAt ? new Date(scheduledAt) : null,
      status: isImmediate ? 'SENDING' : 'SCHEDULED',
      createdBy: adminId,
    },
  });

  if (isImmediate) {
    // Envío asíncrono — no bloquea la respuesta
    _sendMassNotification(notif.id, title, message, targetType, targetZone ?? null).catch(() => {});
  }

  res.status(201).json({ success: true, data: notif });
}));

/** DELETE /api/admin/mass-notifications/:id — solo si DRAFT o SCHEDULED */
router.delete('/mass-notifications/:id', asyncHandler(async (req, res) => {
  const notif = await prisma.massNotification.findUnique({ where: { id: req.params.id } });
  if (!notif || !['DRAFT', 'SCHEDULED'].includes(notif.status)) {
    return res.status(400).json({ success: false, error: { message: 'Solo se pueden eliminar notificaciones no enviadas.' } });
  }
  await prisma.massNotification.delete({ where: { id: req.params.id } });
  res.json({ success: true });
}));

/** Helper interno: enviar push masivo y actualizar estado */
const MASS_NOTIF_BATCH = 200; // filas por ciclo para no saturar la DB ni la memoria

async function _sendMassNotification(
  id: string, title: string, message: string, targetType: string, targetZone: string | null
) {
  const { sendPushToUser } = await import('../../services/firebase.service.js');
  try {
    // Construir where clause según segmentación
    const where: any = { isDeleted: { not: true } };
    if (targetType === 'clients') where.role = 'CLIENT';
    else if (targetType === 'caregivers') where.role = 'CAREGIVER';
    else if (targetType === 'zone' && targetZone) {
      // Zona: cuidadores de esa zona + clientes con dirección en esa zona
      where.OR = [
        { caregiverProfile: { zone: targetZone } },
        { clientProfile: { addressZone: targetZone } },
      ];
    }

    let sentCount = 0;
    let failCount = 0;
    let cursor: string | undefined;

    // Procesamiento por lotes — evita OOM con bases de usuarios grandes
    while (true) {
      const users = await prisma.user.findMany({
        where,
        select: { id: true },
        take: MASS_NOTIF_BATCH,
        ...(cursor ? { skip: 1, cursor: { id: cursor } } : {}),
        orderBy: { id: 'asc' },
      });

      if (users.length === 0) break;
      cursor = users[users.length - 1]!.id;

      try {
        // createMany es ~10× más rápido que create en bucle
        await prisma.notification.createMany({
          data: users.map(u => ({ userId: u.id, title, message, type: 'SYSTEM' })),
          skipDuplicates: true,
        });
        sentCount += users.length;
        // Push en paralelo por lote (fire-and-forget)
        users.forEach(u => sendPushToUser(u.id, title, message).catch(() => {}));
      } catch {
        failCount += users.length;
      }

      if (users.length < MASS_NOTIF_BATCH) break; // último lote
    }

    await prisma.massNotification.update({
      where: { id },
      data: { status: 'SENT', sentAt: new Date(), sentCount, failCount },
    });
  } catch (err) {
    await prisma.massNotification.update({
      where: { id },
      data: { status: 'FAILED' },
    });
    throw err;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// USER FEATURE FLAGS
// ═══════════════════════════════════════════════════════════════════════════

/** GET /api/admin/feature-flags — listar todos los flags activos */
router.get('/feature-flags', asyncHandler(async (_req, res) => {
  const flags = await prisma.userFeatureFlag.findMany({
    include: { user: { select: { id: true, firstName: true, lastName: true, email: true, role: true } } },
    orderBy: { createdAt: 'desc' },
  });
  res.json({ success: true, data: flags });
}));

/** POST /api/admin/feature-flags — asignar flag a usuario */
router.post('/feature-flags', asyncHandler(async (req, res) => {
  const { userId, flagKey, enabled = true, expiresAt } = req.body as {
    userId: string; flagKey: string; enabled?: boolean; expiresAt?: string;
  };
  const flag = await prisma.userFeatureFlag.upsert({
    where: { userId_flagKey: { userId, flagKey } },
    create: { userId, flagKey, enabled, expiresAt: expiresAt ? new Date(expiresAt) : null },
    update: { enabled, expiresAt: expiresAt ? new Date(expiresAt) : null },
    include: { user: { select: { id: true, firstName: true, lastName: true, email: true } } },
  });
  res.status(201).json({ success: true, data: flag });
}));

/** DELETE /api/admin/feature-flags/:id */
router.delete('/feature-flags/:id', asyncHandler(async (req, res) => {
  const existing = await prisma.userFeatureFlag.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ success: false, error: { message: 'Feature flag no encontrado' } });
  await prisma.userFeatureFlag.delete({ where: { id: req.params.id } });
  res.json({ success: true });
}));

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC: banners activos para el marketplace (sin auth)
// ═══════════════════════════════════════════════════════════════════════════

/** GET /api/admin/payment-qr — URLs actuales de los 3 QR provisionales de pago. */
router.get('/payment-qr', adminController.getPaymentQrImages);

/** POST /api/admin/payment-qr/:serviceType — multipart 'qr'. Sube/reemplaza el QR provisional de ese servicio. */
router.post('/payment-qr/:serviceType', ...adminController.uploadPaymentQrHandler);

export default router;

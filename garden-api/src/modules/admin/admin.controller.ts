/**
 * Controlador admin: revisión de cuidadores (approve / reject / request_revision).
 * - GET /api/admin/caregivers/pending
 * - PATCH /api/admin/caregivers/:id/review
 */

import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import prisma from '../../config/database.js';
import * as adminService from './admin.service.js';
import { auditLog } from '../../services/audit.service.js';
import {
  reviewCaregiverBodySchema,
  pendingCaregiversQuerySchema,
  listCaregiversQuerySchema,
  suspendCaregiverSchema,
  activateCaregiverSchema,
  flagReviewSchema,
  deleteCaregiverSchema,
  createGiftCodeSchema,
  rejectWithdrawalSchema,
  ALLOWED_SETTING_KEYS,
  sendAdminNotificationSchema,
  scheduleAdminNotificationSchema,
  postAgentInstructionSchema,
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
  auditLog({ userId: adminId, action: `PROFILE_${body.action.toUpperCase()}`, entity: 'CaregiverProfile', entityId: profileId, details: { action: body.action }, ip: req.ip });
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

/** PATCH /api/admin/caregivers/:id/flag-review — poner perfil aprobado bajo revisión por actividad sospechosa. */
export const flagCaregiverForReview = asyncHandler(async (req: Request, res: Response) => {
  const profileId = req.params.id!;
  const { reason } = flagReviewSchema.parse(req.body);
  const adminId = req.user!.userId;
  const result = await adminService.flagCaregiverForReview(profileId, adminId, reason);
  res.json({ success: true, data: result });
});

/** DELETE /api/admin/caregivers/:id — permanent delete. */
export const deleteCaregiver = asyncHandler(async (req: Request, res: Response) => {
  const profileId = req.params.id!;
  const body = deleteCaregiverSchema.parse(req.body);
  const adminId = req.user!.userId;
  const result = await adminService.deleteCaregiver(profileId, adminId, body as any);
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

/** PATCH /api/admin/caregivers/:id/toggle-professional — toggle isProfessional flag. */
export const toggleProfessional = asyncHandler(async (req: Request, res: Response) => {
  const result = await adminService.toggleProfessional(req.params.id!, req.user!.userId);
  res.json({ success: true, data: result });
});

/** PATCH /api/admin/caregivers/:id/unlock-verification — reset identity verification lockout. */
export const unlockVerification = asyncHandler(async (req: Request, res: Response) => {
  const result = await adminService.unlockVerification(req.params.id!, req.user!.userId);
  res.json({ success: true, data: result });
});

/** GET /api/admin/payments-pending?page=1&limit=50 — reservas en PAYMENT_PENDING_APPROVAL. */
export const getPaymentsPending = asyncHandler(async (req: Request, res: Response) => {
  const page = Math.max(1, parseInt(String(req.query.page ?? '1'), 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(String(req.query.limit ?? '50'), 10) || 50));
  const result = await adminService.getPaymentsPending(page, limit);
  res.json({ success: true, data: result });
});

/** GET /api/admin/payments-history?page=1&limit=50 — pagos procesados (paidAt != null). */
export const getPaymentsHistory = asyncHandler(async (req: Request, res: Response) => {
  const page = Math.max(1, parseInt(String(req.query.page ?? '1'), 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(String(req.query.limit ?? '50'), 10) || 50));
  const result = await adminService.getPaymentsHistory(page, limit);
  res.json({ success: true, data: result });
});

/** POST /api/admin/bookings/:id/reject-payment — rechazar pago manual (vuelve a PENDING_PAYMENT). */
export const rejectPayment = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const adminId = req.user!.userId;
  const result = await adminService.rejectPayment(bookingId, adminId);
  auditLog({ userId: adminId, action: 'PAYMENT_REJECTED', entity: 'Booking', entityId: bookingId, ip: req.ip });
  res.json({ success: true, data: result });
});

/** POST /api/admin/bookings/:id/approve-payment — aprobar pago manual */
export const approvePayment = asyncHandler(async (req: Request, res: Response) => {
  const id = req.params.id!;
  const adminId = req.user!.userId;

  const booking = await prisma.booking.findUnique({ where: { id } });
  if (!booking) return res.status(404).json({ success: false, error: { message: 'Reserva no encontrada' } });

  if (booking.status !== 'PAYMENT_PENDING_APPROVAL' && booking.status !== 'PENDING_PAYMENT') {
    return res.status(400).json({ success: false, error: { message: 'La reserva no está en un estado válido para aprobación de pago' } });
  }

  // Fetch caregiver userId before transaction for notification
  const caregiverProfile = await prisma.caregiverProfile.findUnique({
    where: { id: booking.caregiverId },
    select: { userId: true },
  });

  // Atomic: update booking + create audit log + create DB notification
  await prisma.$transaction(async (tx) => {
    await tx.booking.update({
      where: { id },
      data: {
        status: 'WAITING_CAREGIVER_APPROVAL',
        paidAt: new Date(),
      },
    });

    // Audit trail — every admin payment action must be logged
    await tx.adminAction.create({
      data: {
        adminId,
        actionType: 'APPROVE_PAYMENT',
        targetId: id,
        notes: `Pago aprobado manualmente. Booking ${id} → WAITING_CAREGIVER_APPROVAL`,
      },
    });

    if (caregiverProfile) {
      await tx.notification.create({
        data: {
          userId: caregiverProfile.userId,
          title: 'Nueva reserva confirmada',
          message: 'El pago fue verificado. Tienes una nueva reserva esperando tu aceptación.',
          type: 'NEW_BOOKING',
        },
      });
    }
  });

  // Push notification (best-effort, outside transaction)
  if (caregiverProfile) {
    const { sendPushToUser } = await import('../../services/firebase.service.js');
    sendPushToUser(
      caregiverProfile.userId,
      'Nueva reserva confirmada',
      'El pago fue verificado. Tienes una nueva reserva esperando tu aceptación.'
    ).catch(() => {});
  }

  auditLog({ userId: adminId, action: 'PAYMENT_APPROVED', entity: 'Booking', entityId: id, ip: req.ip });
  res.json({ success: true, data: { status: 'WAITING_CAREGIVER_APPROVAL' } });
});

/** GET /api/admin/extension-payments-pending — extensiones de paseo pendientes de aprobación */
export const getExtensionPaymentsPending = asyncHandler(async (req: Request, res: Response) => {
  const result = await adminService.getExtensionPaymentsPending();
  res.json({ success: true, data: result });
});

/** POST /api/admin/bookings/:id/approve-extension-payment — aprobar extensión manual */
export const approveExtensionPayment = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const { extensionId } = req.body;
  const adminId = req.user!.userId;
  if (!extensionId) return res.status(400).json({ success: false, error: { message: 'extensionId requerido' } });
  const result = await adminService.approveExtensionPayment(bookingId, extensionId, adminId);
  res.json({ success: true, data: result });
});

/** POST /api/admin/bookings/:id/reject-extension-payment — rechazar extensión manual */
export const rejectExtensionPayment = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const { extensionId } = req.body;
  const adminId = req.user!.userId;
  if (!extensionId) return res.status(400).json({ success: false, error: { message: 'extensionId requerido' } });
  const result = await adminService.rejectExtensionPayment(bookingId, extensionId, adminId);
  res.json({ success: true, data: result });
});

/** GET /api/admin/reservations?status=&page=1&limit=50 — listado de reservas paginado */
export const getReservations = asyncHandler(async (req: Request, res: Response) => {
  const status = typeof req.query.status === 'string' ? req.query.status : undefined;
  const page = Math.max(1, parseInt(String(req.query.page ?? '1'), 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(String(req.query.limit ?? '50'), 10) || 50));
  const result = await adminService.getReservations(status, page, limit);
  res.json({ success: true, data: result });
});

/** GET /api/admin/reservations/:id — detalle completo de una reserva */
export const getReservationDetail = asyncHandler(async (req: Request, res: Response) => {
  const result = await adminService.getReservationDetail(req.params.id!);
  res.json({ success: true, data: result });
});


/** GET /api/admin/identity-reviews — lista sesiones de identidad. ?status=REVIEW|APPROVED|REJECTED|ALL */
export const listIdentityReviews = asyncHandler(async (req: Request, res: Response) => {
  const status = typeof req.query.status === 'string' ? req.query.status : 'REVIEW';
  const result = await adminService.listIdentityReviews(status);
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

export const getWithdrawals = asyncHandler(async (req: Request, res: Response) => {
  const status = req.query.status as string | undefined;
  
  const withdrawals = await prisma.walletTransaction.findMany({
    where: { 
      type: 'WITHDRAWAL',
      ...(status ? { status } : { status: { in: ['PENDING', 'PROCESSING'] } }),
    },
    include: {
      user: {
        select: {
          id: true, firstName: true, lastName: true, email: true, role: true,
          balance: true,
          bankName: true, bankAccount: true, bankHolder: true, bankType: true,
          caregiverProfile: {
            select: { bankName: true, bankAccount: true, bankHolder: true, bankType: true }
          }
        }
      }
    },
    orderBy: { createdAt: 'desc' },
  });

  res.json({ success: true, data: { withdrawals, total: withdrawals.length } });
});

export const processWithdrawal = asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;

  const tx = await prisma.walletTransaction.findUnique({ where: { id } });
  if (!tx || tx.type !== 'WITHDRAWAL' || tx.status !== 'PENDING') {
    return res.status(400).json({ success: false, error: { message: 'Solicitud no encontrada o no está pendiente' } });
  }

  await prisma.walletTransaction.update({
    where: { id },
    data: { status: 'PROCESSING' },
  });

  auditLog({ userId: req.user!.userId, action: 'WITHDRAWAL_PROCESSING', entity: 'WalletTransaction', entityId: id, details: { amount: Number(tx.amount), caregiverId: tx.userId }, ip: req.ip });

  // Notificar al cuidador
  await prisma.notification.create({
    data: {
      userId: tx.userId,
      title: '⏳ Retiro en proceso',
      message: `Tu retiro de Bs ${tx.amount} está siendo procesado. Te notificaremos cuando se complete.`,
      type: 'SYSTEM',
    },
  });

  res.json({ success: true, data: { status: 'PROCESSING' } });
});

export const completeWithdrawal = asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;

  // Fast pre-check outside the transaction (avoids a DB round-trip on completed items)
  const txPre = await prisma.walletTransaction.findUnique({ where: { id } });
  if (!txPre || txPre.type !== 'WITHDRAWAL' || !['PENDING', 'PROCESSING'].includes(txPre.status)) {
    return res.status(400).json({ success: false, error: { message: 'Solicitud no válida' } });
  }

  // All critical checks run INSIDE the transaction so two concurrent admin requests
  // cannot both pass the status guard and double-deduct the balance.
  let notifyUserId: string;
  let notifyAmount: number;

  try {
    await prisma.$transaction(async (prismaTx) => {
      // Re-read under transaction lock to catch concurrent completions
      const tx = await prismaTx.walletTransaction.findUnique({ where: { id } });
      if (!tx || tx.type !== 'WITHDRAWAL' || !['PENDING', 'PROCESSING'].includes(tx.status)) {
        throw Object.assign(new Error('ALREADY_PROCESSED'), { code: 'ALREADY_PROCESSED' });
      }

      const userRecord = await prismaTx.user.findUnique({
        where: { id: tx.userId },
        select: { balance: true },
      });
      if (!userRecord) {
        throw Object.assign(new Error('NO_PROFILE'), { code: 'NO_PROFILE' });
      }

      // Atomic conditional decrement — the earlier read-then-compare against
      // userRecord.balance was check-then-act: two withdrawal requests for
      // the same user, each individually within balance, could both pass this
      // check before either's decrement committed (two admins approving
      // concurrently, or one admin double-clicking). The `balance: gte` guard
      // makes the check and the decrement a single atomic operation.
      const decremented = await prismaTx.user.updateMany({
        where: { id: tx.userId, balance: { gte: tx.amount } },
        data: { balance: { decrement: tx.amount } },
      });
      if (decremented.count === 0) {
        throw Object.assign(
          new Error(`Saldo insuficiente. Tiene Bs ${userRecord.balance}, solicita Bs ${tx.amount}`),
          { code: 'INSUFFICIENT_BALANCE' }
        );
      }
      const updatedUser = await prismaTx.user.findUnique({ where: { id: tx.userId }, select: { balance: true } });
      const newBalance = Number(updatedUser!.balance);

      await prismaTx.walletTransaction.update({
        where: { id },
        data: { status: 'COMPLETED', balance: newBalance },
      });

      await prismaTx.notification.create({
        data: {
          userId: tx.userId,
          title: '✅ Retiro completado',
          message: `Tu retiro de Bs ${tx.amount} fue procesado exitosamente. El dinero ya está en tu cuenta.`,
          type: 'SYSTEM',
        },
      });

      notifyUserId = tx.userId;
      notifyAmount = Number(tx.amount);
    });
  } catch (err: any) {
    if (err.code === 'ALREADY_PROCESSED') {
      return res.status(409).json({ success: false, error: { message: 'Esta solicitud ya fue procesada' } });
    }
    if (err.code === 'NO_PROFILE') {
      return res.status(404).json({ success: false, error: { message: 'Perfil de cuidador no encontrado' } });
    }
    if (err.code === 'INSUFFICIENT_BALANCE') {
      return res.status(409).json({ success: false, error: { message: err.message, code: 'INSUFFICIENT_BALANCE' } });
    }
    throw err;
  }

  auditLog({ userId: req.user!.userId, action: 'WITHDRAWAL_COMPLETED', entity: 'WalletTransaction', entityId: id, details: { amount: notifyAmount!, caregiverId: notifyUserId! }, ip: req.ip });
  res.json({ success: true, data: { status: 'COMPLETED' } });
});

export const rejectWithdrawal = asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  const parsed = rejectWithdrawalSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ success: false, error: { code: 'VALIDATION_ERROR', message: parsed.error.errors } });
  }
  const { reason } = parsed.data;

  const tx = await prisma.walletTransaction.findUnique({ where: { id } });
  if (!tx || tx.type !== 'WITHDRAWAL') {
    return res.status(404).json({ success: false, error: { message: 'Solicitud no encontrada' } });
  }

  // Guard: only allow rejecting PENDING or PROCESSING withdrawals
  if (!['PENDING', 'PROCESSING'].includes(tx.status)) {
    return res.status(409).json({
      success: false,
      error: {
        message: `No se puede rechazar una solicitud en estado ${tx.status}. Solo PENDING o PROCESSING son válidos.`,
        code: 'INVALID_STATUS_TRANSITION',
      },
    });
  }

  await prisma.$transaction(async (prismaTx) => {
    await prismaTx.walletTransaction.update({
      where: { id },
      data: { status: 'REJECTED' },
    });

    await prismaTx.notification.create({
      data: {
        userId: tx.userId,
        title: '❌ Retiro rechazado',
        message: `Tu retiro de Bs ${tx.amount} fue rechazado. ${reason ?? 'Contacta al soporte para más información.'}`,
        type: 'SYSTEM',
      },
    });
  });

  auditLog({ userId: req.user!.userId, action: 'WITHDRAWAL_REJECTED', entity: 'WalletTransaction', entityId: id, details: { amount: Number(tx.amount), caregiverId: tx.userId, reason: reason ?? null }, ip: req.ip });
  res.json({ success: true, data: { status: 'REJECTED' } });
});

/** GET /api/admin/gift-codes — listar todos los códigos de regalo con nombres de usuarios que los usaron */
export const listGiftCodes = asyncHandler(async (_req: Request, res: Response) => {
  const codes = await prisma.giftCode.findMany({ orderBy: { createdAt: 'desc' } });

  // Collect all unique user IDs across all codes
  const allUserIds = [...new Set(codes.flatMap((c) => c.usedBy))];
  const users = allUserIds.length > 0
    ? await prisma.user.findMany({
        where: { id: { in: allUserIds } },
        select: { id: true, firstName: true, lastName: true, email: true },
      })
    : [];
  const userMap = new Map(users.map((u) => [u.id, u]));

  res.json({
    success: true,
    data: codes.map((c) => ({
      id: c.id,
      code: c.code,
      amount: Number(c.amount),
      usedCount: c.usedBy.length,
      maxUses: c.maxUses,
      expiresAt: c.expiresAt?.toISOString() ?? null,
      active: c.active,
      createdAt: c.createdAt.toISOString(),
      usedByUsers: c.usedBy.map((uid) => {
        const u = userMap.get(uid);
        return u
          ? { id: u.id, name: `${u.firstName} ${u.lastName}`, email: u.email }
          : { id: uid, name: 'Usuario desconocido', email: '' };
      }),
    })),
  });
});

/** POST /api/admin/gift-codes — crear nuevo código de regalo */
export const createGiftCode = asyncHandler(async (req: Request, res: Response) => {
  const parsed = createGiftCodeSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ success: false, error: { code: 'VALIDATION_ERROR', message: parsed.error.errors } });
  }
  const { code, amount, maxUses, expiresAt } = parsed.data;

  // Check for duplicate code (give friendly error before DB unique constraint fires)
  const existing = await prisma.giftCode.findFirst({ where: { code: code.toUpperCase().trim() } });
  if (existing) {
    return res.status(409).json({ success: false, error: { code: 'DUPLICATE_CODE', message: 'Ya existe un código con ese nombre' } });
  }

  const created = await prisma.giftCode.create({
    data: {
      code: code.toUpperCase().trim(),
      amount,
      maxUses: maxUses ?? 1,
      expiresAt: expiresAt ? new Date(expiresAt) : undefined,
    },
  });
  res.status(201).json({ success: true, data: { id: created.id, code: created.code } });
});

/** PATCH /api/admin/gift-codes/:id/toggle — activar/desactivar código */
export const toggleGiftCode = asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  const gc = await prisma.giftCode.findUnique({ where: { id } });
  if (!gc) return res.status(404).json({ success: false, error: { message: 'Código no encontrado' } });
  const updated = await prisma.giftCode.update({ where: { id }, data: { active: !gc.active } });
  res.json({ success: true, data: { active: updated.active } });
});

/** GET /api/admin/disputes — listar todas las disputas */
export const getDisputes = asyncHandler(async (req: Request, res: Response) => {
  const status = req.query.status as string | undefined;

  const disputes = await prisma.dispute.findMany({
    where: status ? { status } : {},
    include: {
      booking: {
        include: {
          client: { select: { firstName: true, lastName: true, email: true } },
          caregiver: { include: { user: { select: { firstName: true, lastName: true, email: true } } } },
        },
      },
    },
    orderBy: { createdAt: 'desc' },
  });

  res.json({
    success: true,
    data: disputes.map((d: any) => {
      let aiRecommendations: string[] = [];
      try { aiRecommendations = JSON.parse(d.aiRecommendations ?? '[]'); } catch { /* no-op */ }
      return {
        id: d.id,
        bookingId: d.bookingId,
        status: d.status,
        clientReasons: d.clientReasons,
        caregiverResponse: d.caregiverResponse,
        aiVerdict: d.aiVerdict,
        aiAnalysis: d.aiAnalysis,
        aiRecommendations,
        resolution: d.resolution,
        discountCodeId: d.discountCodeId ?? null,
        createdAt: d.createdAt,
        updatedAt: d.updatedAt,
        clientName: `${d.booking.client.firstName} ${d.booking.client.lastName}`,
        clientEmail: d.booking.client.email,
        caregiverName: `${d.booking.caregiver.user.firstName} ${d.booking.caregiver.user.lastName}`,
        serviceType: d.booking.serviceType,
        petName: d.booking.petName,
        amount: d.booking.totalAmount,
      };
    }),
  });
});

// ─── Owners ──────────────────────────────────────────────────────────────────

/** GET /api/admin/owners */
export const getOwnersList = asyncHandler(async (req: Request, res: Response) => {
  const page = Number(req.query.page) || 1;
  const limit = Number(req.query.limit) || 30;
  const search = req.query.search as string | undefined;
  const data = await adminService.listOwners(page, limit, search);
  res.json({ success: true, data });
});

/** GET /api/admin/owners/:id */
export const getOwnerDetail = asyncHandler(async (req: Request, res: Response) => {
  const data = await adminService.getOwnerDetail(req.params.id!);
  res.json({ success: true, data });
});

// ─── Stats ───────────────────────────────────────────────────────────────────

/** GET /api/admin/stats/live */
export const getLiveStats = asyncHandler(async (_req: Request, res: Response) => {
  const data = await adminService.getLiveStats();
  res.json({ success: true, data });
});

/** GET /api/admin/stats/financial */
export const getFinancialStats = asyncHandler(async (_req: Request, res: Response) => {
  const data = await adminService.getFinancialStats();
  res.json({ success: true, data });
});

// ─── Zones ───────────────────────────────────────────────────────────────────

/** GET /api/admin/zones */
export const getZones = asyncHandler(async (_req: Request, res: Response) => {
  const data = await adminService.getZonesConfig();
  res.json({ success: true, data });
});

/** PATCH /api/admin/zones/:zone/toggle */
export const toggleZone = asyncHandler(async (req: Request, res: Response) => {
  const zone = req.params.zone!.toUpperCase();
  const data = await adminService.toggleZone(zone);
  res.json({ success: true, data });
});

// ── App Settings ─────────────────────────────────────────────────────────

/** GET /api/admin/settings */
export const getSettings = asyncHandler(async (req: Request, res: Response) => {
  const settings = await prisma.appSettings.findMany();
  // Build a key->value map
  const map: Record<string, unknown> = {};
  for (const s of settings) {
    try { map[s.key] = JSON.parse(s.value); } catch { map[s.key] = s.value; }
  }
  // Defaults for keys not yet in DB
  const defaults: Record<string, unknown> = {
    walk30Enabled: true,
    maintenanceMode: false,
    newRegistrationsEnabled: true,
    marketplaceEnabled: true,
    paymentsEnabled: true,
  };
  res.json({ success: true, data: { ...defaults, ...map } });
});

/** PATCH /api/admin/settings/:key */
export const updateSetting = asyncHandler(async (req: Request, res: Response) => {
  const key = req.params.key as string;
  const adminId = req.user?.userId ?? (req.user as { id?: string })?.id;

  // Allowlist: only known setting keys may be modified to prevent arbitrary data injection
  if (!(ALLOWED_SETTING_KEYS as readonly string[]).includes(key)) {
    return res.status(400).json({
      success: false,
      error: {
        code: 'INVALID_SETTING_KEY',
        message: `Clave de configuración desconocida: "${key}". Claves válidas: ${ALLOWED_SETTING_KEYS.join(', ')}`,
      },
    });
  }

  const { value } = req.body;
  if (value === undefined) {
    return res.status(400).json({ success: false, error: { code: 'MISSING_VALUE', message: 'El campo value es requerido' } });
  }

  const stored = await prisma.appSettings.upsert({
    where: { key },
    update: { value: JSON.stringify(value), updatedBy: adminId },
    create: { key, value: JSON.stringify(value), updatedBy: adminId },
  });
  // Invalida el cache del setting modificado para efecto inmediato (sin esperar los 30s)
  const { invalidateSetting } = await import('../../utils/settings-cache.js');
  invalidateSetting(key);
  res.json({ success: true, data: stored });
});

/** GET /api/admin/agent-logs — soporta ?type=PRECIO|... y ?limit= */
export const getAgentLogs = asyncHandler(async (req: Request, res: Response) => {
  const limit = Math.min(parseInt((req.query.limit as string) ?? '50'), 200);
  const type = typeof req.query.type === 'string' && req.query.type !== 'ALL'
    ? req.query.type
    : undefined;
  const logs = await prisma.agentLog.findMany({
    where: type ? { agentType: type } : undefined,
    orderBy: { createdAt: 'desc' },
    take: limit,
  });
  res.json({ success: true, data: logs });
});

/** GET /api/admin/agent-stats — estadísticas del monitor de agentes */
export const getAgentStats = asyncHandler(async (_req: Request, res: Response) => {
  const [total, byType, byStatus, last24h] = await Promise.all([
    prisma.agentLog.count(),
    prisma.agentLog.groupBy({ by: ['agentType'], _count: { id: true } }),
    prisma.agentLog.groupBy({ by: ['status'], _count: { id: true } }),
    prisma.agentLog.count({
      where: { createdAt: { gte: new Date(Date.now() - 24 * 60 * 60 * 1000) } },
    }),
  ]);
  const typeMap: Record<string, number> = {};
  for (const r of byType) typeMap[r.agentType] = r._count.id;
  const statusMap: Record<string, number> = {};
  for (const r of byStatus) statusMap[r.status] = r._count.id;
  res.json({ success: true, data: { total, last24h, byType: typeMap, byStatus: statusMap } });
});

/** POST /api/admin/agent-logs — post a custom instruction/event */
export const postAgentInstruction = asyncHandler(async (req: Request, res: Response) => {
  const parsed = postAgentInstructionSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ success: false, error: { code: 'VALIDATION_ERROR', message: parsed.error.errors } });
  }
  const { agentType, action, input } = parsed.data;
  const adminId = req.user?.userId ?? (req.user as { id?: string })?.id;
  const log = await prisma.agentLog.create({
    data: {
      agentType,
      action: action ?? 'ADMIN_INSTRUCTION',
      input: input ?? null,
      status: 'PENDING',
      userId: adminId,
    },
  });
  res.json({ success: true, data: log });
});

// ─────────────────────────────────────────────
//  NOTIFICACIONES ADMIN
// ─────────────────────────────────────────────

import { sendPush } from '../../services/firebase.service.js';

/** POST /api/admin/notifications/send — broadcast inmediato */
export const sendAdminNotification = asyncHandler(async (req: Request, res: Response) => {
  const parsed = sendAdminNotificationSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ success: false, error: { code: 'VALIDATION_ERROR', message: parsed.error.errors } });
  }
  const { title, message, target, type } = parsed.data;
  const adminId = req.user?.userId;

  // Determinar qué usuarios reciben la notificación
  // NOTE: unknown target explicitly rejected by Zod schema above (enum: TODOS | CUIDADORES | DUENOS)
  let whereRole: object = {};
  if (target === 'CUIDADORES') whereRole = { role: 'CAREGIVER' };
  else if (target === 'DUENOS') whereRole = { role: 'CLIENT' };
  // target === 'TODOS' → whereRole stays {} → all non-deleted users

  const users = await prisma.user.findMany({
    where: { ...whereRole, isDeleted: false },
    select: { id: true, fcmToken: true },
  });

  // Crear notificaciones en DB
  const notifData = users.map(u => ({
    userId: u.id, title, message, type, read: false,
  }));
  await prisma.notification.createMany({ data: notifData });

  // Push FCM (best-effort, no bloquea)
  const pushPromises = users
    .filter(u => !!u.fcmToken)
    .map(u => sendPush(u.fcmToken!, title, message));
  await Promise.allSettled(pushPromises);
  const sentCount = users.length;

  // Guardar historial
  const record = await prisma.adminBroadcastNotification.create({
    data: {
      title, message, target, type,
      sentCount,
      status: 'SENT',
      sentAt: new Date(),
      createdBy: adminId,
    },
  });

  res.json({ success: true, data: { id: record.id, sentCount } });
});

/** POST /api/admin/notifications/schedule — programar para fecha futura */
export const scheduleAdminNotification = asyncHandler(async (req: Request, res: Response) => {
  const parsed = scheduleAdminNotificationSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ success: false, error: { code: 'VALIDATION_ERROR', message: parsed.error.errors } });
  }
  const { title, message, target, type, scheduledAt } = parsed.data;

  const scheduledDate = new Date(scheduledAt);
  if (scheduledDate <= new Date()) {
    return res.status(400).json({ success: false, error: { message: 'scheduledAt debe ser una fecha futura válida' } });
  }

  const adminId = req.user?.userId;
  const record = await prisma.adminBroadcastNotification.create({
    data: {
      title, message, target, type,
      status: 'SCHEDULED',
      scheduledAt: scheduledDate,
      createdBy: adminId,
    },
  });
  res.json({ success: true, data: record });
});

/** GET /api/admin/notifications/scheduled — listar notificaciones programadas */
export const getScheduledNotifications = asyncHandler(async (_req: Request, res: Response) => {
  const items = await prisma.adminBroadcastNotification.findMany({
    where: { status: 'SCHEDULED' },
    orderBy: { scheduledAt: 'asc' },
  });
  res.json({ success: true, data: items });
});

/** DELETE /api/admin/notifications/scheduled/:id — cancelar notificación programada */
export const cancelScheduledNotification = asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  const item = await prisma.adminBroadcastNotification.findUnique({ where: { id } });
  if (!item || item.status !== 'SCHEDULED') {
    return res.status(404).json({ success: false, error: { message: 'Notificación programada no encontrada' } });
  }
  await prisma.adminBroadcastNotification.update({
    where: { id },
    data: { status: 'CANCELLED' },
  });
  res.json({ success: true, data: { cancelled: true } });
});

/** GET /api/admin/notifications/history — historial de notificaciones enviadas */
export const getNotificationHistory = asyncHandler(async (req: Request, res: Response) => {
  const limit = Math.min(parseInt((req.query.limit as string) ?? '50'), 200);
  const items = await prisma.adminBroadcastNotification.findMany({
    where: { status: { in: ['SENT', 'CANCELLED'] } },
    orderBy: { createdAt: 'desc' },
    take: limit,
  });
  res.json({ success: true, data: items });
});

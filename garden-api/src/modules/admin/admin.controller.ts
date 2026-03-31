/**
 * Controlador admin: revisión de cuidadores (approve / reject / request_revision).
 * - GET /api/admin/caregivers/pending
 * - PATCH /api/admin/caregivers/:id/review
 */

import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import prisma from '../../config/database.js';
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

/** GET /api/admin/payments-pending — reservas en PAYMENT_PENDING_APPROVAL. */
export const getPaymentsPending = asyncHandler(async (_req: Request, res: Response) => {
  const result = await adminService.getPaymentsPending();
  res.json({ success: true, data: result });
});

/** GET /api/admin/payments-history — pagos procesados (paidAt != null). */
export const getPaymentsHistory = asyncHandler(async (_req: Request, res: Response) => {
  const result = await adminService.getPaymentsHistory();
  res.json({ success: true, data: result });
});

/** POST /api/admin/bookings/:id/reject-payment — rechazar pago manual (vuelve a PENDING_PAYMENT). */
export const rejectPayment = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const adminId = req.user!.userId;
  const result = await adminService.rejectPayment(bookingId, adminId);
  res.json({ success: true, data: result });
});

/** POST /api/admin/bookings/:id/approve-payment — aprobar pago manual */
export const approvePayment = asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  
  const booking = await prisma.booking.findUnique({ where: { id } });
  if (!booking) return res.status(404).json({ success: false, error: { message: 'Reserva no encontrada' } });
  
  if (booking.status !== 'PAYMENT_PENDING_APPROVAL' && booking.status !== 'PENDING_PAYMENT') {
    return res.status(400).json({ success: false, error: { message: 'La reserva no está en un estado válido para aprobación de pago' } });
  }
  
  await prisma.booking.update({
    where: { id },
    data: { 
      status: 'WAITING_CAREGIVER_APPROVAL',
      paidAt: new Date(),
    },
  });

  // Notificar al cuidador
  const caregiverProfile = await prisma.caregiverProfile.findUnique({
    where: { id: booking.caregiverId },
    select: { userId: true },
  });
  
  if (caregiverProfile) {
    await prisma.notification.create({
      data: {
        userId: caregiverProfile.userId,
        title: 'Nueva reserva confirmada',
        message: 'El pago fue verificado. Tienes una nueva reserva esperando tu aceptación.',
        type: 'NEW_BOOKING',
      },
    });
  }
  
  res.json({ success: true, data: { status: 'WAITING_CAREGIVER_APPROVAL' } });
});

/** GET /api/admin/reservations — listado de reservas, opcional ?status= */
export const getReservations = asyncHandler(async (req: Request, res: Response) => {
  const status = typeof req.query.status === 'string' ? req.query.status : undefined;
  const result = await adminService.getReservations(status);
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
          id: true, firstName: true, lastName: true, email: true,
          caregiverProfile: {
            select: { bankName: true, bankAccount: true, bankHolder: true, bankType: true, balance: true }
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
  
  const tx = await prisma.walletTransaction.findUnique({ where: { id } });
  if (!tx || tx.type !== 'WITHDRAWAL' || !['PENDING', 'PROCESSING'].includes(tx.status)) {
    return res.status(400).json({ success: false, error: { message: 'Solicitud no válida' } });
  }

  // Descontar saldo Y marcar como completado en una transacción
  await prisma.$transaction(async (prismaTx) => {
    await prismaTx.caregiverProfile.update({
      where: { userId: tx.userId },
      data: { balance: { decrement: Number(tx.amount) } },
    });

    const updatedProfile = await prismaTx.caregiverProfile.findUnique({
      where: { userId: tx.userId },
      select: { balance: true },
    });

    await prismaTx.walletTransaction.update({
      where: { id },
      data: { 
        status: 'COMPLETED',
        balance: Number(updatedProfile?.balance ?? 0),
      },
    });

    await prismaTx.notification.create({
      data: {
        userId: tx.userId,
        title: '✅ Retiro completado',
        message: `Tu retiro de Bs ${tx.amount} fue procesado exitosamente. El dinero ya está en tu cuenta.`,
        type: 'SYSTEM',
      },
    });
  });

  res.json({ success: true, data: { status: 'COMPLETED' } });
});

export const rejectWithdrawal = asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  const { reason } = req.body;
  
  const tx = await prisma.walletTransaction.findUnique({ where: { id } });
  if (!tx || tx.type !== 'WITHDRAWAL') {
    return res.status(400).json({ success: false, error: { message: 'Solicitud no encontrada' } });
  }

  await prisma.walletTransaction.update({
    where: { id },
    data: { status: 'REJECTED' },
  });

  await prisma.notification.create({
    data: {
      userId: tx.userId,
      title: '❌ Retiro rechazado',
      message: `Tu retiro de Bs ${tx.amount} fue rechazado. ${reason ?? 'Contacta al soporte para más información.'}`,
      type: 'SYSTEM',
    },
  });

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
  const { code, amount, maxUses, expiresAt } = req.body;
  if (!code || !amount) {
    return res.status(400).json({ success: false, error: { message: 'code y amount son requeridos' } });
  }
  const created = await prisma.giftCode.create({
    data: {
      code: String(code).toUpperCase().trim(),
      amount: Number(amount),
      maxUses: maxUses ? Number(maxUses) : 1,
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
  const data = adminService.getZonesConfig();
  res.json({ success: true, data });
});

/** PATCH /api/admin/zones/:zone/toggle */
export const toggleZone = asyncHandler(async (req: Request, res: Response) => {
  const zone = req.params.zone!.toUpperCase();
  const data = adminService.toggleZone(zone);
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
    walk30Enabled: false,
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
  const { value } = req.body;
  const adminId = req.user?.userId ?? (req.user as { id?: string })?.id;
  const stored = await prisma.appSettings.upsert({
    where: { key },
    update: { value: JSON.stringify(value), updatedBy: adminId },
    create: { key, value: JSON.stringify(value), updatedBy: adminId },
  });
  res.json({ success: true, data: stored });
});

/** GET /api/admin/agent-logs */
export const getAgentLogs = asyncHandler(async (req: Request, res: Response) => {
  const limit = Math.min(parseInt((req.query.limit as string) ?? '50'), 200);
  const logs = await prisma.agentLog.findMany({
    orderBy: { createdAt: 'desc' },
    take: limit,
  });
  res.json({ success: true, data: logs });
});

/** POST /api/admin/agent-logs — post a custom instruction/event */
export const postAgentInstruction = asyncHandler(async (req: Request, res: Response) => {
  const { agentType, action, input } = req.body;
  const adminId = req.user?.userId ?? (req.user as { id?: string })?.id;
  const log = await prisma.agentLog.create({
    data: {
      agentType: agentType ?? 'CUSTOM',
      action: action ?? 'ADMIN_INSTRUCTION',
      input: input ?? null,
      status: 'PENDING',
      userId: adminId,
    },
  });
  res.json({ success: true, data: log });
});

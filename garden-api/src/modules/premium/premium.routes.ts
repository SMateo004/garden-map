import { Router, Request, Response } from 'express';
import rateLimit from 'express-rate-limit';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import { auditLog } from '../../services/audit.service.js';
import * as premium from './premium.service.js';

/**
 * Rutas del cuidador/empresa (titular): Premium y quién paga la comisión.
 * Montadas en /api/caregiver (ver app.ts).
 */
export const caregiverPremiumRoutes = Router();
caregiverPremiumRoutes.use(authMiddleware, requireRole('CAREGIVER'));

// Generar QR repetidas veces no cuesta nada, pero sí ensucia la lista del admin.
const purchaseLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  max: 15,
  // Siempre hay sesión (authMiddleware va antes): se limita por usuario.
  keyGenerator: (req: Request) => req.user?.userId ?? 'anon',
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiados intentos. Espera unos minutos.' } },
  standardHeaders: true,
  legacyHeaders: false,
});

caregiverPremiumRoutes.get(
  '/premium',
  asyncHandler(async (req: Request, res: Response) => {
    res.json({ success: true, data: await premium.getMyPremium(req.user!.userId) });
  })
);

caregiverPremiumRoutes.post(
  '/premium/purchases',
  purchaseLimiter,
  asyncHandler(async (req: Request, res: Response) => {
    res.status(201).json({ success: true, data: await premium.startPurchase(req.user!.userId, req.body?.weeks) });
  })
);

caregiverPremiumRoutes.post(
  '/premium/purchases/:id/declared',
  asyncHandler(async (req: Request, res: Response) => {
    res.json({ success: true, data: await premium.declarePayment(req.user!.userId, req.params.id!) });
  })
);

caregiverPremiumRoutes.post(
  '/premium/purchases/:id/cancel',
  asyncHandler(async (req: Request, res: Response) => {
    res.json({ success: true, data: await premium.cancelPurchase(req.user!.userId, req.params.id!) });
  })
);

caregiverPremiumRoutes.get(
  '/commission-payer',
  asyncHandler(async (req: Request, res: Response) => {
    res.json({ success: true, data: await premium.getMyCommissionPayer(req.user!.userId) });
  })
);

caregiverPremiumRoutes.put(
  '/commission-payer',
  asyncHandler(async (req: Request, res: Response) => {
    const data = await premium.setMyCommissionPayer(req.user!.userId, req.body?.commissionPaidBy);
    auditLog({ userId: req.user!.userId, action: 'COMMISSION_PAYER_CHANGED', entity: 'CaregiverProfile', entityId: req.user!.userId, details: { commissionPaidBy: data.commissionPaidBy }, ip: req.ip });
    res.json({ success: true, data });
  })
);

/** Rutas del admin. Montadas en /api/admin/premium (ver app.ts). */
export const adminPremiumRoutes = Router();
adminPremiumRoutes.use(authMiddleware, requireRole('ADMIN'));

adminPremiumRoutes.get(
  '/settings',
  asyncHandler(async (_req: Request, res: Response) => {
    res.json({ success: true, data: await premium.getPremiumSettings() });
  })
);

adminPremiumRoutes.put(
  '/settings',
  asyncHandler(async (req: Request, res: Response) => {
    const data = await premium.updatePremiumSettings(
      { enabled: req.body?.enabled, priceTable: req.body?.priceTable },
      req.user!.userId
    );
    res.json({ success: true, data });
  })
);

adminPremiumRoutes.get(
  '/purchases',
  asyncHandler(async (req: Request, res: Response) => {
    const filter = typeof req.query.filter === 'string' ? req.query.filter : undefined;
    res.json({ success: true, data: await premium.listPurchasesForAdmin(filter) });
  })
);

adminPremiumRoutes.get(
  '/revenue',
  asyncHandler(async (_req: Request, res: Response) => {
    const now = new Date();
    // Mes calendario de Bolivia (UTC-4).
    const bo = new Date(now.getTime() - 4 * 60 * 60 * 1000);
    const from = new Date(Date.UTC(bo.getUTCFullYear(), bo.getUTCMonth(), 1, 4));
    res.json({ success: true, data: { thisMonth: await premium.premiumRevenue(from, now) } });
  })
);

adminPremiumRoutes.post(
  '/purchases/:id/approve',
  asyncHandler(async (req: Request, res: Response) => {
    res.json({ success: true, data: await premium.approvePurchase(req.params.id!, req.user!.userId) });
  })
);

adminPremiumRoutes.post(
  '/purchases/:id/reject',
  asyncHandler(async (req: Request, res: Response) => {
    res.json({ success: true, data: await premium.rejectPurchase(req.params.id!, req.user!.userId, req.body?.reason) });
  })
);

adminPremiumRoutes.post(
  '/purchases/:id/review',
  asyncHandler(async (req: Request, res: Response) => {
    res.json({ success: true, data: await premium.reviewAutoApproved(req.params.id!, req.user!.userId, req.body?.outcome) });
  })
);

adminPremiumRoutes.post(
  '/purchases/:id/revoke',
  asyncHandler(async (req: Request, res: Response) => {
    res.json({
      success: true,
      data: await premium.revokePurchase(req.params.id!, req.user!.userId, {
        reason: req.body?.reason,
        adminPassword: req.body?.adminPassword,
      }),
    });
  })
);

adminPremiumRoutes.get(
  '/caregivers/:caregiverId',
  asyncHandler(async (req: Request, res: Response) => {
    res.json({ success: true, data: await premium.getCaregiverPremiumForAdmin(req.params.caregiverId!) });
  })
);

adminPremiumRoutes.post(
  '/caregivers/:caregiverId/activate',
  asyncHandler(async (req: Request, res: Response) => {
    const data = await premium.activateManually(req.params.caregiverId!, req.user!.userId, {
      weeks: req.body?.weeks,
      paymentKind: req.body?.paymentKind,
      note: req.body?.note,
      adminPassword: req.body?.adminPassword,
    });
    auditLog({ userId: req.user!.userId, action: 'PREMIUM_MANUAL', entity: 'CaregiverProfile', entityId: req.params.caregiverId!, details: { weeks: req.body?.weeks, amount: data.amount }, ip: req.ip });
    res.json({ success: true, data });
  })
);

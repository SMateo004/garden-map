import { Router, Request, Response } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import { BadRequestError } from '../../shared/errors.js';
import { startServiceBodySchema } from '../booking-service/booking.validation.js';
import * as bookingService from '../booking-service/booking.service.js';
import * as transport from './transport.service.js';

// ── Handlers de viajes (los usan booking.routes, las rutas de empleados y el admin) ──

/** POST …/:id/transport/:kind/en-route */
export const legEnRoute = asyncHandler(async (req: Request, res: Response) => {
  const data = await transport.markLegEnRoute(req.params.id!, req.user!.userId, transport.parseLegKind(req.params.kind));
  res.json({ success: true, data });
});

/** POST …/:id/transport/:kind/arrive */
export const legArrive = asyncHandler(async (req: Request, res: Response) => {
  const data = await transport.markLegArrived(req.params.id!, req.user!.userId, transport.parseLegKind(req.params.kind));
  res.json({ success: true, data });
});

/** POST …/:id/transport/pickup/done — "Recogí a X" (con foto): inicia el servicio. */
export const pickupDone = asyncHandler(async (req: Request, res: Response) => {
  const parsed = startServiceBodySchema.safeParse(req.body);
  if (!parsed.success) throw new BadRequestError('Toma una foto de la mascota al recogerla.', 'VALIDATION_ERROR');
  const data = await bookingService.pickUpPet(req.params.id!, req.user!.userId, parsed.data.photo);
  res.json({ success: true, data });
});

/** POST …/:id/transport/pickup/at-base — "Ya llegamos". */
export const pickupAtBase = asyncHandler(async (req: Request, res: Response) => {
  const data = await transport.markPickupAtBase(req.params.id!, req.user!.userId);
  res.json({ success: true, data });
});

/** POST …/:id/transport/:kind/cancel — dueño o cuidador (el rol sale del token). */
export const legCancel = asyncHandler(async (req: Request, res: Response) => {
  const role = (req.user!.activeRole ?? req.user!.role) as string;
  const actor = role === 'CLIENT' ? 'CLIENT' : role === 'ADMIN' ? 'ADMIN' : 'CAREGIVER';
  const data = await transport.cancelLeg(
    req.params.id!,
    { userId: req.user!.userId, role: actor },
    transport.parseLegKind(req.params.kind),
    req.body?.reason
  );
  res.json({ success: true, data });
});

// ── /api/caregiver/transport (ajustes del titular) ──
export const caregiverTransportRoutes = Router();
caregiverTransportRoutes.get(
  '/transport',
  authMiddleware,
  requireRole('CAREGIVER'),
  asyncHandler(async (req: Request, res: Response) => {
    res.json({ success: true, data: await transport.getMyTransport(req.user!.userId) });
  })
);
caregiverTransportRoutes.put(
  '/transport',
  authMiddleware,
  requireRole('CAREGIVER'),
  asyncHandler(async (req: Request, res: Response) => {
    res.json({ success: true, data: await transport.setMyTransport(req.user!.userId, req.body ?? {}) });
  })
);

// ── /api/caregivers/:id/transport-quote (dueño, antes de reservar) ──
export const transportQuoteRoutes = Router();
transportQuoteRoutes.get(
  '/:id/transport-quote',
  authMiddleware,
  requireRole('CLIENT'),
  asyncHandler(async (req: Request, res: Response) => {
    const serviceType = typeof req.query.serviceType === 'string' ? req.query.serviceType.toUpperCase() : undefined;
    res.json({ success: true, data: await transport.quoteForClient(req.user!.userId, req.params.id!, serviceType) });
  })
);

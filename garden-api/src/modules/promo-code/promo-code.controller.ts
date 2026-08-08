import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as promoCodeService from './promo-code.service.js';
import { applyPromoCodeSchema, createPromoCodeSchema } from './promo-code.validation.js';

/** POST /api/bookings/:id/promo-code — aplicar código promocional al checkout. */
export const apply = asyncHandler(async (req: Request, res: Response) => {
  const bookingId = req.params.id!;
  const clientId = req.user!.userId;
  const body = applyPromoCodeSchema.parse(req.body);
  const data = await promoCodeService.applyPromoCode(bookingId, clientId, body.code);
  res.json({ success: true, data });
});

/** POST /api/admin/promo-codes — crear código (sin UI propia todavía). */
export const create = asyncHandler(async (req: Request, res: Response) => {
  const body = createPromoCodeSchema.parse(req.body);
  const data = await promoCodeService.createPromoCode(body);
  res.status(201).json({ success: true, data });
});

/** GET /api/admin/promo-codes */
export const list = asyncHandler(async (_req: Request, res: Response) => {
  const data = await promoCodeService.listPromoCodes();
  res.json({ success: true, data });
});

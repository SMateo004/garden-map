import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as referralService from './referral.service.js';
import { applyReferralCodeSchema } from './referral.validation.js';

/** GET /api/referral — mi código propio + cuántos referí + si puedo cargar uno ajeno. */
export const getMy = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const data = await referralService.getMyReferral(userId);
  res.json({ success: true, data });
});

/** POST /api/referral/apply — cargar el código de quien me invitó. */
export const apply = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const body = applyReferralCodeSchema.parse(req.body);
  const data = await referralService.applyReferralCode(userId, body.code);
  res.json({ success: true, data });
});

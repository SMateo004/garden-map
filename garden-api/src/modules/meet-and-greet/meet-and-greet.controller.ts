import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as svc from './meet-and-greet.service.js';

export const get = asyncHandler(async (req: Request, res: Response) => {
  const mg = await svc.getMeetAndGreet(req.params.bookingId!);
  res.json({ success: true, data: mg });
});

export const propose = asyncHandler(async (req: Request, res: Response) => {
  const { getBoolSetting } = await import('../../utils/settings-cache.js');
  if (!await getBoolSetting('meetGreetEnabled', true)) {
    return res.status(503).json({
      success: false,
      error: { code: 'MEET_GREET_DISABLED', message: 'El Meet & Greet está temporalmente deshabilitado.' },
    });
  }
  const mg = await svc.propose(req.params.bookingId!, (req as any).user.userId, req.body);
  res.json({ success: true, data: mg });
});

export const accept = asyncHandler(async (req: Request, res: Response) => {
  const mg = await svc.accept(req.params.bookingId!, (req as any).user.userId);
  res.json({ success: true, data: mg });
});

export const reschedule = asyncHandler(async (req: Request, res: Response) => {
  const mg = await svc.reschedule(req.params.bookingId!, (req as any).user.userId, req.body);
  res.json({ success: true, data: mg });
});

export const complete = asyncHandler(async (req: Request, res: Response) => {
  const mg = await svc.complete(req.params.bookingId!, (req as any).user.userId, req.body);
  res.json({ success: true, data: mg });
});

export const cancel = asyncHandler(async (req: Request, res: Response) => {
  const mg = await svc.cancel(req.params.bookingId!, (req as any).user.userId);
  res.json({ success: true, data: mg });
});

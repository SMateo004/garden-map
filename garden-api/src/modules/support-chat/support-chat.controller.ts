import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as service from './support-chat.service.js';

// ── Cliente ──────────────────────────────────────────────────────────────

export const sendMessage = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const data = await service.sendClientMessage(userId, req.body?.message);
  res.status(201).json({ success: true, data });
});

/** GET /support/chat — devuelve la conversación actual completa. Ya no
 * "empieza de cero" al abrir la app: persiste hasta que un admin la marca
 * resuelta (ver resolveThread / resolvedAt en SupportThread). */
export const getSessionMessages = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const data = await service.getClientSessionMessages(userId);
  res.json({ success: true, data });
});

// ── Admin ────────────────────────────────────────────────────────────────

export const listThreads = asyncHandler(async (_req: Request, res: Response) => {
  const data = await service.listThreadsForAdmin();
  res.json({ success: true, data });
});

export const getThreadMessages = asyncHandler(async (req: Request, res: Response) => {
  const data = await service.getThreadMessagesForAdmin(req.params.threadId!);
  res.json({ success: true, data });
});

export const reply = asyncHandler(async (req: Request, res: Response) => {
  const adminUserId = req.user!.userId;
  const data = await service.sendAdminReply(adminUserId, req.params.threadId!, req.body?.message);
  res.status(201).json({ success: true, data });
});

export const markRead = asyncHandler(async (req: Request, res: Response) => {
  await service.markThreadReadByAdmin(req.params.threadId!);
  res.json({ success: true, data: { ok: true } });
});

/** POST /admin/support/threads/:threadId/resolve — cierra el caso. Recién acá
 * el cliente vuelve a "empezar de cero" en su próximo mensaje. */
export const resolve = asyncHandler(async (req: Request, res: Response) => {
  const data = await service.resolveThread(req.params.threadId!);
  res.json({ success: true, data });
});

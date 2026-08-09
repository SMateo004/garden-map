import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import { BadRequestError } from '../../shared/errors.js';
import * as service from './support-chat.service.js';

// ── Cliente ──────────────────────────────────────────────────────────────

export const sendMessage = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const data = await service.sendClientMessage(userId, req.body?.message);
  res.status(201).json({ success: true, data });
});

/** GET /support/chat?since=<ISO> — `since` es obligatorio: lo calcula la app
 * una sola vez al arrancar el proceso, así la conversación "empieza de cero"
 * cada vez que el cliente cierra y vuelve a abrir la app. */
export const getSessionMessages = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const sinceRaw = req.query.since;
  if (typeof sinceRaw !== 'string' || !sinceRaw) {
    throw new BadRequestError('Falta el parámetro since', 'MISSING_SINCE');
  }
  const since = new Date(sinceRaw);
  if (Number.isNaN(since.getTime())) {
    throw new BadRequestError('since inválido', 'INVALID_SINCE');
  }
  const data = await service.getClientSessionMessages(userId, since);
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

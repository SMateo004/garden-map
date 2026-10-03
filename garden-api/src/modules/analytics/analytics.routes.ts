/**
 * POST /api/analytics/batch — ingesta de uso de la app (sesión + eventos).
 * Pública (también la usan invitados), identifica al usuario solo si manda un
 * JWT válido. Siempre responde 204: la analítica jamás debe romper la app.
 */
import { Router } from 'express';
import jwt from 'jsonwebtoken';
import rateLimit from 'express-rate-limit';
import { env } from '../../config/env.js';
import logger from '../../shared/logger.js';
import { ingestBatch } from './analytics.service.js';
import type { JwtPayload } from '../../middleware/auth.middleware.js';

const router = Router();

const limiter = rateLimit({
  windowMs: 60_000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (_req, res) => { res.status(204).end(); },
});

router.post('/batch', limiter, (req, res) => {
  res.status(204).end();
  let userId: string | null = null;
  const header = req.headers.authorization;
  if (header?.startsWith('Bearer ')) {
    try {
      userId = (jwt.verify(header.slice(7), env.JWT_SECRET) as JwtPayload).userId ?? null;
    } catch { /* token vencido: se registra como invitado */ }
  }
  ingestBatch(req.body, userId).catch((err) =>
    logger.warn('[ANALYTICS] ingest failed', { err: (err as Error).message }));
});

export default router;

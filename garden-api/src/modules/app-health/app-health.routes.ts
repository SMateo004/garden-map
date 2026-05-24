/**
 * POST /api/app/error-report
 * Recibe errores críticos de la app (Flutter) y notifica al admin por push.
 * No requiere rol ADMIN — funciona con o sin sesión activa.
 */
import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { asyncHandler } from '../../shared/async-handler.js';
import { sendPushToUser } from '../../services/firebase.service.js';
import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';

const router = Router();

// Máximo 5 reportes por IP por minuto para evitar spam
const errorReportLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Demasiados reportes. Intenta más tarde.' },
});

router.post('/error-report', errorReportLimiter, asyncHandler(async (req, res) => {
  const { error, stackTrace, platform, timestamp } = req.body as {
    error?: string;
    stackTrace?: string;
    platform?: string;
    timestamp?: string;
  };

  if (!error) {
    res.status(400).json({ success: false, message: 'error field required' });
    return;
  }

  logger.error('[APP-ERROR] Client error report received', {
    error: error.substring(0, 200),
    platform,
    timestamp,
  });

  // Notificar a todos los admins que tienen token FCM registrado
  try {
    const admins = await prisma.user.findMany({
      where: { role: 'ADMIN', fcmToken: { not: null } },
      select: { id: true },
    });

    if (admins.length > 0) {
      const title = `🚨 Error en la app (${platform ?? 'unknown'})`;
      const body = error.length > 100 ? `${error.substring(0, 97)}...` : error;

      await Promise.allSettled(
        admins.map((admin) => sendPushToUser(admin.id, title, body))
      );
    }
  } catch (pushErr) {
    logger.warn('[APP-ERROR] No se pudo notificar al admin', { pushErr });
  }

  res.json({ success: true });
}));

export default router;

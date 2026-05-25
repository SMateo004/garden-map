/**
 * POST /api/app/error-report
 *
 * Recibe errores críticos de la app Flutter.
 * El Agente de Resolución de Errores:
 *  1. Clasifica el tipo y severidad del error (via Claude)
 *  2. Intenta remediación automática cuando es posible
 *  3. Notifica al admin con: tipo de error, severidad y resultado de resolución
 *
 * No requiere rol ADMIN — accesible con o sin sesión activa.
 * Protegido por: rate limiting estricto + header X-App-Secret opcional.
 */
import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { asyncHandler } from '../../shared/async-handler.js';
import { analyzeAndResolveError } from '../../agents/error-resolution.agent.js';
import { sendPushToUser } from '../../services/firebase.service.js';
import { env } from '../../config/env.js';
import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';

const router = Router();

// Máximo 3 reportes por IP por minuto — más restrictivo para evitar spam / loops de error
const errorReportLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 3,
  standardHeaders: true,
  legacyHeaders: false,
  skipFailedRequests: false,
  message: { success: false, message: 'Demasiados reportes. Intenta más tarde.' },
});

// Si APP_SECRET está configurado en el entorno, valida el header X-App-Secret
// para asegurar que sólo builds legítimas de la app pueden reportar errores.
const _appSecret = (env as Record<string, unknown>)['APP_SECRET'] as string | undefined;

// Emojis por severidad para el título del push
const SEVERITY_EMOJI: Record<string, string> = {
  critical: '🔴',
  high:     '🟠',
  medium:   '🟡',
  low:      '🔵',
};

router.post('/error-report', errorReportLimiter, asyncHandler(async (req, res) => {
  // Optional app-secret validation: if APP_SECRET is set, reject requests
  // that don't include the matching X-App-Secret header.
  if (_appSecret) {
    const supplied = req.headers['x-app-secret'] as string | undefined;
    if (!supplied || supplied !== _appSecret) {
      logger.warn('[APP-HEALTH] Rejected error-report — bad or missing X-App-Secret', { ip: req.ip });
      // Return 200 to avoid leaking whether the endpoint exists to scanners
      res.json({ success: true });
      return;
    }
  }

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

  logger.error('[APP-HEALTH] Error report received', {
    error: error.substring(0, 200),
    platform,
    timestamp,
  });

  // Responder al cliente inmediatamente — el agente trabaja en background
  res.json({ success: true });

  // ── Agente de resolución (background, no bloquea la respuesta) ────────────
  setImmediate(async () => {
    try {
      // 1 ─ Clasificar y remediar
      const result = await analyzeAndResolveError({
        error,
        stackTrace,
        platform,
        timestamp,
      });

      const { analysis, isResolved, actionTaken, requiresManualAction, manualActionGuide } = result;
      const emoji = SEVERITY_EMOJI[analysis.severity] ?? '⚪';

      // 2 ─ Construir notificaciones para el admin
      // Notificación 1: reporte inicial + tipo de error
      const initialTitle = `${emoji} [${analysis.errorTypeLabel}] Error en la app`;
      const initialBody = `${analysis.summary} • ${analysis.severity.toUpperCase()} • ${platform ?? 'unknown'}`;

      // Notificación 2: resultado de la resolución
      const resolvedTitle = isResolved
        ? `✅ Error resuelto automáticamente`
        : requiresManualAction
          ? `⚠️ Acción manual requerida`
          : `ℹ️ Error registrado sin solución automática`;

      const resolvedBody = isResolved
        ? `${analysis.errorTypeLabel}: ${actionTaken}`
        : `${analysis.errorTypeLabel}: ${manualActionGuide ?? actionTaken}`;

      // 3 ─ Obtener admins con token FCM
      const admins = await prisma.user.findMany({
        where: { role: 'ADMIN', fcmToken: { not: null } },
        select: { id: true },
      });

      if (admins.length === 0) {
        logger.warn('[APP-HEALTH] No admin FCM tokens found — push skipped');
        return;
      }

      // 4 ─ Enviar ambas notificaciones con 3 segundos de separación
      await Promise.allSettled(
        admins.map((admin) => sendPushToUser(admin.id, initialTitle, initialBody))
      );

      // Pequeña pausa para que lleguen como dos notificaciones separadas y visibles
      await new Promise((r) => setTimeout(r, 3000));

      await Promise.allSettled(
        admins.map((admin) => sendPushToUser(admin.id, resolvedTitle, resolvedBody))
      );

      logger.info('[APP-HEALTH] Agent completed', {
        errorType: analysis.errorType,
        severity: analysis.severity,
        isResolved,
        actionTaken,
      });
    } catch (agentErr) {
      logger.error('[APP-HEALTH] Agent failed', { agentErr });

      // Fallback: notificación básica sin análisis de agente
      try {
        const admins = await prisma.user.findMany({
          where: { role: 'ADMIN', fcmToken: { not: null } },
          select: { id: true },
        });
        const fallbackTitle = `🚨 Error en la app (${platform ?? 'unknown'})`;
        const fallbackBody = error.length > 100 ? `${error.substring(0, 97)}...` : error;
        await Promise.allSettled(
          admins.map((admin) => sendPushToUser(admin.id, fallbackTitle, fallbackBody))
        );
      } catch (_) { /* silencioso */ }
    }
  });
}));

export default router;

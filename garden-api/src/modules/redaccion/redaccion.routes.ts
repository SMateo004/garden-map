/**
 * Botón "Mejorar con IA" de los campos de texto libre.
 *
 * POST /api/ai/improve-text — cualquier usuario con sesión (cuidador, dueño, mascota…).
 * Body: { field, text?, notes? }. Con texto lo mejora; sin texto redacta uno nuevo a partir de
 * `notes`. Devuelve { text, mode }. Los campos válidos están en CAMPOS_REDACCION
 * (agents/redaccion.agent.ts). El cuidador además lo tiene en /api/caregiver/profile/improve-text
 * (misma lógica, ruta histórica que usan las versiones anteriores de la app).
 */
import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import { mejorarRedaccion, RedaccionRechazadaError } from '../../agents/redaccion.agent.js';
import logger from '../../shared/logger.js';

// Cada llamada es una invocación real y facturada a Claude: límite por usuario (no por IP).
export const improveTextLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 30,
  keyGenerator: (req) => (req as any).user?.userId ?? req.ip ?? 'anon',
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Usaste mucho el asistente de IA. Intenta de nuevo en un rato.' } },
});

export const improveTextHandler = asyncHandler(async (req, res) => {
  const { field, text, notes } = (req.body ?? {}) as { field?: unknown; text?: unknown; notes?: unknown };
  if (typeof field !== 'string') {
    return res.status(400).json({ success: false, error: { code: 'INVALID_BODY', message: 'field es requerido' } });
  }
  try {
    const out = await mejorarRedaccion({
      campo: field,
      texto: typeof text === 'string' ? text : undefined,
      notas: typeof notes === 'string' ? notes : undefined,
    });
    return res.json({ success: true, data: { text: out.texto, mode: out.modo } });
  } catch (err) {
    if (err instanceof RedaccionRechazadaError) {
      return res.status(422).json({ success: false, error: { code: 'TEXT_NOT_USABLE', message: err.message } });
    }
    logger.warn('[improve-text] fallo técnico', { error: err instanceof Error ? err.message : String(err) });
    return res.status(503).json({ success: false, error: { code: 'AI_UNAVAILABLE', message: 'El asistente de IA no está disponible ahora. Puedes escribirlo tú y lo revisaremos al publicar.' } });
  }
});

const router = Router();
router.post('/improve-text', authMiddleware, improveTextLimiter, improveTextHandler);

export default router;

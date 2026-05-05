import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { analizarCalificacion, analizarDisputa } from '../../agents/reputacion.agent.js';
import {
  sugerirPrecioOnboarding,
  calcularAjusteDinamico,
  explicarBadgeTemporadaAlta,
} from '../../agents/precios.agent.js';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import { runPricingJob } from '../../jobs/ajuste-precios.job.js';
import prisma from '../../config/database.js';

const router = Router();

// ── Rate limiters ────────────────────────────────────────────────────────────
// Claude calls are expensive — limit aggressively to prevent DoS / credit drain
const claudePublicLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiadas consultas al agente. Espera 1 hora.' } },
});

const claudeAuthLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiadas consultas al agente. Espera 1 hora.' } },
});

// ── Input schemas (Zod) ───────────────────────────────────────────────────────
const onboardingPrecioSchema = z.object({
  zona: z.string().min(1).max(100),
  servicio: z.string().min(1).max(50),
  experienciaMeses: z.number().int().min(0).max(600),
  trustScore: z.number().min(0).max(100),
  precioPromedioZona: z.number().min(0).max(10000),
  precioMinZona: z.number().min(0).max(10000),
  precioMaxZona: z.number().min(0).max(10000),
});

const calificacionSchema = z.object({
  calificacionNueva: z.number().min(1).max(5),
  cuidadorId: z.string().min(1).max(100),
  historialCalificaciones: z.array(z.number().min(1).max(5)).max(100),
  calificacionPromedio: z.number().min(0).max(5),
  totalResenas: z.number().int().min(0),
  tiempoEnPlataforma: z.string().min(1).max(100),
  duenoHistorial: z.array(z.number().min(1).max(5)).max(100),
});

const disputaSchema = z.object({
  reserva: z.record(z.unknown()),
  cuidador: z.record(z.unknown()),
  dueno: z.record(z.unknown()),
  mascota: z.record(z.unknown()),
  motivoDisputa: z.string().min(1).max(2000),
  mensajesRelevantes: z.array(z.string().max(500)).max(20).optional(),
});

// ── Helpers ───────────────────────────────────────────────────────────────────
function handleAgentError(res: any, context: string, error: any) {
  const isClientError = error?.message?.includes('JSON inválido') || error?.status === 400;
  const status = isClientError ? 422 : 500;
  return res.status(status).json({
    success: false,
    error: { code: 'AGENT_ERROR', message: `Error en ${context}: ${error?.message ?? 'desconocido'}` },
  });
}

// ── Agente 2: Precios — onboarding (rate-limited, no auth required — is public) ──
// Still rate-limited because it calls Claude (API cost)
router.post('/precio/onboarding', claudePublicLimiter, async (req, res) => {
  try {
    const body = onboardingPrecioSchema.parse(req.body);
    const resultado = await sugerirPrecioOnboarding(body);
    res.json({ success: true, data: resultado });
  } catch (error: any) {
    if (error?.name === 'ZodError') {
      return res.status(400).json({ success: false, error: { code: 'VALIDATION_ERROR', message: error.errors } });
    }
    return handleAgentError(res, 'agente precio onboarding', error);
  }
});

// ── All routes below require auth ─────────────────────────────────────────────
router.use(authMiddleware);

// ── Agente 1: Reputación — analizar calificación ──────────────────────────────
router.post('/calificacion/analizar', claudeAuthLimiter, async (req, res) => {
  try {
    const body = calificacionSchema.parse(req.body);
    const resultado = await analizarCalificacion(body);
    res.json({ success: true, data: resultado });
  } catch (error: any) {
    if (error?.name === 'ZodError') {
      return res.status(400).json({ success: false, error: { code: 'VALIDATION_ERROR', message: error.errors } });
    }
    return handleAgentError(res, 'agente calificación', error);
  }
});

// ── Agente 1: Reputación — analizar disputa ───────────────────────────────────
router.post('/disputa/analizar', claudeAuthLimiter, async (req, res) => {
  try {
    const body = disputaSchema.parse(req.body);
    const resultado = await analizarDisputa(body);
    res.json({ success: true, data: resultado });
  } catch (error: any) {
    if (error?.name === 'ZodError') {
      return res.status(400).json({ success: false, error: { code: 'VALIDATION_ERROR', message: error.errors } });
    }
    return handleAgentError(res, 'agente disputa', error);
  }
});

// ── Agente 2: Precios — ajuste dinámico ──────────────────────────────────────
router.post('/precio/ajuste-dinamico', claudeAuthLimiter, async (req, res) => {
  try {
    const resultado = await calcularAjusteDinamico(req.body);
    res.json({ success: true, data: resultado });
  } catch (error: any) {
    return handleAgentError(res, 'agente ajuste dinámico', error);
  }
});

// ── Agente 2: Precios — explicar badge temporada alta ────────────────────────
router.post('/precio/explicar-badge', claudeAuthLimiter, async (req, res) => {
  try {
    const resultado = await explicarBadgeTemporadaAlta(req.body);
    res.json({ success: true, data: resultado });
  } catch (error: any) {
    return handleAgentError(res, 'agente badge', error);
  }
});

// ── Sugerencias de precio ─────────────────────────────────────────────────────

/** GET: obtener sugerencias pendientes del cuidador autenticado */
router.get('/precio/suggestion', requireRole('CAREGIVER'), async (req, res) => {
  try {
    const userId = (req as any).user!.userId;
    const profile = await prisma.caregiverProfile.findFirst({
      where: { userId },
      select: { id: true },
    });
    if (!profile) return res.json({ success: true, data: [] });

    const suggestions = await prisma.sugerenciaPrecio.findMany({
      where: {
        caregiverId: profile.id,
        status: 'PENDING',
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: 'desc' },
    });

    res.json({ success: true, data: suggestions });
  } catch (err: any) {
    res.status(500).json({ success: false, error: { message: err.message } });
  }
});

/** POST: aceptar sugerencia → actualiza precio del cuidador (atómico) */
router.post('/precio/suggestion/:id/accept', requireRole('CAREGIVER'), async (req, res) => {
  try {
    const userId = (req as any).user!.userId;

    // Atomic: mark ACCEPTED only if still PENDING and owned by this caregiver
    // updateMany returns count=0 if the suggestion is already processed or not owned
    const profile = await prisma.caregiverProfile.findFirst({
      where: { userId },
      select: { id: true },
    });
    if (!profile) {
      return res.status(404).json({ success: false, error: { message: 'Perfil de cuidador no encontrado' } });
    }

    // Load suggestion with ownership check in the same query
    const suggestion = await prisma.sugerenciaPrecio.findFirst({
      where: {
        id: req.params.id,
        caregiverId: profile.id, // ← ownership enforced here
        status: 'PENDING',
        expiresAt: { gt: new Date() },
      },
    });

    if (!suggestion) {
      return res.status(404).json({
        success: false,
        error: { message: 'Sugerencia no encontrada, ya procesada o expirada' },
      });
    }

    // Atomic accept: only succeeds if suggestion is still PENDING (prevents race condition)
    const accepted = await prisma.sugerenciaPrecio.updateMany({
      where: { id: suggestion.id, status: 'PENDING' },
      data: { status: 'ACCEPTED' },
    });

    if (accepted.count === 0) {
      return res.status(409).json({
        success: false,
        error: { message: 'La sugerencia ya fue procesada por otra solicitud simultánea' },
      });
    }

    // Actualizar precio en el perfil del cuidador
    // Convention: pricePerWalk60 is the canonical PASEO price; walk30 = walk60 / 2
    const priceField =
      suggestion.serviceType === 'PASEO'
        ? {
            pricePerWalk60: suggestion.precioSugerido,
            pricePerWalk30: Math.round(suggestion.precioSugerido / 2),
          }
        : { pricePerDay: suggestion.precioSugerido };

    await prisma.caregiverProfile.update({
      where: { id: suggestion.caregiverId },
      data: priceField,
    });

    res.json({
      success: true,
      data: { message: 'Precio actualizado exitosamente', newPrice: suggestion.precioSugerido },
    });
  } catch (err: any) {
    res.status(500).json({ success: false, error: { message: err.message } });
  }
});

/** POST: rechazar sugerencia (ownership enforced) */
router.post('/precio/suggestion/:id/reject', requireRole('CAREGIVER'), async (req, res) => {
  try {
    const userId = (req as any).user!.userId;

    const profile = await prisma.caregiverProfile.findFirst({
      where: { userId },
      select: { id: true },
    });
    if (!profile) {
      return res.status(404).json({ success: false, error: { message: 'Perfil no encontrado' } });
    }

    // Ownership + status check in a single atomic operation
    const result = await prisma.sugerenciaPrecio.updateMany({
      where: {
        id: req.params.id,
        caregiverId: profile.id, // ← ownership enforced
        status: 'PENDING',
      },
      data: { status: 'REJECTED' },
    });

    if (result.count === 0) {
      return res.status(404).json({
        success: false,
        error: { message: 'Sugerencia no encontrada o ya procesada' },
      });
    }

    res.json({ success: true });
  } catch (err: any) {
    res.status(500).json({ success: false, error: { message: err.message } });
  }
});

/** POST: forzar generación de sugerencias — SOLO ADMIN */
router.post(
  '/precio/generate-suggestions',
  requireRole('ADMIN'),
  async (req, res) => {
    try {
      runPricingJob().catch(err =>
        console.error('[PRICING] Background job error:', err)
      );
      res.json({ success: true, message: 'Job de precios iniciado en background' });
    } catch (err: any) {
      res.status(500).json({ success: false, error: { message: err.message } });
    }
  }
);

export default router;

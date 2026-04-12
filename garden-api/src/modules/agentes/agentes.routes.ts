import { Router } from 'express';
import { analizarCalificacion, analizarDisputa } from '../../agents/reputacion.agent.js';
import { sugerirPrecioOnboarding, calcularAjusteDinamico, explicarBadgeTemporadaAlta } from '../../agents/precios.agent.js';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import { runPricingJob } from '../../jobs/ajuste-precios.job.js';

const router = Router();

// --- Agente 2: Precios Inteligentes (Públicos o sin sesión completa) ---
router.post('/precio/onboarding', async (req, res) => {
    try {
        const resultado = await sugerirPrecioOnboarding(req.body);
        res.json(resultado);
    } catch (error: any) {
        console.error('Error en agente precio onboarding:', error);
        res.status(500).json({ error: 'Error al sugerir precio', details: error.message });
    }
});

// Usamos el middleware para el resto de rutas donde la app de Flutter envía el token
router.use(authMiddleware);

// --- Agente 1: Reputación y Disputas ---
router.post('/calificacion/analizar', async (req, res) => {
    try {
        const resultado = await analizarCalificacion(req.body);
        res.json(resultado);
    } catch (error: any) {
        console.error('Error en agente calificación:', error);
        res.status(500).json({ error: 'Error al analizar calificación', details: error.message });
    }
});

router.post('/disputa/analizar', async (req, res) => {
    try {
        const resultado = await analizarDisputa(req.body);
        res.json(resultado);
    } catch (error: any) {
        console.error('Error en agente disputa:', error);
        res.status(500).json({ error: 'Error al analizar disputa', details: error.message });
    }
});

// --- Agente 2: Precios Inteligentes (Con sesión) ---
router.post('/precio/ajuste-dinamico', async (req, res) => {
    try {
        const resultado = await calcularAjusteDinamico(req.body);
        res.json(resultado);
    } catch (error: any) {
        console.error('Error en agente ajuste dinamico:', error);
        res.status(500).json({ error: 'Error al calcular ajuste', details: error.message });
    }
});

router.post('/precio/explicar-badge', async (req, res) => {
    try {
        const resultado = await explicarBadgeTemporadaAlta(req.body);
        res.json(resultado);
    } catch (error: any) {
        console.error('Error en agente explicar badge:', error);
        res.status(500).json({ error: 'Error al generar explicación', details: error.message });
    }
});

// --- Sugerencias de precio por cuidador ---

// GET: obtener sugerencia pendiente del cuidador autenticado
router.get('/precio/suggestion', requireRole('CAREGIVER'), async (req, res) => {
    try {
        const userId = (req as any).user!.userId;
        const profile = await (await import('../../config/database.js')).default.caregiverProfile.findFirst({
            where: { userId },
            select: { id: true },
        });
        if (!profile) return res.json({ success: true, data: null });

        const db = (await import('../../config/database.js')).default;
        const suggestions = await db.sugerenciaPrecio.findMany({
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

// POST: aceptar sugerencia → actualiza precio del cuidador
router.post('/precio/suggestion/:id/accept', requireRole('CAREGIVER'), async (req, res) => {
    try {
        const userId = (req as any).user!.userId;
        const db = (await import('../../config/database.js')).default;

        const suggestion = await db.sugerenciaPrecio.findUnique({
            where: { id: req.params.id },
            include: { caregiver: { select: { userId: true } } },
        });

        if (!suggestion || suggestion.caregiver.userId !== userId) {
            return res.status(404).json({ success: false, error: { message: 'Sugerencia no encontrada' } });
        }
        if (suggestion.status !== 'PENDING') {
            return res.status(400).json({ success: false, error: { message: 'Sugerencia ya procesada' } });
        }

        // Actualizar precio en el perfil del cuidador
        const priceField = suggestion.serviceType === 'PASEO'
            ? { pricePerWalk30: suggestion.precioSugerido, pricePerWalk60: Math.round(suggestion.precioSugerido * 1.7) }
            : { pricePerDay: suggestion.precioSugerido };

        await db.caregiverProfile.update({
            where: { id: suggestion.caregiverId },
            data: priceField,
        });

        await db.sugerenciaPrecio.update({
            where: { id: suggestion.id },
            data: { status: 'ACCEPTED' },
        });

        res.json({ success: true, data: { message: 'Precio actualizado exitosamente', newPrice: suggestion.precioSugerido } });
    } catch (err: any) {
        res.status(500).json({ success: false, error: { message: err.message } });
    }
});

// POST: rechazar sugerencia
router.post('/precio/suggestion/:id/reject', requireRole('CAREGIVER'), async (req, res) => {
    try {
        const db = (await import('../../config/database.js')).default;
        await db.sugerenciaPrecio.update({
            where: { id: req.params.id },
            data: { status: 'REJECTED' },
        });
        res.json({ success: true });
    } catch (err: any) {
        res.status(500).json({ success: false, error: { message: err.message } });
    }
});

// POST: forzar generación (solo para admin/testing)
router.post('/precio/generate-suggestions', async (req, res) => {
    try {
        runPricingJob().catch(err => console.error('[PRICING] Background job error:', err));
        res.json({ success: true, message: 'Job iniciado en background' });
    } catch (err: any) {
        res.status(500).json({ success: false, error: { message: err.message } });
    }
});

export default router;

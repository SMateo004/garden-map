import { Router } from 'express';
import { analizarCalificacion, analizarDisputa } from '../../agents/reputacion.agent.js';
import { sugerirPrecioOnboarding, calcularAjusteDinamico, explicarBadgeTemporadaAlta } from '../../agents/precios.agent.js';
import { authMiddleware } from '../../middleware/auth.middleware.js';

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

export default router;

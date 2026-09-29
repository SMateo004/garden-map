import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import * as controller from './support-chat.controller.js';

const router = Router();
router.use(authMiddleware);

// Mismo límite que el chat cliente-cuidador (chat.routes.ts) — 60/min alcanza
// de sobra para una conversación real y frena flood/spam.
//
// FIX (auditoría 2026-09-27, B5): antes, sin `keyGenerator`, express-rate-limit
// usa el IP como clave por defecto — un usuario autenticado podía generar
// decenas de miles de llamadas a Claude por día rotando de red/IP (datos
// móviles, VPN, wifi distinto), ya que cada IP nueva arrancaba su propia
// cuota de 60/min. Esta ruta ya vive detrás de authMiddleware, así que se
// puede limitar por userId real en vez de por IP — cierra ese vector y de
// paso evita que varios usuarios detrás del mismo IP compartido (NAT, wifi
// de oficina) se bloqueen entre sí.
const supportMessageLimiter = rateLimit({
  windowMs: 60 * 1_000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => (req as any).user?.userId ?? req.ip,
  message: { success: false, error: { code: 'RATE_LIMITED', message: 'Demasiados mensajes. Espera un momento.' } },
});

router.get('/', controller.getSessionMessages);
router.post('/', supportMessageLimiter, controller.sendMessage);

export default router;

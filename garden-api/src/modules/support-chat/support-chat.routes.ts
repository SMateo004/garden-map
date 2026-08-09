import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import * as controller from './support-chat.controller.js';

const router = Router();
router.use(authMiddleware);

// Mismo límite que el chat cliente-cuidador (chat.routes.ts) — 60/min alcanza
// de sobra para una conversación real y frena flood/spam.
const supportMessageLimiter = rateLimit({
  windowMs: 60 * 1_000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'RATE_LIMITED', message: 'Demasiados mensajes. Espera un momento.' } },
});

router.get('/', controller.getSessionMessages);
router.post('/', supportMessageLimiter, controller.sendMessage);

export default router;

import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import * as authController from './auth.controller.js';

// ── Rate limiters ────────────────────────────────────────────────────────────
// 5 intentos por 15 min — bloquea brute force; no cuenta logins exitosos
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiados intentos. Espera 15 minutos e inténtalo de nuevo.' } },
});

// 3 registros por hora por IP — evita creación masiva de cuentas
const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 3,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiados intentos de registro. Espera 1 hora.' } },
});

// 3 envíos de código por hora — previene spam de email
const emailCodeLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 3,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiados envíos de código. Espera 1 hora.' } },
});

// 10 intentos de refresh por hora — permite uso normal, bloquea abuso
const refreshLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiadas renovaciones de sesión.' } },
});

// ── Rutas ────────────────────────────────────────────────────────────────────
const router = Router();

router.get('/me', authMiddleware, authController.me);
router.patch('/me', authMiddleware, authController.patchMe);
router.get('/check-email', authController.checkEmail);

router.post('/caregiver/register', registerLimiter, authController.registerCaregiver);
router.post('/client/register',    registerLimiter, authController.registerClient);
router.post('/login',              loginLimiter,    authController.login);

/** POST /api/auth/refresh — body: { refreshToken }. Rota el refresh token y devuelve nuevos tokens. */
router.post('/refresh', refreshLimiter, authController.refreshToken);

/** POST /api/auth/logout — revoca todos los refresh tokens del usuario. */
router.post('/logout', authMiddleware, authController.logout);

/** POST /api/auth/send-verification-email — sends 6-digit code (10 min expiry). */
router.post('/send-verification-email', authMiddleware, emailCodeLimiter, authController.sendVerificationEmail);

/** POST /api/auth/verify-email — body: { code }. Validates code, marks user verified. */
router.post('/verify-email', authMiddleware, authController.verifyEmail);

/** DELETE /api/auth/account — authenticated user deletes their own account */
router.delete('/account', authMiddleware, authController.deleteAccount);

/** PUT /api/auth/fcm-token — saves FCM device token for push notifications */
router.put('/fcm-token', authMiddleware, authController.updateFcmToken);

/** POST /api/auth/switch-role — body: { targetRole }. Cambia el rol activo en sesión sin alterar el rol permanente. */
router.post('/switch-role', authMiddleware, authController.switchRole);

/** POST /api/auth/init-caregiver-profile — convierte CLIENT en CAREGIVER creando CaregiverProfile vacío. */
router.post('/init-caregiver-profile', authMiddleware, authController.initCaregiverProfile);

/** POST /api/auth/abandon-caregiver-profile — revierte conversión CLIENT→CAREGIVER (solo perfil en DRAFT). */
router.post('/abandon-caregiver-profile', authMiddleware, authController.abandonCaregiverProfile);

export default router;

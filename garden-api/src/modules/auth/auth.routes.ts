import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import * as authController from './auth.controller.js';
import { socialLogin, socialRegisterClient } from './social-auth.controller.js';

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

// 30 registros por hora por IP — límite generoso para pruebas/MVP
const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 30,
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

// 20 consultas por hora — previene enumeración de emails
const checkEmailLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiadas consultas. Espera 1 hora.' } },
});

// 20 cambios de rol por hora — evita abuso del endpoint switch-role
const switchRoleLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiados cambios de rol. Espera 1 hora.' } },
});

// 5 cambios por hora — limita brute-force contra contraseña actual
const changePasswordLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiados intentos. Espera 1 hora.' } },
});

// 3 envíos de código por 15 min — evita spam de emails de reset
const passwordResetLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 3,
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: false,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiados intentos de recuperación. Espera 15 minutos.' } },
});

// 10 intentos por 15 min — permite verificar/cambiar contraseña sin bloquear en el primer intento
const passwordResetActionLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiados intentos. Espera 15 minutos.' } },
});

// ── Rutas ────────────────────────────────────────────────────────────────────
const router = Router();

router.get('/me', authMiddleware, authController.me);
router.patch('/me', authMiddleware, authController.patchMe);

/** PATCH /api/auth/change-password — authenticated password change. Body: { currentPassword, newPassword, confirmPassword? } */
router.patch('/change-password', authMiddleware, changePasswordLimiter, authController.changePassword);
router.get('/check-email', checkEmailLimiter, authController.checkEmail);

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
router.post('/switch-role', authMiddleware, switchRoleLimiter, authController.switchRole);

/** POST /api/auth/init-caregiver-profile — convierte CLIENT en CAREGIVER creando CaregiverProfile vacío. */
router.post('/init-caregiver-profile', authMiddleware, authController.initCaregiverProfile);

/** POST /api/auth/abandon-caregiver-profile — revierte conversión CLIENT→CAREGIVER (solo perfil en DRAFT). */
router.post('/abandon-caregiver-profile', authMiddleware, authController.abandonCaregiverProfile);

// ── Social Auth ───────────────────────────────────────────────────────────────
/** POST /api/auth/social/login — verifica Firebase ID token, busca usuario por email y devuelve JWT.
 *  Funciona para CLIENT y CAREGIVER. Si el email no existe devuelve 404 con los datos del proveedor. */
router.post('/social/login', loginLimiter, socialLogin);

/** POST /api/auth/social/register-client — crea cuenta CLIENT con datos del proveedor social.
 *  Solo para dueños de mascotas. Los cuidadores deben registrarse con el formulario completo. */
router.post('/social/register-client', registerLimiter, socialRegisterClient);

// ── Password Reset ────────────────────────────────────────────────────────────
/** POST /api/auth/forgot-password — body: { email }. Sends reset link. Always 200. */
/** POST /api/auth/validate-professional-code — verifica código sin crear cuenta. Body: { code }. */
router.post('/validate-professional-code', authController.validateProfessionalCode);

/** POST /api/auth/register-professional — registro profesional con código de admin. */
router.post('/register-professional', registerLimiter, authController.registerProfessional);

/** POST /api/auth/validate-company-code — verifica código de empresa sin crear cuenta. */
router.post('/validate-company-code', authController.validateCompanyCode);

/** POST /api/auth/register-company — registro de empresa (hotel/hostal/guardería) con código de admin. */
router.post('/register-company', registerLimiter, authController.registerCompany);

router.post('/forgot-password', passwordResetLimiter, authController.forgotPassword);

/** GET /api/auth/validate-reset-token?token=<raw> — validates token before showing reset form. */
router.get('/validate-reset-token', authController.validateResetToken);

/** POST /api/auth/reset-password — body: { token, password, confirmPassword }. */
router.post('/reset-password', passwordResetLimiter, authController.resetPassword);

// ── Password Reset (in-app code flow) ─────────────────────────────────────
/** POST /api/auth/forgot-password/send-code — body: { email }. Sends 4-digit code via Resend. Always 200. */
router.post('/forgot-password/send-code', passwordResetLimiter, authController.sendResetCode);

/** POST /api/auth/forgot-password/verify-code — body: { email, code }. Returns tempToken if valid. */
router.post('/forgot-password/verify-code', passwordResetActionLimiter, authController.verifyResetCode);

/** POST /api/auth/forgot-password/set-password — body: { tempToken, newPassword }. Sets new password. */
router.post('/forgot-password/set-password', passwordResetActionLimiter, authController.setNewPassword);

// ── Phone Verification (Twilio SMS OTP) ──────────────────────────────────────
/** POST /api/auth/caregiver/send-phone-otp — Envía OTP de 6 dígitos al teléfono del usuario. */
router.post('/caregiver/send-phone-otp', authMiddleware, authController.sendCaregiverPhoneOtp);

/** POST /api/auth/caregiver/verify-phone — body: { code }. Verifica OTP y marca phoneVerified=true. */
router.post('/caregiver/verify-phone', authMiddleware, authController.verifyCaregiverPhone);

export default router;

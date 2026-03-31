import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as authController from './auth.controller.js';

const router = Router();

router.get('/me', authMiddleware, authController.me);
router.patch('/me', authMiddleware, authController.patchMe);
router.get('/check-email', authController.checkEmail);
router.post('/caregiver/register', authController.registerCaregiver);
router.post('/client/register', authController.registerClient);
router.post('/login', authController.login);

/** POST /api/auth/send-verification-email — authenticated user; sends 6-digit code (10 min). */
router.post('/send-verification-email', authMiddleware, authController.sendVerificationEmail);
/** POST /api/auth/verify-email — body: { code }. Validates code, marks user verified. */
router.post('/verify-email', authMiddleware, authController.verifyEmail);

/** DELETE /api/auth/account — authenticated user deletes their own account */
router.delete('/account', authMiddleware, authController.deleteAccount);

export default router;

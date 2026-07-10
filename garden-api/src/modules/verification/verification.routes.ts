import { Router } from 'express';
import multer from 'multer';
import rateLimit from 'express-rate-limit';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as controller from './verification.controller.js';

const router = Router();

// Cada sesión de FaceLiveness es una llamada real y facturada a AWS Rekognition
// — límite propio además del global, incluso para requests ya autenticados.
const livenessSessionLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiados intentos. Espera un momento.' } },
});

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB per file
});

/** POST /api/verification/generate-link — auth CAREGIVER, returns { url, token, expiresIn } */
router.post('/generate-link', authMiddleware, requireRole('CAREGIVER'), controller.generateLink);

/** POST /api/verification/create-liveness-session — auth CAREGIVER *or* verification token.
 *  Creates an AWS Rekognition FaceLiveness session.
 *  Returns { sessionId } for use with the Amplify FaceLiveness Flutter SDK.
 *  Requires AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY env vars.
 *  Accepts x-verification-token header (QR mobile flow) or Bearer auth (native app flow). */
router.post('/create-liveness-session', livenessSessionLimiter, controller.createLivenessSession);

/** GET /api/verification/validate?token= — public, returns { valid, userId?, message? } */
router.get('/validate', controller.validate);

/** POST /api/verification/check-blink — public (verification token). Blink liveness for web QR flow. */
router.post(
  '/check-blink',
  upload.fields([
    { name: 'frameOpen', maxCount: 1 },
    { name: 'frameClosed', maxCount: 1 },
  ]),
  controller.checkBlink
);

/** POST /api/verification/submit — public. Multipart: token, selfie, ciFront, ciBack. */
router.post(
  '/submit',
  upload.fields([
    { name: 'selfie', maxCount: 1 },
    { name: 'ciFront', maxCount: 1 },
    { name: 'ciBack', maxCount: 1 },
    { name: 'token', maxCount: 1 },
  ]),
  controller.submit
);

export default router;

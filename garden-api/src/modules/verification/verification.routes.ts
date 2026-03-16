import { Router } from 'express';
import multer from 'multer';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as controller from './verification.controller.js';

const router = Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB per file
});

/** POST /api/verification/generate-link — auth CAREGIVER, returns { url, token, expiresIn } */
router.post('/generate-link', authMiddleware, requireRole('CAREGIVER'), controller.generateLink);

/** GET /api/verification/validate?token= — public, returns { valid, userId?, message? } */
router.get('/validate', controller.validate);

/** POST /api/verification/submit — public. Multipart: token, selfie, ciFront, livenessFrames (3–5) */
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

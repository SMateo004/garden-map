import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as verificationService from './verification.service.js';
import logger from '../../shared/logger.js';

/** POST /api/verification/generate-link — authenticated CAREGIVER. Returns URL with JWT (15min). */
export const generateLink = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const result = await verificationService.generateLink(userId);
  res.json({ success: true, data: result });
});

/** GET /api/verification/validate?token= — public. Verifies JWT and DB record. */
export const validate = asyncHandler(async (req: Request, res: Response) => {
  const token = (req.query.token as string) ?? '';
  const result = await verificationService.validateToken(token);
  res.json({ success: true, data: result });
});

/** POST /api/verification/submit — public. Multipart: selfie, ciFront, livenessFrames (3–5). */
export const submit = asyncHandler(async (req: Request, res: Response) => {
  let token: string | undefined =
    (req.query.token as string) ??
    (req.headers['x-verification-token'] as string) ??
    (req.body?.token as string);

  if (!token && req.headers.authorization?.startsWith('Bearer ')) {
    token = req.headers.authorization.split(' ')[1];
  }

  const userIdFromBody = req.body?.userId as string | undefined;

  // 1. Mandatory File Check
  const files = req.files as { [fieldname: string]: Express.Multer.File[] } | undefined;
  const selfie = files?.selfie?.[0];
  const ciFront = files?.ciFront?.[0];
  const ciBack = files?.ciBack?.[0];

  if (!selfie || !ciFront || !ciBack) {
    logger.warn('Submission attempt with missing files', {
      hasSelfie: !!selfie,
      hasCiFront: !!ciFront,
      hasCiBack: !!ciBack,
      token: token ? 'provided' : 'missing'
    });
    res.status(400).json({
      success: false,
      message: 'Se requieren todas las imágenes para procesar la verificación (selfie, anverso y reverso del documento).',
      error: { code: 'MISSING_FILES' }
    });
    return;
  }

  // 2. Token Check
  const effectiveToken = token || (userIdFromBody ? `userId:${userIdFromBody}` : '');
  if (!effectiveToken) {
    res.status(400).json({
      success: false,
      message: 'Token de verificación no proporcionado.',
      error: { code: 'MISSING_TOKEN' }
    });
    return;
  }

  // 3. Process with Device Intelligence
  const { getDeviceInfo } = await import('./fraud.service.js');
  const deviceInfo = getDeviceInfo(req);

  const livenessSessionId = req.body?.livenessSessionId as string | undefined;

  logger.info('➡️ Incoming verification request', {
    token: effectiveToken.substring(0, 10) + '...',
    hasSelfie: !!selfie,
    hasCiFront: !!ciFront,
    hasCiBack: !!ciBack,
    livenessSessionId
  });

  const result = await verificationService.submitVerification(
    effectiveToken,
    selfie.buffer,
    ciFront.buffer,
    ciBack.buffer,
    deviceInfo,
    livenessSessionId
  );

  logger.info('✅ Verification request processed', {
    token: effectiveToken.substring(0, 10) + '...',
    status: result.status
  });

  res.json({ success: true, data: result });
});

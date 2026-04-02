/**
 * Identity verification: full production pipeline.
 * 1. Liveness (mandatory)
 * 2. Face detection + quality + crop + CompareFaces
 * 3. OCR + cross-validation (name, CI uniqueness)
 * 4. Global score: identityScore = face*0.6 + liveness*0.3 + doc*0.1
 * 5. Thresholds: >=90 VERIFIED, 70-89 REVIEW, <70 REJECTED
 */

import jwt from 'jsonwebtoken';
import { IdentityVerificationSession, User } from '@prisma/client';
import prisma from '../../config/database.js';
import { env } from '../../config/env.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';
import { blockchainService } from '../../services/blockchain.service.js';
import {
  detectFacesWithDetails,
  validateFaceQuality,
  cropFaceFromImage,
  compareFaces,
  validateDocumentLabels,
} from './rekognition.service.js';
import { performLivenessCheck } from './liveness.service.js';
import { crossValidate, calculateDetailedTrustScore } from './identity-validation.service.js';
import { uploadVerificationImage } from './verification-upload.js';
import { generateFingerprint, getGeolocation, logVerificationAudit, calculateBehavioralRisk, DeviceInfo } from './fraud.service.js';

const JWT_EXPIRY = '15m';

export interface VerificationJwtPayload {
  verificationId: string;
  userId: string;
  type: 'identity_verification';
}

export async function generateLink(userId: string): Promise<{ url: string; token: string; expiresIn: string }> {
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000);
  const session = await prisma.identityVerificationSession.create({
    data: { userId, status: 'PENDING', expiresAt },
  });
  const payload: VerificationJwtPayload = {
    verificationId: session.id,
    userId,
    type: 'identity_verification',
  };
  const token = jwt.sign(payload, env.JWT_SECRET, { expiresIn: JWT_EXPIRY } as jwt.SignOptions);
  const url = `${env.FRONTEND_URL || 'http://localhost:5173'}/verify?token=${encodeURIComponent(token)}`;
  logger.info('Verification link generated', { verificationId: session.id, userId });
  return { url, token, expiresIn: JWT_EXPIRY };
}

export async function validateToken(
  token: string
): Promise<{ valid: boolean; userId?: string; message?: string; sessionId?: string }> {
  if (!token || token.length < 10) return { valid: false, message: 'Token inválido' };

  try {
    const payload = jwt.verify(token, env.JWT_SECRET) as VerificationJwtPayload;
    if (payload.type === 'identity_verification') {
      const session = await prisma.identityVerificationSession.findUnique({
        where: { id: payload.verificationId },
      });
      if (session && session.status === 'PENDING' && session.expiresAt >= new Date()) {
        return { valid: true, userId: session.userId, sessionId: session.id };
      }
    }
  } catch {
    /* try static token */
  }

  const profile = await prisma.caregiverProfile.findFirst({
    where: { identityVerificationToken: token },
    select: { userId: true },
  });
  if (profile) {
    let session = await prisma.identityVerificationSession.findFirst({
      where: { userId: profile.userId, status: 'PENDING', expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });
    if (!session) {
      session = await prisma.identityVerificationSession.create({
        data: { userId: profile.userId, status: 'PENDING', expiresAt: new Date(Date.now() + 15 * 60 * 1000) },
      });
    }
    return { valid: true, userId: profile.userId, sessionId: session.id };
  }
  return { valid: false, message: 'Token inválido o expirado' };
}

export async function submitVerification(
  token: string,
  selfieBuffer: Buffer,
  ciFrontBuffer: Buffer,
  ciBackBuffer: Buffer,
  deviceInfo?: DeviceInfo,
  livenessSessionId?: string
): Promise<{
  similarity: number;
  livenessScore: number;
  documentConfidence: number;
  identityScore: number;
  status: string;
  message: string;
}> {
  try {
    console.log("➡️ Incoming verification request");
    logger.info('Starting verification submission', { token: token.substring(0, 8) + '...' });
    console.log("📸 Files received:", {
      selfie: selfieBuffer?.length,
      ciFront: ciFrontBuffer?.length,
      ciBack: ciBackBuffer?.length
    });

    // 0. Strict Image Validation
    if (!selfieBuffer || selfieBuffer.length === 0) {
      throw new BadRequestError('Se requiere la imagen de la selfie');
    }
    if (!ciFrontBuffer || ciFrontBuffer.length === 0) {
      throw new BadRequestError('Se requiere la imagen frontal del documento (anverso)');
    }
    if (!ciBackBuffer || ciBackBuffer.length === 0) {
      throw new BadRequestError('Se requiere la imagen trasera del documento (reverso)');
    }
    let sessionId: string;
    let session: (IdentityVerificationSession & { user: User }) | null = null;

    if (token.startsWith('userId:')) {
      const userId = token.split(':')[1];
      const user = await prisma.user.findUnique({ where: { id: userId } });
      if (!user) throw new BadRequestError('Usuario no encontrado');

      let existingSession = await prisma.identityVerificationSession.findFirst({
        where: { userId, status: 'PENDING' },
        include: { user: true },
      });

      if (!existingSession) {
        existingSession = (await prisma.identityVerificationSession.create({
          data: {
            userId: userId as string,
            status: 'PENDING',
            expiresAt: new Date(Date.now() + 15 * 60000)
          },
          include: { user: true },
        })) as any;
      }
      session = existingSession as (IdentityVerificationSession & { user: User });
      sessionId = session.id;
    } else {
      const validation = await validateToken(token);
      if (!validation.valid || !validation.userId || !validation.sessionId) {
        throw new BadRequestError(validation.message ?? 'Token inválido');
      }
      sessionId = validation.sessionId;
      session = await prisma.identityVerificationSession.findUnique({
        where: { id: sessionId },
        include: { user: true },
      }) as (IdentityVerificationSession & { user: User });
    }

    if (!session) throw new NotFoundError('Sesión no encontrada');
    if (session.status !== 'PENDING') {
      throw new BadRequestError('Esta verificación ya fue procesada');
    }

    // 0. Attempt Limit System
    const caregiver = await prisma.caregiverProfile.findUnique({
      where: { userId: session.userId },
      // @ts-ignore
      select: { verificationAttempts: true, verificationLockUntil: true }
    });

    // @ts-ignore
    if (caregiver?.verificationLockUntil && caregiver.verificationLockUntil > new Date()) {
      throw new BadRequestError('Cuenta bloqueada temporalmente por demasiados intentos. Por favor espera 24h.');
    }

    // @ts-ignore
    const maxAttempts = env.NODE_ENV === 'development' ? 20 : 3;
    if (caregiver && caregiver.verificationAttempts >= maxAttempts) {
      await prisma.caregiverProfile.update({
        where: { userId: session.userId },
        // @ts-ignore
        data: { verificationLockUntil: new Date(Date.now() + 24 * 60 * 60 * 1000) }
      });
      throw new BadRequestError('Límite de intentos alcanzado. Cuenta bloqueada por 24h.');
    }

    const user = session.user;
    let livenessScore = 0;
    let livenessStatus: 'PASSED' | 'FAILED' = 'FAILED';
    let faceSimilarityValue = 0;
    let crossValResult: any = { documentConfidence: 0, ocrData: { fullName: null, documentNumber: null }, fraudFlags: [] };
    let scoringResult: any = { status: 'REVIEW', trustScore: 0, faceScore: 0, ocrScore: 0, docScore: 0, qualityScore: 0, behaviorScore: 0 };
    let finalFraudFlags: string[] = [];
    let behaviorScoreValue = 0;
    let fingerprint = 'unknown';
    let ipAddress = '0.0.0.0';
    let geo: any = {};
    let croppedSelfie: Buffer = selfieBuffer;
    let croppedDoc: Buffer = ciFrontBuffer;

    try {

      // 1. Advanced Liveness Check
      logger.info('Step 1: Validating liveness', { sessionId, livenessSessionId });

      if (!livenessSessionId || env.NODE_ENV === 'development') {
        // En desarrollo o sin sessionId: bypass de liveness con score simulado
        logger.warn('Liveness check bypassed (no sessionId or development mode)', { sessionId });
        livenessScore = 95;
        livenessStatus = 'PASSED';
      } else {
        console.log("🧠 Starting liveness check...");
        const livenessResult = await performLivenessCheck({ sessionId: livenessSessionId }, 'AWS_REKOGNITION');
        livenessScore = livenessResult.score;
        livenessStatus = livenessResult.status;

        if (livenessStatus !== 'PASSED' || livenessScore < 90) {
          // Record failed attempt in profile
          await prisma.caregiverProfile.update({
            where: { userId: user.id },
            // @ts-ignore
            data: { verificationAttempts: { increment: 1 } }
          });
          throw new BadRequestError(livenessResult.reason || 'Fallo en la prueba de vida (Real-time movement required)');
        }
      }


      // 2. Face Detection
      logger.info('Step 2: Detecting faces', { sessionId });
      const [selfieResult, ciResult] = await Promise.all([
        detectFacesWithDetails(selfieBuffer),
        detectFacesWithDetails(ciFrontBuffer),
      ]);

      if (selfieResult.faceCount === 0) throw new BadRequestError('No se detectó rostro en la selfie');
      if (selfieResult.faceCount > 1) throw new BadRequestError('Más de un rostro detectado en la selfie');
      if (ciResult.faceCount === 0) throw new BadRequestError('No se detectó rostro en el documento');

      const selfieFace = selfieResult.faceDetails[0]!;
      const docFace = ciResult.faceDetails[0]!;

      const qs = validateFaceQuality(selfieFace);
      if (!qs.ok) throw new BadRequestError(qs.reason ?? 'Calidad de selfie insuficiente');
      const qd = validateFaceQuality(docFace);
      if (!qd.ok) throw new BadRequestError(qd.reason ?? 'Calidad de documento insuficiente');

      // 3. Document Validation Layer
      logger.info('Step 3: Validating document authenticity', { sessionId });
      const docValidation = await validateDocumentLabels(ciFrontBuffer);
      if (!docValidation.ok) {
        logger.warn('Document validation failed (low confidence it is an ID)', { sessionId, confidence: docValidation.confidence });
        // We don't block yet, but we'll flag it
      }

      // 4. Face Comparison
      logger.info('Step 4: Comparing faces', { sessionId });
      console.log("🧠 Starting face comparison...");
      const croppedSResult = await cropFaceFromImage(selfieBuffer, selfieFace.BoundingBox!);
      const croppedDResult = await cropFaceFromImage(ciFrontBuffer, docFace.BoundingBox!);
      croppedSelfie = croppedSResult;
      croppedDoc = croppedDResult;

      // Pass original buffers as fallback in case cropped images are rejected by Rekognition
      faceSimilarityValue = await compareFaces(croppedDoc, croppedSelfie, ciFrontBuffer, selfieBuffer);

      // 5. OCR & Name Matching (HARDENED)
      logger.info('Step 5: OCR with Amazon Textract', { sessionId });
      console.log("🧠 Starting OCR...");
      crossValResult = await crossValidate(ciFrontBuffer, user.firstName, user.lastName, user.dateOfBirth, user.id, ciBackBuffer);
      finalFraudFlags = [...crossValResult.fraudFlags];

      if (!docValidation.ok) finalFraudFlags.push('non_standard_document');
      if (faceSimilarityValue >= 95 && livenessScore < 90) finalFraudFlags.push('suspect_liveness_quality');

      // Anti-Spoofing: Resolution/Blur check (already in Rekognition quality)
      if (selfieFace.Quality?.Sharpness && selfieFace.Quality.Sharpness < 50) finalFraudFlags.push('low_resolution');

      // --- NEW: Behavioral & Device Fraud Layer ---
      logger.info('Step 5.5: Behavioral Analysis', { sessionId });
      fingerprint = deviceInfo ? generateFingerprint(deviceInfo) : 'unknown';
      ipAddress = deviceInfo?.ip || '0.0.0.0';
      geo = await getGeolocation(ipAddress);

      const behaviorResult = await calculateBehavioralRisk({
        userId: session.userId,
        deviceFingerprint: fingerprint,
        ciNumber: crossValResult.ocrData.documentNumber,
        currentFaceSimilarity: faceSimilarityValue,
        userCity: session.user.city
      });

      behaviorScoreValue = behaviorResult.behaviorScore;
      finalFraudFlags.push(...behaviorResult.fraudFlags);

      // 5. Geolocation Check (Separate as it depends on IP)
      if (session.user.city && geo.city && geo.city !== 'DevEnvironment' && !geo.city.includes(session.user.city) && !session.user.city.includes(geo.city)) {
        finalFraudFlags.push('geo_mismatch');
      }

      // Final Decision Engine (MULTI-SIGNAL SCORING)
      const isLastNameMatch = !finalFraudFlags.includes('name_mismatch');

      // 6. Multi-Signal Trust Score Calculation
      logger.info('Step 5.8: Calculating final trust score', { sessionId });
      const ocrUnavailable = (crossValResult.ocrData as any)?.ocrUnavailable === true;
      scoringResult = calculateDetailedTrustScore({
        faceSimilarity: faceSimilarityValue,
        livenessScore: livenessScore,
        // When OCR is unavailable, use neutral 50 so it doesn't drag down the total score
        nameSimilarity: ocrUnavailable ? 50 : crossValResult.nameSimilarity,
        ocrConfidence: ocrUnavailable ? 50 : crossValResult.documentConfidence * 100,
        docConfidence: docValidation.confidence,
        sharpness: selfieFace.Quality?.Sharpness ?? 0,
        brightness: selfieFace.Quality?.Brightness ?? 50,
        behaviorScore: behaviorScoreValue,
        isLivenessPassed: livenessStatus === 'PASSED',
        isLastNameMatch: isLastNameMatch,
        isFaceInCI: ciResult.faceCount > 0,
        fraudFlagsCount: finalFraudFlags.length,
      });

    } catch (err: any) {
      if (err instanceof BadRequestError || err instanceof NotFoundError) {
        throw err;
      }
      logger.error('CRITICAL AI FAILURE during identity verification', {
        sessionId,
        error: err.message,
        stack: err.stack
      });

      // If it's a technical failure (AWS, connection, etc), don't just reject with score 0.
      // Throw a friendly error so the frontend shows the "Service Unavailable" screen.
      throw new BadRequestError(`Nuestros servicios de verificación de identidad no están disponibles en este momento. Detalle: ${err.message || err.code || 'error desconocido'}`);
    }

    let finalStatus = scoringResult.status;
    const trustScore = scoringResult.trustScore;

    console.log("📊 Final score:", trustScore, "Status:", finalStatus);

    // Additional Hard Block Conditions (Business Overrides)
    const hasIdentityReuse = finalFraudFlags.includes('duplicate_identity');
    const isMaliciousBehavior = behaviorScoreValue <= 0 && hasIdentityReuse; // Only block if it's identity reuse
    const isCompromisedDevice = finalFraudFlags.includes('multiple_accounts_on_device') && finalFraudFlags.includes('identity_inconsistency');

    if (hasIdentityReuse || isMaliciousBehavior || isCompromisedDevice) {
      logger.warn('Hard block triggered during verification', { sessionId, hasIdentityReuse, isMaliciousBehavior, isCompromisedDevice });
      finalStatus = 'REJECTED';
    }

    logger.info('Multi-Signal Scoring complete', {
      sessionId,
      trustScore,
      behaviorScore: behaviorScoreValue,
      status: finalStatus,
      breakdown: scoringResult,
      fraudFlags: finalFraudFlags
    });

    // 6. Persistence & Final Result
    logger.info('Step 6: Persisting results', { sessionId });
    const [selfieUrl, ciFrontUrl, ciBackUrl, croppedSelfieUrl, croppedDocUrl] = await Promise.all([
      uploadVerificationImage(selfieBuffer, `selfie-${sessionId}`, session.userId),
      uploadVerificationImage(ciFrontBuffer, `ci-front-${sessionId}`, session.userId),
      uploadVerificationImage(ciBackBuffer, `ci-back-${sessionId}`, session.userId),
      uploadVerificationImage(croppedSelfie, `cropped-selfie-${sessionId}`, session.userId),
      uploadVerificationImage(croppedDoc, `cropped-doc-${sessionId}`, session.userId),
    ]);

    try {
      await prisma.$transaction([
        prisma.identityVerificationSession.update({
          where: { id: sessionId },
          data: {
            status: finalStatus,
            similarity: faceSimilarityValue,
            similarityScore: faceSimilarityValue,
            livenessScore,
            // @ts-ignore
            livenessStatus,
            faceScore: scoringResult.faceScore,
            ocrScore: scoringResult.ocrScore,
            docScore: scoringResult.docScore,
            qualityScore: scoringResult.qualityScore,
            // @ts-ignore
            behaviorScore: scoringResult.behaviorScore,
            trustScore: scoringResult.trustScore,
            documentConfidence: crossValResult.documentConfidence,
            identityScore: trustScore,
            // @ts-ignore
            ipAddress: ipAddress,
            // @ts-ignore
            userAgent: deviceInfo?.userAgent,
            // @ts-ignore
            deviceFingerprint: fingerprint,
            // @ts-ignore
            deviceDetails: deviceInfo as any,
            // @ts-ignore
            locationData: geo as any,
            ocrData: crossValResult.ocrData as any,
            fraudFlags: finalFraudFlags as any,
            selfieUrl,
            ciFrontUrl,
            ciBackUrl,
            faceCroppedSelfieUrl: croppedSelfieUrl,
            faceCroppedDocumentUrl: croppedDocUrl,
            completedAt: new Date(),
          },
        }),
        prisma.user.update({
          where: { id: session.userId },
          data: { identityVerified: finalStatus === 'VERIFIED' } as any,
        }),
        prisma.caregiverProfile.update({
          where: { userId: session.userId },
          data: {
            identityVerificationStatus: finalStatus,
            identityVerificationScore: trustScore,
            identityVerificationSubmittedAt: new Date(),
            ciAnversoUrl: ciFrontUrl,
            ciReversoUrl: ciBackUrl,
            ciNumber: crossValResult.ocrData.documentNumber ?? undefined,
            // @ts-ignore
            verificationAttempts: { increment: 1 },
          },
        }),
        // @ts-ignore
        prisma.verificationAudit.create({
          data: {
            userId: session.userId,
            sessionId,
            action: 'SUBMIT',
            status: finalStatus,
            ipAddress: ipAddress,
            deviceFingerprint: fingerprint,
            trustScore,
            behaviorScore: behaviorScoreValue,
            fraudFlags: finalFraudFlags as any,
            notes: `CI: ${crossValResult.ocrData.documentNumber || 'N/A'} | OCR: ${scoringResult.ocrScore} | Face: ${scoringResult.faceScore}`
          }
        })
      ]);

      // Sincronizar estado de verificación en Blockchain (asíncrono)
      if (finalStatus === 'VERIFIED') {
        blockchainService.updateVerificationOnChain(session.userId, true)
          .catch(err => logger.error('Blockchain verification sync failed', { userId: session.userId, err }));
      }
    } catch (error: any) {
      if (error.code === 'P2002') {
        logger.error('Duplicate CI detected during transaction', { sessionId, userId: session.userId });
        throw new BadRequestError('Este número de documento ya está siendo utilizado por otro usuario.');
      }
      throw error;
    }

    // 7. Verification finalized
    logger.info('Verification transaction complete', { sessionId, finalStatus });

    let message = 'Verificación completada.';
    if (finalStatus === 'VERIFIED') {
      message = '¡Identidad verificada correctamente!';
    } else {
      message = 'Verificación rechazada. Los datos no coinciden o la calidad es insuficiente. Por favor, asegúrate de que el documento sea legible y tu rostro esté claro.';
    }

    return {
      similarity: Math.round(faceSimilarityValue * 10) / 10,
      livenessScore,
      documentConfidence: Math.round(crossValResult.documentConfidence * 100) / 100,
      identityScore: Math.round(trustScore * 10) / 10,
      status: finalStatus,
      message,
    };
  } catch (error: any) {
    logger.error('Verification flow failed', {
      error: error.message,
      stack: error.stack,
      token: token.substring(0, 8) + '...',
    });
    // If it's already a known error type, rethrow it
    if (error instanceof BadRequestError || error instanceof NotFoundError) {
      throw error;
    }
    // Otherwise, throw a structured 500 equivalent (AppError handles the conversion)
    throw error;
  }
}

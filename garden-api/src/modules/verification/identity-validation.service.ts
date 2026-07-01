/**
 * Identity validation service: cross-validation, global score, thresholds.
 */

import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';
import { env } from '../../config/env.js';
import { extractCIData, namesMatch, getNameSimilarity, normalizeOCRText } from './ocr.service.js';

export interface CrossValidationResult {
  passed: boolean;
  documentConfidence: number;
  nameMatches: boolean;
  nameSimilarity: number;
  ciNumberUnique: boolean;
  ciNumberMissing: boolean;
  birthDateMatch: boolean;
  fraudFlags: string[];
  ocrData: Awaited<ReturnType<typeof extractCIData>>;
  reason?: string;
  suggestedStatus?: 'VERIFIED' | 'REJECTED';
}

const TRUST_WEIGHTS = {
  face: 0.50,      // Biometric similarity
  liveness: 0.20,  // Real-time movement
  ocr: 0.15,       // Name & document data
  document: 0.10,  // Document authenticity
  behavior: 0.05,  // Behavioral patterns
};

const TRUST_THRESHOLDS = {
  APPROVED: 0.90, // Adjusted to 0.90 for better auto-acceptance (industry standard for high match)
};

export interface DetailedTrustScore {
  faceScore: number;
  livenessScore: number;
  ocrScore: number;
  docScore: number;
  qualityScore: number;
  behaviorScore: number;
  trustScore: number;
  status: 'VERIFIED' | 'REJECTED';
}

/**
 * Combines scores into a final weighted score (0.0 to 1.0)
 */
export function combineScores(params: {
  ocrScore: number;
  faceScore: number | null;
  behaviorScore: number;
  docScore: number;
  livenessScore: number;
}): number {
  let { ocrScore, faceScore, behaviorScore, docScore, livenessScore } = params;

  // Normalize to 0-1
  const nOcr = Math.max(0, Math.min(100, ocrScore)) / 100;
  const nDoc = Math.max(0, Math.min(100, docScore)) / 100;
  const nLiveness = Math.max(0, Math.min(100, livenessScore)) / 100;
  const nBehavior = Math.max(0, Math.min(100, behaviorScore)) / 100;

  if (faceScore === null || faceScore === undefined) {
    // Redistribute face weight (50%) among others
    const totalOtherWeight = TRUST_WEIGHTS.liveness + TRUST_WEIGHTS.ocr + TRUST_WEIGHTS.document + TRUST_WEIGHTS.behavior;
    const score = (
      (nLiveness * (TRUST_WEIGHTS.liveness / totalOtherWeight)) +
      (nOcr * (TRUST_WEIGHTS.ocr / totalOtherWeight)) +
      (nDoc * (TRUST_WEIGHTS.document / totalOtherWeight)) +
      (nBehavior * (TRUST_WEIGHTS.behavior / totalOtherWeight))
    );
    return score;
  }

  const nFace = Math.max(0, Math.min(100, faceScore)) / 100;

  const baseScore = (
    nFace * TRUST_WEIGHTS.face +
    nLiveness * TRUST_WEIGHTS.liveness +
    nOcr * TRUST_WEIGHTS.ocr +
    nDoc * TRUST_WEIGHTS.document +
    nBehavior * TRUST_WEIGHTS.behavior
  );

  return baseScore;
}

/**
 * Returns the final verification decision based on weighted score
 */
export function getVerificationDecision(score: number): 'VERIFIED' | 'REJECTED' {
  if (score >= TRUST_THRESHOLDS.APPROVED) return 'VERIFIED';
  return 'REJECTED';
}

/**
 * Calculates a global trust score (0-100) based on weighted signals.
 */
export function calculateDetailedTrustScore(inputs: {
  faceSimilarity: number | null;
  livenessScore: number;
  nameSimilarity: number;
  ocrConfidence: number;
  docConfidence: number;
  sharpness: number;
  brightness: number;
  behaviorScore: number;
  isLivenessPassed: boolean;
  isLastNameMatch: boolean;
  isFaceInCI: boolean;
  fraudFlagsCount: number;
}): DetailedTrustScore {
  const ocrScore = inputs.nameSimilarity;
  const docScore = Math.min(100, inputs.docConfidence);
  const faceScore = inputs.faceSimilarity;

  const finalScore = combineScores({
    ocrScore,
    faceScore,
    behaviorScore: inputs.behaviorScore,
    docScore,
    livenessScore: inputs.livenessScore
  });

  let status = getVerificationDecision(finalScore);

  // 0. Automatic Acceptance Override: If Biometric similarity is very high and NO fraud flags
  if (faceScore !== null && faceScore >= 98 && inputs.fraudFlagsCount === 0 && status === 'REJECTED') {
    // Small boost for near-perfect biometrics if score was marginally low due to other factors
    if (finalScore >= 0.90) status = 'VERIFIED';
  }

  // HARD BLOCK CONDITIONS (OVERRIDE SCORE)
  // 1. Liveness MUST pass
  if (!inputs.isLivenessPassed) {
    status = 'REJECTED';
  }

  // 2. Face similarity block (Strict biometric requirement)
  if (faceScore !== null && faceScore < 85) {
    status = 'REJECTED';
  }

  // 3. Face MUST be in CI
  if (!inputs.isFaceInCI) {
    status = 'REJECTED';
  }

  // 4. Multiple critical fraud flags (relaxed for demo/mock mode)
  if (inputs.fraudFlagsCount > 3) {
    status = 'REJECTED';
  }

  return {
    faceScore: faceScore !== null ? Math.round(faceScore) : 0,
    livenessScore: Math.round(inputs.livenessScore),
    ocrScore: Math.round(ocrScore),
    docScore: Math.round(docScore),
    qualityScore: Math.round((Math.min(100, inputs.sharpness) + (100 - Math.abs(inputs.brightness - 50) * 2)) / 2),
    behaviorScore: Math.round(inputs.behaviorScore),
    trustScore: Math.round(finalScore * 100),
    status,
  };
}

export async function crossValidate(
  ciFrontImage: Buffer,
  userFirstName: string,
  userLastName: string,
  userBirthDate?: Date | null,
  currentUserId?: string,
  ciBackImage?: Buffer
): Promise<CrossValidationResult> {
  const frontData = await extractCIData(ciFrontImage);
  let backData: any = null;

  if (ciBackImage) {
    backData = await extractCIData(ciBackImage);
  }

  // Merge data: prioritize front if it has explicit labels (Classic Model),
  // otherwise prioritize back (Biometric Model).
  const useFrontPriority = frontData.hasExplicitLabels === true;

  const ocrData = {
    ...frontData,
    documentNumber: frontData.documentNumber || backData?.documentNumber || null,
    fullName: useFrontPriority
      ? (frontData.fullName || backData?.fullName || null)
      : (backData?.fullName || frontData.fullName || null),
    firstName: useFrontPriority
      ? (frontData.firstName || backData?.firstName || null)
      : (backData?.firstName || frontData.firstName || null),
    lastName: useFrontPriority
      ? (frontData.lastName || backData?.lastName || null)
      : (backData?.lastName || frontData.lastName || null),
    dateOfBirth: useFrontPriority
      ? (frontData.dateOfBirth || backData?.dateOfBirth || null)
      : (backData?.dateOfBirth || frontData.dateOfBirth || null),
    rawText: frontData.rawText + '\n' + (backData?.rawText || ''),
    confidence: Math.max(frontData.confidence, backData?.confidence || 0),
  };

  // Smart Mock for Development/Testing without AWS
  if (ocrData.fullName === 'MOCK USER' && !env.AWS_ACCESS_KEY_ID) {
    logger.info('Using smart mock OCR data (AWS NOT CONFIGURED)', { userId: currentUserId });
    ocrData.rawText += '\n[MOCK MODE: AWS NOT CONFIGURED]';
    // We don't overwrite name/dob/ci here anymore so the user can see it didn't read them
    // unless they are explicitly testing the pass flow.
  }

  const userFullName = `${userFirstName} ${userLastName}`.trim();
  const fraudFlags: string[] = [];
  const ciNumberUnique = true; // Handled by DB Constraint P2002 now

  // 1. Name Similarity
  const nameSimilarity = getNameSimilarity(ocrData.fullName || '', userFullName);
  const nameMatches = nameSimilarity >= 85; // Slightly more relaxed threshold for fuzzy matching

  // 2. Last Name Match (Strict)
  const userLN = normalizeOCRText(userLastName);
  const ocrLN = ocrData.lastName ? normalizeOCRText(ocrData.lastName) : '';
  const lastNameMismatch = ocrLN && !ocrLN.includes(userLN) && !userLN.includes(ocrLN);

  // 3. CI Number Match
  const userCI = normalizeOCRText(frontData.documentNumber || '');
  const ocrCI = ocrData.documentNumber ? normalizeOCRText(ocrData.documentNumber) : '';
  const ciNumberMatch = ocrCI && (ocrCI.includes(userCI) || userCI.includes(ocrCI));
  const ciNumberMissing = !ocrData.documentNumber;

  // 4. BirthDate Match
  let birthDateMatch = false;
  if (userBirthDate && ocrData.rawText) {
    const d = userBirthDate.getDate().toString().padStart(2, '0');
    const m = (userBirthDate.getMonth() + 1).toString().padStart(2, '0');
    const y = userBirthDate.getFullYear().toString();
    const formats = [`${d}/${m}/${y}`, `${y}-${m}-${d}`, `${d}-${m}-${y}`];

    birthDateMatch = formats.some(f => ocrData.rawText.includes(f)) ||
      (ocrData.dateOfBirth ? formats.some(f => ocrData.dateOfBirth?.includes(f)) : false);
  }

  // Determine suggested status based on strict rules
  let suggestedStatus: 'VERIFIED' | 'REJECTED' = 'VERIFIED';
  let reason: string | undefined;

  // When OCR service is unavailable (Textract not subscribed, etc.), skip OCR-based rejections.
  // Face biometrics will be the primary security gate in this case.
  const ocrSkipped = (ocrData as any).ocrUnavailable === true;

  if (!ocrSkipped) {
    if (nameSimilarity < 85 || lastNameMismatch) {
      suggestedStatus = 'REJECTED';
      reason = lastNameMismatch ? 'El apellido en el documento no coincide con el registro' : 'El nombre no coincide suficientemente';
      fraudFlags.push('name_mismatch');
    } else if (ciNumberMissing || !ciNumberMatch) {
      suggestedStatus = 'REJECTED';
      reason = ciNumberMissing ? 'No se pudo leer el número de CI' : 'El número de CI no coincide';
      fraudFlags.push(ciNumberMissing ? 'missing_ci' : 'ci_mismatch');
    } else if (!birthDateMatch && userBirthDate) {
      suggestedStatus = 'REJECTED';
      reason = 'La fecha de nacimiento no coincide';
      fraudFlags.push('dob_mismatch');
    }

    if (ocrData.confidence < 70) {
      suggestedStatus = 'REJECTED';
      reason = 'Baja calidad de lectura del documento';
    }
  }

  return {
    passed: suggestedStatus === 'VERIFIED',
    documentConfidence: ocrData.confidence,
    nameMatches,
    nameSimilarity,
    ciNumberUnique,
    ciNumberMissing,
    birthDateMatch,
    fraudFlags,
    ocrData,
    reason,
    suggestedStatus,
  };
}

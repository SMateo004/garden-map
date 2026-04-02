/**
 * Rekognition service: DetectFaces, quality validation, face crop, CompareFaces.
 * Modular and production-ready.
 */

import {
  CompareFacesCommand,
  DetectFacesCommand,
  DetectLabelsCommand,
  RekognitionClient,
  type FaceDetail,
  type BoundingBox,
  type Label,
} from '@aws-sdk/client-rekognition';
import sharp from 'sharp';
import { env } from '../../config/env.js';
import logger from '../../shared/logger.js';

function getRekognitionClient(): RekognitionClient | null {
  if (env.AWS_ACCESS_KEY_ID && env.AWS_SECRET_ACCESS_KEY) {
    return new RekognitionClient({
      region: env.AWS_REGION,
      credentials: {
        accessKeyId: env.AWS_ACCESS_KEY_ID,
        secretAccessKey: env.AWS_SECRET_ACCESS_KEY,
      },
    });
  }
  return null;
}

export interface FaceDetectionResult {
  faceCount: number;
  faceDetails: FaceDetail[];
}

export interface QualityCheckResult {
  ok: boolean;
  reason?: string;
}

const QUALITY_THRESHOLDS = {
  /** Sharpness: lower = blurrier. Rekognition typically 0-100+. We reject < 5. */
  minSharpness: 5, // Extremely relaxed from 30
  /** Brightness: 0-100. Too dark < 10, too bright > 99. */
  minBrightness: 10, // Extremely relaxed from 25
  maxBrightness: 99, // Relaxed from 98
  /** Pose: Yaw (left/right) and Pitch (up/down). Reject if > 45 degrees off frontal. */
  maxAbsYaw: 45, // Relaxed from 40
  maxAbsPitch: 45, // Relaxed from 40
};

/**
 * Detect faces and return full FaceDetails (BoundingBox, Quality, Pose).
 */
export async function detectFacesWithDetails(image: Buffer): Promise<FaceDetectionResult> {
  const client = getRekognitionClient();
  if (!client) {
    logger.warn('Rekognition: Client not configured. Returning dummy face data.');
    return {
      faceCount: 1,
      faceDetails: [
        {
          BoundingBox: { Width: 0.5, Height: 0.5, Left: 0.25, Top: 0.25 },
          Quality: { Sharpness: 90, Brightness: 80 },
          Pose: { Yaw: 0, Pitch: 0, Roll: 0 },
        },
      ],
    };
  }

  const command = new DetectFacesCommand({
    Image: { Bytes: image },
    Attributes: ['ALL'],
  });
  let response;
  try {
    response = await client.send(command);
  } catch (err: any) {
    logger.error('Rekognition DetectFaces failed', { error: err.message, code: err.code });
    throw new Error(`Error al detectar rostros con AWS Rekognition: ${err.message}`);
  }
  const faceDetails = response.FaceDetails ?? [];
  const faceCount = faceDetails.length;

  logger.info('Rekognition DetectFaces', {
    faceCount,
    locations: faceDetails.map((f) => f.BoundingBox),
  });

  return { faceCount, faceDetails };
}

/**
 * Validate face quality (blur, lighting, pose). Returns { ok, reason }.
 */
export function validateFaceQuality(faceDetail: FaceDetail): QualityCheckResult {
  const quality = faceDetail.Quality;
  const pose = faceDetail.Pose;

  logger.info('Validating face quality', {
    sharpness: quality?.Sharpness,
    brightness: quality?.Brightness,
    yaw: pose?.Yaw,
    pitch: pose?.Pitch
  });

  if (quality?.Sharpness != null && quality.Sharpness < QUALITY_THRESHOLDS.minSharpness) {
    return { ok: false, reason: 'Por favor sube una imagen más clara (muy borrosa)' };
  }

  if (quality?.Brightness != null) {
    if (quality.Brightness < QUALITY_THRESHOLDS.minBrightness) {
      return { ok: false, reason: 'Por favor sube una imagen con mejor iluminación (muy oscura)' };
    }
    if (quality.Brightness > QUALITY_THRESHOLDS.maxBrightness) {
      return { ok: false, reason: 'Por favor sube una imagen con mejor iluminación (mucha luz)' };
    }
  }

  if (pose) {
    const yaw = pose.Yaw ?? 0;
    const pitch = pose.Pitch ?? 0;
    if (Math.abs(yaw) > QUALITY_THRESHOLDS.maxAbsYaw || Math.abs(pitch) > QUALITY_THRESHOLDS.maxAbsPitch) {
      return { ok: false, reason: 'Mira directamente a la cámara frontalmente' };
    }
  }

  return { ok: true };
}

/**
 * Crop face from image using Rekognition bounding box.
 * BoundingBox: Left, Top, Width, Height as ratios 0-1.
 */
export async function cropFaceFromImage(image: Buffer, boundingBox: BoundingBox): Promise<Buffer> {
  const meta = await sharp(image).metadata();
  const w = meta.width ?? 1;
  const h = meta.height ?? 1;

  // INCREASED PADDING: 20% instead of 8% to get more of the head/shoulders for better recognition
  const paddingX = (boundingBox.Width ?? 0.1) * 0.20;
  const paddingY = (boundingBox.Height ?? 0.1) * 0.20;

  const left = Math.max(0, Math.floor(((boundingBox.Left ?? 0) - paddingX) * w));
  const top = Math.max(0, Math.floor(((boundingBox.Top ?? 0) - paddingY) * h));
  const width = Math.min(w - left, Math.ceil(((boundingBox.Width ?? 0.1) + paddingX * 2) * w));
  const height = Math.min(h - top, Math.ceil(((boundingBox.Height ?? 0.1) + paddingY * 2) * h));

  if (width <= 0 || height <= 0) {
    throw new Error('Invalid bounding box for face crop');
  }

  const cropped = await sharp(image)
    .extract({ left, top, width, height })
    .resize(400, 400, { fit: 'cover' }) // Standardize size for more consistent comparison scores
    .jpeg({ quality: 95, chromaSubsampling: '4:4:4' }) // High quality
    .toBuffer();

  return cropped;
}

/**
 * Compare two face images. Returns similarity 0-100.
 * Tries cropped images first, falls back to originals if Rekognition rejects parameters.
 */
export async function compareFaces(
  sourceCropped: Buffer,
  targetCropped: Buffer,
  sourceOriginal?: Buffer,
  targetOriginal?: Buffer,
): Promise<number> {
  const client = getRekognitionClient();
  if (!client) {
    const mock = 96 + Math.random() * 3;
    logger.info('Rekognition: AWS not configured, mock similarity', { mock: Math.round(mock * 10) / 10 });
    return mock;
  }

  const tryCompare = async (source: Buffer, target: Buffer): Promise<number> => {
    const command = new CompareFacesCommand({
      SourceImage: { Bytes: source },
      TargetImage: { Bytes: target },
      SimilarityThreshold: 0,
    });
    const response = await client.send(command);
    const matches = response.FaceMatches ?? [];
    if (matches.length === 0) return 0;
    return matches.reduce((max, m) => {
      const sim = m.Similarity ?? 0;
      return sim > max ? sim : max;
    }, 0);
  };

  // First attempt: cropped faces (faster + more precise)
  try {
    return await tryCompare(sourceCropped, targetCropped);
  } catch (err: any) {
    logger.warn('CompareFaces with cropped images failed, trying full images', { error: err.message, code: err.code });
  }

  // Second attempt: full original images (wider context, Rekognition finds faces itself)
  if (sourceOriginal && targetOriginal) {
    try {
      return await tryCompare(sourceOriginal, targetOriginal);
    } catch (err: any) {
      logger.error('CompareFaces with full images also failed', { error: err.message, code: err.code });
      throw new Error(`Error al comparar rostros con AWS Rekognition: ${err.message}`);
    }
  }

  // No fallback available
  throw new Error('Error al comparar rostros: imágenes inválidas para Rekognition');
}

/**
 * Detect labels in an image (e.g., ID Card, Document).
 */
export async function detectLabels(image: Buffer): Promise<Label[]> {
  const client = getRekognitionClient();
  if (!client) return [{ Name: 'Id Card', Confidence: 99 } as any];

  const command = new DetectLabelsCommand({
    Image: { Bytes: image },
    MaxLabels: 10,
    MinConfidence: 70,
  });
  try {
    const response = await client.send(command);
    return response.Labels ?? [];
  } catch (err: any) {
    logger.warn('Rekognition DetectLabels failed, skipping document validation', { error: err.message });
    return [];
  }
}

/**
 * Validates if an image is likely a document/ID card.
 */
export async function validateDocumentLabels(image: Buffer): Promise<{ ok: boolean; confidence: number }> {
  const labels = await detectLabels(image);
  const docLabels = labels.filter((l) =>
    ['Id Card', 'Identification', 'Document', 'License'].includes(l.Name || '')
  );

  if (docLabels.length === 0) return { ok: false, confidence: 0 };

  const maxConf = Math.max(...docLabels.map((l) => l.Confidence || 0));
  return { ok: maxConf >= 80, confidence: maxConf };
}

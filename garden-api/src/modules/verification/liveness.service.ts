import logger from '../../shared/logger.js';
import { BadRequestError } from '../../shared/errors.js';
import { RekognitionClient, GetFaceLivenessSessionResultsCommand, CreateFaceLivenessSessionCommand, DetectFacesCommand, CompareFacesCommand } from '@aws-sdk/client-rekognition';
import jwt from 'jsonwebtoken';
import sharp from 'sharp';
import { randomUUID, createHash } from 'crypto';
import { env } from '../../config/env.js';

export type LivenessProvider = 'FACETEC' | 'ONFIDO' | 'AWS_REKOGNITION';

/**
 * AWS recomienda 90 como punto de partida, pero con cámara de celular e
 * iluminación variable es común no llegar justo a ese número aunque la
 * persona sea real. 85 sigue bloqueando spoofing evidente (fotos, videos,
 * máscaras) con bastantes menos falsos rechazos legítimos.
 */
export const LIVENESS_CONFIDENCE_THRESHOLD = 85;

/** Parpadeo web: similitud mínima entre el frame de ojos abiertos y el de ojos cerrados. */
const BLINK_SAME_PERSON_MIN_SIMILARITY = 90;

export interface LivenessResult {
  passed: boolean;
  score: number;
  provider: LivenessProvider;
  status: 'PASSED' | 'FAILED';
  externalSessionId?: string;
  reason?: string;
  /** Imagen de referencia que AWS capturó durante la prueba de vida (solo si la devolvió). */
  referenceImage?: Buffer;
}

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

/**
 * Advanced Liveness Detection Service.
 */
export async function performLivenessCheck(
  sessionData: { sessionId?: string },
  provider: LivenessProvider = 'AWS_REKOGNITION'
): Promise<LivenessResult> {
  logger.info('Performing production liveness check', { provider, sessionId: sessionData?.sessionId });

  if (!sessionData?.sessionId) {
    logger.error('Liveness check failed: Missing sessionId');
    return {
      passed: false,
      score: 0,
      provider,
      status: 'FAILED',
      reason: 'No se proporcionó un ID de sesión válido'
    };
  }

  if (provider === 'AWS_REKOGNITION') {
    return verifyAwsLiveness(sessionData.sessionId);
  }

  throw new BadRequestError('Provider de liveness no soportado para producción');
}

/**
 * Miniatura (base64) de la cara capturada EN la prueba de vida. Viaja dentro del JWT
 * firmado para que /submit compare esa cara —la que de verdad estuvo frente a la
 * cámara— contra la foto del documento. Sin esto la selfie se subía aparte y nada
 * probaba que fuera la misma persona que pasó el liveness.
 */
async function makeReferenceThumb(image: Buffer): Promise<string | undefined> {
  try {
    const out = await sharp(image).resize(320, 320, { fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 75 }).toBuffer();
    return out.toString('base64');
  } catch (err: any) {
    logger.warn('Liveness: no se pudo generar la miniatura de referencia', { error: err.message });
    return undefined;
  }
}

async function verifyAwsLiveness(sessionId: string): Promise<LivenessResult> {
  const client = getRekognitionClient();

  // If no AWS credentials: fail the liveness check so the submission routes to
  // manual admin review instead of silently auto-approving.
  const isDummy = sessionId.startsWith('session-');
  if (!client) {
    logger.warn('Identity: AWS credentials not configured — liveness check cannot run', {
      sessionId: sessionId.substring(0, 16),
    });
    return {
      passed: false,
      score: 0,
      provider: 'AWS_REKOGNITION',
      status: 'FAILED',
      reason: 'Verificación de vida no disponible — se requiere revisión manual',
    };
  }
  if (isDummy) {
    // Placeholder sessionId from a client that hasn't integrated the real SDK yet.
    // Return a low score so the verification lands in REVIEW, not auto-approved.
    logger.warn('Identity: Dummy sessionId received — routing to manual review', {
      sessionId: sessionId.substring(0, 16),
    });
    return {
      passed: false,
      score: 0,
      provider: 'AWS_REKOGNITION',
      status: 'FAILED',
      reason: 'Verificación de vida pendiente — un administrador revisará tu solicitud',
    };
  }

  try {
    const command = new GetFaceLivenessSessionResultsCommand({ SessionId: sessionId });
    const response = await client.send(command);

    const confidence = response.Confidence ?? 0;
    const status = response.Status; // EXPIRED | CREATED | IN_PROGRESS | SUCCEEDED | FAILED

    const passed = status === 'SUCCEEDED' && confidence >= LIVENESS_CONFIDENCE_THRESHOLD;

    logger.info('AWS Liveness Result', { sessionId, confidence, status, passed });

    return {
      passed,
      score: Math.round(confidence),
      provider: 'AWS_REKOGNITION',
      status: passed ? 'PASSED' : 'FAILED',
      externalSessionId: sessionId,
      referenceImage: response.ReferenceImage?.Bytes ? Buffer.from(response.ReferenceImage.Bytes) : undefined,
      reason: passed ? undefined : `Fallo en prueba de vida (Confianza: ${confidence}%)`
    };
  } catch (error: any) {
    logger.error('AWS Liveness API Error', { sessionId, error: error.message });
    return {
      passed: false,
      score: 0,
      provider: 'AWS_REKOGNITION',
      status: 'FAILED',
      reason: 'Error al validar prueba de vida con el servidor'
    };
  }
}

/**
 * Verifica el resultado de una sesión de AWS Face Liveness apenas el widget nativo
 * termina de capturar (en vez de esperar a /submit, varios minutos después de
 * tomar las 3 fotos siguientes). Si pasa, emite un JWT de corta duración que
 * /submit acepta sin volver a consultar a AWS — evita cualquier problema de
 * resultados que ya no estén disponibles/actualizados para cuando el usuario
 * termina de subir las fotos del CI.
 */
export async function checkAwsLivenessNow(
  sessionId: string,
  userId: string,
): Promise<{ passed: boolean; score: number; status: string; reason?: string; token?: string }> {
  const result = await verifyAwsLiveness(sessionId);

  if (!result.passed) {
    return { passed: false, score: result.score, status: result.status, reason: result.reason };
  }

  const ref = result.referenceImage ? await makeReferenceThumb(result.referenceImage) : undefined;
  if (!ref) {
    logger.warn('Liveness: AWS no devolvió imagen de referencia — el token no queda atado al documento', { sessionId });
  }

  const token = jwt.sign(
    // jti = sessionId de AWS: /submit lo marca como usado (una prueba de vida = una verificación).
    { userId, sessionId, jti: sessionId, type: 'aws_liveness', score: result.score, ...(ref ? { ref } : {}) },
    env.JWT_SECRET as string,
    { expiresIn: '15m' },
  );

  return { passed: true, score: result.score, status: result.status, token };
}

/**
 * Creates an AWS Rekognition FaceLiveness session.
 * Returns the sessionId that the mobile client passes to the Amplify Liveness SDK.
 * Requires AWS credentials with rekognition:CreateFaceLivenessSession permission.
 */
export async function createLivenessSession(): Promise<{ sessionId: string } | null> {
  const client = getRekognitionClient();
  if (!client) {
    logger.warn('createLivenessSession: AWS credentials not configured');
    return null;
  }
  try {
    const command = new CreateFaceLivenessSessionCommand({});
    const response = await client.send(command);
    if (!response.SessionId) throw new Error('No SessionId returned from AWS');
    logger.info('FaceLiveness session created', { sessionId: response.SessionId });
    return { sessionId: response.SessionId };
  } catch (error: any) {
    logger.error('Failed to create FaceLiveness session', { error: error.message });
    return null;
  }
}

/**
 * Blink liveness for Flutter web (QR flow).
 * Accepts 2 frames: eyesOpen + eyesClosed.
 * Uses Rekognition DetectFaces to verify eye state changed → real person.
 * Returns a short-lived signed JWT that /submit accepts as livenessToken.
 */
export async function checkBlinkLiveness(
  frameOpen: Buffer,
  frameClosed: Buffer,
  userId: string,
): Promise<{ passed: boolean; score: number; token?: string; reason?: string }> {
  const client = getRekognitionClient();
  if (!client) {
    return { passed: false, score: 0, reason: 'AWS no configurado' };
  }

  try {
    const [resOpen, resClosed] = await Promise.all([
      client.send(new DetectFacesCommand({ Image: { Bytes: frameOpen }, Attributes: ['ALL'] })),
      client.send(new DetectFacesCommand({ Image: { Bytes: frameClosed }, Attributes: ['ALL'] })),
    ]);

    const faceOpen = resOpen.FaceDetails?.[0];
    const faceClosed = resClosed.FaceDetails?.[0];

    if (!faceOpen) return { passed: false, score: 0, reason: 'No se detectó rostro en el frame de ojos abiertos' };
    if (!faceClosed) return { passed: false, score: 0, reason: 'No se detectó rostro en el frame de ojos cerrados' };

    const openValue = faceOpen.EyesOpen?.Value === true;
    const closedValue = faceClosed.EyesOpen?.Value === false;
    const openConf = faceOpen.EyesOpen?.Confidence ?? 0;
    const closedConf = faceClosed.EyesOpen?.Confidence ?? 0;

    logger.info('Blink liveness check', {
      userId,
      eyesOpenFrame: { value: openValue, confidence: openConf },
      eyesClosedFrame: { value: closedValue, confidence: closedConf },
    });

    // Both frames must show the expected eye state with >70% confidence
    const passed = openValue && closedValue && openConf >= 70 && closedConf >= 70;
    const score = passed ? Math.round((openConf + closedConf) / 2) : 0;

    if (!passed) {
      return {
        passed: false,
        score,
        reason: !openValue
          ? 'No se detectaron los ojos abiertos en el primer frame'
          : 'No se detectó el parpadeo en el segundo frame',
      };
    }

    // Los dos frames deben ser fotos distintas de LA MISMA persona: sin esto bastaba con
    // mandar cualquier cara con ojos abiertos y otra cualquiera con ojos cerrados.
    const sha = (b: Buffer) => createHash('sha256').update(b).digest('hex');
    if (sha(frameOpen) === sha(frameClosed)) {
      return { passed: false, score: 0, reason: 'Los dos frames son idénticos. Parpadea frente a la cámara.' };
    }
    const sameFace = await client.send(new CompareFacesCommand({
      SourceImage: { Bytes: frameOpen },
      TargetImage: { Bytes: frameClosed },
      SimilarityThreshold: 0,
    }));
    const faceSimilarity = Math.max(0, ...(sameFace.FaceMatches ?? []).map((m) => m.Similarity ?? 0));
    if (faceSimilarity < BLINK_SAME_PERSON_MIN_SIMILARITY) {
      logger.warn('Blink liveness: los frames no parecen ser la misma persona', { userId, faceSimilarity });
      return { passed: false, score: 0, reason: 'No se pudo confirmar que ambos frames sean la misma persona. Intenta de nuevo.' };
    }

    // Issue a short-lived JWT so /submit can verify this blink check happened
    // El frame de ojos abiertos hace de imagen de referencia (mismo rol que en AWS Liveness).
    const ref = await makeReferenceThumb(frameOpen);
    const blinkToken = jwt.sign(
      { userId, jti: randomUUID(), type: 'blink_liveness', score, ...(ref ? { ref } : {}) },
      env.JWT_SECRET as string,
      { expiresIn: '15m' },
    );

    return { passed: true, score, token: blinkToken };
  } catch (error: any) {
    logger.error('Blink liveness check failed', { userId, error: error.message });
    return { passed: false, score: 0, reason: 'Error al analizar los frames' };
  }
}

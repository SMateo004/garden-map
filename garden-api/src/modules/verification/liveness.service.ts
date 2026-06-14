import logger from '../../shared/logger.js';
import { BadRequestError } from '../../shared/errors.js';
import { RekognitionClient, GetFaceLivenessSessionResultsCommand, CreateFaceLivenessSessionCommand } from '@aws-sdk/client-rekognition';
import { env } from '../../config/env.js';

export type LivenessProvider = 'FACETEC' | 'ONFIDO' | 'AWS_REKOGNITION';

export interface LivenessResult {
  passed: boolean;
  score: number;
  provider: LivenessProvider;
  status: 'PASSED' | 'FAILED';
  externalSessionId?: string;
  reason?: string;
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

    const passed = status === 'SUCCEEDED' && confidence >= 90;

    logger.info('AWS Liveness Result', { sessionId, confidence, status, passed });

    return {
      passed,
      score: Math.round(confidence),
      provider: 'AWS_REKOGNITION',
      status: passed ? 'PASSED' : 'FAILED',
      externalSessionId: sessionId,
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

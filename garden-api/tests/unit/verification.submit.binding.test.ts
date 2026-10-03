/**
 * submitVerification: el liveness debe estar atado al documento (claim `ref`) y
 * cada token de liveness se puede usar una sola vez.
 */
import jwt from 'jsonwebtoken';

const SECRET = 'x'.repeat(32);
const store = new Map<string, unknown>();

jest.mock('../../src/config/env', () => ({
  env: { JWT_SECRET: 'x'.repeat(32), NODE_ENV: 'test', FRONTEND_URL: 'http://localhost' },
}));
jest.mock('../../src/shared/cache', () => ({
  getCache: () => ({
    get: async (k: string) => (store.has(k) ? store.get(k) : null),
    set: async (k: string, v: unknown) => { store.set(k, v); },
    del: async (k: string) => { store.delete(k); },
  }),
}));

const sessionUpdate = jest.fn();
jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    identityVerificationSession: {
      findUnique: jest.fn(async () => ({
        id: 'sess-1', userId: 'u1', status: 'PENDING', expiresAt: new Date(Date.now() + 60_000),
        user: { id: 'u1', firstName: 'Ana', lastName: 'Perez', dateOfBirth: null, city: 'Santa Cruz' },
      })),
      update: (...a: unknown[]) => sessionUpdate(...a),
    },
    caregiverProfile: {
      findUnique: jest.fn(async () => ({ verificationAttempts: 0, verificationLockUntil: null, status: 'DRAFT' })),
      update: jest.fn(async () => ({})),
    },
    user: { update: jest.fn(async () => ({})) },
    notification: { create: jest.fn(async () => ({})) },
    verificationAudit: { create: jest.fn(async () => ({})) },
    $transaction: jest.fn(async (ops: Promise<unknown>[]) => Promise.all(ops)),
  },
}));

const mockCompare = jest.fn();
jest.mock('../../src/modules/verification/rekognition.service', () => ({
  detectFacesWithDetails: jest.fn(async () => ({
    faceCount: 1, faceDetails: [{ BoundingBox: {}, Quality: { Sharpness: 90, Brightness: 50 } }],
  })),
  validateFaceQuality: jest.fn(() => ({ ok: true })),
  cropFaceFromImage: jest.fn(async (b: Buffer) => b),
  compareFaces: (...a: unknown[]) => mockCompare(...a),
  validateDocumentLabels: jest.fn(async () => ({ ok: true, confidence: 95 })),
}));
jest.mock('../../src/modules/verification/liveness.service', () => ({
  performLivenessCheck: jest.fn(),
  LIVENESS_CONFIDENCE_THRESHOLD: 85,
}));
jest.mock('../../src/modules/verification/identity-validation.service', () => ({
  crossValidate: jest.fn(async () => ({
    documentConfidence: 0.9, nameSimilarity: 95, fraudFlags: [],
    ocrData: { documentNumber: '1234567', dateOfBirth: '01/01/1990' },
  })),
  calculateDetailedTrustScore: jest.fn(() => ({
    status: 'VERIFIED', trustScore: 95, faceScore: 98, ocrScore: 95, docScore: 95, qualityScore: 90, behaviorScore: 90,
  })),
}));
jest.mock('../../src/modules/verification/ocr.service', () => ({
  parseExtractedDOB: jest.fn(() => new Date('1990-01-01')),
  calculateAgeFromDOB: jest.fn(() => 35),
}));
jest.mock('../../src/modules/verification/fraud.service', () => ({
  generateFingerprint: jest.fn(() => 'fp'),
  getGeolocation: jest.fn(async () => ({})),
  logVerificationAudit: jest.fn(),
  calculateBehavioralRisk: jest.fn(async () => ({ behaviorScore: 90, fraudFlags: [] })),
}));
jest.mock('../../src/modules/verification/verification-upload', () => ({
  uploadVerificationImage: jest.fn(async () => 'url'),
}));
jest.mock('../../src/services/blockchain.service', () => ({
  blockchainService: { updateVerificationOnChain: jest.fn(async () => undefined) },
}));

import { submitVerification } from '../../src/modules/verification/verification.service';

const buf = Buffer.from('img');
const sessionToken = () => jwt.sign({ verificationId: 'sess-1', userId: 'u1', type: 'identity_verification' }, SECRET);
const livenessToken = (extra: Record<string, unknown>) =>
  jwt.sign({ userId: 'u1', type: 'aws_liveness', score: 97, ...extra }, SECRET, { expiresIn: '15m' });
const submit = (awsToken: string) =>
  submitVerification(sessionToken(), buf, buf, buf, undefined, undefined, undefined, awsToken);

describe('submitVerification — liveness atado al documento', () => {
  beforeEach(() => { store.clear(); mockCompare.mockReset(); sessionUpdate.mockReset(); });

  it('rechaza si la cara del liveness no coincide con el documento', async () => {
    mockCompare.mockResolvedValueOnce(98).mockResolvedValueOnce(40); // selfie↔CI ok, liveness↔CI no
    await expect(submit(livenessToken({ jti: 'j1', ref: Buffer.from('r').toString('base64') })))
      .rejects.toThrow(/no coincide con el documento/);
    expect(sessionUpdate).not.toHaveBeenCalled();
  });

  it('aprueba si coincide y bloquea reusar el mismo token de liveness', async () => {
    mockCompare.mockResolvedValue(97);
    const token = livenessToken({ jti: 'j2', ref: Buffer.from('r').toString('base64') });

    const first = await submit(token);
    expect(first.status).toBe('VERIFIED');
    expect(mockCompare).toHaveBeenCalledTimes(2);

    await expect(submit(token)).rejects.toThrow(/ya fue usada/);
  });

  it('sin ref aprueba pero deja la marca liveness_not_bound', async () => {
    mockCompare.mockResolvedValue(97);
    const res = await submit(livenessToken({ jti: 'j3' }));
    expect(res.status).toBe('VERIFIED');
    expect(mockCompare).toHaveBeenCalledTimes(1);
    expect(sessionUpdate.mock.calls[0][0].data.fraudFlags).toContain('liveness_not_bound');
  });
});

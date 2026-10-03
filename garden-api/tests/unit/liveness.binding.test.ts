/**
 * El token de liveness debe llevar la cara capturada EN la prueba de vida (claim `ref`)
 * y un `jti` para que /submit lo marque como usado — ver verification.service.ts.
 */
import jwt from 'jsonwebtoken';
import sharp from 'sharp';

const mockSend = jest.fn();

jest.mock('@aws-sdk/client-rekognition', () => ({
  RekognitionClient: jest.fn().mockImplementation(() => ({ send: mockSend })),
  GetFaceLivenessSessionResultsCommand: jest.fn().mockImplementation((input) => ({ kind: 'results', input })),
  CreateFaceLivenessSessionCommand: jest.fn(),
  DetectFacesCommand: jest.fn().mockImplementation((input) => ({ kind: 'detect', input })),
  CompareFacesCommand: jest.fn().mockImplementation((input) => ({ kind: 'compare', input })),
}));

jest.mock('../../src/config/env', () => ({
  env: {
    AWS_ACCESS_KEY_ID: 'k',
    AWS_SECRET_ACCESS_KEY: 's',
    AWS_REGION: 'us-east-1',
    JWT_SECRET: 'x'.repeat(32),
  },
}));

import { checkAwsLivenessNow, checkBlinkLiveness } from '../../src/modules/verification/liveness.service';

const SECRET = 'x'.repeat(32);

async function fakeFace(): Promise<Buffer> {
  return sharp({ create: { width: 640, height: 480, channels: 3, background: { r: 120, g: 90, b: 70 } } })
    .jpeg()
    .toBuffer();
}

describe('liveness token binding', () => {
  beforeEach(() => mockSend.mockReset());

  it('AWS: el token incluye ref (miniatura) y jti = sessionId', async () => {
    const face = await fakeFace();
    mockSend.mockResolvedValue({ Status: 'SUCCEEDED', Confidence: 97, ReferenceImage: { Bytes: face } });

    const res = await checkAwsLivenessNow('sess-123', 'user-1');
    expect(res.passed).toBe(true);

    const payload = jwt.verify(res.token!, SECRET) as any;
    expect(payload.type).toBe('aws_liveness');
    expect(payload.userId).toBe('user-1');
    expect(payload.jti).toBe('sess-123');
    const thumb = Buffer.from(payload.ref, 'base64');
    const meta = await sharp(thumb).metadata();
    expect(meta.format).toBe('jpeg');
    expect(Math.max(meta.width!, meta.height!)).toBeLessThanOrEqual(320);
  });

  it('AWS: si AWS no devuelve imagen de referencia, el token sale sin ref (rollout gradual)', async () => {
    mockSend.mockResolvedValue({ Status: 'SUCCEEDED', Confidence: 97 });
    const res = await checkAwsLivenessNow('sess-456', 'user-1');
    const payload = jwt.verify(res.token!, SECRET) as any;
    expect(payload.ref).toBeUndefined();
    expect(payload.jti).toBe('sess-456');
  });

  it('AWS: liveness fallido no emite token', async () => {
    mockSend.mockResolvedValue({ Status: 'FAILED', Confidence: 40 });
    const res = await checkAwsLivenessNow('sess-789', 'user-1');
    expect(res.passed).toBe(false);
    expect(res.token).toBeUndefined();
  });

  it('Parpadeo: rechaza si los frames son de personas distintas', async () => {
    const open = await sharp({ create: { width: 640, height: 480, channels: 3, background: { r: 1, g: 2, b: 3 } } }).jpeg().toBuffer();
    const closed = await fakeFace();
    mockSend.mockImplementation(async (cmd: any) => {
      if (cmd.kind === 'compare') return { FaceMatches: [{ Similarity: 40 }] };
      return { FaceDetails: [{ EyesOpen: { Value: cmd.input.Image.Bytes === open, Confidence: 95 } }] };
    });
    const res = await checkBlinkLiveness(open, closed, 'user-3');
    expect(res.passed).toBe(false);
    expect(res.token).toBeUndefined();
  });

  it('Parpadeo: rechaza si los dos frames son la misma imagen', async () => {
    const same = await fakeFace();
    mockSend.mockImplementation(async (cmd: any) => ({ FaceDetails: [{ EyesOpen: { Value: true, Confidence: 95 } }] }));
    const res = await checkBlinkLiveness(same, Buffer.from(same), 'user-3');
    expect(res.passed).toBe(false);
  });

  it('Parpadeo: el frame de ojos abiertos queda como ref y cada token tiene jti propio', async () => {
    const open = await fakeFace();
    const closed = await sharp({ create: { width: 640, height: 480, channels: 3, background: { r: 130, g: 95, b: 75 } } }).jpeg().toBuffer();
    mockSend.mockImplementation(async (cmd: any) => {
      if (cmd.kind === 'compare') return { FaceMatches: [{ Similarity: 99 }] };
      return { FaceDetails: [{ EyesOpen: { Value: cmd.input.Image.Bytes === open, Confidence: 95 } }] };
    });

    const a = await checkBlinkLiveness(open, closed, 'user-2');
    const b = await checkBlinkLiveness(open, closed, 'user-2');
    expect(a.passed).toBe(true);
    const pa = jwt.verify(a.token!, SECRET) as any;
    const pb = jwt.verify(b.token!, SECRET) as any;
    expect(pa.type).toBe('blink_liveness');
    expect(pa.ref).toBeTruthy();
    expect(pa.jti).not.toBe(pb.jti);
  });
});

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: { user: { findUnique: jest.fn() } },
}));

import jwt from 'jsonwebtoken';
import prisma from '../../src/config/database';
import { env } from '../../src/config/env';
import { issuePinToken, isValidPinToken, requirePinToken } from '../../src/middleware/require-pin.middleware';

const findUnique = (prisma as any).user.findUnique as jest.Mock;

function call(userId: string, pinToken?: string) {
  const req: any = { user: { userId }, headers: pinToken ? { 'x-pin-token': pinToken } : {} };
  let status = 200;
  let body: any;
  const res: any = {
    status: (s: number) => { status = s; return res; },
    json: (b: unknown) => { body = b; return res; },
  };
  const next = jest.fn();
  return requirePinToken(req, res, next).then(() => ({ status, body, nextCalled: next.mock.calls.length === 1 }));
}

describe('requirePinToken', () => {
  beforeEach(() => findUnique.mockReset());

  it('sin PIN configurado (registro inicial) deja pasar', async () => {
    findUnique.mockResolvedValue({ securityPinHash: null });
    const r = await call('u1');
    expect(r.nextCalled).toBe(true);
  });

  it('con PIN y sin token responde 403 PIN_REQUIRED', async () => {
    findUnique.mockResolvedValue({ securityPinHash: 'hash' });
    const r = await call('u1');
    expect(r.nextCalled).toBe(false);
    expect(r.status).toBe(403);
    expect(r.body.error.code).toBe('PIN_REQUIRED');
  });

  it('con PIN y token válido del mismo usuario deja pasar', async () => {
    findUnique.mockResolvedValue({ securityPinHash: 'hash' });
    const r = await call('u1', issuePinToken('u1'));
    expect(r.nextCalled).toBe(true);
  });

  it('rechaza el token de otro usuario', async () => {
    findUnique.mockResolvedValue({ securityPinHash: 'hash' });
    const r = await call('u1', issuePinToken('u2'));
    expect(r.status).toBe(403);
  });

  it('el token de PIN no sirve como token de sesión (secreto distinto)', () => {
    const pinToken = issuePinToken('u1');
    expect(() => jwt.verify(pinToken, env.JWT_SECRET)).toThrow();
    // y un JWT de sesión no sirve como token de PIN
    const session = jwt.sign({ userId: 'u1', sub: 'u1', scope: 'security-pin' }, env.JWT_SECRET);
    expect(isValidPinToken(session, 'u1')).toBe(false);
  });
});

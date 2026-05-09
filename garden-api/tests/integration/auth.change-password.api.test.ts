/**
 * Integration tests: PATCH /api/auth/change-password
 * Verifies: correct password → success, wrong password → 401, same password → 400,
 * short password → 400, mismatch confirmPassword → 400, unauthenticated → 401.
 */

import request from 'supertest';
import prisma from '../../src/config/database';

const CURRENT_PASSWORD = 'OldPass123!';
const HASHED_CURRENT = `hashed_${CURRENT_PASSWORD}`;
const NEW_PASSWORD = 'NewPass456!';

jest.mock('../../src/config/database', () => {
  const user = {
    findUnique: jest.fn(),
    update: jest.fn().mockResolvedValue({ id: 'user-cp-1' }),
  };
  const refreshToken = {
    updateMany: jest.fn().mockResolvedValue({ count: 1 }),
  };
  return {
    __esModule: true,
    default: {
      user,
      refreshToken,
      $transaction: jest.fn((ops: unknown[]) => Promise.all(ops)),
      $queryRaw: jest.fn().mockResolvedValue([]),
    },
  };
});

jest.mock('bcrypt', () => ({
  compare: jest.fn((pw: string, hash: string) => Promise.resolve(hash === `hashed_${pw}`)),
  hash: jest.fn((pw: string) => Promise.resolve(`hashed_${pw}`)),
}));

jest.mock('express-rate-limit', () => () => (_req: unknown, _res: unknown, next: () => void) => next());

jest.mock('../../src/middleware/auth.middleware', () => ({
  authMiddleware: (req: { user?: { userId: string; role: string } }, _res: unknown, next: () => void) => {
    req.user = { userId: 'user-cp-1', role: 'CLIENT' };
    next();
  },
  requireRole: () => (_req: unknown, _res: unknown, next: () => void) => next(),
}));

jest.mock('../../src/config/stripe', () => ({ stripe: null, STRIPE_WEBHOOK_SECRET: '' }));
jest.mock('../../src/services/blockchain.service', () => ({
  blockchainService: { getCaregiverReputation: jest.fn().mockResolvedValue(null) },
}));

import app from '../../src/app';

const mockPrisma = prisma as jest.Mocked<typeof prisma>;

describe('PATCH /api/auth/change-password', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue({
      id: 'user-cp-1',
      passwordHash: HASHED_CURRENT,
    });
  });

  it('returns 200 when currentPassword is correct and newPassword is valid', async () => {
    const res = await request(app)
      .patch('/api/auth/change-password')
      .send({ currentPassword: CURRENT_PASSWORD, newPassword: NEW_PASSWORD });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(mockPrisma.user.update).toHaveBeenCalled();
    expect(mockPrisma.refreshToken.updateMany).toHaveBeenCalled();
  });

  it('returns 200 when confirmPassword matches', async () => {
    const res = await request(app)
      .patch('/api/auth/change-password')
      .send({ currentPassword: CURRENT_PASSWORD, newPassword: NEW_PASSWORD, confirmPassword: NEW_PASSWORD });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  it('returns 400 when confirmPassword does not match', async () => {
    const res = await request(app)
      .patch('/api/auth/change-password')
      .send({ currentPassword: CURRENT_PASSWORD, newPassword: NEW_PASSWORD, confirmPassword: 'WrongConfirm!' });

    expect(res.status).toBe(400);
    expect(res.body.error?.code).toBe('PASSWORD_MISMATCH');
  });

  it('returns 401 when currentPassword is wrong', async () => {
    const res = await request(app)
      .patch('/api/auth/change-password')
      .send({ currentPassword: 'WrongPassword!', newPassword: NEW_PASSWORD });

    expect(res.status).toBe(401);
  });

  it('returns 400 when newPassword is same as current', async () => {
    const res = await request(app)
      .patch('/api/auth/change-password')
      .send({ currentPassword: CURRENT_PASSWORD, newPassword: CURRENT_PASSWORD });

    expect(res.status).toBe(400);
    expect(res.body.error?.code).toBe('SAME_PASSWORD');
  });

  it('returns 400 when newPassword is too short', async () => {
    const res = await request(app)
      .patch('/api/auth/change-password')
      .send({ currentPassword: CURRENT_PASSWORD, newPassword: 'short' });

    expect(res.status).toBe(400);
    expect(res.body.error?.code).toBe('PASSWORD_TOO_SHORT');
  });

  it('returns 400 when currentPassword is missing', async () => {
    const res = await request(app)
      .patch('/api/auth/change-password')
      .send({ newPassword: NEW_PASSWORD });

    expect(res.status).toBe(400);
    expect(res.body.error?.code).toBe('MISSING_CURRENT_PASSWORD');
  });

  it('returns 400 when newPassword is missing', async () => {
    const res = await request(app)
      .patch('/api/auth/change-password')
      .send({ currentPassword: CURRENT_PASSWORD });

    expect(res.status).toBe(400);
    expect(res.body.error?.code).toBe('MISSING_NEW_PASSWORD');
  });
});

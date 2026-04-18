/**
 * Tests para rotateRefreshToken y revokeAllRefreshTokens (Fase 1 — JWT Refresh Tokens).
 */

import {
  rotateRefreshToken,
  revokeAllRefreshTokens,
} from '../../src/modules/auth/auth.service';
import prisma from '../../src/config/database';
import { UserRole } from '@prisma/client';

// ── Mocks ─────────────────────────────────────────────────────────────────────

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    refreshToken: {
      findUnique: jest.fn(),
      update: jest.fn(),
      create: jest.fn(),
      updateMany: jest.fn(),
    },
    user: {
      findUnique: jest.fn(),
    },
  },
}));

jest.mock('../../src/shared/analytics', () => ({
  track: jest.fn(),
  identify: jest.fn(),
}));

jest.mock('../../src/services/blockchain.service', () => ({
  blockchainService: { registerUser: jest.fn() },
}));

const mockPrisma = prisma as jest.Mocked<typeof prisma>;

// ── rotateRefreshToken ────────────────────────────────────────────────────────

describe('rotateRefreshToken', () => {
  const mockUser = {
    id: 'user-1',
    role: UserRole.CLIENT,
    isDeleted: false,
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (mockPrisma.refreshToken.create as jest.Mock).mockResolvedValue({
      id: 'rt-new',
      tokenHash: 'new-hash',
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    });
  });

  it('devuelve null si el token no existe en la BD', async () => {
    (mockPrisma.refreshToken.findUnique as jest.Mock).mockResolvedValue(null);

    const result = await rotateRefreshToken('invalid-raw-token');
    expect(result).toBeNull();
  });

  it('devuelve null si el token está revocado', async () => {
    (mockPrisma.refreshToken.findUnique as jest.Mock).mockResolvedValue({
      id: 'rt-1',
      userId: 'user-1',
      revokedAt: new Date(), // ya revocado
      expiresAt: new Date(Date.now() + 1000),
    });

    const result = await rotateRefreshToken('revoked-token');
    expect(result).toBeNull();
  });

  it('devuelve null si el token está expirado', async () => {
    (mockPrisma.refreshToken.findUnique as jest.Mock).mockResolvedValue({
      id: 'rt-1',
      userId: 'user-1',
      revokedAt: null,
      expiresAt: new Date(Date.now() - 1000), // expirado
    });

    const result = await rotateRefreshToken('expired-token');
    expect(result).toBeNull();
  });

  it('devuelve null si el usuario no existe o está eliminado', async () => {
    (mockPrisma.refreshToken.findUnique as jest.Mock).mockResolvedValue({
      id: 'rt-1',
      userId: 'user-deleted',
      revokedAt: null,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    });
    (mockPrisma.refreshToken.update as jest.Mock).mockResolvedValue({});
    (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue(null);

    const result = await rotateRefreshToken('valid-format-but-deleted-user');
    expect(result).toBeNull();
  });

  it('devuelve nuevos tokens y revoca el token anterior en rotación exitosa', async () => {
    (mockPrisma.refreshToken.findUnique as jest.Mock).mockResolvedValue({
      id: 'rt-1',
      userId: 'user-1',
      revokedAt: null,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    });
    (mockPrisma.refreshToken.update as jest.Mock).mockResolvedValue({});
    (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue(mockUser);

    const result = await rotateRefreshToken('valid-raw-token');

    expect(result).not.toBeNull();
    expect(result!.accessToken).toBeDefined();
    expect(result!.refreshToken).toBeDefined();
    expect(result!.expiresIn).toBeDefined();

    // El token viejo debe haberse revocado
    expect(mockPrisma.refreshToken.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'rt-1' },
        data: expect.objectContaining({ revokedAt: expect.any(Date) }),
      })
    );
    // Debe haberse creado uno nuevo
    expect(mockPrisma.refreshToken.create).toHaveBeenCalled();
  });
});

// ── revokeAllRefreshTokens ────────────────────────────────────────────────────

describe('revokeAllRefreshTokens', () => {
  beforeEach(() => jest.clearAllMocks());

  it('llama a updateMany revocando todos los tokens activos del usuario', async () => {
    (mockPrisma.refreshToken.updateMany as jest.Mock).mockResolvedValue({ count: 3 });

    await revokeAllRefreshTokens('user-1');

    expect(mockPrisma.refreshToken.updateMany).toHaveBeenCalledWith({
      where: { userId: 'user-1', revokedAt: null },
      data: { revokedAt: expect.any(Date) },
    });
  });

  it('no lanza si no hay tokens activos (count 0)', async () => {
    (mockPrisma.refreshToken.updateMany as jest.Mock).mockResolvedValue({ count: 0 });

    await expect(revokeAllRefreshTokens('user-with-no-tokens')).resolves.not.toThrow();
  });
});

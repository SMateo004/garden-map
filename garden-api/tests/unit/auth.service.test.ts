import {
  registerCaregiver,
  login,
  hashPassword,
  comparePassword,
} from '../../src/modules/auth/auth.service';
import { ConflictError, UnauthorizedError, BadRequestError } from '../../src/shared/errors';
import prisma from '../../src/config/database';
import { UserRole, VerificationStatus } from '@prisma/client';
import type { RegisterCaregiverBody } from '../../src/modules/auth/auth.validation';

jest.mock('../../src/config/database', () => {
  const user = {
    findUnique: jest.fn(),
    create: jest.fn(),
  };
  const caregiverProfile = { create: jest.fn() };
  const refreshToken = {
    create: jest.fn().mockResolvedValue({ id: 'rt-1', tokenHash: 'hash', expiresAt: new Date() }),
    findFirst: jest.fn(),
    updateMany: jest.fn(),
  };
  const transactionTx = {
    user: { findUnique: jest.fn(), create: jest.fn() },
    caregiverProfile: { create: jest.fn() },
  };
  return {
    __esModule: true,
    default: {
      user,
      caregiverProfile,
      refreshToken,
      $transaction: jest.fn((fn: (tx: typeof transactionTx) => Promise<unknown>) => fn(transactionTx)),
    },
  };
});

jest.mock('../../src/shared/analytics', () => ({
  track: jest.fn(),
  identify: jest.fn(),
}));

jest.mock('../../src/services/blockchain.service', () => ({
  blockchainService: {
    registerUser: jest.fn(),
    syncProfileOnChain: jest.fn().mockResolvedValue(null),
  },
}));

jest.mock('bcrypt', () => ({
  hash: jest.fn((pw: string) => Promise.resolve(`hashed_${pw}`)),
  compare: jest.fn((pw: string, hash: string) =>
    Promise.resolve(Boolean(hash && hash === `hashed_${pw}`))
  ),
}));

const mockPrisma = prisma as jest.Mocked<typeof prisma>;

const validRegisterBody: RegisterCaregiverBody = {
  user: {
    email: 'cuidador@test.com',
    password: 'password123',
    firstName: 'Juan',
    lastName: 'Pérez',
    phone: '+59171234567',
    dateOfBirth: new Date('1990-01-01'),
    country: 'Bolivia',
    city: 'Santa Cruz',
    isOver18: true,
  },
  profile: {
    servicesOffered: ['HOSPEDAJE'],
    photos: [
      'https://res.cloudinary.com/x/1.jpg',
      'https://res.cloudinary.com/x/2.jpg',
      'https://res.cloudinary.com/x/3.jpg',
      'https://res.cloudinary.com/x/4.jpg',
    ],
    zone: 'EQUIPETROL',
    bio: 'Descripción de al menos cincuenta caracteres para cumplir validación del perfil.',
    ciAnversoUrl: 'https://res.cloudinary.com/x/ci-anverso.jpg',
    ciReversoUrl: 'https://res.cloudinary.com/x/ci-reverso.jpg',
  },
};

describe('AuthService', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (mockPrisma.$transaction as jest.Mock).mockImplementation(
      (fn: (tx: unknown) => Promise<unknown>) => {
        const tx = {
          user: {
            findUnique: mockPrisma.user.findUnique,
            create: jest.fn().mockResolvedValue({
              id: 'user-1',
              email: 'cuidador@test.com',
              role: UserRole.CAREGIVER,
              firstName: 'Juan',
              lastName: 'Pérez',
              phone: '+59171234567',
              country: 'Bolivia',
              city: 'Santa Cruz',
              isOver18: true,
            }),
          },
          caregiverProfile: {
            create: jest.fn().mockResolvedValue({
              id: 'profile-1',
              userId: 'user-1',
              verificationStatus: VerificationStatus.PENDING_REVIEW,
            }),
          },
        };
        return fn(tx);
      }
    );
  });

  describe('hashPassword / comparePassword', () => {
    it('hashes password and compares correctly', async () => {
      const hashed = await hashPassword('mypass');
      expect(hashed).toContain('hashed_');
      const ok = await comparePassword('mypass', hashed);
      expect(ok).toBe(true);
      const bad = await comparePassword('other', hashed);
      expect(bad).toBe(false);
    });
  });

  describe('registerCaregiver', () => {
    it('returns user, profileId, verificationStatus and tokens on success', async () => {
      (mockPrisma.user.findUnique as jest.Mock)
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(null);

      const result = await registerCaregiver(validRegisterBody);

      expect(result.user.email).toBe('cuidador@test.com');
      expect(result.user.role).toBe(UserRole.CAREGIVER);
      expect(result.profileId).toBe('profile-1');
      expect(result.verificationStatus).toBe(VerificationStatus.PENDING_REVIEW);
      expect(result.accessToken).toBeDefined();
      expect(result.expiresIn).toBeDefined();
    });

    it('throws ConflictError with code EMAIL_EXISTS when email already exists', async () => {
      (mockPrisma.user.findUnique as jest.Mock).mockImplementation((args: { where: { email?: string } }) => {
        if (args.where.email) return Promise.resolve({ id: 'existing' });
        return Promise.resolve(null);
      });

      await expect(registerCaregiver(validRegisterBody)).rejects.toThrow(ConflictError);
      await expect(registerCaregiver(validRegisterBody)).rejects.toMatchObject({
        code: 'EMAIL_EXISTS',
        statusCode: 409,
      });
    });

    it('throws ConflictError with code PHONE_EXISTS when phone already exists', async () => {
      (mockPrisma.user.findUnique as jest.Mock).mockImplementation((args: { where: { phone?: string } }) => {
        if (args.where.phone) return Promise.resolve({ id: 'existing' });
        return Promise.resolve(null);
      });

      await expect(registerCaregiver(validRegisterBody)).rejects.toThrow(ConflictError);
      await expect(registerCaregiver(validRegisterBody)).rejects.toMatchObject({
        code: 'PHONE_EXISTS',
        statusCode: 409,
      });
    });
  });

  describe('login', () => {
    it('returns tokens and user on valid credentials', async () => {
      const bcrypt = require('bcrypt');
      (bcrypt.compare as jest.Mock).mockResolvedValue(true);
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue({
        id: 'user-1',
        email: 'cuidador@test.com',
        role: UserRole.CAREGIVER,
        firstName: 'Juan',
        lastName: 'Pérez',
        passwordHash: 'hashed_password123',
      });

      const result = await login({ email: 'cuidador@test.com', password: 'password123' });

      expect(result.user.email).toBe('cuidador@test.com');
      expect(result.accessToken).toBeDefined();
      expect(result.expiresIn).toBeDefined();
    });

    it('throws UnauthorizedError when user not found', async () => {
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue(null);

      await expect(login({ email: 'nobody@test.com', password: 'any' })).rejects.toThrow(
        UnauthorizedError
      );
    });

    it('throws UnauthorizedError when password is wrong', async () => {
      const bcrypt = require('bcrypt');
      (bcrypt.compare as jest.Mock).mockResolvedValue(false);
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue({
        id: 'user-1',
        email: 'cuidador@test.com',
        passwordHash: 'hashed_password123',
      });

      await expect(
        login({ email: 'cuidador@test.com', password: 'wrongpassword' })
      ).rejects.toThrow(UnauthorizedError);
    });

    it('throws BadRequestError with INVALID_ROLE when roleFilter is CAREGIVER and user is not', async () => {
      const bcrypt = require('bcrypt');
      (bcrypt.compare as jest.Mock).mockResolvedValue(true);
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue({
        id: 'user-1',
        email: 'client@test.com',
        role: UserRole.CLIENT,
        firstName: 'Maria',
        lastName: 'Lopez',
        passwordHash: 'hashed_password123',
      });

      await expect(
        login({ email: 'client@test.com', password: 'password123' }, 'CAREGIVER')
      ).rejects.toThrow(BadRequestError);
      await expect(
        login({ email: 'client@test.com', password: 'password123' }, 'CAREGIVER')
      ).rejects.toMatchObject({ code: 'INVALID_ROLE', statusCode: 400 });
    });
  });
});

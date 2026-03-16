/**
 * Integration tests: auth caregiver flow (register, login).
 * Prisma and uploads mocked; Supertest against app.
 */

import request from 'supertest';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => {
  const user = { findUnique: jest.fn(), create: jest.fn() };
  const caregiverProfile = { create: jest.fn() };
  const tx = { user: { findUnique: jest.fn(), create: jest.fn() }, caregiverProfile: { create: jest.fn() } };
  return {
    __esModule: true,
    default: {
      user,
      caregiverProfile,
      $transaction: jest.fn((fn: (t: typeof tx) => Promise<unknown>) => fn(tx)),
    },
  };
});

jest.mock('bcrypt', () => ({
  hash: jest.fn((pw: string) => Promise.resolve(`hashed_${pw}`)),
  compare: jest.fn((pw: string, hash: string) => Promise.resolve(hash === `hashed_${pw}`)),
}));

import app from '../../src/app';

const mockPrisma = prisma as jest.Mocked<typeof prisma>;

const validRegisterBody = {
  user: {
    email: 'cuidador@test.com',
    password: 'password123',
    firstName: 'Juan',
    lastName: 'Pérez',
    phone: '+59171234567',
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

describe('Auth caregiver API (integration)', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    const tx = {
      user: {
        findUnique: mockPrisma.user.findUnique,
        create: jest.fn().mockResolvedValue({
          id: 'user-1',
          email: 'cuidador@test.com',
          role: 'CAREGIVER',
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
          verificationStatus: 'PENDING_REVIEW',
        }),
      },
    };
    (mockPrisma.$transaction as jest.Mock).mockImplementation((fn: (t: typeof tx) => Promise<unknown>) => fn(tx));
  });

  describe('POST /api/auth/caregiver/register', () => {
    it('returns 201 and tokens when valid body', async () => {
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue(null).mockResolvedValueOnce(null).mockResolvedValueOnce(null);

      const res = await request(app)
        .post('/api/auth/caregiver/register')
        .set('Content-Type', 'application/json')
        .send(validRegisterBody);

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toMatchObject({
        user: expect.objectContaining({ email: 'cuidador@test.com', role: 'CAREGIVER' }),
        profileId: 'profile-1',
        verificationStatus: 'PENDING_REVIEW',
      });
      expect(res.body.data.accessToken).toBeDefined();
      expect(res.body.data.expiresIn).toBeDefined();
    });

    it('returns 400 when isOver18 is false', async () => {
      const body = {
        ...validRegisterBody,
        user: { ...validRegisterBody.user, isOver18: false },
      };

      const res = await request(app)
        .post('/api/auth/caregiver/register')
        .set('Content-Type', 'application/json')
        .send(body);

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
      expect(res.body.error?.code).toBe('VALIDATION_ERROR');
    });

    it('returns 409 and EMAIL_EXISTS when email already exists', async () => {
      (mockPrisma.user.findUnique as jest.Mock).mockImplementation((args: { where: { email?: string } }) =>
        Promise.resolve(args.where.email ? { id: 'existing' } : null)
      );

      const res = await request(app)
        .post('/api/auth/caregiver/register')
        .set('Content-Type', 'application/json')
        .send(validRegisterBody);

      expect(res.status).toBe(409);
      expect(res.body.success).toBe(false);
      expect(res.body.error?.code).toBe('EMAIL_EXISTS');
    });

    it('returns 409 and PHONE_EXISTS when phone already exists', async () => {
      (mockPrisma.user.findUnique as jest.Mock).mockImplementation((args: { where: { phone?: string } }) =>
        Promise.resolve(args.where.phone ? { id: 'existing' } : null)
      );

      const res = await request(app)
        .post('/api/auth/caregiver/register')
        .set('Content-Type', 'application/json')
        .send(validRegisterBody);

      expect(res.status).toBe(409);
      expect(res.body.success).toBe(false);
      expect(res.body.error?.code).toBe('PHONE_EXISTS');
    });

    it('returns 400 when phone format invalid', async () => {
      const body = {
        ...validRegisterBody,
        user: { ...validRegisterBody.user, phone: '+5491112345678' },
      };

      const res = await request(app)
        .post('/api/auth/caregiver/register')
        .set('Content-Type', 'application/json')
        .send(body);

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });

    it('returns 400 when photos fewer than 4', async () => {
      const body = {
        ...validRegisterBody,
        profile: { ...validRegisterBody.profile, photos: ['https://x.co/1.jpg', 'https://x.co/2.jpg'] },
      };

      const res = await request(app)
        .post('/api/auth/caregiver/register')
        .set('Content-Type', 'application/json')
        .send(body);

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });
  });

  describe('POST /api/auth/login', () => {
    it('returns 200 and tokens when valid credentials', async () => {
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue({
        id: 'user-1',
        email: 'cuidador@test.com',
        role: 'CAREGIVER',
        firstName: 'Juan',
        lastName: 'Pérez',
        passwordHash: 'hashed_password123',
      });

      const res = await request(app)
        .post('/api/auth/login')
        .set('Content-Type', 'application/json')
        .send({ email: 'cuidador@test.com', password: 'password123' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.accessToken).toBeDefined();
      expect(res.body.data.user).toMatchObject({ email: 'cuidador@test.com', role: 'CAREGIVER' });
    });

    it('returns 401 when user not found', async () => {
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue(null);

      const res = await request(app)
        .post('/api/auth/login')
        .set('Content-Type', 'application/json')
        .send({ email: 'nobody@test.com', password: 'any' });

      expect(res.status).toBe(401);
      expect(res.body.success).toBe(false);
    });

    it('returns 401 when password wrong', async () => {
      const bcrypt = require('bcrypt');
      (bcrypt.compare as jest.Mock).mockResolvedValue(false);
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue({
        id: 'user-1',
        email: 'cuidador@test.com',
        passwordHash: 'hashed_password123',
      });

      const res = await request(app)
        .post('/api/auth/login')
        .set('Content-Type', 'application/json')
        .send({ email: 'cuidador@test.com', password: 'wrong' });

      expect(res.status).toBe(401);
      expect(res.body.success).toBe(false);
    });

    it('returns 400 when role=caregiver and user is not CAREGIVER', async () => {
      const bcrypt = require('bcrypt');
      (bcrypt.compare as jest.Mock).mockResolvedValue(true);
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue({
        id: 'user-1',
        email: 'client@test.com',
        role: 'CLIENT',
        firstName: 'Maria',
        lastName: 'Lopez',
        passwordHash: 'hashed_password123',
      });

      const res = await request(app)
        .post('/api/auth/login')
        .query({ role: 'caregiver' })
        .set('Content-Type', 'application/json')
        .send({ email: 'client@test.com', password: 'password123' });

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
      expect(res.body.error?.code).toBe('INVALID_ROLE');
    });
  });
});

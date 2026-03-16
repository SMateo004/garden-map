/**
 * Integration tests: caregivers API (GET list, GET by id).
 * Prisma is mocked below; no real DB required. Flexible for evolution (e.g. test DB).
 */

import request from 'supertest';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => {
  const caregiverProfile = {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    count: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
  };
  const user = { findUnique: jest.fn() };
  const db = {
    caregiverProfile,
    user,
    booking: { findFirst: jest.fn(), findUnique: jest.fn(), update: jest.fn() },
    adminAction: { create: jest.fn() },
    $transaction: jest.fn((fn: (tx: unknown) => Promise<unknown>) => {
      return fn({ caregiverProfile, user });
    }),
  };
  return { __esModule: true, default: db };
});

jest.mock('../../src/shared/cache', () => ({
  getCache: () => ({
    get: jest.fn().mockResolvedValue(null),
    set: jest.fn().mockResolvedValue(undefined),
    del: jest.fn().mockResolvedValue(undefined),
  }),
  caregiverListCacheKey: (filters: Record<string, string | number>) =>
    `caregivers:list:${JSON.stringify(filters)}`,
  caregiverDetailCacheKey: (id: string) => `caregivers:detail:${id}`,
}));

jest.mock('../../src/config/stripe', () => ({
  stripe: null,
  STRIPE_WEBHOOK_SECRET: '',
}));

jest.mock('../../src/middleware/auth.middleware', () => ({
  authMiddleware: (req: { user?: { id: string; role: string } }, _res: unknown, next: () => void) => {
    req.user = { id: 'user-caregiver-1', role: 'CAREGIVER' } as { id: string; email: string; role: string };
    next();
  },
  requireRole: () => (_req: unknown, _res: unknown, next: () => void) => next(),
}));

const mockProcessAndUpload = jest.fn().mockResolvedValue([
  'https://cloudinary.com/1.jpg',
  'https://cloudinary.com/2.jpg',
  'https://cloudinary.com/3.jpg',
  'https://cloudinary.com/4.jpg',
]);
jest.mock('../../src/modules/caregiver-service/upload.middleware', () => ({
  uploadCaregiverPhotos: (req: { files?: unknown[]; body?: Record<string, unknown> }, _res: unknown, next: () => void) => {
    req.files = Array(5).fill(null).map((_, i) => ({
      buffer: Buffer.alloc(100),
      fieldname: 'photos',
      originalname: `photo${i}.jpg`,
      mimetype: 'image/jpeg',
      size: 100,
    }));
    next();
  },
  processAndUploadToCloudinary: mockProcessAndUpload,
}));

import app from '../../src/app';

const mockPrisma = prisma as jest.Mocked<typeof prisma>;

const mockCaregiverList = [
  {
    id: 'cp-1',
    zone: 'EQUIPETROL',
    verified: true,
    suspended: false,
    rating: 4.5,
    reviewCount: 10,
    pricePerDay: 120,
    pricePerWalk30: 30,
    pricePerWalk60: 50,
    spaceType: 'casa_patio',
    servicesOffered: ['HOSPEDAJE', 'PASEO'],
    user: { firstName: 'María', lastName: 'López', profilePicture: null },
  },
];

const mockCaregiverDetail = {
  id: 'cp-1',
  zone: 'EQUIPETROL',
  verified: true,
  suspended: false,
  rating: 4.5,
  reviewCount: 10,
  pricePerDay: 120,
  pricePerWalk30: 30,
  pricePerWalk60: 50,
  spaceType: 'casa_patio',
  servicesOffered: ['HOSPEDAJE', 'PASEO'],
  bio: 'Bio test',
  photos: ['https://example.com/1.jpg'],
  user: { firstName: 'María', lastName: 'López', profilePicture: null },
  reviews: [] as { id: string; client: { firstName: string; lastName: string; profilePicture: string | null }; rating: number; comment: string | null; serviceType: string; createdAt: Date }[],
  availability: [] as { date: Date; serviceType: string; isAvailable: boolean; timeSlots: string[] }[],
};

describe('Caregivers API (integration)', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('GET /api/caregivers', () => {
    it('returns 200 and paginated list when DB returns data', async () => {
      (mockPrisma.caregiverProfile.findMany as jest.Mock).mockResolvedValue(mockCaregiverList);
      (mockPrisma.caregiverProfile.count as jest.Mock).mockResolvedValue(1);

      const res = await request(app)
        .get('/api/caregivers')
        .query({ page: 1, limit: 10 });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.caregivers).toHaveLength(1);
      expect(res.body.data.caregivers[0].firstName).toBe('María');
      expect(res.body.data.caregivers[0].verified).toBe(true);
      expect(res.body.data.pagination).toMatchObject({
        total: 1,
        page: 1,
        currentPage: 1,
        pages: 1,
        limit: 10,
      });
    });

    it('applies service filter when query param present', async () => {
      (mockPrisma.caregiverProfile.findMany as jest.Mock).mockResolvedValue([]);
      (mockPrisma.caregiverProfile.count as jest.Mock).mockResolvedValue(0);

      await request(app).get('/api/caregivers').query({ service: 'hospedaje' });

      expect(mockPrisma.caregiverProfile.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ verified: true, suspended: false }),
        })
      );
    });

    it('applies zone filter when query param present', async () => {
      (mockPrisma.caregiverProfile.findMany as jest.Mock).mockResolvedValue([]);
      (mockPrisma.caregiverProfile.count as jest.Mock).mockResolvedValue(0);

      await request(app).get('/api/caregivers').query({ zone: 'equipetrol' });

      expect(mockPrisma.caregiverProfile.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            verified: true,
            zone: { in: ['EQUIPETROL'] },
          }),
        })
      );
    });

    it('applies priceRange filter when query param present', async () => {
      (mockPrisma.caregiverProfile.findMany as jest.Mock).mockResolvedValue([]);
      (mockPrisma.caregiverProfile.count as jest.Mock).mockResolvedValue(0);

      await request(app).get('/api/caregivers').query({ priceRange: 'economico' });

      expect(mockPrisma.caregiverProfile.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            verified: true,
            pricePerDay: { gte: 60, lte: 100 },
          }),
        })
      );
    });
  });

  describe('POST /api/caregivers', () => {
    it('returns 201 and profile when valid body and mock files', async () => {
      const created = {
        id: 'cp-new',
        zone: 'EQUIPETROL',
        servicesOffered: ['HOSPEDAJE'],
        rating: 0,
        reviewCount: 0,
        pricePerDay: null,
        pricePerWalk30: null,
        pricePerWalk60: null,
        verified: false,
        spaceType: null,
        user: { firstName: 'Ana', lastName: 'G', profilePicture: null },
      };
      (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue(null);
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue({ id: 'u1', role: 'CAREGIVER' });
      (mockPrisma.caregiverProfile.create as jest.Mock).mockResolvedValue(created);

      const body = {
        bio: 'Casa con patio.',
        zone: 'EQUIPETROL',
        servicesOffered: ['HOSPEDAJE'],
      };

      const res = await request(app)
        .post('/api/caregivers')
        .set('Content-Type', 'application/json')
        .send({ data: JSON.stringify(body) });

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toBeDefined();
      expect(mockProcessAndUpload).toHaveBeenCalled();
    });
  });

  describe('GET /api/caregivers/:id', () => {
    it('returns 200 and detail when profile exists', async () => {
      (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue(mockCaregiverDetail);

      const res = await request(app).get('/api/caregivers/cp-1');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.firstName).toBe('María');
      expect(res.body.data.bio).toBe('Bio test');
      expect(res.body.data.photos).toHaveLength(1);
    });

    it('returns 404 when profile not found', async () => {
      (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue(null);

      const res = await request(app).get('/api/caregivers/non-existent');

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
      expect(res.body.error?.code).toBe('CAREGIVER_NOT_FOUND');
    });
  });

  describe('GET /health', () => {
    it('returns 200 and status ok', async () => {
      const res = await request(app).get('/health');
      expect(res.status).toBe(200);
      expect(res.body.data.status).toBe('ok');
    });
  });
});

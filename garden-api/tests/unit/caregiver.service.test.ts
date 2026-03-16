import {
  validatePhotoCount,
  validateBio,
  listCaregivers,
  getCaregiverById,
  createCaregiverProfile,
  upsertCaregiverProfile,
} from '../../src/modules/caregiver-service/caregiver.service';
import { CaregiverProfileValidationError, ConflictError } from '../../src/shared/errors';
import { MAX_BIO_CHARS } from '../../src/modules/caregiver-service/caregiver.validation';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => {
  const caregiverProfile = {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    findFirst: jest.fn(),
    count: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
  };
  const user = { findUnique: jest.fn() };
  interface MockTx {
    caregiverProfile: typeof caregiverProfile;
    user: typeof user;
  }
  const db: MockTx & {
    $transaction: (fn: (tx: MockTx) => Promise<unknown>) => Promise<unknown>;
  } = {
    caregiverProfile,
    user,
    $transaction: jest.fn((fn: (tx: MockTx) => Promise<unknown>) => fn(db)),
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

const mockPrisma = prisma as jest.Mocked<typeof prisma>;

describe('CaregiverService', () => {
  beforeEach(() => jest.clearAllMocks());

  describe('validatePhotoCount', () => {
    it('throws when fewer than 4 photos', () => {
      expect(() => validatePhotoCount(['a', 'b', 'c'])).toThrow(CaregiverProfileValidationError);
      expect(() => validatePhotoCount([])).toThrow(CaregiverProfileValidationError);
    });

    it('throws when more than 6 photos', () => {
      expect(() =>
        validatePhotoCount(['a', 'b', 'c', 'd', 'e', 'f', 'g'])
      ).toThrow(CaregiverProfileValidationError);
    });

    it('accepts 4 to 6 photos', () => {
      expect(() => validatePhotoCount(['a', 'b', 'c', 'd'])).not.toThrow();
      expect(() => validatePhotoCount(['a', 'b', 'c', 'd', 'e', 'f'])).not.toThrow();
    });
  });

  describe('validateBio', () => {
    it('throws when bio exceeds max length', () => {
      const long = 'a'.repeat(MAX_BIO_CHARS + 1);
      expect(() => validateBio(long)).toThrow(CaregiverProfileValidationError);
    });

    it('accepts bio within limit', () => {
      expect(() => validateBio('Hola, tengo patio.')).not.toThrow();
      expect(() => validateBio('a'.repeat(MAX_BIO_CHARS))).not.toThrow();
    });
  });

  describe('listCaregivers', () => {
    it('returns paginated list with only verified, non-suspended', async () => {
      const mockList = [
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
      (mockPrisma.caregiverProfile.findMany as jest.Mock).mockResolvedValue(mockList as never);
      (mockPrisma.caregiverProfile.count as jest.Mock).mockResolvedValue(1);

      const result = await listCaregivers({ page: 1, limit: 12 });

      expect(result.caregivers).toHaveLength(1);
      const c = result.caregivers[0]!;
      expect(c.firstName).toBe('María');
      expect(c.verified).toBe(true);
      expect(result.pagination.total).toBe(1);
      expect(result.pagination.pages).toBe(1);
      expect(mockPrisma.caregiverProfile.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ verified: true, suspended: false }),
          skip: 0,
          take: 12,
        })
      );
    });

    it('applies zone filter when provided', async () => {
      (mockPrisma.caregiverProfile.findMany as jest.Mock).mockResolvedValue([]);
      (mockPrisma.caregiverProfile.count as jest.Mock).mockResolvedValue(0);

      await listCaregivers({ zone: ['EQUIPETROL', 'URBARI'], page: 1, limit: 12 });

      expect(mockPrisma.caregiverProfile.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ zone: { in: ['EQUIPETROL', 'URBARI'] } }),
        })
      );
    });
  });

  describe('getCaregiverById', () => {
    it('returns null when profile not found', async () => {
      (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue(null);

      const result = await getCaregiverById('non-existent');

      expect(result).toBeNull();
    });
  });

  describe('createCaregiverProfile', () => {
    it('throws ConflictError when profile already exists for user', async () => {
      (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue({ id: 'existing' } as never);
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue({
        id: 'u1',
        role: 'CAREGIVER',
      } as never);

      await expect(
        createCaregiverProfile(
          'u1',
          {
            bio: 'Bio ok',
            zone: 'EQUIPETROL',
            servicesOffered: ['HOSPEDAJE'],
          },
          ['url1', 'url2', 'url3', 'url4']
        )
      ).rejects.toThrow(ConflictError);

      expect(mockPrisma.caregiverProfile.create).not.toHaveBeenCalled();
    });

    it('throws when user is not CAREGIVER', async () => {
      (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue(null);
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue({ id: 'u1', role: 'CLIENT' } as never);

      await expect(
        createCaregiverProfile(
          'u1',
          { bio: 'Bio', zone: 'EQUIPETROL', servicesOffered: ['HOSPEDAJE'] },
          ['u1', 'u2', 'u3', 'u4']
        )
      ).rejects.toThrow(CaregiverProfileValidationError);
    });
  });

  describe('upsertCaregiverProfile', () => {
    it('creates profile when none exists (created: true)', async () => {
      (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue(null);
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue({ id: 'u1', role: 'CAREGIVER' } as never);
      const createdProfile = {
        id: 'cp-1',
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
      (mockPrisma.caregiverProfile.create as jest.Mock).mockResolvedValue(createdProfile as never);

      const result = await upsertCaregiverProfile(
        'u1',
        { bio: 'Bio', zone: 'EQUIPETROL', servicesOffered: ['HOSPEDAJE'] },
        ['u1', 'u2', 'u3', 'u4']
      );

      expect(result.created).toBe(true);
      expect(result.profile.id).toBe('cp-1');
      expect(result.profile.verified).toBe(false);
      expect(mockPrisma.caregiverProfile.create).toHaveBeenCalled();
      expect(mockPrisma.caregiverProfile.update).not.toHaveBeenCalled();
    });

    it('updates profile when one exists (created: false)', async () => {
      const existing = {
        id: 'cp-1',
        userId: 'u1',
        zone: 'EQUIPETROL',
        servicesOffered: ['HOSPEDAJE'],
        rating: 0,
        reviewCount: 0,
        verified: false,
        user: { firstName: 'Ana', lastName: 'G', profilePicture: null },
      };
      (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue(existing as never);
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue({ id: 'u1', role: 'CAREGIVER' } as never);
      const updatedProfile = {
        ...existing,
        bio: 'Nueva bio',
        zone: 'URBARI',
        spaceType: 'Casa con patio',
        servicesOffered: ['HOSPEDAJE', 'PASEO'],
        pricePerDay: 100,
        pricePerWalk30: 30,
        pricePerWalk60: 50,
      };
      (mockPrisma.caregiverProfile.update as jest.Mock).mockResolvedValue(updatedProfile as never);

      const result = await upsertCaregiverProfile(
        'u1',
        {
          bio: 'Nueva bio',
          zone: 'URBARI',
          spaceType: 'Casa con patio',
          servicesOffered: ['HOSPEDAJE', 'PASEO'],
          pricePerDay: 100,
          pricePerWalk30: 30,
          pricePerWalk60: 50,
        },
        ['url1', 'url2', 'url3', 'url4']
      );

      expect(result.created).toBe(false);
      expect(result.profile.zone).toBe('URBARI');
      expect(mockPrisma.caregiverProfile.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'cp-1' },
          data: expect.objectContaining({
            bio: 'Nueva bio',
            zone: 'URBARI',
            spaceType: 'Casa con patio',
            servicesOffered: ['HOSPEDAJE', 'PASEO'],
          }),
        })
      );
      expect(mockPrisma.caregiverProfile.create).not.toHaveBeenCalled();
    });

    it('throws when user is not CAREGIVER', async () => {
      (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue(null);
      (mockPrisma.user.findUnique as jest.Mock).mockResolvedValue({ id: 'u1', role: 'CLIENT' } as never);

      await expect(
        upsertCaregiverProfile(
          'u1',
          { bio: 'Bio', zone: 'EQUIPETROL', servicesOffered: ['HOSPEDAJE'] },
          ['u1', 'u2', 'u3', 'u4']
        )
      ).rejects.toThrow(CaregiverProfileValidationError);
    });
  });
});

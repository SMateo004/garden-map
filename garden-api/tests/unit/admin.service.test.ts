import { toggleVerify, listPendingCaregivers } from '../../src/modules/admin/admin.service';
import { CaregiverNotFoundError } from '../../src/shared/errors';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    caregiverProfile: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      update: jest.fn(),
      count: jest.fn(),
    },
    adminAction: { create: jest.fn() },
  },
}));

jest.mock('../../src/shared/cache', () => ({
  getCache: () => ({
    del: jest.fn().mockResolvedValue(undefined),
  }),
  caregiverDetailCacheKey: (id: string) => `caregivers:detail:${id}`,
}));

const mockPrisma = prisma as jest.Mocked<typeof prisma>;

describe('AdminService', () => {
  beforeEach(() => jest.clearAllMocks());

  describe('toggleVerify', () => {
    it('throws CaregiverNotFoundError when profile does not exist', async () => {
      (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue(null);

      await expect(toggleVerify('non-existent', 'admin-1')).rejects.toThrow(CaregiverNotFoundError);
      expect(mockPrisma.caregiverProfile.update).not.toHaveBeenCalled();
    });

    it('sets verified to true and verifiedAt when currently false', async () => {
      const profile = {
        id: 'cp-1',
        verified: false,
        suspended: false,
        userId: 'u1',
        zone: 'EQUIPETROL',
        photos: [],
        servicesOffered: [],
        bio: null,
        spaceType: null,
        pricePerDay: null,
        pricePerWalk30: null,
        pricePerWalk60: null,
        rating: 0,
        reviewCount: 0,
        createdAt: new Date(),
        updatedAt: new Date(),
        verifiedAt: null,
        verifiedBy: null,
        verificationNotes: null,
        suspendedAt: null,
        suspensionReason: null,
      };
      (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue(profile as never);
      (mockPrisma.caregiverProfile.update as jest.Mock).mockResolvedValue({
        ...profile,
        verified: true,
        verifiedAt: new Date(),
        verifiedBy: 'admin-1',
      } as never);

      const result = await toggleVerify('cp-1', 'admin-1');

      expect(result.verified).toBe(true);
      expect(result.verifiedAt).toBeTruthy();
      expect(mockPrisma.caregiverProfile.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'cp-1' },
          data: expect.objectContaining({ verified: true, verifiedAt: expect.any(Date), verifiedBy: 'admin-1' }),
        })
      );
      expect(mockPrisma.adminAction.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ actionType: 'VERIFY_TOGGLE', targetId: 'cp-1' }),
        })
      );
    });

    it('sets verified to false and verifiedAt to null when currently true', async () => {
      const profile = {
        id: 'cp-1',
        verified: true,
        suspended: false,
        verifiedAt: new Date(),
        verifiedBy: 'admin-1',
        verificationNotes: null,
        userId: 'u1',
        zone: 'EQUIPETROL',
        photos: [],
        servicesOffered: [],
        bio: null,
        spaceType: null,
        pricePerDay: null,
        pricePerWalk30: null,
        pricePerWalk60: null,
        rating: 0,
        reviewCount: 0,
        createdAt: new Date(),
        updatedAt: new Date(),
        suspendedAt: null,
        suspensionReason: null,
      };
      (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue(profile as never);
      (mockPrisma.caregiverProfile.update as jest.Mock).mockResolvedValue({
        ...profile,
        verified: false,
        verifiedAt: null,
        verifiedBy: null,
      } as never);

      const result = await toggleVerify('cp-1', 'admin-1');

      expect(result.verified).toBe(false);
      expect(result.verifiedAt).toBeNull();
      expect(mockPrisma.caregiverProfile.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ verified: false, verifiedAt: null, verifiedBy: null }),
        })
      );
    });
  });

  describe('listPendingCaregivers', () => {
    it('returns profiles with status PENDING_REVIEW or NEEDS_REVISION, paginated', async () => {
      const list = [
        {
          id: 'cp-1',
          status: 'PENDING_REVIEW',
          createdAt: new Date(),
          updatedAt: new Date(),
          rejectionReason: null,
          user: { firstName: 'Ana', lastName: 'G', email: 'a@b.com', phone: '+591' },
        },
      ];
      (mockPrisma.caregiverProfile.findMany as jest.Mock).mockResolvedValue(list as never);
      (mockPrisma.caregiverProfile.count as jest.Mock).mockResolvedValue(1);

      const result = await listPendingCaregivers(1, 20);

      expect(result.caregivers).toHaveLength(1);
      expect(result.total).toBe(1);
      expect(result.page).toBe(1);
      expect(result.limit).toBe(20);
      expect(result.caregivers[0]).toMatchObject({ id: 'cp-1', email: 'a@b.com', fullName: 'Ana G', status: 'PENDING_REVIEW' });
      expect(mockPrisma.caregiverProfile.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { status: { in: ['PENDING_REVIEW', 'NEEDS_REVISION'] } },
          skip: 0,
          take: 20,
        })
      );
    });
  });
});

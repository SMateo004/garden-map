import { toggleVerify, listPendingCaregivers, reviewCaregiver } from '../../src/modules/admin/admin.service';
import { CaregiverNotFoundError, BadRequestError } from '../../src/shared/errors';
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
    availability: {
      count: jest.fn().mockResolvedValue(1),
    },
    adminAction: { create: jest.fn().mockResolvedValue({}) },
    notification: { create: jest.fn().mockResolvedValue({}) },
    verificationAudit: { create: jest.fn().mockResolvedValue({}) },
  },
}));

jest.mock('../../src/shared/cache', () => ({
  getCache: () => ({
    del: jest.fn().mockResolvedValue(undefined),
  }),
  delByPrefix: jest.fn().mockResolvedValue(undefined),
  caregiverDetailCacheKey: (id: string) => `caregivers:detail:${id}`,
}));

jest.mock('../../src/shared/analytics', () => ({
  track: jest.fn(),
  identify: jest.fn(),
}));

jest.mock('../../src/services/notification.service', () => ({
  onCaregiverApproved: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('../../src/services/firebase.service', () => ({
  sendPushToUser: jest.fn().mockResolvedValue(undefined),
  sendPushToAdmins: jest.fn().mockResolvedValue(undefined),
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
        photos: ['https://x.co/1.jpg'],
        servicesOffered: ['HOSPEDAJE'],
        bio: 'Bio de más de cincuenta caracteres para pasar la validación del servicio',
        profilePhoto: 'https://x.co/photo.jpg',
        emailVerified: true,
        identityVerificationStatus: 'VERIFIED',
        defaultAvailabilitySchedule: { lunes: true },
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
        user: { id: 'u1' },
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

  describe('reviewCaregiver — approve gate', () => {
    const baseOuterProfile = {
      id: 'cp-1',
      status: 'PENDING_REVIEW',
      userId: 'user-1',
      defaultAvailabilitySchedule: { lunes: true },
      user: { email: 'a@b.com', firstName: 'Ana', lastName: 'G' },
    };

    const baseFullProfile = {
      bio: 'Bio de más de cincuenta caracteres para pasar la validación del servicio',
      zone: 'EQUIPETROL',
      servicesOffered: ['HOSPEDAJE'],
      profilePhoto: 'https://x.co/photo.jpg',
      identityVerificationStatus: 'VERIFIED',
      emailVerified: true,
      phoneVerified: true,
      isAmateur: false,
      trainingComplete: false, // irrelevant salvo isAmateur=true
    };

    function mockProfiles(fullProfileOverrides: Partial<typeof baseFullProfile>) {
      // mockReset (no clearAllMocks) porque queremos vaciar también la cola
      // de mockResolvedValueOnce de tests anteriores — sin esto, valores no
      // consumidos de un test se filtran al siguiente.
      (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockReset();
      (mockPrisma.caregiverProfile.findUnique as jest.Mock)
        .mockResolvedValueOnce(baseOuterProfile as never) // lookup inicial (include: user)
        .mockResolvedValueOnce({ ...baseFullProfile, ...fullProfileOverrides } as never); // fullProfile (select)
      (mockPrisma.caregiverProfile.update as jest.Mock).mockResolvedValue({
        ...baseOuterProfile,
        status: 'APPROVED',
      } as never);
    }

    it('rejects approval when phoneVerified is false', async () => {
      mockProfiles({ phoneVerified: false });

      const err = await reviewCaregiver('cp-1', 'admin-1', { action: 'approve' } as never).catch((e) => e);
      expect(err).toBeInstanceOf(BadRequestError);
      expect((err as BadRequestError).code).toBe('PROFILE_INCOMPLETE');
      expect((err as BadRequestError).message).toContain('verificación de teléfono');
      expect(mockPrisma.caregiverProfile.update).not.toHaveBeenCalled();
    });

    it('rejects approval when an amateur caregiver has not completed mandatory training', async () => {
      mockProfiles({ isAmateur: true, trainingComplete: false });

      const err = await reviewCaregiver('cp-1', 'admin-1', { action: 'approve' } as never).catch((e) => e);
      expect(err).toBeInstanceOf(BadRequestError);
      expect((err as BadRequestError).message).toContain('capacitación obligatoria (amateur)');
    });

    it('approves normally when everything (incl. phone + training) is complete', async () => {
      mockProfiles({ isAmateur: true, trainingComplete: true });

      const result = await reviewCaregiver('cp-1', 'admin-1', { action: 'approve' } as never);

      expect(result.status).toBe('APPROVED');
      expect(mockPrisma.adminAction.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            actionType: 'REVIEW_APPROVE',
            notes: 'Solicitud aprobada; perfil visible en listado público.',
          }),
        })
      );
    });

    it('force:true approves despite missing requirements and records exactly what was skipped', async () => {
      mockProfiles({ phoneVerified: false, isAmateur: true, trainingComplete: false });

      const result = await reviewCaregiver('cp-1', 'admin-1', { action: 'approve', force: true } as never);

      expect(result.status).toBe('APPROVED');
      expect(mockPrisma.adminAction.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            actionType: 'REVIEW_APPROVE',
            notes: expect.stringContaining('force:true'),
          }),
        })
      );
      const notes = (mockPrisma.adminAction.create as jest.Mock).mock.calls[0][0].data.notes as string;
      expect(notes).toContain('verificación de teléfono');
      expect(notes).toContain('capacitación obligatoria (amateur)');
    });
  });
});

import { requireStaffPermission } from '../../src/middleware/require-staff-membership.middleware';
import { setStaffPermissions, staffUserIdsWithPermission } from '../../src/modules/caregiver-staff/caregiver-staff.service';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    caregiverProfile: { findFirst: jest.fn(), findUnique: jest.fn() },
    caregiverStaffMember: { findUnique: jest.fn(), update: jest.fn(), findMany: jest.fn() },
  },
}));

const db = prisma as any;
const company = (features: Record<string, boolean>) => ({
  id: 'p1',
  isCompany: true,
  isProfessional: false,
  suspended: false,
  businessFeatures: features,
});

beforeEach(() => {
  jest.clearAllMocks();
  db.caregiverStaffMember.findUnique.mockResolvedValue({ id: 'm1', caregiverProfileId: 'p1', status: 'ACTIVE', userId: 'u2' });
  db.caregiverStaffMember.update.mockImplementation(({ data }: any) =>
    Promise.resolve({ canManageBookings: false, canChat: false, ...data })
  );
});

describe('requireStaffPermission', () => {
  it('sin permiso del dueño → 403 STAFF_PERMISSION_DENIED', () => {
    const next = jest.fn();
    requireStaffPermission('canManageBookings')({ staffContext: { canManageBookings: false } } as any, {} as any, next);
    expect(next.mock.calls[0][0]).toMatchObject({ code: 'STAFF_PERMISSION_DENIED' });
  });

  it('con permiso pasa', () => {
    const next = jest.fn();
    requireStaffPermission('canChat')({ staffContext: { canChat: true } } as any, {} as any, next);
    expect(next).toHaveBeenCalledWith();
  });
});

describe('setStaffPermissions', () => {
  it('el dueño no puede dar un permiso que el admin no habilitó', async () => {
    db.caregiverProfile.findFirst.mockResolvedValue(company({ STAFF_TEAM: true }));
    db.caregiverProfile.findUnique.mockResolvedValue(company({ STAFF_TEAM: true }));
    await expect(setStaffPermissions('owner', 'm1', { canManageBookings: true })).rejects.toMatchObject({ code: 'FEATURE_DISABLED' });
    expect(db.caregiverStaffMember.update).not.toHaveBeenCalled();
  });

  it('habilitado por el admin: lo da; quitar siempre se puede', async () => {
    const p = company({ STAFF_TEAM: true, STAFF_BOOKING_DECISIONS: true });
    db.caregiverProfile.findFirst.mockResolvedValue(p);
    db.caregiverProfile.findUnique.mockResolvedValue(p);
    await expect(setStaffPermissions('owner', 'm1', { canManageBookings: true })).resolves.toMatchObject({ canManageBookings: true });
    await expect(setStaffPermissions('owner', 'm1', { canChat: false })).resolves.toMatchObject({ canChat: false });
  });
});

describe('staffUserIdsWithPermission', () => {
  it('vacío si el admin no habilitó la función, aunque haya empleados con permiso', async () => {
    db.caregiverProfile.findUnique.mockResolvedValue(company({ STAFF_TEAM: true }));
    expect(await staffUserIdsWithPermission('p1', 'canChat')).toEqual([]);
    expect(db.caregiverStaffMember.findMany).not.toHaveBeenCalled();
  });

  it('con la función habilitada devuelve los empleados activos con permiso', async () => {
    db.caregiverProfile.findUnique.mockResolvedValue(company({ STAFF_TEAM: true, STAFF_CLIENT_CHAT: true }));
    db.caregiverStaffMember.findMany.mockResolvedValue([{ userId: 'u2' }]);
    expect(await staffUserIdsWithPermission('p1', 'canChat')).toEqual(['u2']);
    expect(db.caregiverStaffMember.findMany.mock.calls[0][0].where).toEqual({ caregiverProfileId: 'p1', status: 'ACTIVE', canChat: true });
  });
});

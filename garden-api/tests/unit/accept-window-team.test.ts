/**
 * Plazo para aceptar una reserva (auditoría 2026-10-10, H1): una empresa con empleados que pueden
 * aceptar tiene el doble, pero nunca más allá del inicio del servicio.
 */
import prisma from '../../src/config/database';
import { procesarAceptacionesExpiradas } from '../../src/jobs/caregiver-accept-expiry.job';
import { staffUserIdsWithPermission } from '../../src/modules/caregiver-staff/caregiver-staff.service';

jest.mock('../../src/config/database', () => {
  const db: any = {
    booking: { findMany: jest.fn(), updateMany: jest.fn().mockResolvedValue({ count: 1 }), update: jest.fn() },
    user: { update: jest.fn().mockResolvedValue({ balance: 100 }) },
    walletTransaction: { create: jest.fn() },
    notification: { create: jest.fn() },
    adminNotification: { create: jest.fn() },
    $transaction: jest.fn(),
  };
  db.$transaction.mockImplementation((fn: (tx: unknown) => unknown) => fn(db));
  return { __esModule: true, default: db };
});
jest.mock('../../src/utils/settings-cache', () => ({ getNumericSetting: jest.fn().mockResolvedValue(3) }));
jest.mock('../../src/services/firebase.service', () => ({ sendPushToUser: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../src/modules/caregiver-staff/caregiver-staff.service', () => ({ staffUserIdsWithPermission: jest.fn() }));

const db = prisma as any;
const H = 60 * 60 * 1000;
const booking = (over: Record<string, unknown> = {}) => ({
  id: 'b1', clientId: 'c1', caregiverId: 'cp1', petName: 'Toby', totalAmount: 100,
  updatedAt: new Date(Date.now() - 4 * H), serviceType: 'HOSPEDAJE',
  startDate: new Date(Date.now() + 3 * 24 * H), walkDate: null, startTime: null, ...over,
});

beforeEach(() => jest.clearAllMocks());

it('sin equipo vence a las 3 h', async () => {
  (staffUserIdsWithPermission as jest.Mock).mockResolvedValue([]);
  db.booking.findMany.mockResolvedValue([booking()]);
  await procesarAceptacionesExpiradas();
  expect(db.booking.updateMany).toHaveBeenCalledTimes(1);
});

it('con equipo a las 4 h todavía no vence (plazo 6 h)', async () => {
  (staffUserIdsWithPermission as jest.Mock).mockResolvedValue(['staff1']);
  db.booking.findMany.mockResolvedValue([booking()]);
  await procesarAceptacionesExpiradas();
  expect(db.booking.updateMany).not.toHaveBeenCalled();
});

it('con equipo vence igual si el servicio ya empezó', async () => {
  (staffUserIdsWithPermission as jest.Mock).mockResolvedValue(['staff1']);
  db.booking.findMany.mockResolvedValue([booking({ startDate: new Date(Date.now() - 30 * 60 * 1000) })]);
  await procesarAceptacionesExpiradas();
  expect(db.booking.updateMany).toHaveBeenCalledTimes(1);
});

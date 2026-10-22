/**
 * Referidos del lado del cuidador: el primer servicio terminado de un cuidador invitado le da el
 * bono a los dos, una sola vez (un bono de referido por persona, como dueño o como cuidador).
 */
import prisma from '../../src/config/database';
import { grantCaregiverReferralRewardIfEligible } from '../../src/modules/referral/referral.service';

jest.mock('../../src/config/database', () => {
  const db: any = {
    caregiverProfile: { findUnique: jest.fn().mockResolvedValue({ userId: 'cg-user' }) },
    user: { findUnique: jest.fn(), updateMany: jest.fn(), update: jest.fn().mockResolvedValue({ balance: 30 }) },
    booking: { count: jest.fn(), findUnique: jest.fn() },
    walletTransaction: { create: jest.fn() },
    $queryRaw: jest.fn().mockResolvedValue([]),
    $transaction: jest.fn(),
  };
  db.$transaction.mockImplementation((fn: (tx: unknown) => unknown) => fn(db));
  return { __esModule: true, default: db };
});
jest.mock('../../src/utils/settings-cache', () => ({ getNumericSetting: jest.fn().mockResolvedValue(30) }));
jest.mock('../../src/services/firebase.service', () => ({ sendPushToUser: jest.fn().mockResolvedValue(undefined) }));

const db = prisma as any;
const booking = (over: Record<string, unknown> = {}) => ({
  paidAt: new Date(), createdByAdmin: false, clientId: 'cliente',
  client: { referredByUserId: null }, caregiver: { userId: 'cg-user', user: { referredByUserId: 'ref' } }, ...over,
});
beforeEach(() => {
  jest.clearAllMocks();
  db.booking.findUnique.mockResolvedValue(booking());
});

it('primer servicio de un cuidador invitado: Bs 30 para cada uno', async () => {
  db.user.findUnique.mockResolvedValue({ referredByUserId: 'ref', referralRewardGiven: false });
  db.booking.count.mockResolvedValue(1);
  db.user.updateMany.mockResolvedValue({ count: 1 });
  await grantCaregiverReferralRewardIfEligible('cp1', 'b1');
  expect(db.walletTransaction.create).toHaveBeenCalledTimes(2);
  const ids = db.walletTransaction.create.mock.calls.map((c: any) => c[0].data.userId).sort();
  expect(ids).toEqual(['cg-user', 'ref']);
});

it('ya cobró un bono (como dueño o cuidador): no hay otro', async () => {
  db.user.findUnique.mockResolvedValue({ referredByUserId: 'ref', referralRewardGiven: true });
  await grantCaregiverReferralRewardIfEligible('cp1', 'b1');
  expect(db.walletTransaction.create).not.toHaveBeenCalled();
});

it('no es su primer servicio: nada', async () => {
  db.user.findUnique.mockResolvedValue({ referredByUserId: 'ref', referralRewardGiven: false });
  db.booking.count.mockResolvedValue(2);
  await grantCaregiverReferralRewardIfEligible('cp1', 'b1');
  expect(db.walletTransaction.create).not.toHaveBeenCalled();
});

describe('abuso: el servicio no puede ser entre el que invita y su invitado', () => {
  beforeEach(() => {
    db.user.findUnique.mockResolvedValue({ referredByUserId: 'ref', referralRewardGiven: false });
    db.booking.count.mockResolvedValue(1);
    db.user.updateMany.mockResolvedValue({ count: 1 });
  });
  it('el cliente es quien lo invitó', async () => {
    db.booking.findUnique.mockResolvedValue(booking({ clientId: 'ref' }));
    await grantCaregiverReferralRewardIfEligible('cp1', 'b1');
    expect(db.walletTransaction.create).not.toHaveBeenCalled();
  });
  it('el cliente también es invitado de la misma persona', async () => {
    db.booking.findUnique.mockResolvedValue(booking({ client: { referredByUserId: 'ref' } }));
    await grantCaregiverReferralRewardIfEligible('cp1', 'b1');
    expect(db.walletTransaction.create).not.toHaveBeenCalled();
  });
  it('la reserva no se pagó o la creó un admin', async () => {
    db.booking.findUnique.mockResolvedValue(booking({ paidAt: null }));
    await grantCaregiverReferralRewardIfEligible('cp1', 'b1');
    db.booking.findUnique.mockResolvedValue(booking({ createdByAdmin: true }));
    await grantCaregiverReferralRewardIfEligible('cp1', 'b1');
    expect(db.walletTransaction.create).not.toHaveBeenCalled();
  });
});

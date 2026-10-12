/**
 * Alertas para los admins (sendPushToAdmins / notifyAdmins): antes solo eran
 * push, y ningún admin tenía token (el panel se usa desde el navegador), así
 * que se perdían todas. Ahora cada alerta queda además en la bandeja de cada
 * admin — la campana del panel — tenga o no push activo.
 */
import prisma from '../../src/config/database';
import { adminInboxType, sendPushToAdmins } from '../../src/services/firebase.service';

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    user: { findMany: jest.fn() },
    notification: { createMany: jest.fn().mockResolvedValue({ count: 0 }) },
  },
}));

const db = prisma as unknown as {
  user: { findMany: jest.Mock };
  notification: { createMany: jest.Mock };
};

describe('sendPushToAdmins', () => {
  beforeEach(() => jest.clearAllMocks());

  it('deja el aviso en la bandeja de todos los admins aunque ninguno tenga push', async () => {
    db.user.findMany.mockResolvedValue([
      { id: 'a1', fcmToken: null },
      { id: 'a2', fcmToken: null },
    ]);
    await sendPushToAdmins('Pago declarado', 'Reserva ABC: el cliente dice que ya pagó.', {
      type: 'PAYMENT_DECLARED',
      bookingId: 'b1',
    });
    expect(db.user.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: { role: 'ADMIN' } }));
    expect(db.notification.createMany).toHaveBeenCalledWith({
      data: [
        expect.objectContaining({ userId: 'a1', type: 'ADMIN_PAYMENT', bookingId: 'b1', title: 'Pago declarado' }),
        expect.objectContaining({ userId: 'a2', type: 'ADMIN_PAYMENT', bookingId: 'b1' }),
      ],
    });
  });

  it('nunca lanza aunque falle la base', async () => {
    db.user.findMany.mockRejectedValue(new Error('db caída'));
    await expect(sendPushToAdmins('x', 'y')).resolves.toBeUndefined();
  });
});

describe('adminInboxType', () => {
  it.each([
    ['PAYMENT_DECLARED', 'ADMIN_PAYMENT'],
    ['PAYMENT_AUTO_APPROVED', 'ADMIN_PAYMENT'],
    ['SIP_FAILURE', 'ADMIN_PAYMENT'],
    ['EXTENSION_PAYMENT', 'ADMIN_EXTENSION'],
    ['WITHDRAWAL_REQUEST', 'ADMIN_WITHDRAWAL'],
    ['CLIENT_SOS_URGENT', 'ADMIN_URGENT'],
    ['SERVICE_INCIDENT_URGENT', 'ADMIN_URGENT'],
    ['DISPUTE_APPEALED', 'ADMIN_DISPUTE'],
    ['BLOCKCHAIN_LOW_BALANCE', 'ADMIN_BLOCKCHAIN'],
    ['PHONE_OTP_MANUAL_HELP', 'ADMIN_VERIFY_PHONE'],
    ['LOW_RATING', 'ADMIN_RATING'],
    [undefined, 'ADMIN_ALERT'],
  ])('%s → %s', (input, expected) => {
    expect(adminInboxType(input)).toBe(expected);
  });

  it('cabe en Notification.type (VarChar 20)', () => {
    for (const t of ['EMAIL_OTP_MANUAL_HELP', 'CHAT_REPORT', 'NIT_VERIFICATION_SUBMITTED', 'WALKIN_INCIDENT', 'CAREGIVER_SUBMIT']) {
      expect(adminInboxType(t).length).toBeLessThanOrEqual(20);
    }
  });
});

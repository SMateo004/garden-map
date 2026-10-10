/**
 * "Ya realicé el pago" (regla definida con el founder, 2026-10-07):
 *  - declarar el pago saca la reserva del vencimiento del QR (no se cancela como "QR sin pagar");
 *  - si ningún admin lo revisa antes de que venza el QR, la reserva se aprueba sola;
 *  - después el admin puede verificarla: CONFIRMED (llegó) o NOT_RECEIVED (no llegó → se
 *    descuenta de la billetera del cliente, puede quedar en negativo, y se le avisa);
 *  - el descuento SOLO aplica a reservas aprobadas automáticamente;
 *  - una reserva con pago declarado no se puede cancelar mientras está en revisión.
 */
import { declarePaymentMade, cancelBooking } from '../../src/modules/booking-service/booking.service';
import { verifyPaymentManual, verifyPaymentBySipCallback } from '../../src/modules/payment-service/payment.service';
import { reviewAutoApprovedPayment, amountExpectedByQr } from '../../src/modules/payment-service/payment-review.service';
import { aprobarPagosDeclaradosVencidos, recordarPagosSinVerificar } from '../../src/jobs/payment-review.job';
import { procesarQrsExpirados } from '../../src/jobs/qr-expiry.job';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => {
  const db = {
    booking: { findFirst: jest.fn(), findUnique: jest.fn(), findMany: jest.fn(), update: jest.fn(), updateMany: jest.fn() },
    user: { update: jest.fn() },
    walletTransaction: { create: jest.fn() },
    notification: { create: jest.fn() },
    adminNotification: { create: jest.fn() },
    adminAction: { create: jest.fn() },
    donation: { upsert: jest.fn().mockResolvedValue({}) },
    appSettings: { findUnique: jest.fn().mockResolvedValue(null) },
    caregiverCommissionOverride: { findMany: jest.fn().mockResolvedValue([]) },
    $queryRaw: jest.fn().mockResolvedValue([]),
    $transaction: jest.fn(),
  };
  db.$transaction.mockImplementation((fn: (tx: unknown) => unknown) => fn(db));
  return { __esModule: true, default: db };
});
jest.mock('../../src/services/firebase.service', () => ({
  sendPushToUser: jest.fn().mockResolvedValue(undefined),
  sendPushToAdmins: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../src/services/notification.service', () => ({
  onBookingWaitingApproval: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../src/services/blockchain.service', () => ({ blockchainService: {} }));
jest.mock('../../src/services/chain-registry.service', () => ({
  enqueueBookingCreate: jest.fn().mockResolvedValue(undefined),
  enqueueSafely: jest.fn(),
}));
jest.mock('../../src/shared/analytics', () => ({ track: jest.fn() }));

const db = prisma as unknown as {
  booking: { findFirst: jest.Mock; findUnique: jest.Mock; findMany: jest.Mock; update: jest.Mock; updateMany: jest.Mock };
  user: { update: jest.Mock };
  walletTransaction: { create: jest.Mock };
  notification: { create: jest.Mock };
  adminNotification: { create: jest.Mock };
  adminAction: { create: jest.Mock };
};
const firebase = jest.requireMock('../../src/services/firebase.service') as {
  sendPushToUser: jest.Mock;
  sendPushToAdmins: jest.Mock;
};

const NOW = new Date('2026-10-07T15:00:00Z');

beforeEach(() => {
  jest.clearAllMocks();
  db.booking.updateMany.mockResolvedValue({ count: 1 });
  db.booking.update.mockResolvedValue({});
});

describe('declarePaymentMade — "Ya realicé el pago"', () => {
  const pending = { id: 'b1', status: 'PENDING_PAYMENT', qrId: 'qr-1', paidAt: null, caregiverId: 'c1', paymentDeclaredAt: null };

  it('pasa a pago en revisión, avisa a los admins y no lo vuelve a hacer si se toca dos veces', async () => {
    db.booking.findFirst.mockResolvedValue(pending);
    const r = await declarePaymentMade('b1', 'client-1');
    expect(r.status).toBe('PAYMENT_PENDING_APPROVAL');
    expect(r.alreadyDeclared).toBe(false);
    const upd = db.booking.updateMany.mock.calls[0][0];
    expect(upd.where).toMatchObject({ id: 'b1', status: 'PENDING_PAYMENT', paidAt: null });
    expect(upd.data.status).toBe('PAYMENT_PENDING_APPROVAL');
    expect(upd.data.paymentDeclaredAt).toBeInstanceOf(Date);
    expect(db.adminNotification.create).toHaveBeenCalledTimes(1);
    expect(firebase.sendPushToAdmins).toHaveBeenCalledTimes(1);

    db.booking.findFirst.mockResolvedValue({ ...pending, status: 'PAYMENT_PENDING_APPROVAL', paymentDeclaredAt: NOW });
    const again = await declarePaymentMade('b1', 'client-1');
    expect(again.alreadyDeclared).toBe(true);
    expect(db.adminNotification.create).toHaveBeenCalledTimes(1);
    expect(firebase.sendPushToAdmins).toHaveBeenCalledTimes(1);
  });

  it('guardería de varios días: todo el grupo pasa a verificación y se guarda la suma que debía llegar', async () => {
    const lead = { ...pending, bookingGroupId: 'g1', totalAmount: 100, walletPaymentAmount: 0, donationAmount: 10 };
    db.booking.findFirst.mockResolvedValue(lead);
    db.booking.findMany.mockResolvedValue([{ id: 'b2', totalAmount: 100 }, { id: 'b3', totalAmount: 100 }]);
    await declarePaymentMade('b1', 'client-1');

    const [leadUpd, siblingsUpd] = db.booking.updateMany.mock.calls.map((c) => c[0]);
    expect(Number(leadUpd.data.paymentExpectedAmount)).toBe(310); // 3 días × 100 + 10 de donación
    expect(siblingsUpd.where.id.in).toEqual(['b2', 'b3']);
    expect(siblingsUpd.data.status).toBe('PAYMENT_PENDING_APPROVAL');
  });

  it('si el job de vencimiento la canceló justo antes (count 0), avisa que escriba a Soporte', async () => {
    db.booking.findFirst.mockResolvedValue(pending);
    db.booking.updateMany.mockResolvedValue({ count: 0 });
    await expect(declarePaymentMade('b1', 'client-1')).rejects.toThrow(/Soporte/);
  });

  it('reserva ya cancelada: no se puede declarar, se indica escribir a Soporte con el comprobante', async () => {
    db.booking.findFirst.mockResolvedValue({ ...pending, status: 'CANCELLED' });
    await expect(declarePaymentMade('b1', 'client-1')).rejects.toThrow(/comprobante/);
  });

  it('sin QR generado no se puede declarar', async () => {
    db.booking.findFirst.mockResolvedValue({ ...pending, qrId: null });
    await expect(declarePaymentMade('b1', 'client-1')).rejects.toThrow(/código de pago/);
  });
});

describe('el vencimiento del QR ya no cancela un pago declarado', () => {
  it('qr-expiry solo busca reservas PENDING_PAYMENT (las declaradas están en revisión)', async () => {
    db.booking.findMany.mockResolvedValue([]);
    await procesarQrsExpirados();
    expect(db.booking.findMany.mock.calls[0][0].where.status).toBe('PENDING_PAYMENT');
  });

  it('cancelar una reserva con pago declarado en revisión está bloqueado (cliente o "QR vencido")', async () => {
    db.booking.findFirst.mockResolvedValue({ id: 'b1', status: 'PAYMENT_PENDING_APPROVAL', paymentDeclaredAt: NOW, paidAt: null });
    await expect(cancelBooking('b1', 'client-1', 'x', 'CLIENT_REQUEST')).rejects.toThrow(/verificando tu pago/);
    await expect(cancelBooking('b1', 'client-1', 'x', 'QR_ABANDONED')).rejects.toThrow(/verificando tu pago/);
    expect(db.booking.updateMany).not.toHaveBeenCalled();
  });
});

describe('aprobación automática al vencer la ventana', () => {
  it('aprueba las declaradas vencidas, las marca para verificar y avisa a los admins', async () => {
    db.booking.findMany.mockResolvedValue([{ id: 'b1', caregiverId: 'c1' }]);
    db.booking.findUnique.mockResolvedValue({
      id: 'b1', clientId: 'client-1', status: 'PAYMENT_PENDING_APPROVAL', paidAt: null,
      donationAmount: null, totalAmount: 110,
    });
    const r = await aprobarPagosDeclaradosVencidos(NOW);

    expect(r.approved).toEqual(['b1']);
    const where = db.booking.findMany.mock.calls[0][0].where;
    expect(where).toMatchObject({ status: 'PAYMENT_PENDING_APPROVAL', paymentDeclaredAt: { not: null }, paidAt: null });
    expect(where.OR[0]).toEqual({ qrExpiresAt: { lt: NOW } });
    const upd = db.booking.updateMany.mock.calls[0][0];
    expect(upd.where).toMatchObject({ status: 'PAYMENT_PENDING_APPROVAL', paymentDeclaredAt: { not: null }, paidAt: null });
    expect(upd.data).toMatchObject({ status: 'WAITING_CAREGIVER_APPROVAL' });
    expect(upd.data.paymentAutoApprovedAt).toBeInstanceOf(Date);
    expect(firebase.sendPushToAdmins).toHaveBeenCalledWith(expect.stringMatching(/automáticamente/), expect.any(String));
  });

  it('si un admin o el banco la resolvió en el medio, no la cuenta como aprobada', async () => {
    db.booking.findMany.mockResolvedValue([{ id: 'b1', caregiverId: 'c1' }]);
    db.booking.findUnique.mockResolvedValue({ id: 'b1', status: 'PAYMENT_PENDING_APPROVAL', paidAt: null });
    db.booking.updateMany.mockResolvedValue({ count: 0 });
    expect((await aprobarPagosDeclaradosVencidos(NOW)).approved).toEqual([]);
    expect(firebase.sendPushToAdmins).not.toHaveBeenCalled();
  });

  it('una aprobación normal del admin NO marca la reserva como aprobada automáticamente', async () => {
    db.booking.findUnique.mockResolvedValue({ id: 'b1', clientId: 'c', status: 'PAYMENT_PENDING_APPROVAL', paidAt: null });
    await verifyPaymentManual('b1');
    expect(db.booking.updateMany.mock.calls[0][0].data.paymentAutoApprovedAt).toBeUndefined();
  });
});

describe('verificación posterior del admin', () => {
  const autoApproved = {
    id: 'b1', clientId: 'client-1', totalAmount: 110, walletPaymentAmount: 30, donationAmount: 10,
    paymentAutoApprovedAt: NOW, paymentReviewedAt: null,
  };

  it('lo que debía llegar por QR = lo guardado al declarar; si falta, total − billetera + donación', () => {
    expect(amountExpectedByQr({ ...autoApproved, paymentExpectedAmount: 310 })).toBe(310);
    expect(amountExpectedByQr(autoApproved)).toBe(90);
    expect(amountExpectedByQr({ totalAmount: 110, walletPaymentAmount: 0, donationAmount: null })).toBe(110);
  });

  it('NO llegó: descuenta de la billetera (con bloqueo), puede quedar en negativo y avisa al cliente', async () => {
    db.booking.findUnique.mockResolvedValue(autoApproved);
    db.user.update.mockResolvedValue({ balance: -60 });
    const r = await reviewAutoApprovedPayment('b1', 'admin-1', 'NOT_RECEIVED');

    expect(r).toMatchObject({ outcome: 'NOT_RECEIVED', chargedAmount: 90, clientBalance: -60 });
    expect(db.user.update.mock.calls[0][0]).toEqual({
      where: { id: 'client-1' }, data: { balance: { decrement: 90 } }, select: { balance: true },
    });
    // Bloqueo de la reserva y del usuario antes de tocar el saldo.
    const locks = (prisma as unknown as { $queryRaw: jest.Mock }).$queryRaw.mock.calls.map((c) => String(c[0].join('?')));
    expect(locks.some((s) => s.includes('"bookings"') && s.includes('FOR UPDATE'))).toBe(true);
    expect(locks.some((s) => s.includes('"users"') && s.includes('FOR UPDATE'))).toBe(true);
    expect(db.walletTransaction.create.mock.calls[0][0].data).toMatchObject({ type: 'PAYMENT_NOT_RECEIVED', amount: 90, balance: -60 });
    expect(db.booking.update.mock.calls[0][0].data).toMatchObject({ paymentReviewOutcome: 'NOT_RECEIVED', paymentChargedBackAmount: 90 });
    const notif = db.notification.create.mock.calls[0][0].data;
    expect(notif).toMatchObject({ bookingId: 'b1', userId: 'client-1', title: 'Tienes un pago pendiente', type: 'PAYMENT_NOT_RECEIVED' });
    expect(notif.message).toMatch(/Bs 90\.00/);
    expect(notif.message).toMatch(/próximo pago/);
    expect(firebase.sendPushToUser).toHaveBeenCalledWith('client-1', 'Tienes un pago pendiente', expect.any(String));
    // La reserva no se cancela.
    expect(db.booking.update.mock.calls[0][0].data.status).toBeUndefined();
  });

  it('LLEGÓ: solo se registra, sin tocar la billetera', async () => {
    db.booking.findUnique.mockResolvedValue(autoApproved);
    const r = await reviewAutoApprovedPayment('b1', 'admin-1', 'CONFIRMED');
    expect(r.chargedAmount).toBe(0);
    expect(db.user.update).not.toHaveBeenCalled();
    expect(db.booking.update.mock.calls[0][0].data).toMatchObject({ paymentReviewOutcome: 'CONFIRMED', paymentReviewedBy: 'admin-1' });
  });

  it('solo aplica a reservas aprobadas automáticamente, y una sola vez', async () => {
    db.booking.findUnique.mockResolvedValueOnce({ ...autoApproved, paymentAutoApprovedAt: null });
    await expect(reviewAutoApprovedPayment('b1', 'a', 'NOT_RECEIVED')).rejects.toThrow(/no fue aprobado automáticamente/);
    db.booking.findUnique.mockResolvedValueOnce({ ...autoApproved, paymentReviewedAt: NOW });
    await expect(reviewAutoApprovedPayment('b1', 'a', 'NOT_RECEIVED')).rejects.toThrow(/ya fue verificado/);
    expect(db.user.update).not.toHaveBeenCalled();
  });
});

describe('banco (SIP)', () => {
  it('confirma una reserva con pago declarado aún en revisión', async () => {
    db.booking.findFirst.mockResolvedValue({ id: 'b1', clientId: 'c', status: 'PAYMENT_PENDING_APPROVAL', paidAt: null, totalAmount: 110 });
    const r = await verifyPaymentBySipCallback('b1');
    expect(r.status).toBe('WAITING_CAREGIVER_APPROVAL');
    expect(db.booking.updateMany.mock.calls[0][0].where.status.in).toEqual(['PENDING_PAYMENT', 'PAYMENT_PENDING_APPROVAL']);
  });

  it('si ya se había aprobado sola, la confirmación del banco la deja verificada', async () => {
    db.booking.findFirst.mockResolvedValue({
      id: 'b1', status: 'WAITING_CAREGIVER_APPROVAL', paidAt: NOW, paymentAutoApprovedAt: NOW, paymentReviewedAt: null,
    });
    await verifyPaymentBySipCallback('b1');
    expect(db.booking.updateMany.mock.calls[0][0].data).toMatchObject({ paymentReviewOutcome: 'CONFIRMED' });
  });
});

describe('recordatorio de pagos sin verificar', () => {
  it('avisa una vez por plazo y no cambia el estado de la reserva', async () => {
    db.booking.findMany.mockResolvedValue([{ id: 'b1', caregiverId: 'c1' }]);
    const r = await recordarPagosSinVerificar(NOW);
    expect(r.alerted).toBe(1);
    const upd = db.booking.updateMany.mock.calls[0][0];
    expect(Object.keys(upd.data)).toEqual(['paymentReviewAlertedAt']);
    expect(firebase.sendPushToAdmins).toHaveBeenCalledTimes(1);
  });
});

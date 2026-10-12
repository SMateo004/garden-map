/**
 * El aviso `wallet_updated` sale para TODO cambio de billetera (saldo,
 * movimiento, donación), detectado en un solo lugar (middleware de Prisma),
 * en vez de depender de que cada flujo se acuerde de avisar.
 */
import { scheduleWalletUpdated, walletUsersOf, WALLET_EVENT_DELAY_MS } from '../../src/services/wallet-events.service';

const emitWalletUpdated = jest.fn();
jest.mock('../../src/services/socket.service', () => ({ emitWalletUpdated: (id: string) => emitWalletUpdated(id) }));

describe('walletUsersOf', () => {
  it.each([
    ['movimiento creado', { model: 'WalletTransaction', action: 'create', args: { data: { userId: 'u1' } } }, { id: 't1', userId: 'u1' }, ['u1']],
    ['movimientos en lote', { model: 'WalletTransaction', action: 'createMany', args: { data: [{ userId: 'u1' }, { userId: 'u2' }] } }, { count: 2 }, ['u1', 'u2']],
    ['retiro que cambia de estado', { model: 'WalletTransaction', action: 'update', args: { where: { id: 't1' }, data: { status: 'COMPLETED' } } }, { id: 't1', userId: 'u3' }, ['u3']],
    ['donación (upsert)', { model: 'Donation', action: 'upsert', args: { where: { bookingId: 'b1' }, create: { clientId: 'c1' }, update: {} } }, { id: 'd1', clientId: 'c1' }, ['c1']],
    ['saldo que sube', { model: 'User', action: 'update', args: { where: { id: 'u4' }, data: { balance: { increment: 10 } } } }, { id: 'u4' }, ['u4']],
    ['saldo en lote', { model: 'User', action: 'updateMany', args: { where: { id: { in: ['u5', 'u6'] } }, data: { balance: 0 } } }, { count: 2 }, ['u5', 'u6']],
  ])('%s', (_label, params, result, expected) => {
    expect(walletUsersOf(params as never, result)).toEqual(expected);
  });

  it.each([
    ['cambio de usuario sin saldo', { model: 'User', action: 'update', args: { where: { id: 'u1' }, data: { firstName: 'Ana' } } }],
    ['lectura', { model: 'WalletTransaction', action: 'findMany', args: {} }],
    ['otra tabla', { model: 'Booking', action: 'update', args: { where: { id: 'b1' }, data: { status: 'CONFIRMED' } } }],
  ])('no avisa: %s', (_label, params) => {
    expect(walletUsersOf(params as never, { id: 'x', userId: 'u1' })).toEqual([]);
  });
});

describe('scheduleWalletUpdated', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    emitWalletUpdated.mockClear();
  });
  afterEach(() => jest.useRealTimers());

  it('junta varias escrituras seguidas en un solo aviso, después de la espera', async () => {
    scheduleWalletUpdated('u1');
    scheduleWalletUpdated('u1');
    scheduleWalletUpdated('u1');
    expect(emitWalletUpdated).not.toHaveBeenCalled();
    jest.advanceTimersByTime(WALLET_EVENT_DELAY_MS);
    await jest.runAllTimersAsync();
    await Promise.resolve();
    await new Promise(jest.requireActual('timers').setImmediate);
    expect(emitWalletUpdated).toHaveBeenCalledTimes(1);
    expect(emitWalletUpdated).toHaveBeenCalledWith('u1');
  });
});

/**
 * Unit tests: cola persistente de registros on-chain (chain-registry.service.ts).
 * Prisma es un store en memoria; blockchainService está mockeado.
 */

type Row = Record<string, any>;
const store: { records: Row[]; bookings: Record<string, Row>; notifications: Row[] } = {
  records: [], bookings: {}, notifications: [],
};
let seq = 0;

function matches(row: Row, where: Row = {}): boolean {
  return Object.entries(where).every(([k, v]) => {
    if (k === 'OR') return (v as Row[]).some((w) => matches(row, w));
    if (v && typeof v === 'object' && !(v instanceof Date)) {
      if ('in' in v) return (v.in as unknown[]).includes(row[k]);
      if ('lte' in v) return row[k] <= v.lte;
      if ('gte' in v) return row[k] >= v.gte;
      if ('not' in v) return row[k] !== v.not;
    }
    return row[k] === v;
  });
}

jest.mock('../../src/config/database', () => {
  const blockchainRecord = {
    createMany: jest.fn(async ({ data }: { data: Row[] }) => {
      let count = 0;
      for (const d of data) {
        if (store.records.some((r) => r.dedupeKey === d.dedupeKey)) continue;
        store.records.push({
          id: `rec-${++seq}`, status: 'PENDING', attempts: 0, nextAttemptAt: new Date(0), payload: null,
          txHash: null, chainId: null, sentBlock: null, sentAt: null, alertedAt: null, lastError: null,
          createdAt: new Date(Date.now() + seq), updatedAt: new Date(), ...d,
        });
        count++;
      }
      return { count };
    }),
    findMany: jest.fn(async ({ where, take }: Row) =>
      store.records.filter((r) => matches(r, where)).sort((a, b) => a.createdAt - b.createdAt).slice(0, take ?? 1000)),
    findFirst: jest.fn(async ({ where }: Row) => store.records.find((r) => matches(r, where)) ?? null),
    findUnique: jest.fn(async ({ where }: Row) =>
      store.records.find((r) => (where.id ? r.id === where.id : r.dedupeKey === where.dedupeKey)) ?? null),
    update: jest.fn(async ({ where, data }: Row) => {
      const r = store.records.find((x) => x.id === where.id)!;
      Object.assign(r, data, { updatedAt: new Date() });
      return { ...r };
    }),
  };
  const db = {
    blockchainRecord,
    booking: {
      findUnique: jest.fn(async ({ where }: Row) => store.bookings[where.id] ?? null),
      update: jest.fn(async ({ where, data }: Row) => Object.assign(store.bookings[where.id]!, data)),
    },
    adminNotification: { create: jest.fn(async ({ data }: Row) => { store.notifications.push(data); return data; }) },
    // Correo por usuario: las cuentas de prueba (reviewer.*@gardenbo.com) no van a la cadena.
    user: { findUnique: jest.fn(async ({ where }: Row) => ({ email: `${where.id}@example.com` })) },
  };
  return { __esModule: true, default: db, prisma: db };
});

jest.mock('../../src/services/firebase.service', () => ({ sendPushToAdmins: jest.fn().mockResolvedValue(undefined) }));

const mockChain = {
  checkReady: jest.fn(),
  send: jest.fn(),
  waitForReceipt: jest.fn(),
  getReceipt: jest.fn(),
  getConfirmations: jest.fn(),
  isKnownTransaction: jest.fn(),
  findEventTx: jest.fn(),
  partyRef: jest.fn((id: string) => `ref(${id})`),
};
jest.mock('../../src/services/blockchain.service', () => {
  const actual = jest.requireActual('../../src/services/blockchain.service');
  return { ...actual, blockchainService: mockChain };
});

import {
  enqueueBookingCreate,
  enqueueBookingFinalize,
  enqueueDisputeResolution,
  getBookingChainProof,
  processQueue,
  enqueueProfileSync,
  disputeAmounts,
} from '../../src/services/chain-registry.service';
import { ChainRevertError, GasTooHighError } from '../../src/services/blockchain.service';

const BID = '8f14e45f-ceea-467a-9575-1a2b3c4d5e6f';
const READY = { ok: true, chainId: 137, escrowAddress: '0xEscrow', profilesAddress: '0xProfiles', profilesOk: true };

function booking(extra: Row = {}): Row {
  return {
    id: BID, status: 'CONFIRMED', serviceType: 'PASEO', totalAmount: 45.5, createdByAdmin: false,
    paidAt: new Date('2026-10-05T15:00:00Z'), createdAt: new Date('2026-10-05T14:00:00Z'),
    startDate: null, endDate: null, walkDate: new Date('2026-10-06T00:00:00Z'), walkDays: null, startTime: '09:00', duration: 60,
    clientId: 'client-user', cancellationSource: null, refundAmount: null, refundStatus: null,
    petName: 'Firulais',
    client: { email: 'dueno@example.com' },
    caregiver: { userId: 'caregiver-user', user: { email: 'cuidador@example.com' } },
    ...extra,
  };
}

beforeEach(() => {
  store.records = []; store.bookings = {}; store.notifications = []; seq = 0;
  jest.clearAllMocks();
  delete process.env.BLOCKCHAIN_RECORDS_SINCE;
  mockChain.checkReady.mockResolvedValue(READY);
  mockChain.send.mockResolvedValue({ hash: '0xtx1', sentBlock: 500 });
  mockChain.waitForReceipt.mockResolvedValue({ status: 1, blockNumber: 502 });
});

describe('processQueue', () => {
  it('en pausa si la cadena no está lista: no toca la cola', async () => {
    mockChain.checkReady.mockResolvedValue({ ok: false, reason: 'OUTDATED_CONTRACT' });
    store.bookings[BID] = booking();
    await enqueueBookingCreate(BID);
    const res = await processQueue();
    expect(res.paused).toBe('OUTDATED_CONTRACT');
    expect(store.records[0]!.status).toBe('PENDING');
    expect(mockChain.send).not.toHaveBeenCalled();
  });

  it('registra el pago sin datos personales y guarda el hash en la fila y en la reserva', async () => {
    store.bookings[BID] = booking();
    await enqueueBookingCreate(BID);
    await enqueueBookingCreate(BID); // duplicado: se ignora
    expect(store.records).toHaveLength(1);

    const res = await processQueue();
    expect(res.confirmed).toBe(1);
    const [target, method, args] = mockChain.send.mock.calls[0];
    expect([target, method]).toEqual(['escrow', 'recordBooking']);
    expect(args[0]).toBe('0x8f14e45fceea467a95751a2b3c4d5e6f');
    expect(args[1]).toBe('ref(client-user)');
    expect(args[2]).toBe('ref(caregiver-user)');
    expect(args[3]).toBe(1); // PASEO
    expect(args[4]).toBe(4550n);
    expect(JSON.stringify(args, (_k, v) => (typeof v === 'bigint' ? v.toString() : v))).not.toContain('Firulais');

    const rec = store.records[0]!;
    expect(rec).toMatchObject({ status: 'CONFIRMED', txHash: '0xtx1', chainId: 137, blockNumber: 502 });
    expect(store.bookings[BID]!.blockchainTxHash).toBe('0xtx1');
  });

  it('no registra reservas pagadas antes de la fecha de inicio ni reservas de prueba', async () => {
    store.bookings[BID] = booking({ paidAt: new Date('2026-07-20T00:00:00Z') });
    await enqueueBookingCreate(BID);
    await processQueue();
    expect(store.records[0]!.status).toBe('SKIPPED');

    const other = '00000000-0000-4000-8000-000000000001';
    store.bookings[other] = booking({ id: other, createdByAdmin: true });
    await enqueueBookingCreate(other);
    await processQueue();
    expect(store.records[1]!.status).toBe('SKIPPED');
    expect(mockChain.send).not.toHaveBeenCalled();
  });

  it('no registra nada de las cuentas de prueba reviewer.* (cliente o cuidador)', async () => {
    const asClient = '00000000-0000-4000-8000-000000000002';
    const asCaregiver = '00000000-0000-4000-8000-000000000003';
    store.bookings[asClient] = booking({ id: asClient, client: { email: 'Reviewer.Cliente@gardenbo.com' } });
    store.bookings[asCaregiver] = booking({
      id: asCaregiver,
      caregiver: { userId: 'caregiver-user', user: { email: 'reviewer.cuidador@gardenbo.com' } },
    });
    await enqueueBookingCreate(asClient);
    await enqueueBookingCreate(asCaregiver);
    await processQueue();
    expect(store.records.map((r) => r.status)).toEqual(['SKIPPED', 'SKIPPED']);
    expect(store.records[0]!.lastError).toMatch(/cuenta de prueba/i);
    expect(mockChain.send).not.toHaveBeenCalled();
  });

  it('un correo parecido pero de otro dominio sí se registra', async () => {
    store.bookings[BID] = booking({ client: { email: 'reviewer.cliente@gmail.com' } });
    await enqueueBookingCreate(BID);
    await processQueue();
    expect(store.records[0]!.status).toBe('CONFIRMED');
  });

  it('tampoco sincroniza el perfil de una cuenta de prueba', async () => {
    const db = jest.requireMock('../../src/config/database').default as { user: { findUnique: jest.Mock } };
    db.user.findUnique.mockResolvedValueOnce({ email: 'reviewer.cuidador@gardenbo.com' });
    await enqueueProfileSync('caregiver-user', 'CAREGIVER', true);
    await processQueue();
    expect(store.records[0]!.status).toBe('SKIPPED');
    expect(mockChain.send).not.toHaveBeenCalled();
  });

  it('el cierre espera a que el pago esté confirmado on-chain', async () => {
    store.bookings[BID] = booking();
    await enqueueBookingFinalize(BID, null);
    await processQueue();
    // No había CREATE: lo encola y la finalización espera.
    expect(store.records.map((r) => r.kind)).toEqual(['FINALIZE', 'CREATE']);
    expect(store.records[0]!.status).toBe('PENDING');
    expect(mockChain.send).not.toHaveBeenCalled();

    await processQueue();
    expect(mockChain.send).toHaveBeenCalledTimes(1);
    expect(mockChain.send.mock.calls[0][1]).toBe('recordBooking');
    expect(store.records[0]!.status).toBe('PENDING');

    store.records[0]!.nextAttemptAt = new Date(0);
    mockChain.send.mockResolvedValue({ hash: '0xtx2', sentBlock: 600 });
    await processQueue();
    expect(mockChain.send.mock.calls[1][1]).toBe('finalizeBooking');
    expect(mockChain.send.mock.calls[1][2][1]).toBe(0); // sin calificación, nunca un 5 inventado
    expect(store.records[0]!.status).toBe('CONFIRMED');
  });

  it('un revert del contrato deja la fila FAILED y avisa a los admins', async () => {
    store.bookings[BID] = booking();
    mockChain.send.mockRejectedValue(new ChainRevertError('InvalidInput'));
    await enqueueBookingCreate(BID);
    const res = await processQueue();
    expect(res.failed).toBe(1);
    expect(store.records[0]!.status).toBe('FAILED');
    expect(store.notifications).toHaveLength(1);
    expect(store.notifications[0]).toMatchObject({ type: 'BLOCKCHAIN_FAILURE', bookingId: BID });
  });

  it('"ya registrado" recupera el hash desde los eventos en vez de fallar', async () => {
    store.bookings[BID] = booking();
    mockChain.send.mockRejectedValue(new ChainRevertError('AlreadyRecorded'));
    mockChain.findEventTx.mockResolvedValue({ hash: '0xoriginal', blockNumber: 480 });
    await enqueueBookingCreate(BID);
    await processQueue();
    expect(store.records[0]!).toMatchObject({ status: 'CONFIRMED', txHash: '0xoriginal' });
    expect(store.notifications).toHaveLength(0);
  });

  it('un error de red reintenta con backoff y avisa al tercer intento, sin perder la fila', async () => {
    store.bookings[BID] = booking();
    mockChain.send.mockRejectedValue(Object.assign(new Error('socket hang up'), { code: 'NETWORK_ERROR' }));
    await enqueueBookingCreate(BID);
    for (let i = 1; i <= 3; i++) {
      store.records[0]!.nextAttemptAt = new Date(0);
      await processQueue();
      expect(store.records[0]!).toMatchObject({ status: 'PENDING', attempts: i });
    }
    expect(store.records[0]!.nextAttemptAt.getTime()).toBeGreaterThan(Date.now());
    expect(store.notifications).toHaveLength(1);
  });

  it('sin saldo avisa de inmediato', async () => {
    store.bookings[BID] = booking();
    mockChain.send.mockRejectedValue(Object.assign(new Error('insufficient funds'), { code: 'INSUFFICIENT_FUNDS' }));
    await enqueueBookingCreate(BID);
    await processQueue();
    expect(store.records[0]!.status).toBe('PENDING');
    expect(store.notifications).toHaveLength(1);
  });

  it('gas caro posterga sin contar intento', async () => {
    store.bookings[BID] = booking();
    mockChain.send.mockRejectedValue(new GasTooHighError(2000));
    await enqueueBookingCreate(BID);
    await processQueue();
    expect(store.records[0]!).toMatchObject({ status: 'PENDING', attempts: 0 });
  });

  it('si el proceso no ve la confirmación, la fila queda SENT con su hash y se confirma después', async () => {
    store.bookings[BID] = booking();
    mockChain.waitForReceipt.mockResolvedValue(null);
    await enqueueBookingCreate(BID);
    await processQueue();
    expect(store.records[0]!).toMatchObject({ status: 'SENT', txHash: '0xtx1' });

    mockChain.getReceipt.mockResolvedValue({ status: 1, blockNumber: 510 });
    mockChain.getConfirmations.mockResolvedValue(5);
    await processQueue();
    expect(store.records[0]!).toMatchObject({ status: 'CONFIRMED', blockNumber: 510 });
    expect(mockChain.send).toHaveBeenCalledTimes(1);
  });

  it('una tx descartada por la red vuelve a la cola', async () => {
    store.bookings[BID] = booking();
    mockChain.waitForReceipt.mockResolvedValue(null);
    await enqueueBookingCreate(BID);
    await processQueue();
    store.records[0]!.sentAt = new Date(Date.now() - 20 * 60_000);
    mockChain.getReceipt.mockResolvedValue(null);
    mockChain.isKnownTransaction.mockResolvedValue(false);
    mockChain.waitForReceipt.mockResolvedValue({ status: 1, blockNumber: 700 });
    mockChain.send.mockResolvedValue({ hash: '0xtx-retry', sentBlock: 690 });
    await processQueue();
    expect(store.records[0]!).toMatchObject({ status: 'CONFIRMED', txHash: '0xtx-retry' });
  });

  it('una finalización no se envía si la disputa ya cerró la reserva on-chain', async () => {
    store.bookings[BID] = booking();
    await enqueueBookingCreate(BID);
    await processQueue();
    await enqueueDisputeResolution(BID, { verdict: 'CAREGIVER_WINS', caregiverAmount: 36, clientAmount: 0, phase: 'INITIAL' });
    await enqueueBookingFinalize(BID, 4);
    await processQueue();
    const finalize = store.records.find((r) => r.kind === 'FINALIZE')!;
    expect(finalize.status).toBe('SKIPPED');
    const dispute = store.records.find((r) => r.kind === 'DISPUTE')!;
    expect(dispute.status).toBe('CONFIRMED');
    const disputeCall = mockChain.send.mock.calls.find((c) => c[1] === 'resolveDispute')!;
    expect(disputeCall[2].slice(1)).toEqual([1, 3600n, 0n]);
  });
});

describe('disputeAmounts', () => {
  const b = { totalAmount: 100, commissionAmount: 15, taxAmount: 13 };
  it('reparte igual que applyResolution', () => {
    expect(disputeAmounts('CAREGIVER_WINS', b)).toMatchObject({ caregiverAmount: 72, clientAmount: 0 });
    expect(disputeAmounts('CLIENT_WINS', b)).toMatchObject({ caregiverAmount: 0, clientAmount: 100 });
    expect(disputeAmounts('PARTIAL', b)).toMatchObject({ caregiverAmount: 57.6, clientAmount: 14.4 });
  });
});

describe('getBookingChainProof', () => {
  it('estado honesto según el caso', async () => {
    expect((await getBookingChainProof({ id: BID, paidAt: null })).status).toBe('NOT_APPLICABLE');
    const old = await getBookingChainProof({ id: BID, paidAt: new Date('2026-07-01') });
    expect(old).toMatchObject({ status: 'NOT_APPLICABLE', reason: 'BEFORE_START' });
    expect((await getBookingChainProof({ id: BID, paidAt: new Date('2026-10-05'), createdByAdmin: true })).reason)
      .toBe('TEST_BOOKING');
    expect((await getBookingChainProof({ id: BID, paidAt: new Date('2026-10-05') })).status).toBe('PENDING');
  });

  it('con el pago confirmado devuelve los enlaces a polygonscan', async () => {
    store.bookings[BID] = booking();
    await enqueueBookingCreate(BID);
    await processQueue();
    const proof = await getBookingChainProof({ id: BID, paidAt: store.bookings[BID]!.paidAt });
    expect(proof.status).toBe('RECORDED');
    expect(proof.network).toMatchObject({ chainId: 137, testnet: false });
    expect(proof.records[0]).toMatchObject({ kind: 'CREATE', explorerUrl: 'https://polygonscan.com/tx/0xtx1' });
  });
});

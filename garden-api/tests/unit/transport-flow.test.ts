/**
 * Flujo de los viajes de recojo / entrega con una base en memoria: estados, ventanas de
 * hora, quién puede cancelar y cuándo, y el dinero exacto que vuelve a la billetera.
 */
import { describe, it, expect, beforeEach } from '@jest/globals';

type Row = Record<string, any>;
const db: Record<string, Row[]> = {};
let seq = 0;

function matches(row: Row, where: Row | undefined): boolean {
  if (!where) return true;
  return Object.entries(where).every(([k, cond]) => {
    if (k === 'OR') return (cond as Row[]).some((w) => matches(row, w));
    if (k === 'AND') return (cond as Row[]).every((w) => matches(row, w));
    if (k === 'booking' && cond && typeof cond === 'object') {
      const b = db.bookings!.find((x) => x.id === row.bookingId);
      return !!b && matches(b, cond as Row);
    }
    const v = row[k];
    if (cond === null) return v === null || v === undefined;
    if (cond instanceof Date) return v instanceof Date && v.getTime() === cond.getTime();
    if (typeof cond === 'object') {
      const c = cond as Row;
      if ('in' in c) return c.in.includes(v);
      if ('not' in c) return c.not === null ? v != null : v !== c.not;
      return true;
    }
    return v === cond;
  });
}
const num = (v: any) => Number(v ?? 0);
function applyData(row: Row, data: Row) {
  for (const [k, v] of Object.entries(data)) {
    if (v && typeof v === 'object' && ('increment' in v || 'decrement' in v)) {
      row[k] = Math.round((num(row[k]) + num((v as any).increment) - num((v as any).decrement)) * 100) / 100;
    } else if (v && typeof v === 'object' && typeof (v as any).toNumber === 'function') {
      row[k] = (v as any).toNumber();
    } else {
      row[k] = v;
    }
  }
}
function withInclude(table: string, row: Row, include?: Row) {
  const out: Row = { ...row };
  if (include?.transportLegs) out.transportLegs = db.legs!.filter((l) => l.bookingId === row.id).map((l) => ({ ...l }));
  if (include?.booking) out.booking = { ...db.bookings!.find((b) => b.id === row.bookingId)! };
  if (table === 'profiles' && include === undefined) out.user = db.users!.find((u) => u.id === row.userId);
  return out;
}
function table(name: string) {
  return {
    findFirst: async ({ where, include }: any = {}) => {
      const r = db[name]!.find((x) => matches(x, where));
      return r ? withInclude(name, r, include) : null;
    },
    findUnique: async ({ where, include }: any = {}) => {
      const r = db[name]!.find((x) => matches(x, where));
      return r ? withInclude(name, r, include) : null;
    },
    findUniqueOrThrow: async ({ where, include }: any = {}) => {
      const r = db[name]!.find((x) => matches(x, where));
      if (!r) throw new Error('not found');
      return withInclude(name, r, include);
    },
    findMany: async ({ where, include }: any = {}) => db[name]!.filter((x) => matches(x, where)).map((r) => withInclude(name, r, include)),
    create: async ({ data }: any) => {
      const row = { id: `id-${++seq}`, createdAt: new Date(), ...data };
      db[name]!.push(row);
      return { ...row };
    },
    update: async ({ where, data }: any) => {
      const row = db[name]!.find((x) => matches(x, where));
      if (!row) throw new Error('not found');
      applyData(row, data);
      return { ...row };
    },
    updateMany: async ({ where, data }: any) => {
      const rows = db[name]!.filter((x) => matches(x, where));
      rows.forEach((r) => applyData(r, data));
      return { count: rows.length };
    },
  };
}

const fakePrisma: any = {
  booking: table('bookings'),
  bookingTransportLeg: table('legs'),
  caregiverProfile: table('profiles'),
  caregiverStaffMember: table('staff'),
  clientProfile: table('clients'),
  user: table('users'),
  walletTransaction: table('wallet'),
  notification: table('notifications'),
  $queryRaw: async () => [],
  $executeRaw: async () => 1,
  $transaction: async (fn: any) => fn(fakePrisma),
};

jest.mock('../../src/config/database', () => ({ __esModule: true, default: fakePrisma }));
const pushes: any[] = [];
const adminPushes: any[] = [];
jest.mock('../../src/services/firebase.service.js', () => ({
  sendPushToUser: jest.fn(async (...a: any[]) => { pushes.push(a); }),
  notifyAdmins: jest.fn(async (...a: any[]) => { adminPushes.push(a); }),
}));
jest.mock('../../src/services/socket.service.js', () => ({ getIO: () => null, emitWalletUpdated: jest.fn() }));
jest.mock('../../src/shared/cache.js', () => ({ getCache: () => ({ del: async () => {} }), delByPrefix: async () => {} }));

import * as transport from '../../src/modules/transport/transport.service.js';

const MIN = 60_000;
/** Reserva de hospedaje que empieza hoy: recojo a la hora `pickupInMin` desde ahora. */
function setup(opts: { pickupInMin?: number; status?: string; taxed?: boolean; dropoff?: boolean; pickupFee?: number } = {}) {
  for (const k of ['bookings', 'legs', 'profiles', 'staff', 'clients', 'users', 'wallet', 'notifications']) db[k] = [];
  pushes.length = 0;
  adminPushes.length = 0;
  const now = Date.now();
  const pickupAt = now + (opts.pickupInMin ?? 30) * MIN;
  // Hora Bolivia del recojo y el día (en UTC-4).
  const bo = new Date(pickupAt - 4 * 60 * MIN);
  const hh = `${String(bo.getUTCHours()).padStart(2, '0')}:${String(bo.getUTCMinutes()).padStart(2, '0')}`;
  const startDate = new Date(Date.UTC(bo.getUTCFullYear(), bo.getUTCMonth(), bo.getUTCDate()));
  const endDate = new Date(startDate.getTime() + 2 * 24 * 60 * MIN);
  db.users!.push({ id: 'client', balance: 50, firstName: 'Ana' }, { id: 'cgUser', balance: 0, firstName: 'Luis' }, { id: 'staffUser', balance: 0 });
  db.profiles!.push({ id: 'cp', userId: 'cgUser', isCompany: false, companyName: null });
  db.staff!.push({ id: 'sm1', userId: 'staffUser' });
  const pickupFee = opts.pickupFee ?? 15;
  const pickupTax = opts.taxed ? 2 : 0;
  const dropTax = opts.taxed ? 2 : 0;
  const withDrop = opts.dropoff !== false;
  const transportAmount = pickupFee + (withDrop ? 10 : 0);
  const transportTax = pickupTax + (withDrop ? dropTax : 0);
  db.bookings!.push({
    id: 'b1', clientId: 'client', caregiverId: 'cp', assignedStaffMemberId: 'sm1', status: opts.status ?? 'CONFIRMED',
    serviceType: 'HOSPEDAJE', startDate, endDate, walkDate: null, startTime: null, timeSlot: null, duration: null,
    petName: 'Toby', pausedAt: null, enRouteAt: null, paidAt: new Date(), paymentAutoApprovedAt: null, paymentReviewedAt: null,
    // servicio 300 (comisión 30) + transporte
    totalAmount: 300 + (opts.taxed ? 48 : 0) + transportAmount + transportTax,
    commissionAmount: 30, taxAmount: (opts.taxed ? 48 : 0) + transportTax,
    transportAmount, transportTaxAmount: transportTax, transportRefundAmount: 0,
  });
  db.legs!.push({ id: 'legP', bookingId: 'b1', kind: 'PICKUP', fee: pickupFee, tax: pickupTax, time: hh, status: 'SCHEDULED', addressLat: -17.75, addressLng: -63.18, distanceKm: 3, refundedAmount: 0, address: 'Av. Banzer #123' });
  if (withDrop) db.legs!.push({ id: 'legD', bookingId: 'b1', kind: 'DROPOFF', fee: 10, tax: dropTax, time: '18:00', status: 'SCHEDULED', addressLat: -17.75, addressLng: -63.18, distanceKm: 3, refundedAmount: 0 });
}
const booking = () => db.bookings!.find((b) => b.id === 'b1')!;
const leg = (k: 'PICKUP' | 'DROPOFF') => db.legs!.find((l) => l.kind === k)!;
const balance = (id: string) => db.users!.find((u) => u.id === id)!.balance;
/** Lo del cuidador (caregiverNetOf). */
const caregiverNet = () => booking().totalAmount - booking().commissionAmount - booking().taxAmount;

describe('cancelar un viaje', () => {
  beforeEach(() => setup({ pickupInMin: 24 * 60 }));

  it('el dueño cancela el recojo: se le devuelve exacto y el cuidador ya no lo cobra', async () => {
    expect(caregiverNet()).toBe(295); // 270 + 25 de transporte
    await transport.cancelLeg('b1', { userId: 'client', role: 'CLIENT' }, 'PICKUP', 'Lo llevo yo');
    expect(balance('client')).toBe(65);
    expect(booking()).toMatchObject({ totalAmount: 310, transportAmount: 10, transportRefundAmount: 15 });
    expect(caregiverNet()).toBe(280);
    expect(leg('PICKUP')).toMatchObject({ status: 'CANCELLED', cancelledBy: 'CLIENT', refundedAmount: 15, cancelReason: 'Lo llevo yo' });
    expect(db.wallet).toEqual([expect.objectContaining({ userId: 'client', type: 'REFUND', amount: 15, balance: 65, bookingId: 'b1' })]);
    // avisos: al cuidador titular y al empleado asignado, y al dueño
    const to = db.notifications!.map((n) => n.userId).sort();
    expect(to).toEqual(['cgUser', 'client', 'staffUser']);
  });

  it('con impuestos: devuelve precio + su impuesto, al centavo', async () => {
    setup({ pickupInMin: 24 * 60, taxed: true });
    const before = booking().totalAmount;
    await transport.cancelLeg('b1', { userId: 'client', role: 'CLIENT' }, 'PICKUP');
    expect(balance('client')).toBe(67);
    expect(booking().totalAmount).toBe(before - 17);
    expect(booking().taxAmount).toBe(48 + 2);
    expect(booking().transportTaxAmount).toBe(2);
    await transport.cancelLeg('b1', { userId: 'client', role: 'CLIENT' }, 'DROPOFF');
    expect(balance('client')).toBe(79);
    expect(booking()).toMatchObject({ totalAmount: 348, taxAmount: 48, transportAmount: 0, transportTaxAmount: 0, transportRefundAmount: 29 });
    expect(caregiverNet()).toBe(270); // exactamente lo del servicio
  });

  it('un doble toque no devuelve dos veces', async () => {
    await transport.cancelLeg('b1', { userId: 'client', role: 'CLIENT' }, 'PICKUP');
    await transport.cancelLeg('b1', { userId: 'client', role: 'CLIENT' }, 'PICKUP');
    expect(balance('client')).toBe(65);
    expect(db.wallet).toHaveLength(1);
  });

  it('un viaje gratis se cancela sin mover dinero', async () => {
    setup({ pickupInMin: 24 * 60, pickupFee: 0 });
    await transport.cancelLeg('b1', { userId: 'client', role: 'CLIENT' }, 'PICKUP');
    expect(balance('client')).toBe(50);
    expect(db.wallet).toHaveLength(0);
    expect(leg('PICKUP').status).toBe('CANCELLED');
  });

  it('otro dueño no puede tocar la reserva', async () => {
    await expect(transport.cancelLeg('b1', { userId: 'intruso', role: 'CLIENT' }, 'PICKUP')).rejects.toThrow(/no encontrada/);
    expect(leg('PICKUP').status).toBe('SCHEDULED');
  });

  it('con el cuidador ya en camino el dueño no puede cancelar; el cuidador sí (imprevisto)', async () => {
    leg('PICKUP').status = 'EN_ROUTE';
    await expect(transport.cancelLeg('b1', { userId: 'client', role: 'CLIENT' }, 'PICKUP')).rejects.toThrow(/ya salió/);
    await transport.cancelLeg('b1', { userId: 'cgUser', role: 'CAREGIVER' }, 'PICKUP', 'Se me pinchó la llanta');
    expect(balance('client')).toBe(65);
    expect(adminPushes).toHaveLength(1); // los admins se enteran
    const clientMsg = db.notifications!.find((n) => n.userId === 'client')!;
    expect(clientMsg.message).toMatch(/llévalo tú/);
    expect(clientMsg.message).toMatch(/Se me pinchó la llanta/);
  });

  it('ya llegó o ya se hizo: nadie lo cancela', async () => {
    leg('PICKUP').status = 'ARRIVED';
    await expect(transport.cancelLeg('b1', { userId: 'cgUser', role: 'CAREGIVER' }, 'PICKUP')).rejects.toThrow(/termina el viaje/);
    leg('PICKUP').status = 'DONE';
    await expect(transport.cancelLeg('b1', { userId: 'client', role: 'CLIENT' }, 'PICKUP')).rejects.toThrow(/ya se hizo/);
    expect(balance('client')).toBe(50);
  });

  it.each([
    ['PENDING_PAYMENT', /ya no admite cambios/],
    ['PAYMENT_PENDING_APPROVAL', /verificando el pago/],
    ['COMPLETED', /ya no admite cambios/],
    ['CANCELLED', /ya no admite cambios/],
  ])('reserva en %s: no se puede (ni se devuelve nada)', async (status, msg) => {
    booking().status = status;
    await expect(transport.cancelLeg('b1', { userId: 'client', role: 'CLIENT' }, 'DROPOFF')).rejects.toThrow(msg);
    expect(balance('client')).toBe(50);
  });

  it('pago aprobado solo y sin verificar: espera a que el admin lo confirme', async () => {
    booking().paymentAutoApprovedAt = new Date();
    await expect(transport.cancelLeg('b1', { userId: 'client', role: 'CLIENT' }, 'DROPOFF')).rejects.toThrow(/verificando/);
    booking().paymentReviewedAt = new Date();
    await transport.cancelLeg('b1', { userId: 'client', role: 'CLIENT' }, 'DROPOFF');
    expect(balance('client')).toBe(60);
  });

  it('la entrega se puede cancelar con el servicio en curso (el dueño lo recoge)', async () => {
    booking().status = 'IN_PROGRESS';
    leg('PICKUP').status = 'DONE';
    await transport.cancelLeg('b1', { userId: 'client', role: 'CLIENT' }, 'DROPOFF');
    expect(leg('DROPOFF').status).toBe('CANCELLED');
    await expect(transport.cancelLeg('b1', { userId: 'client', role: 'CLIENT' }, 'PICKUP')).rejects.toThrow(/ya se hizo|empezó/);
  });

  it('el admin puede cancelar por el cuidador que no aparece', async () => {
    await transport.cancelLeg('b1', { userId: 'admin', role: 'ADMIN' }, 'PICKUP', 'El cuidador no respondió');
    expect(leg('PICKUP').cancelledBy).toBe('ADMIN');
    expect(balance('client')).toBe(65);
  });
});

describe('avisos del viaje y ventanas de hora', () => {
  it('no se puede salir a recogerlo con horas de anticipación', async () => {
    setup({ pickupInMin: 5 * 60 });
    await expect(transport.markLegEnRoute('b1', 'cgUser', 'PICKUP')).rejects.toThrow(/Todavía es pronto/);
    expect(leg('PICKUP').status).toBe('SCHEDULED');
  });

  it('en camino → llegué, con un solo aviso aunque toque dos veces', async () => {
    setup({ pickupInMin: 20 });
    await transport.markLegEnRoute('b1', 'cgUser', 'PICKUP');
    await transport.markLegEnRoute('b1', 'cgUser', 'PICKUP');
    expect(leg('PICKUP').status).toBe('EN_ROUTE');
    expect(booking().enRouteAt).toBeInstanceOf(Date);
    await transport.markLegArrived('b1', 'cgUser', 'PICKUP');
    await transport.markLegArrived('b1', 'cgUser', 'PICKUP');
    expect(leg('PICKUP').status).toBe('ARRIVED');
    const toClient = db.notifications!.filter((n) => n.userId === 'client');
    expect(toClient.map((n) => n.title)).toEqual(['🚗 Luis va en camino a recoger a Toby', '📍 Luis llegó a tu casa']);
  });

  it('otro cuidador no puede mover los viajes de esta reserva', async () => {
    setup({ pickupInMin: 20 });
    db.users!.push({ id: 'otro' });
    db.profiles!.push({ id: 'cp2', userId: 'otro' });
    await expect(transport.markLegEnRoute('b1', 'otro', 'PICKUP')).rejects.toThrow(/no encontrada/);
  });

  it('el recojo es antes de iniciar; la entrega, con el servicio en curso', async () => {
    setup({ pickupInMin: 20 });
    await expect(transport.markLegEnRoute('b1', 'cgUser', 'DROPOFF')).rejects.toThrow(/servicio en curso/);
    booking().status = 'IN_PROGRESS';
    await expect(transport.markLegEnRoute('b1', 'cgUser', 'PICKUP')).rejects.toThrow(/antes de iniciar/);
  });

  it('entrega: no puede salir con una emergencia activa, ni "llegar" sin haber salido', async () => {
    setup({ pickupInMin: -600 });
    booking().status = 'IN_PROGRESS';
    leg('PICKUP').status = 'DONE';
    leg('DROPOFF').time = null; // sin hora: no restringe la ventana
    await expect(transport.markLegArrived('b1', 'cgUser', 'DROPOFF')).rejects.toThrow(/Primero marca que saliste/);
    booking().pausedAt = new Date();
    await expect(transport.markLegEnRoute('b1', 'cgUser', 'DROPOFF')).rejects.toThrow(/emergencia/);
    booking().pausedAt = null;
    await transport.markLegEnRoute('b1', 'cgUser', 'DROPOFF');
    await transport.markLegArrived('b1', 'cgUser', 'DROPOFF');
    expect(leg('DROPOFF').status).toBe('ARRIVED');
    expect(db.notifications!.filter((n) => n.userId === 'client').map((n) => n.title)).toEqual([
      '🚗 Toby va de regreso a casa',
      '📍 Toby llegó a casa',
    ]);
  });

  it('un viaje cancelado no se puede retomar', async () => {
    setup({ pickupInMin: 20 });
    leg('PICKUP').status = 'CANCELLED';
    await expect(transport.markLegEnRoute('b1', 'cgUser', 'PICKUP')).rejects.toThrow(/no tiene recojo/);
    await expect(transport.markLegArrived('b1', 'cgUser', 'PICKUP')).rejects.toThrow(/cancelado/);
  });

  it('"ya llegamos" solo después de recogerlo, una vez', async () => {
    setup({ pickupInMin: 20 });
    await expect(transport.markPickupAtBase('b1', 'cgUser')).rejects.toThrow(/Primero marca que recogiste/);
    leg('PICKUP').status = 'DONE';
    leg('PICKUP').doneAt = new Date();
    await transport.markPickupAtBase('b1', 'cgUser');
    await transport.markPickupAtBase('b1', 'cgUser');
    expect(db.notifications!.filter((n) => n.title.includes('ya llegó a el hospedaje'))).toHaveLength(1);
  });
});

describe('GPS durante los viajes', () => {
  it('solo con un viaje en curso', async () => {
    setup({ pickupInMin: 20 });
    await expect(transport.trackLegLocation(booking() as any, -17.7, -63.1)).rejects.toThrow(/No hay un viaje en curso/);
    leg('PICKUP').status = 'EN_ROUTE';
    await expect(transport.trackLegLocation(booking() as any, -17.7, -63.1)).resolves.toBeUndefined();
    // recogido y sin "ya llegamos": sigue en vivo hasta 3 h
    leg('PICKUP').status = 'DONE';
    leg('PICKUP').doneAt = new Date(Date.now() - 2 * 60 * MIN);
    expect(transport.isLegLive(leg('PICKUP') as any)).toBe(true);
    leg('PICKUP').doneAt = new Date(Date.now() - 4 * 60 * MIN);
    expect(transport.isLegLive(leg('PICKUP') as any)).toBe(false);
  });
});

describe('job: recordatorio, atraso y alerta a admins', () => {
  it('recordatorio 1 h antes, una sola vez, al titular y al empleado', async () => {
    setup({ pickupInMin: 40 });
    const r1 = await transport.runTransportMaintenance();
    const r2 = await transport.runTransportMaintenance();
    expect(r1.reminded).toBe(1);
    expect(r2.reminded).toBe(0);
    expect(db.notifications!.map((n) => n.userId).sort()).toEqual(['cgUser', 'staffUser']);
  });

  it('a los 15 min sin salir avisa al cuidador y al dueño; a la hora, a los admins', async () => {
    setup({ pickupInMin: -20 });
    const r = await transport.runTransportMaintenance();
    expect(r.late).toBe(1);
    expect(r.alerted).toBe(0);
    expect(db.notifications!.some((n) => n.userId === 'client' && /retraso/.test(n.title))).toBe(true);
    setup({ pickupInMin: -70 });
    const r2 = await transport.runTransportMaintenance();
    expect(r2.alerted).toBe(1);
    expect(adminPushes).toHaveLength(1);
    expect((await transport.runTransportMaintenance()).alerted).toBe(0);
  });

  it('no molesta por reservas canceladas ni por un recojo con el servicio ya empezado', async () => {
    setup({ pickupInMin: -70 });
    booking().status = 'CANCELLED';
    expect(await transport.runTransportMaintenance()).toEqual({ reminded: 0, late: 0, alerted: 0, closed: 0 });
    setup({ pickupInMin: -70, dropoff: false });
    booking().status = 'IN_PROGRESS';
    expect((await transport.runTransportMaintenance()).late).toBe(0);
  });

  it('cierra solo el mapa del recojo a las 3 h', async () => {
    setup({ pickupInMin: -300 });
    booking().status = 'IN_PROGRESS';
    leg('PICKUP').status = 'DONE';
    leg('PICKUP').doneAt = new Date(Date.now() - 3.5 * 60 * MIN);
    leg('PICKUP').atBaseAt = null;
    leg('DROPOFF').status = 'CANCELLED';
    expect((await transport.runTransportMaintenance()).closed).toBe(1);
    expect(leg('PICKUP').atBaseAt).toBeInstanceOf(Date);
  });
});

describe('ajustes del cuidador', () => {
  beforeEach(() => {
    setup();
    Object.assign(db.profiles![0]!, {
      servicesOffered: ['HOSPEDAJE'], addressLat: -17.78, addressLng: -63.18, address: 'x',
      transportEnabled: false, transportPickupFee: 0, transportDropoffFee: 0, transportMaxKm: 5,
    });
  });

  it('guarda precios y radio', async () => {
    const r = await transport.setMyTransport('cgUser', { enabled: true, pickupFee: 20, dropoffFee: '0', maxKm: 7.25 });
    expect(r).toMatchObject({ enabled: true, pickupFee: 20, dropoffFee: 0, maxKm: 7.3 });
  });

  it.each([
    [{ enabled: 'si', pickupFee: 1, dropoffFee: 1, maxKm: 5 }, /Indica si/],
    [{ enabled: true, pickupFee: -5, dropoffFee: 1, maxKm: 5 }, /negativo/],
    [{ enabled: true, pickupFee: 9.5, dropoffFee: 1, maxKm: 5 }, /enteros/],
    [{ enabled: true, pickupFee: 501, dropoffFee: 1, maxKm: 5 }, /Bs 500/],
    [{ enabled: true, pickupFee: 'abc', dropoffFee: 1, maxKm: 5 }, /Escribe el precio/],
    [{ enabled: true, pickupFee: 1, dropoffFee: null, maxKm: 5 }, /Escribe el precio/],
    [{ enabled: true, pickupFee: 1, dropoffFee: 1, maxKm: 0 }, /de 1 a 30 km/],
    [{ enabled: true, pickupFee: 1, dropoffFee: 1, maxKm: 99 }, /de 1 a 30 km/],
  ])('rechaza datos inválidos %#', async (body, msg) => {
    await expect(transport.setMyTransport('cgUser', body as any)).rejects.toThrow(msg);
    expect(db.profiles![0]!.transportEnabled).toBe(false);
  });

  it('para activarlo hace falta guardería/hospedaje y la ubicación', async () => {
    db.profiles![0]!.servicesOffered = ['PASEO'];
    await expect(transport.setMyTransport('cgUser', { enabled: true, pickupFee: 1, dropoffFee: 1, maxKm: 5 })).rejects.toThrow(/guardería u hospedaje/);
    db.profiles![0]!.servicesOffered = ['GUARDERIA'];
    db.profiles![0]!.addressLat = null;
    await expect(transport.setMyTransport('cgUser', { enabled: true, pickupFee: 1, dropoffFee: 1, maxKm: 5 })).rejects.toThrow(/dirección en el mapa/);
    // desactivarlo siempre se puede
    await expect(transport.setMyTransport('cgUser', { enabled: false, pickupFee: 0, dropoffFee: 0, maxKm: 5 })).resolves.toMatchObject({ enabled: false });
  });

  it('un empleado (sin perfil propio) no puede configurarlo', async () => {
    await expect(transport.getMyTransport('staffUser')).rejects.toThrow(/titular/);
  });
});

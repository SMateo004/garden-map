/**
 * Ciclo completo de Premium contra una base en memoria: compra con QR, "ya pagué",
 * aprobación (también doble/simultánea), rechazo, aprobación automática, "no recibido",
 * quitar con re-encadenado, activación presencial, vencimiento y orden del marketplace.
 * Pensado para usuarios que tocan dos veces, admins que se pisan y datos raros.
 */
type Row = Record<string, any>;
const db: { purchases: Row[]; profiles: Row[]; settings: Row[]; actions: Row[]; notifications: Row[]; users: Row[] } = {
  purchases: [], profiles: [], settings: [], actions: [], notifications: [], users: [],
};
let seq = 0;

function matches(row: Row, where: Row | undefined): boolean {
  if (!where) return true;
  return Object.entries(where).every(([k, cond]) => {
    if (k === 'OR') return (cond as Row[]).some((w) => matches(row, w));
    if (k === 'AND') return (cond as Row[]).every((w) => matches(row, w));
    if (k === 'NOT') return !matches(row, cond as Row);
    const v = row[k];
    if (cond === null) return v === null || v === undefined;
    if (cond instanceof Date) return v instanceof Date && v.getTime() === cond.getTime();
    if (typeof cond === 'object') {
      const c = cond as Row;
      if ('in' in c && !c.in.includes(v)) return false;
      if ('not' in c && (c.not === null ? v === null || v === undefined : v === c.not)) return false;
      const t = v instanceof Date ? v.getTime() : v;
      const cmp = (x: any) => (x instanceof Date ? x.getTime() : x);
      if ('lt' in c && !(v != null && t < cmp(c.lt))) return false;
      if ('lte' in c && !(v != null && t <= cmp(c.lte))) return false;
      if ('gt' in c && !(v != null && t > cmp(c.gt))) return false;
      if ('gte' in c && !(v != null && t >= cmp(c.gte))) return false;
      return true;
    }
    return v === cond;
  });
}
const pick = (r: Row | undefined) => (r ? { ...r } : null);
function sortBy(rows: Row[], orderBy: any): Row[] {
  const list = Array.isArray(orderBy) ? orderBy : orderBy ? [orderBy] : [];
  return [...rows].sort((a, b) => {
    for (const o of list) {
      const [k, dir] = Object.entries(o)[0] as [string, string];
      const av = a[k] instanceof Date ? a[k].getTime() : a[k] ?? 0;
      const bv = b[k] instanceof Date ? b[k].getTime() : b[k] ?? 0;
      if (av !== bv) return (av < bv ? -1 : 1) * (dir === 'desc' ? -1 : 1);
    }
    return 0;
  });
}
function table(name: keyof typeof db) {
  return {
    findUnique: async ({ where }: any) => pick(db[name].find((r) => matches(r, where))),
    findFirst: async ({ where }: any) => pick(db[name].find((r) => matches(r, where))),
    findMany: async ({ where, orderBy, take }: any = {}) =>
      sortBy(db[name].filter((r) => matches(r, where)), orderBy).slice(0, take ?? 1e9).map((r) => ({ ...r })),
    count: async ({ where }: any = {}) => db[name].filter((r) => matches(r, where)).length,
    create: async ({ data }: any) => {
      const row = { id: data.id ?? `id-${++seq}`, createdAt: new Date(), status: 'PENDING_PAYMENT', ...data };
      db[name].push(row);
      return { ...row };
    },
    update: async ({ where, data }: any) => {
      const row = db[name].find((r) => matches(r, where));
      if (!row) throw new Error('not found');
      Object.assign(row, data);
      return { ...row };
    },
    updateMany: async ({ where, data }: any) => {
      const rows = db[name].filter((r) => matches(r, where));
      rows.forEach((r) => Object.assign(r, data));
      return { count: rows.length };
    },
    upsert: async ({ where, create, update }: any) => {
      const row = db[name].find((r) => matches(r, where));
      if (row) Object.assign(row, update);
      else db[name].push({ ...create });
      return {};
    },
    aggregate: async ({ where }: any) => {
      const rows = db[name].filter((r) => matches(r, where));
      return { _sum: { amount: rows.reduce((s, r) => s + Number(r.amount), 0) }, _count: { _all: rows.length } };
    },
  };
}

const fakePrisma: any = {
  premiumPurchase: table('purchases'),
  caregiverProfile: table('profiles'),
  appSettings: table('settings'),
  adminAction: table('actions'),
  notification: table('notifications'),
  user: table('users'),
  $queryRaw: async () => [],
  $transaction: async (arg: any) => (typeof arg === 'function' ? arg(fakePrisma) : Promise.all(arg)),
};

jest.mock('../../src/config/database', () => ({ __esModule: true, get default() { return fakePrisma; } }));
jest.mock('../../src/services/firebase.service', () => ({
  sendPushToUser: jest.fn().mockResolvedValue(undefined),
  notifyAdmins: jest.fn().mockResolvedValue(undefined),
  sendPushToAdmins: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../src/shared/cache', () => ({ getCache: () => ({ del: jest.fn() }), delByPrefix: jest.fn() }));
jest.mock('../../src/utils/settings-cache', () => ({ getNumericSetting: jest.fn().mockResolvedValue(15) }));
jest.mock('../../src/modules/booking-service/booking.service', () => ({
  generateQR: jest.fn(async (id: string, minutes: number) => ({
    qrId: `qr-${id}`, qrImageUrl: 'https://qr/img.png', qrImageType: 'url', qrExpiresAt: new Date(Date.now() + minutes * 60_000),
  })),
}));
jest.mock('../../src/modules/auth/auth.service', () => ({ comparePassword: jest.fn(async (p: string) => p === 'ok') }));
jest.mock('../../src/modules/pricing/pricing.service', () => ({
  invalidatePricingConfig: jest.fn(),
  normalizePayer: (v: unknown) => (v === 'CAREGIVER' ? 'CAREGIVER' : 'CLIENT'),
  getPricingConfig: jest.fn().mockResolvedValue({}),
  resolveCommissionPct: () => 10,
  PRICED_SERVICES: ['PASEO', 'GUARDERIA', 'HOSPEDAJE'],
}));

import * as premium from '../../src/modules/premium/premium.service';

const WEEK = 7 * 24 * 3600 * 1000;
const TABLE = [{ weeks: 1, price: 50 }, { weeks: 4, price: 150 }, { weeks: 52, price: 1400 }];

async function reset(opts: { enabled?: boolean } = {}) {
  db.purchases = []; db.profiles = []; db.settings = []; db.actions = []; db.notifications = []; db.users = [];
  db.profiles.push({ id: 'cp1', userId: 'u1', status: 'APPROVED', suspended: false, premiumUntil: null, commissionPaidBy: 'CLIENT', listingBoost: 0, isCompany: false });
  db.users.push({ id: 'admin', passwordHash: 'h' });
  await premium.updatePremiumSettings({ enabled: opts.enabled ?? true, priceTable: TABLE }, 'admin');
}
const profile = () => db.profiles[0]!;

describe('compra de Premium por QR', () => {
  beforeEach(() => reset());

  it('cotiza con la tabla, crea el QR y guarda el monto del servidor', async () => {
    const p = await premium.startPurchase('u1', 2);
    expect(p).toMatchObject({ weeks: 2, amount: 83, status: 'PENDING_PAYMENT', qrImageUrl: 'https://qr/img.png' });
  });

  it.each([0, -3, 53, 2.5, 'abc', null, undefined, '1e3'])('duración inválida: %p', async (w) => {
    await expect(premium.startPurchase('u1', w)).rejects.toThrow();
    expect(db.purchases).toHaveLength(0);
  });

  it('Premium pausado o perfil no aprobado/suspendido: no se puede comprar', async () => {
    await reset({ enabled: false });
    await expect(premium.startPurchase('u1', 1)).rejects.toThrow(/no está disponible/);
    await reset();
    profile().suspended = true;
    await expect(premium.startPurchase('u1', 1)).rejects.toThrow(/aprobado y activo/);
  });

  it('quien no tiene perfil de cuidador (dueño, empleado) no puede comprar', async () => {
    await expect(premium.startPurchase('otro', 1)).rejects.toThrow(/titular/);
  });

  it('generar otro QR reemplaza el anterior sin pagar', async () => {
    const a = await premium.startPurchase('u1', 1);
    const b = await premium.startPurchase('u1', 4);
    expect(db.purchases.find((p) => p.id === a.id)!.status).toBe('CANCELLED');
    expect(b.amount).toBe(150);
  });

  it('con un pago declarado en revisión no se puede iniciar otro', async () => {
    const a = await premium.startPurchase('u1', 1);
    await premium.declarePayment('u1', a.id);
    await expect(premium.startPurchase('u1', 4)).rejects.toThrow(/revisando/);
  });

  it('"ya pagué" dos veces no duplica nada y no se puede declarar algo cancelado', async () => {
    const a = await premium.startPurchase('u1', 1);
    await premium.declarePayment('u1', a.id);
    const again = await premium.declarePayment('u1', a.id);
    expect(again.status).toBe('PAYMENT_PENDING_APPROVAL');
    const b = db.purchases.find((p) => p.id === a.id)!;
    b.status = 'CANCELLED';
    await expect(premium.declarePayment('u1', a.id)).rejects.toThrow(/ya no está pendiente/);
  });

  it('no se puede declarar ni cancelar la compra de otro cuidador', async () => {
    const a = await premium.startPurchase('u1', 1);
    db.profiles.push({ id: 'cp2', userId: 'u2', status: 'APPROVED', suspended: false, premiumUntil: null, commissionPaidBy: 'CLIENT', listingBoost: 0 });
    await expect(premium.declarePayment('u2', a.id)).rejects.toThrow(/no encontrada/);
    await expect(premium.cancelPurchase('u2', a.id)).rejects.toThrow();
  });

  it('cancelar solo un QR sin pagar', async () => {
    const a = await premium.startPurchase('u1', 1);
    await premium.declarePayment('u1', a.id);
    await expect(premium.cancelPurchase('u1', a.id)).rejects.toThrow(/todavía no pagaste/);
  });
});

describe('aprobación, rechazo y orden del marketplace', () => {
  beforeEach(() => reset());

  it('aprobar activa Premium por las semanas compradas y lo pone primero', async () => {
    const a = await premium.startPurchase('u1', 4);
    await premium.declarePayment('u1', a.id);
    const before = Date.now();
    await premium.approvePurchase(a.id, 'admin');
    const until = profile().premiumUntil.getTime();
    expect(until - before).toBeGreaterThanOrEqual(4 * WEEK - 1000);
    expect(until - before).toBeLessThanOrEqual(4 * WEEK + 5000);
    expect(profile().listingBoost).toBe(2);
    expect(db.notifications.some((n) => n.type === 'PREMIUM_ACTIVE')).toBe(true);
  });

  it('aprobar dos veces (doble clic o dos admins a la vez) activa una sola vez', async () => {
    const a = await premium.startPurchase('u1', 1);
    await premium.declarePayment('u1', a.id);
    const results = await Promise.allSettled([premium.approvePurchase(a.id, 'admin'), premium.approvePurchase(a.id, 'admin')]);
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    const until = profile().premiumUntil.getTime();
    expect(until - Date.now()).toBeLessThanOrEqual(WEEK + 5000);
  });

  it('una segunda compra se encadena después del período vigente', async () => {
    const a = await premium.startPurchase('u1', 1);
    await premium.approvePurchase(a.id, 'admin');
    const firstUntil = profile().premiumUntil.getTime();
    const b = await premium.startPurchase('u1', 4);
    await premium.approvePurchase(b.id, 'admin');
    expect(profile().premiumUntil.getTime()).toBe(firstUntil + 4 * WEEK);
  });

  it('rechazar no activa nada; rechazar algo ya aprobado falla', async () => {
    const a = await premium.startPurchase('u1', 1);
    await premium.declarePayment('u1', a.id);
    await premium.rejectPurchase(a.id, 'admin', 'no llegó');
    expect(profile().premiumUntil).toBeNull();
    const b = await premium.startPurchase('u1', 1);
    await premium.approvePurchase(b.id, 'admin');
    await expect(premium.rejectPurchase(b.id, 'admin', '')).rejects.toThrow(/ya fue procesada/);
  });

  it('quien paga su comisión queda detrás de Premium y delante del resto', async () => {
    await premium.setMyCommissionPayer('u1', 'CAREGIVER');
    expect(profile().listingBoost).toBe(1);
    const a = await premium.startPurchase('u1', 1);
    await premium.approvePurchase(a.id, 'admin');
    expect(profile().listingBoost).toBe(2);
    // Un cambio cada 24 h: no se puede ir y venir para escalar en el listado.
    await expect(premium.setMyCommissionPayer('u1', 'CLIENT')).rejects.toThrow(/24 horas|hora/);
    expect(profile().commissionPaidBy).toBe('CAREGIVER');
    expect((await premium.getMyCommissionPayer('u1')).nextChangeAt).not.toBeNull();
    profile().commissionPaidByChangedAt = new Date(Date.now() - 25 * 3600 * 1000);
    await premium.setMyCommissionPayer('u1', 'CLIENT');
    expect(profile().listingBoost).toBe(2); // sigue siendo Premium
    await expect(premium.setMyCommissionPayer('u1', 'cualquiera')).rejects.toThrow();
  });

  it('elegir lo mismo que ya tiene no gasta el cambio del día', async () => {
    await premium.setMyCommissionPayer('u1', 'CLIENT');
    expect(profile().commissionPaidByChangedAt ?? null).toBeNull();
    await premium.setMyCommissionPayer('u1', 'CAREGIVER');
    expect(profile().listingBoost).toBe(1);
  });

  it('el banco confirma un QR que se había reemplazado: se activa igual (pagó)', async () => {
    const a = await premium.startPurchase('u1', 1);
    const b = await premium.startPurchase('u1', 4); // cambió de idea; A queda CANCELLED
    expect(db.purchases.find((p) => p.id === a.id)!.status).toBe('CANCELLED');
    expect(await premium.confirmByBank(a.id)).toBe(true);
    expect(db.purchases.find((p) => p.id === a.id)!.status).toBe('PAID');
    expect(profile().listingBoost).toBe(2);
    // y si después paga también B, se encadena (pagó las dos)
    await premium.confirmByBank(b.id);
    const until = profile().premiumUntil.getTime();
    expect(until).toBeGreaterThan(Date.now() + 4.9 * WEEK);
    // una repetición del aviso del banco no suma tiempo
    await premium.confirmByBank(b.id);
    expect(profile().premiumUntil.getTime()).toBe(until);
    expect(await premium.confirmByBank('no-existe')).toBe(false);
  });

  it('el banco no reactiva una compra que el admin quitó', async () => {
    const a = await premium.startPurchase('u1', 1);
    await premium.approvePurchase(a.id, 'admin');
    await premium.revokePurchase(a.id, 'admin', { reason: 'cargado por error', adminPassword: 'ok' });
    await premium.confirmByBank(a.id);
    expect(db.purchases.find((p) => p.id === a.id)!.status).toBe('REVOKED');
    expect(profile().premiumUntil).toBeNull();
  });
});

describe('aprobación automática, no recibido y quitar', () => {
  beforeEach(() => reset());

  it('declarado sin revisión al vencer el QR se aprueba solo; "no recibido" lo quita', async () => {
    const a = await premium.startPurchase('u1', 1);
    await premium.declarePayment('u1', a.id);
    db.purchases.find((p) => p.id === a.id)!.qrExpiresAt = new Date(Date.now() - 1000);
    const r = await premium.runPremiumMaintenance();
    expect(r.autoApproved).toBe(1);
    expect(profile().listingBoost).toBe(2);
    expect(await premium.countPurchasesNeedingAdmin()).toBe(1);
    await premium.reviewAutoApproved(a.id, 'admin', 'NOT_RECEIVED');
    expect(profile().premiumUntil).toBeNull();
    expect(profile().listingBoost).toBe(0);
    expect(db.purchases.find((p) => p.id === a.id)!.status).toBe('REVOKED');
    await expect(premium.reviewAutoApproved(a.id, 'admin', 'CONFIRMED')).rejects.toThrow();
    // Quien declaró un pago que no llegó ya no compra por QR (solo con un admin).
    await expect(premium.startPurchase('u1', 1)).rejects.toThrow(/soporte/);
    const r2 = await premium.activateManually('cp1', 'admin', { weeks: 1, paymentKind: 'CASH', adminPassword: 'ok' });
    expect(r2.success).toBe(true);
  });

  it('no se encadena Premium "fiado": con una aprobada sola sin verificar no compra otra', async () => {
    const a = await premium.startPurchase('u1', 1);
    await premium.declarePayment('u1', a.id);
    db.purchases.find((p) => p.id === a.id)!.qrExpiresAt = new Date(Date.now() - 1000);
    await premium.runPremiumMaintenance();
    await expect(premium.startPurchase('u1', 4)).rejects.toThrow(/verificando/);
    await premium.reviewAutoApproved(a.id, 'admin', 'CONFIRMED');
    await expect(premium.startPurchase('u1', 4)).resolves.toMatchObject({ weeks: 4 });
  });

  it('QR sin "ya pagué" vence (con margen) y queda EXPIRED', async () => {
    const a = await premium.startPurchase('u1', 1);
    db.purchases.find((p) => p.id === a.id)!.qrExpiresAt = new Date(Date.now() - 31 * 60 * 1000);
    const r = await premium.runPremiumMaintenance();
    expect(r.expired).toBe(1);
    expect(profile().premiumUntil).toBeNull();
  });

  it('quitar una compra del medio corre las siguientes hacia adelante', async () => {
    const a = await premium.startPurchase('u1', 1);
    await premium.approvePurchase(a.id, 'admin');
    const b = await premium.startPurchase('u1', 4);
    await premium.approvePurchase(b.id, 'admin');
    const fullUntil = profile().premiumUntil.getTime();
    await premium.revokePurchase(a.id, 'admin', { reason: 'cargado por error', adminPassword: 'ok' });
    // B ya no espera a A: arranca cuando se pagó (nunca antes) y dura sus 4 semanas.
    const rowB = db.purchases.find((p) => p.id === b.id)!;
    expect(rowB.activatedFrom.getTime()).toBe(rowB.paidAt.getTime());
    expect(rowB.activatedUntil.getTime()).toBe(rowB.paidAt.getTime() + 4 * WEEK);
    expect(profile().premiumUntil.getTime()).toBe(rowB.activatedUntil.getTime());
    expect(profile().premiumUntil.getTime()).toBeLessThanOrEqual(fullUntil - WEEK + 1000);
    await expect(premium.revokePurchase(b.id, 'admin', { reason: 'x', adminPassword: 'ok' })).rejects.toThrow(/motivo/);
    await expect(premium.revokePurchase(b.id, 'admin', { reason: 'cargado por error', adminPassword: 'mal' })).rejects.toThrow(/incorrecta/);
  });

  it('al vencer baja en el marketplace y avisa una vez', async () => {
    const a = await premium.startPurchase('u1', 1);
    await premium.approvePurchase(a.id, 'admin');
    profile().premiumUntil = new Date(Date.now() - 1000);
    const r1 = await premium.runPremiumMaintenance();
    const r2 = await premium.runPremiumMaintenance();
    expect(r1.ended).toBe(1);
    expect(r2.ended).toBe(0);
    expect(profile().listingBoost).toBe(0);
    expect(db.notifications.filter((n) => n.type === 'PREMIUM_EXPIRED')).toHaveLength(1);
  });

  it('al vencer, si paga su comisión, vuelve al segundo grupo (no al último)', async () => {
    await premium.setMyCommissionPayer('u1', 'CAREGIVER');
    const a = await premium.startPurchase('u1', 1);
    await premium.approvePurchase(a.id, 'admin');
    profile().premiumUntil = new Date(Date.now() - 1000);
    expect((await premium.runPremiumMaintenance()).ended).toBe(1);
    expect(profile().listingBoost).toBe(1);
  });

  it('aviso 3 días antes, una sola vez', async () => {
    const a = await premium.startPurchase('u1', 1);
    await premium.approvePurchase(a.id, 'admin');
    profile().premiumUntil = new Date(Date.now() + 2 * 24 * 3600 * 1000);
    expect((await premium.runPremiumMaintenance()).reminded).toBe(1);
    expect((await premium.runPremiumMaintenance()).reminded).toBe(0);
  });
});

describe('activación presencial del admin', () => {
  beforeEach(() => reset());

  it('cobra el precio de la tabla y activa al instante', async () => {
    const r = await premium.activateManually('cp1', 'admin', { weeks: 4, paymentKind: 'CASH', note: 'pagó en oficina', adminPassword: 'ok' });
    expect(r.amount).toBe(150);
    expect(profile().listingBoost).toBe(2);
    expect(db.purchases[0]).toMatchObject({ method: 'ADMIN', manualPaymentKind: 'CASH', status: 'PAID' });
  });

  it('un doble toque no registra (ni cobra) dos veces', async () => {
    const input = { weeks: 4, paymentKind: 'CASH', adminPassword: 'ok' };
    await premium.activateManually('cp1', 'admin', input);
    const until = profile().premiumUntil.getTime();
    await expect(premium.activateManually('cp1', 'admin', input)).rejects.toThrow(/hace un momento/);
    expect(db.purchases).toHaveLength(1);
    expect(profile().premiumUntil.getTime()).toBe(until);
  });

  it.each([
    [{ weeks: 4, paymentKind: 'CASH', adminPassword: 'mal' }, /incorrecta/],
    [{ weeks: 4, paymentKind: 'CASH' }, /contraseña/],
    [{ weeks: 4, paymentKind: 'BITCOIN', adminPassword: 'ok' }, /cómo pagó/],
    [{ weeks: 60, paymentKind: 'CASH', adminPassword: 'ok' }, /máxima/],
  ])('rechaza datos inválidos %#', async (input, msg) => {
    await expect(premium.activateManually('cp1', 'admin', input as any)).rejects.toThrow(msg);
    expect(profile().premiumUntil).toBeNull();
  });
});

describe('ajustes del admin', () => {
  beforeEach(() => reset());

  it('una tabla inválida no se guarda y la vigente sigue igual', async () => {
    await expect(
      premium.updatePremiumSettings({ enabled: true, priceTable: [{ weeks: 1, price: 50 }, { weeks: 4, price: 10 }] }, 'admin')
    ).rejects.toThrow(/no puede costar menos/);
    expect((await premium.getPremiumSettings()).priceTable).toEqual(TABLE);
    await expect(premium.updatePremiumSettings({ enabled: 'si', priceTable: TABLE }, 'admin')).rejects.toThrow();
  });
});

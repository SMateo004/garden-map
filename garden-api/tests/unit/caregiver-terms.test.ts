/**
 * Aceptación periódica de los Términos del Cuidador (cada 2 meses) y coherencia de los textos legales.
 */
import { readFileSync } from 'fs';
import { join } from 'path';

const mockAuditCreate = jest.fn();
const mockProfileUpdate = jest.fn();
const mockProfileFind = jest.fn();
const mockAuditFindMany = jest.fn();
const mockProfileFindMany = jest.fn();
const mockNotificationCreate = jest.fn();
const mockNotificationFindFirst = jest.fn();
const mockPush = jest.fn();

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    caregiverProfile: {
      findUnique: (...a: unknown[]) => mockProfileFind(...a),
      update: (...a: unknown[]) => mockProfileUpdate(...a),
      findMany: (...a: unknown[]) => mockProfileFindMany(...a),
    },
    notification: {
      create: (...a: unknown[]) => mockNotificationCreate(...a),
      findFirst: (...a: unknown[]) => mockNotificationFindFirst(...a),
    },
    auditLog: {
      create: (...a: unknown[]) => mockAuditCreate(...a),
      findMany: (...a: unknown[]) => mockAuditFindMany(...a),
    },
    $transaction: jest.fn(async (ops: Promise<unknown>[]) => Promise.all(ops)),
  },
}));

jest.mock('../../src/services/firebase.service', () => ({
  sendPushToUser: (...a: unknown[]) => mockPush(...a),
}));

const mockDelByPrefix = jest.fn();
const mockCacheDel = jest.fn();
jest.mock('../../src/shared/cache', () => ({
  getCache: () => ({ del: (...a: unknown[]) => mockCacheDel(...a) }),
  delByPrefix: (...a: unknown[]) => mockDelByPrefix(...a),
}));

import {
  CAREGIVER_TERMS_EFFECTIVE_AT,
  CAREGIVER_TERMS_VERSION,
  TERMS_RENEWAL_DAYS,
  TERMS_VERSION_GRACE_DAYS,
  computeTermsStatus,
  getTermsStatusForUser,
  isTermsExemptEmail,
  listTermsAcceptances,
  recordCaregiverTermsAcceptance,
  renewalCutoff,
  termsEnforcementFrom,
  termsGateWhere,
} from '../../src/modules/legal/caregiver-terms.service';
import { buildTermsNotification, enviarRecordatoriosTerminos } from '../../src/jobs/terms-renewal.job';

const DAY = 24 * 60 * 60 * 1000;
/** Una fecha lo bastante posterior a la vigencia (60 días + gracia + margen) como para que toda aceptación simulada
 *  de hasta 60 días atrás sea posterior a la versión actual: así se prueba SOLO el vencimiento de 60 días. */
const AFTER_GRACE = new Date(CAREGIVER_TERMS_EFFECTIVE_AT.getTime() + (TERMS_RENEWAL_DAYS + TERMS_VERSION_GRACE_DAYS + 30) * DAY);
const ago = (now: Date, days: number) => new Date(now.getTime() - days * DAY);

describe('computeTermsStatus — vencimiento cada 2 meses', () => {
  it('nunca aceptó: debe aceptar y está bloqueado', () => {
    const s = computeTermsStatus(null, AFTER_GRACE);
    expect(s).toMatchObject({ required: true, blocked: true, reason: 'NEVER' });
  });

  it('aceptó hace 10 días: al día, sin recordatorio', () => {
    const s = computeTermsStatus(ago(AFTER_GRACE, 10), AFTER_GRACE);
    expect(s).toMatchObject({ required: false, blocked: false, reason: null, reminderDue: false, daysLeft: 50 });
  });

  it('a 7 días o menos del vencimiento: recordatorio, todavía no bloqueado', () => {
    const s = computeTermsStatus(ago(AFTER_GRACE, TERMS_RENEWAL_DAYS - 5), AFTER_GRACE);
    expect(s).toMatchObject({ required: false, blocked: false, reminderDue: true, daysLeft: 5 });
  });

  it('a los 60 días exactos vence y bloquea (haya trabajado o no)', () => {
    const s = computeTermsStatus(ago(AFTER_GRACE, TERMS_RENEWAL_DAYS), AFTER_GRACE);
    expect(s).toMatchObject({ required: true, blocked: true, reason: 'EXPIRED', daysLeft: 0 });
  });

  it('a los 59 días todavía no vence', () => {
    expect(computeTermsStatus(ago(AFTER_GRACE, 59), AFTER_GRACE).blocked).toBe(false);
  });

  it('versión nueva: pide aceptar pero NO bloquea durante la gracia de 7 días', () => {
    const now = new Date(CAREGIVER_TERMS_EFFECTIVE_AT.getTime() + 2 * DAY);
    const s = computeTermsStatus(ago(CAREGIVER_TERMS_EFFECTIVE_AT, 5), now);
    expect(s).toMatchObject({ required: true, blocked: false, reason: 'NEW_VERSION' });
  });

  it('versión nueva: pasada la gracia, bloquea', () => {
    const now = new Date(CAREGIVER_TERMS_EFFECTIVE_AT.getTime() + (TERMS_VERSION_GRACE_DAYS + 1) * DAY);
    const s = computeTermsStatus(ago(CAREGIVER_TERMS_EFFECTIVE_AT, 5), now);
    expect(s).toMatchObject({ required: true, blocked: true, reason: 'NEW_VERSION' });
  });

  it('quien aceptó después de la vigencia de la versión no queda marcado como versión nueva', () => {
    const now = new Date(CAREGIVER_TERMS_EFFECTIVE_AT.getTime() + 3 * DAY);
    const s = computeTermsStatus(new Date(CAREGIVER_TERMS_EFFECTIVE_AT.getTime() + DAY), now);
    expect(s.required).toBe(false);
  });
});

describe('termsEnforcementFrom — corte usado en marketplace y reservas', () => {
  it('es el corte de 60 días mientras dura la gracia de una versión nueva', () => {
    const now = new Date(CAREGIVER_TERMS_EFFECTIVE_AT.getTime() + 2 * DAY);
    expect(termsEnforcementFrom(now).getTime()).toBe(renewalCutoff(now).getTime());
  });

  it('pasada la gracia, exige haber aceptado la versión vigente (si el corte de 60 días es más viejo)', () => {
    const now = new Date(CAREGIVER_TERMS_EFFECTIVE_AT.getTime() + (TERMS_VERSION_GRACE_DAYS + 1) * DAY);
    expect(termsEnforcementFrom(now).getTime()).toBe(CAREGIVER_TERMS_EFFECTIVE_AT.getTime());
  });

  it('mucho después, manda el corte de 60 días (más reciente que la vigencia)', () => {
    expect(termsEnforcementFrom(AFTER_GRACE).getTime()).toBe(renewalCutoff(AFTER_GRACE).getTime());
  });
});

describe('recordCaregiverTermsAcceptance — evidencia legal', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockProfileFind.mockResolvedValue({ id: 'prof-1' });
    mockAuditCreate.mockImplementation(async (a: unknown) => a);
    mockProfileUpdate.mockImplementation(async (a: unknown) => a);
  });

  it('guarda versión, fecha, IP y dispositivo en el historial y actualiza la fecha vigente', async () => {
    const status = await recordCaregiverTermsAcceptance('user-1', { source: 'PERIODIC', ip: '190.1.2.3', userAgent: 'Garden/1.0 (Android)' });

    const audit = mockAuditCreate.mock.calls[0]![0].data;
    expect(audit).toMatchObject({ userId: 'user-1', action: 'CAREGIVER_TERMS_ACCEPTED', entity: 'CaregiverProfile', entityId: 'prof-1', ip: '190.1.2.3' });
    const details = JSON.parse(audit.details);
    expect(details).toMatchObject({ version: CAREGIVER_TERMS_VERSION, source: 'PERIODIC', userAgent: 'Garden/1.0 (Android)' });
    expect(details.documents).toEqual(['TERMS', 'PRIVACY', 'CAREGIVER_CONTRACT']);

    const upd = mockProfileUpdate.mock.calls[0]![0];
    expect(upd.where).toEqual({ id: 'prof-1' });
    expect(upd.data.termsAcceptedAt).toBeInstanceOf(Date);
    expect(upd.data).toMatchObject({ termsAccepted: true, privacyAccepted: true });

    expect(status).toMatchObject({ required: false, blocked: false });
    // el perfil vuelve al marketplace al instante
    expect(mockDelByPrefix).toHaveBeenCalledWith('caregivers:list:');
    expect(mockCacheDel).toHaveBeenCalledWith('caregivers:detail:prof-1');
  });

  it('sin perfil de cuidador no registra nada', async () => {
    mockProfileFind.mockResolvedValue(null);
    await expect(recordCaregiverTermsAcceptance('x', { source: 'PERIODIC' })).rejects.toThrow(/no encontrado/i);
    expect(mockAuditCreate).not.toHaveBeenCalled();
  });

  it('si no se puede guardar la evidencia, la aceptación NO vale (el error se propaga)', async () => {
    mockAuditCreate.mockRejectedValue(new Error('db caída'));
    await expect(recordCaregiverTermsAcceptance('user-1', { source: 'PERIODIC' })).rejects.toThrow('db caída');
  });

  it('recorta IP y user-agent a los largos de la columna', async () => {
    await recordCaregiverTermsAcceptance('user-1', { source: 'REGISTRATION', ip: 'x'.repeat(80), userAgent: 'u'.repeat(900) });
    const audit = mockAuditCreate.mock.calls[0]![0].data;
    expect(audit.ip.length).toBe(45);
    expect(JSON.parse(audit.details).userAgent.length).toBe(300);
  });
});

describe('listTermsAcceptances — solo admin', () => {
  it('parsea el historial y tolera detalles corruptos', async () => {
    mockAuditFindMany.mockResolvedValue([
      { details: JSON.stringify({ version: '2026-10-05', source: 'PERIODIC', acceptedAt: '2026-10-05T10:00:00.000Z', userAgent: 'ua' }), ip: '1.1.1.1', createdAt: new Date('2026-10-05T10:00:01Z') },
      { details: '{no es json', ip: null, createdAt: new Date('2026-08-01T00:00:00Z') },
    ]);
    const rows = await listTermsAcceptances('prof-1');
    expect(rows[0]).toMatchObject({ version: '2026-10-05', source: 'PERIODIC', ip: '1.1.1.1', userAgent: 'ua' });
    expect(rows[1]).toMatchObject({ version: null, source: null, acceptedAt: '2026-08-01T00:00:00.000Z' });
    expect(mockAuditFindMany.mock.calls[0]![0].where).toMatchObject({ action: 'CAREGIVER_TERMS_ACCEPTED', entityId: 'prof-1' });
  });
});


describe('excepción para las cuentas de prueba de las tiendas (reviewer.*)', () => {
  it.each([
    ['reviewer.cuidador@gardenbo.com', true],
    ['reviewer.admin@gardenbo.com', true],
    ['reviewer.cliente@gardenbo.com', true],
    ['  REVIEWER.Cuidador@GardenBo.com ', true],
    ['reviewer.cuidador@gmail.com', false],
    ['reviewer@gardenbo.com', false],
    ['reviewer.@gardenbo.com', false],
    ['xreviewer.cuidador@gardenbo.com', false],
    ['reviewer.cuidador@gardenbo.com.evil.com', false],
    ['reviewer.cuidador@evilgardenbo.com', false],
    ['sai@gardenbo.com', false],
    ['', false],
    [null, false],
    [undefined, false],
  ])('isTermsExemptEmail(%p) → %p', (email, expected) => {
    expect(isTermsExemptEmail(email as string | null | undefined)).toBe(expected);
  });

  it('una cuenta exenta nunca queda requerida ni bloqueada, aunque jamás haya aceptado o esté vencida', () => {
    expect(computeTermsStatus(null, AFTER_GRACE, { exempt: true })).toMatchObject({ exempt: true, required: false, blocked: false, reason: null });
    expect(computeTermsStatus(ago(AFTER_GRACE, 200), AFTER_GRACE, { exempt: true })).toMatchObject({ required: false, blocked: false, reminderDue: false });
  });

  it('una cuenta normal sigue exigiéndose igual', () => {
    expect(computeTermsStatus(null, AFTER_GRACE, { exempt: false })).toMatchObject({ exempt: false, required: true, blocked: true });
    expect(computeTermsStatus(null, AFTER_GRACE)).toMatchObject({ exempt: false, required: true, blocked: true });
  });

  it('getTermsStatusForUser aplica la excepción según el correo del usuario', async () => {
    mockProfileFind.mockResolvedValue({ termsAcceptedAt: null, user: { email: 'reviewer.cuidador@gardenbo.com' } });
    expect(await getTermsStatusForUser('u1')).toMatchObject({ exempt: true, required: false, blocked: false });

    mockProfileFind.mockResolvedValue({ termsAcceptedAt: null, user: { email: 'otra@persona.com' } });
    expect(await getTermsStatusForUser('u2')).toMatchObject({ exempt: false, required: true, blocked: true });
  });

  it('termsGateWhere deja pasar por aceptación vigente O por correo reviewer.*@gardenbo.com', () => {
    const where = termsGateWhere(AFTER_GRACE) as { OR: Array<Record<string, any>> };
    expect(where.OR).toHaveLength(2);
    expect(where.OR[0]!.termsAcceptedAt.gte).toEqual(termsEnforcementFrom(AFTER_GRACE));
    expect(where.OR[1]!.user.email).toMatchObject({ startsWith: 'reviewer.', endsWith: '@gardenbo.com', mode: 'insensitive' });
  });

  it('el job de avisos no le escribe a una cuenta exenta, pero sí a una normal vencida', async () => {
    jest.clearAllMocks();
    mockNotificationFindFirst.mockResolvedValue(null);
    mockNotificationCreate.mockResolvedValue({});
    mockPush.mockResolvedValue(undefined);
    mockProfileFindMany.mockResolvedValue([
      { id: 'p-rev', userId: 'u-rev', termsAcceptedAt: null, user: { email: 'reviewer.cuidador@gardenbo.com' } },
      { id: 'p-x', userId: 'u-x', termsAcceptedAt: ago(AFTER_GRACE, 90), user: { email: 'cuidador@real.com' } },
    ]);
    const sent = await enviarRecordatoriosTerminos(AFTER_GRACE);
    expect(sent).toBe(1);
    expect(mockNotificationCreate).toHaveBeenCalledTimes(1);
    expect(mockNotificationCreate.mock.calls[0]![0].data.userId).toBe('u-x');
  });
});

describe('avisos del job de renovación', () => {
  it('vencido: avisa que el perfil está oculto', () => {
    const n = buildTermsNotification(computeTermsStatus(ago(AFTER_GRACE, 70), AFTER_GRACE));
    expect(n?.title).toMatch(/Acepta los Términos/);
  });

  it('por vencer: dice cuántos días faltan', () => {
    const n = buildTermsNotification(computeTermsStatus(ago(AFTER_GRACE, 57), AFTER_GRACE));
    expect(n?.message).toMatch(/3 días/);
  });

  it('al día: no avisa', () => {
    expect(buildTermsNotification(computeTermsStatus(ago(AFTER_GRACE, 5), AFTER_GRACE))).toBeNull();
  });
});

// ── Coherencia de los textos legales (app ↔ página pública ↔ backend) ────────────────────────
const REPO = join(__dirname, '..', '..', '..');
const read = (rel: string) => readFileSync(join(REPO, rel), 'utf-8');

describe('textos legales coherentes', () => {
  const dart = read('garden-app/lib/screens/legal/legal_screen.dart');
  const ts = read('garden-api/src/modules/legal/legal.routes.ts');
  const termsDart = dart.slice(dart.indexOf('class TermsOfServiceScreen'));
  const termsTs = ts.slice(ts.indexOf('const SECTIONS_TERMS'));

  const titles = (src: string, re: RegExp) => [...src.matchAll(re)].map((m) => m[1]!);
  const dartTitles = titles(termsDart, /_LegalSection\(\s*'(\d+\. [^']+)'/g);
  const tsTitles = titles(termsTs, /title: '(\d+\. [^']+)'/g);

  it('la app y la página pública tienen las mismas secciones en el mismo orden', () => {
    expect(dartTitles.length).toBeGreaterThanOrEqual(34);
    expect(tsTitles).toEqual(dartTitles);
  });

  it('las secciones están numeradas sin saltos (1..N)', () => {
    dartTitles.forEach((t, i) => expect(t.startsWith(`${i + 1}. `)).toBe(true));
  });

  it.each([
    'participa en Garden de forma estrictamente VOLUNTARIA',
    'CUSTODIA EXCLUSIVA',
    'RESPONSABILIDAD PRESUMIDA',
    'mantener INDEMNE a Garden',
    'CADA 2 MESES',
    'no es un seguro',
  ])('ambos espejos incluyen: %s', (fragment) => {
    expect(termsDart).toContain(fragment);
    expect(termsTs).toContain(fragment);
  });

  it('ninguna referencia "sección N" apunta a una sección que no existe', () => {
    const max = dartTitles.length;
    for (const src of [termsDart, termsTs]) {
      for (const m of src.matchAll(/[sS]ecci(?:ón|ones) (\d+)(?: y (\d+))?/g)) {
        for (const n of [m[1], m[2]].filter(Boolean).map(Number)) {
          expect(n).toBeGreaterThanOrEqual(1);
          expect(n).toBeLessThanOrEqual(max);
        }
      }
    }
  });

  it('el contrato del cuidador (app) usa la misma versión que el backend', () => {
    const contract = read('garden-app/lib/screens/caregiver/caregiver_contract_content.dart');
    const v = /const String caregiverTermsVersion = '([^']+)'/.exec(contract)?.[1];
    expect(v).toBe(CAREGIVER_TERMS_VERSION);
  });

  it('el contrato no vuelve a presentar al cuidador como empleado ni obliga a usar uniforme', () => {
    const contract = read('garden-app/lib/screens/caregiver/caregiver_contract_content.dart');
    expect(contract).not.toMatch(/te pedimos usar la polera/i);
    expect(contract).toMatch(/VOLUNTARIA/);
    expect(contract).toMatch(/CADA 2 MESES/);
    expect(contract).toMatch(/INDEMNE/);
  });
});

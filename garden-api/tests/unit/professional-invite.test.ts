/**
 * Registro profesional por invitación: un código por persona, un solo uso, y la cuenta
 * NO nace aprobada — tiene que pasar identidad (IA), teléfono y correo.
 */
import prisma from '../../src/config/database';
import {
  createInvite,
  findValidInvite,
  consumeInvite,
  hashInviteCode,
  inviteStatus,
  inviteKindOfLabel,
  listInvites,
} from '../../src/modules/auth/professional-invite.service';
import { registerProfessional, registerCompany, validateProfessionalCode, validateCompanyCode } from '../../src/modules/auth/auth.service';
import { getMissingRequiredFieldsForProfessionalSubmit } from '../../src/modules/caregiver-profile/caregiver-profile.validation';

const invites: Record<string, any> = {};
const txMock = {
  user: { create: jest.fn() },
  caregiverProfile: { create: jest.fn() },
  professionalInvite: { updateMany: jest.fn() },
};

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    professionalInvite: { create: jest.fn(), findUnique: jest.fn(), findMany: jest.fn(), update: jest.fn() },
    adminAction: { create: jest.fn() },
    user: { findUnique: jest.fn().mockResolvedValue(null) },
    refreshToken: { create: jest.fn().mockResolvedValue({ id: 'rt' }) },
    $transaction: jest.fn((fn: any) => fn(txMock)),
  },
}));
jest.mock('../../src/shared/analytics', () => ({ track: jest.fn(), identify: jest.fn() }));
jest.mock('../../src/services/blockchain.service', () => ({
  blockchainService: { syncProfileOnChain: jest.fn().mockResolvedValue(null) },
}));
jest.mock('bcrypt', () => ({ hash: jest.fn(async (p: string) => `h_${p}`), compare: jest.fn() }));

const p = prisma as any;
const future = () => new Date(Date.now() + 86_400_000);

describe('professional-invite.service', () => {
  beforeEach(() => jest.clearAllMocks());

  it('el hash ignora mayúsculas y espacios', () => {
    expect(hashInviteCode(' gp-abcd-efgh ')).toBe(hashInviteCode('GP-ABCD-EFGH'));
  });

  it('createInvite guarda solo el hash y devuelve el código una vez', async () => {
    p.professionalInvite.create.mockImplementation(async ({ data }: any) => ({ id: 'i1', ...data }));
    const res = await createInvite('admin1', 'Dr. Pérez', 7);
    expect(res.code).toMatch(/^GP-[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    const saved = p.professionalInvite.create.mock.calls[0][0].data;
    expect(saved.codeHash).toBe(hashInviteCode(res.code));
    expect(JSON.stringify(saved)).not.toContain(res.code);
  });

  it('createInvite exige una etiqueta', async () => {
    await expect(createInvite('admin1', '   ')).rejects.toThrow(/para quién/);
  });

  it.each([
    ['usada', { usedAt: new Date(), revokedAt: null, expiresAt: future() }, 'USED'],
    ['revocada', { usedAt: null, revokedAt: new Date(), expiresAt: future() }, 'REVOKED'],
    ['vencida', { usedAt: null, revokedAt: null, expiresAt: new Date(Date.now() - 1000) }, 'EXPIRED'],
    ['vigente', { usedAt: null, revokedAt: null, expiresAt: future() }, 'ACTIVE'],
  ])('invitación %s → %s', async (_n, row, status) => {
    expect(inviteStatus(row as any)).toBe(status);
    p.professionalInvite.findUnique.mockResolvedValue({ id: 'i', ...row });
    const found = await findValidInvite('GP-AAAA-BBBB');
    expect(found !== null).toBe(status === 'ACTIVE');
  });

  it('un código inexistente (p. ej. el viejo código compartido) no valida', async () => {
    p.professionalInvite.findUnique.mockResolvedValue(null);
    expect(await validateProfessionalCode('codigo-compartido')).toBe(false);
  });

  it('consumeInvite aborta si otro registro ya la usó (count 0)', async () => {
    txMock.professionalInvite.updateMany.mockResolvedValue({ count: 0 });
    await expect(consumeInvite(txMock as any, 'i1', 'u1')).rejects.toThrow(/inválido/);
  });
});

describe('registerProfessional', () => {
  const body = {
    code: 'GP-AAAA-BBBB', email: 'Pro@Test.com', password: 'Passw0rd!x', firstName: 'Ana', lastName: 'Rojas', phone: '71234567',
  } as any;

  beforeEach(() => {
    jest.clearAllMocks();
    p.professionalInvite.findUnique.mockResolvedValue({ id: 'i1', usedAt: null, revokedAt: null, expiresAt: future() });
    txMock.professionalInvite.updateMany.mockResolvedValue({ count: 1 });
    txMock.user.create.mockResolvedValue({ id: 'u1', email: 'pro@test.com', role: 'CAREGIVER', firstName: 'Ana', lastName: 'Rojas', profilePicture: null });
    txMock.caregiverProfile.create.mockImplementation(async ({ data }: any) => ({ id: 'p1', ...data }));
  });

  it('crea la cuenta SIN aprobación: identidad pendiente, sin verificar y fuera del marketplace', async () => {
    await registerProfessional(body);
    const data = txMock.caregiverProfile.create.mock.calls[0][0].data;
    expect(data.status).toBe('DRAFT');
    expect(data.verified).toBe(false);
    expect(data.identityVerificationStatus).toBe('PENDING');
    expect(data.emailVerified).toBe(false);
    expect(data.phoneVerified).toBe(false);
    expect(data.isProfessional).toBe(true);
  });

  it('consume la invitación con el id del usuario creado', async () => {
    await registerProfessional(body);
    expect(txMock.professionalInvite.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ usedByUserId: 'u1' }) }),
    );
  });

  it('con una invitación ya usada en carrera (count 0) falla y no devuelve tokens', async () => {
    txMock.professionalInvite.updateMany.mockResolvedValue({ count: 0 });
    await expect(registerProfessional(body)).rejects.toThrow(/inválido/);
    expect(txMock.caregiverProfile.create).not.toHaveBeenCalled();
  });

  it('con código inválido no crea nada', async () => {
    p.professionalInvite.findUnique.mockResolvedValue(null);
    await expect(registerProfessional(body)).rejects.toThrow(/inválido/);
    expect(txMock.user.create).not.toHaveBeenCalled();
  });
});

describe('aprobación del profesional', () => {
  const ok = {
    bio: 'Paseador con 8 años de experiencia', servicesOffered: ['PASEO'], profilePhoto: 'u',
    identityVerificationStatus: 'VERIFIED', emailVerified: true, phoneVerified: true,
  };

  it('completo → sin faltantes', () => {
    expect(getMissingRequiredFieldsForProfessionalSubmit(ok)).toEqual([]);
  });

  it.each([
    ['identityVerificationStatus', 'PENDING', 'identityVerified'],
    ['emailVerified', false, 'emailVerified'],
    ['phoneVerified', false, 'phoneVerified'],
  ])('no se aprueba sin %s', (field, value, expected) => {
    expect(getMissingRequiredFieldsForProfessionalSubmit({ ...ok, [field]: value })).toContain(expected);
  });
});

describe('invitaciones de EMPRESA', () => {
  beforeEach(() => jest.clearAllMocks());

  it('createInvite(COMPANY) genera un código GE- y marca la etiqueta como empresa', async () => {
    p.professionalInvite.create.mockImplementation(async ({ data }: any) => ({ id: 'c1', ...data }));
    const res = await createInvite('admin1', 'Hotel Mascotas', 7, 'COMPANY');
    expect(res.code).toMatch(/^GE-[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    expect(res.kind).toBe('COMPANY');
    expect(inviteKindOfLabel(p.professionalInvite.create.mock.calls[0][0].data.label)).toBe('COMPANY');
  });

  it('listInvites devuelve el tipo y la etiqueta sin la marca interna', async () => {
    p.professionalInvite.findMany.mockResolvedValue([
      { id: '1', label: '[Empresa] Hotel X', usedAt: null, revokedAt: null, expiresAt: future(), createdAt: new Date() },
      { id: '2', label: 'Dr. Pérez', usedAt: null, revokedAt: null, expiresAt: future(), createdAt: new Date() },
    ]);
    const rows = await listInvites();
    expect(rows.map((r: any) => [r.kind, r.label])).toEqual([['COMPANY', 'Hotel X'], ['PROFESSIONAL', 'Dr. Pérez']]);
  });

  it('un código de profesional NO sirve para registrar una empresa, ni al revés', async () => {
    p.professionalInvite.findUnique.mockResolvedValue({ id: 'i', usedAt: null, revokedAt: null, expiresAt: future() });
    expect(await validateCompanyCode('GP-AAAA-BBBB')).toBe(false);
    expect(await validateProfessionalCode('GE-AAAA-BBBB')).toBe(false);
    expect(await validateCompanyCode('GE-AAAA-BBBB')).toBe(true);
    expect(await validateProfessionalCode('GP-AAAA-BBBB')).toBe(true);
  });

  it('el viejo código compartido ya no valida para empresas', async () => {
    p.professionalInvite.findUnique.mockResolvedValue(null);
    expect(await validateCompanyCode('codigo-empresa-viejo')).toBe(false);
  });
});

describe('registerCompany', () => {
  const body = {
    code: 'GE-AAAA-BBBB', companyName: 'Hotel Patitas', businessType: 'HOTEL', email: 'Hotel@Test.com',
    password: 'Passw0rd!x', phone: '71234567', lat: -17.78, lng: -63.18,
  } as any;

  beforeEach(() => {
    jest.clearAllMocks();
    p.professionalInvite.findUnique.mockResolvedValue({ id: 'c1', usedAt: null, revokedAt: null, expiresAt: future() });
    txMock.professionalInvite.updateMany.mockResolvedValue({ count: 1 });
    txMock.user.create.mockResolvedValue({ id: 'u9', email: 'hotel@test.com', role: 'CAREGIVER', firstName: 'Hotel Patitas', lastName: '-', profilePicture: null });
    txMock.caregiverProfile.create.mockImplementation(async ({ data }: any) => ({ id: 'p9', ...data }));
  });

  it('la identidad del dueño queda PENDIENTE (ya no nace verificada) y guarda la ubicación', async () => {
    await registerCompany(body);
    const data = txMock.caregiverProfile.create.mock.calls[0][0].data;
    expect(data.identityVerificationStatus).toBe('PENDING');
    expect(data.verified).toBe(false);
    expect(data.isCompany).toBe(true);
    expect(data.addressLat).toBe(-17.78);
  });

  it('consume la invitación con el id del usuario creado', async () => {
    await registerCompany(body);
    expect(txMock.professionalInvite.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ usedByUserId: 'u9' }) }),
    );
  });

  it('con un código de profesional no crea nada', async () => {
    await expect(registerCompany({ ...body, code: 'GP-AAAA-BBBB' })).rejects.toThrow(/inválido/);
    expect(txMock.user.create).not.toHaveBeenCalled();
  });

  it('si otro registro ya usó la invitación (count 0) falla', async () => {
    txMock.professionalInvite.updateMany.mockResolvedValue({ count: 0 });
    await expect(registerCompany(body)).rejects.toThrow(/inválido/);
  });
});

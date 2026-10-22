/**
 * DELETE /api/auth/account: confirmar con contraseña o con Google, y qué se elimina según el rol.
 * - Dueño: se elimina al instante.
 * - Cuidador: nunca al instante; solo solicita (toda la cuenta o solo su perfil de cuidador), o deja solo el de dueño.
 */
jest.mock('../../src/config/env', () => ({ __esModule: true, env: { NODE_ENV: 'test' } }));

const mockUserFind = jest.fn();
const mockBookingCount = jest.fn();
jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    user: { findUnique: (...a: unknown[]) => mockUserFind(...a) },
    booking: { count: (...a: unknown[]) => mockBookingCount(...a) },
    caregiverProfile: { findUnique: jest.fn(async () => null) },
  },
}));

const mockRequest = jest.fn();
const mockRemoveClient = jest.fn();
const mockFinalize = jest.fn();
jest.mock('../../src/modules/auth/auth.service', () => ({
  requestCaregiverAccountDeletion: (...a: unknown[]) => mockRequest(...a),
  removeClientSide: (...a: unknown[]) => mockRemoveClient(...a),
  finalizeAccountDeletion: (...a: unknown[]) => mockFinalize(...a),
}));

// Revisión de obligaciones (reservas, disputas, retiros) — probada en account-deletion-guard.test.ts.
const mockGuard = jest.fn().mockResolvedValue(undefined);
jest.mock('../../src/modules/auth/account-deletion.guard', () => ({
  assertNoDeletionBlockers: (...a: unknown[]) => mockGuard(...a),
}));

const mockVerifyToken = jest.fn();
jest.mock('../../src/modules/auth/social-auth.controller', () => ({
  verifyFirebaseToken: (...a: unknown[]) => mockVerifyToken(...a),
}));

jest.mock('bcrypt', () => ({
  __esModule: true,
  default: { compare: jest.fn(async (pw: string) => pw === 'correcta') },
}));

import { deleteAccount } from '../../src/modules/auth/auth.controller';

const resMock = () => {
  const res: any = {};
  res.status = jest.fn(() => res);
  res.json = jest.fn(() => res);
  return res;
};
/** Claims de un inicio de sesión de Google reciente y con correo verificado. */
const googleClaims = (over: Record<string, unknown> = {}) => ({
  uid: 'x',
  email: 'Ana@Gmail.com',
  email_verified: true,
  sign_in_provider: 'google.com',
  auth_time: Math.floor(Date.now() / 1000) - 30,
  ...over,
});
const reqOf = (body: unknown) => ({ body, user: { userId: 'u1' } }) as any;
const userOf = (role: string) => ({ id: 'u1', email: 'ana@gmail.com', passwordHash: 'h', role });
const call = async (body: unknown) => {
  const res = resMock();
  const next = jest.fn();
  deleteAccount(reqOf(body), res, next); // asyncHandler no devuelve la promesa: se espera a que responda
  for (let i = 0; i < 100 && !res.json.mock.calls.length && !next.mock.calls.length; i++) await new Promise((r) => setImmediate(r));
  return { res, next, payload: res.json.mock.calls[0]?.[0], status: res.status.mock.calls[0]?.[0] };
};

describe('eliminar cuenta', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockBookingCount.mockResolvedValue(0);
  });

  it('sin contraseña ni token → 400', async () => {
    mockUserFind.mockResolvedValue(userOf('CLIENT'));
    const { status, payload } = await call({});
    expect(status).toBe(400);
    expect(payload.error.code).toBe('MISSING_PASSWORD');
  });

  it('contraseña incorrecta → 400 y no elimina nada', async () => {
    mockUserFind.mockResolvedValue(userOf('CLIENT'));
    const { status, payload } = await call({ password: 'mala' });
    expect(status).toBe(400);
    expect(payload.error.code).toBe('WRONG_PASSWORD');
    expect(mockFinalize).not.toHaveBeenCalled();
  });

  it('dueño con contraseña correcta → se elimina al instante', async () => {
    mockUserFind.mockResolvedValue(userOf('CLIENT'));
    const { payload } = await call({ password: 'correcta' });
    expect(mockFinalize).toHaveBeenCalledWith('u1');
    expect(payload.data).toMatchObject({ deleted: true, pendingApproval: false });
  });

  it('la baja del dueño revisa reservas, disputas y retiros en curso antes de eliminar', async () => {
    mockUserFind.mockResolvedValue(userOf('CLIENT'));
    mockGuard.mockRejectedValueOnce(Object.assign(new Error('Tienes un retiro en curso.'), { code: 'PENDING_WITHDRAWAL', statusCode: 400 }));
    await call({ password: 'correcta' }).catch(() => undefined);
    expect(mockGuard).toHaveBeenCalledWith('u1', 'ALL');
    expect(mockFinalize).not.toHaveBeenCalled();
  });

  it('dueño que entra con Google confirma con su idToken (no tiene contraseña)', async () => {
    mockUserFind.mockResolvedValue(userOf('CLIENT'));
    mockVerifyToken.mockResolvedValue(googleClaims());
    const { payload } = await call({ idToken: 'tok' });
    expect(mockFinalize).toHaveBeenCalledWith('u1');
    expect(payload.data.deleted).toBe(true);
  });

  it.each([
    ['correo sin verificar por el proveedor', { email_verified: false }, 400, 'EMAIL_NOT_VERIFIED'],
    ['token que no es de Google/Apple (p. ej. email-contraseña de Firebase)', { sign_in_provider: 'password' }, 400, 'WRONG_PROVIDER'],
    ['token sin proveedor', { sign_in_provider: undefined }, 400, 'WRONG_PROVIDER'],
    ['inicio de sesión de hace más de 5 minutos', { auth_time: Math.floor(Date.now() / 1000) - 600 }, 401, 'REAUTH_REQUIRED'],
    ['token sin auth_time', { auth_time: undefined }, 401, 'REAUTH_REQUIRED'],
  ])('idToken rechazado: %s', async (_t, over, expectedStatus, code) => {
    mockUserFind.mockResolvedValue(userOf('CLIENT'));
    mockVerifyToken.mockResolvedValue(googleClaims(over as Record<string, unknown>));
    const { status, payload } = await call({ idToken: 'tok' });
    expect(status).toBe(expectedStatus);
    expect(payload.error.code).toBe(code);
    expect(mockFinalize).not.toHaveBeenCalled();
    expect(mockRequest).not.toHaveBeenCalled();
  });

  it('un idToken de OTRA cuenta de Google se rechaza', async () => {
    mockUserFind.mockResolvedValue(userOf('CLIENT'));
    mockVerifyToken.mockResolvedValue(googleClaims({ email: 'otra@gmail.com' }));
    const { status, payload } = await call({ idToken: 'tok' });
    expect(status).toBe(400);
    expect(payload.error.code).toBe('WRONG_ACCOUNT');
    expect(mockFinalize).not.toHaveBeenCalled();
  });

  it('cuidador: solicita la baja de toda la cuenta, sin eliminar nada al instante', async () => {
    mockUserFind.mockResolvedValue(userOf('CAREGIVER'));
    const { payload } = await call({ password: 'correcta', scope: 'ALL', lat: -17.7, lng: -63.1 });
    expect(mockRequest).toHaveBeenCalledWith('u1', -17.7, -63.1, 'ALL');
    expect(mockFinalize).not.toHaveBeenCalled();
    expect(payload.data).toMatchObject({ deleted: false, pendingApproval: true });
  });

  it('cuidador que también es dueño y elige solo el perfil de cuidador → solicitud con ese alcance', async () => {
    mockUserFind.mockResolvedValue(userOf('CAREGIVER'));
    const { payload } = await call({ password: 'correcta', scope: 'CAREGIVER' });
    expect(mockRequest).toHaveBeenCalledWith('u1', undefined, undefined, 'CAREGIVER');
    expect(payload.data.pendingApproval).toBe(true);
  });

  it('cuidador que elige solo el perfil de dueño → se quita al instante y sigue como cuidador', async () => {
    mockUserFind.mockResolvedValue(userOf('CAREGIVER'));
    const { payload } = await call({ password: 'correcta', scope: 'CLIENT' });
    expect(mockRemoveClient).toHaveBeenCalledWith('u1');
    expect(mockRequest).not.toHaveBeenCalled();
    expect(payload.data).toMatchObject({ deleted: false, pendingApproval: false, scope: 'CLIENT' });
  });

  it('no se puede quitar el perfil de dueño con reservas activas como dueño', async () => {
    mockUserFind.mockResolvedValue(userOf('CAREGIVER'));
    mockBookingCount.mockResolvedValue(2);
    const { status, payload } = await call({ password: 'correcta', scope: 'CLIENT' });
    expect(status).toBe(400);
    expect(payload.error.code).toBe('PENDING_BOOKINGS');
    expect(mockRemoveClient).not.toHaveBeenCalled();
  });
});

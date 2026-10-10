/**
 * Inicio de sesión con Google/Apple en el servidor: token inválido → 401 (antes 500) y precalentamiento de firebase-admin.
 */
const mockVerify = jest.fn();
const mockInitializeApp = jest.fn();
const mockApps: unknown[] = [];

jest.mock('firebase-admin', () => ({
  __esModule: true,
  default: {
    get apps() { return mockApps; },
    initializeApp: (...a: unknown[]) => { mockInitializeApp(...a); mockApps.push({}); },
    credential: { cert: (c: unknown) => c },
    auth: () => ({ verifyIdToken: (...a: unknown[]) => mockVerify(...a) }),
  },
}));

const mockUserFind = jest.fn();
jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: { user: { findUnique: (...a: unknown[]) => mockUserFind(...a), update: jest.fn() } },
}));
jest.mock('../../src/utils/settings-cache', () => ({ getBoolSetting: jest.fn(async () => true) }));
jest.mock('../../src/modules/auth/auth.service', () => ({
  signAccessToken: jest.fn(() => ({ token: 'access', expiresIn: '15m' })),
  createRefreshToken: jest.fn(async () => 'refresh'),
  assertBetaAccess: jest.fn(async () => undefined),
}));

import { socialLogin, warmupFirebaseAdmin } from '../../src/modules/auth/social-auth.controller';

const ENV_KEYS = ['FIREBASE_PROJECT_ID', 'FIREBASE_PRIVATE_KEY', 'FIREBASE_CLIENT_EMAIL'] as const;
const saved: Record<string, string | undefined> = {};

function configureFirebase() {
  process.env.FIREBASE_PROJECT_ID = 'garden-test';
  process.env.FIREBASE_PRIVATE_KEY = 'line1\\nline2';
  process.env.FIREBASE_CLIENT_EMAIL = 'svc@garden-test.iam.gserviceaccount.com';
}

const reqOf = (body: unknown) => ({ body }) as any;
const resMock = () => {
  const res: any = {};
  res.status = jest.fn(() => res);
  res.json = jest.fn(() => res);
  return res;
};

describe('login social (servidor)', () => {
  beforeAll(() => ENV_KEYS.forEach((k) => { saved[k] = process.env[k]; }));
  afterAll(() => ENV_KEYS.forEach((k) => { if (saved[k] === undefined) delete process.env[k]; else process.env[k] = saved[k]; }));
  beforeEach(() => {
    jest.clearAllMocks();
    mockApps.length = 0;
    configureFirebase();
  });

  it('un idToken inválido responde 401 INVALID_SOCIAL_TOKEN, no 500', async () => {
    mockVerify.mockRejectedValue(new Error('Firebase ID token has expired'));
    const next = jest.fn();
    await socialLogin(reqOf({ provider: 'google', idToken: 'vencido' }), resMock(), next);
    expect(next).toHaveBeenCalledTimes(1);
    const err = next.mock.calls[0][0];
    expect(err.statusCode).toBe(401);
    expect(err.code).toBe('INVALID_SOCIAL_TOKEN');
    expect(err.message).toMatch(/Google/);
    expect(mockUserFind).not.toHaveBeenCalled(); // no toca la base con un token malo
  });

  it('un token válido de un usuario existente devuelve la sesión', async () => {
    mockVerify.mockResolvedValue({ uid: 'u1', email: 'Ana@Test.com' });
    mockUserFind.mockResolvedValue({
      id: 'user-1', email: 'ana@test.com', role: 'CLIENT', activeRole: null, isDeleted: false,
      firstName: 'Ana', lastName: 'Rojas', profilePicture: null, emailVerified: true,
    });
    const res = resMock();
    await socialLogin(reqOf({ provider: 'google', idToken: 'ok' }), res, jest.fn());
    expect(mockUserFind).toHaveBeenCalledWith(expect.objectContaining({ where: { email: 'ana@test.com' } }));
    const payload = res.json.mock.calls[0][0];
    expect(payload).toMatchObject({ success: true, data: { accessToken: 'access', refreshToken: 'refresh' } });
  });

  it('sin cuenta devuelve 404 para que la app la cree', async () => {
    mockVerify.mockResolvedValue({ uid: 'u2', email: 'nuevo@test.com', name: 'Nuevo Usuario' });
    mockUserFind.mockResolvedValue(null);
    const res = resMock();
    await socialLogin(reqOf({ provider: 'google', idToken: 'ok' }), res, jest.fn());
    expect(res.status).toHaveBeenCalledWith(404);
  });

  it('faltan datos → 400', async () => {
    const next = jest.fn();
    await socialLogin(reqOf({ provider: 'google' }), resMock(), next);
    expect(next.mock.calls[0][0].statusCode).toBe(400);
  });
});

describe('precalentamiento de firebase-admin', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockApps.length = 0;
  });

  it('inicializa firebase-admin una sola vez aunque se llame varias veces', async () => {
    configureFirebase();
    await warmupFirebaseAdmin();
    await warmupFirebaseAdmin();
    expect(mockInitializeApp).toHaveBeenCalledTimes(1);
  });

  it('sin credenciales de Firebase no hace nada y no lanza', async () => {
    ENV_KEYS.forEach((k) => delete process.env[k]);
    await expect(warmupFirebaseAdmin()).resolves.toBeUndefined();
    expect(mockInitializeApp).not.toHaveBeenCalled();
  });

  it('si algo falla al precalentar no tumba el arranque', async () => {
    configureFirebase();
    mockInitializeApp.mockImplementationOnce(() => { throw new Error('clave inválida'); });
    await expect(warmupFirebaseAdmin()).resolves.toBeUndefined();
  });
});

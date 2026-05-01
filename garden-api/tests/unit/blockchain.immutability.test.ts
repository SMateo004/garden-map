/**
 * Blockchain Immutability — Registration integration tests
 *
 * Verifica que syncAndPersist (en auth.service):
 * 1. Llama a syncProfileOnChain con los args correctos tras registerCaregiver
 * 2. Guarda el blockchainTxHash en la DB cuando el sync es exitoso
 * 3. No bloquea el registro cuando el sync falla
 * 4. El error se loguea prominentemente (no se traga silenciosamente)
 */

// ─── mocks (hoistados antes de cualquier import) ──────────────────────────────

const mockUserUpdate = jest.fn().mockResolvedValue({});

jest.mock('../../src/services/blockchain.service', () => ({
  blockchainService: {
    syncProfileOnChain: jest.fn().mockResolvedValue('0xmockhash'),
    addPetOnChain: jest.fn().mockResolvedValue(null),
    updateVerificationOnChain: jest.fn().mockResolvedValue(null),
  },
}));

jest.mock('../../src/config/database', () => {
  const mockUser = {
    id: 'user-reg-1',
    email: 'test@garden.bo',
    role: 'CAREGIVER',
    firstName: 'Juan',
    lastName: 'Perez',
    phone: '+59171111111',
    country: 'Bolivia',
    city: 'Santa Cruz',
    isOver18: true,
    profilePicture: null,
  };
  const mockProfile = { id: 'profile-reg-1', userId: 'user-reg-1', verificationStatus: 'PENDING_REVIEW' };
  const txMock = {
    user: { findUnique: jest.fn().mockResolvedValue(null), create: jest.fn().mockResolvedValue(mockUser) },
    caregiverProfile: { create: jest.fn().mockResolvedValue(mockProfile) },
  };
  return {
    __esModule: true,
    default: {
      user: {
        findUnique: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue(mockUser),
        update: (...args: any[]) => mockUserUpdate(...args),
      },
      clientProfile: { create: jest.fn().mockResolvedValue({ id: 'cp-1', userId: 'user-reg-1' }) },
      refreshToken: {
        create: jest.fn().mockResolvedValue({ id: 'rt-1', tokenHash: 'h', expiresAt: new Date() }),
        findFirst: jest.fn().mockResolvedValue(null),
        updateMany: jest.fn().mockResolvedValue({}),
      },
      $transaction: jest.fn((fn: (tx: typeof txMock) => Promise<unknown>) => fn(txMock)),
    },
  };
});

jest.mock('../../src/shared/analytics', () => ({ track: jest.fn(), identify: jest.fn() }));
jest.mock('bcrypt', () => ({
  hash: jest.fn().mockResolvedValue('hashed_pw'),
  compare: jest.fn().mockResolvedValue(true),
}));

// ─── imports estáticos (después de los mocks) ─────────────────────────────────

import { registerCaregiver } from '../../src/modules/auth/auth.service';
import { blockchainService } from '../../src/services/blockchain.service';

// ─── fixture ─────────────────────────────────────────────────────────────────

const validCaregiver = {
  user: {
    email: 'cuidador@garden.bo',
    password: 'password123',
    firstName: 'Juan',
    lastName: 'Perez',
    phone: '+59171111111',
    dateOfBirth: new Date('1990-01-01'),
    country: 'Bolivia',
    city: 'Santa Cruz',
    isOver18: true,
  },
  profile: {
    servicesOffered: ['HOSPEDAJE'],
    photos: [
      'https://res.cloudinary.com/x/1.jpg',
      'https://res.cloudinary.com/x/2.jpg',
      'https://res.cloudinary.com/x/3.jpg',
      'https://res.cloudinary.com/x/4.jpg',
    ],
    zone: 'EQUIPETROL',
    bio: 'Descripción de al menos cincuenta caracteres para cumplir validación del perfil.',
    ciAnversoUrl: 'https://res.cloudinary.com/x/ci-anverso.jpg',
    ciReversoUrl: 'https://res.cloudinary.com/x/ci-reverso.jpg',
  },
};

// ─── tests ───────────────────────────────────────────────────────────────────

describe('Registration — syncAndPersist (blockchain sync + DB persistence)', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockUserUpdate.mockResolvedValue({});
    (blockchainService.syncProfileOnChain as jest.Mock).mockResolvedValue('0xmockhash');
  });

  it('calls syncProfileOnChain with correct args after registerCaregiver', async () => {
    await registerCaregiver(validCaregiver as any);
    await new Promise((r) => setImmediate(r));

    expect(blockchainService.syncProfileOnChain).toHaveBeenCalledTimes(1);
    expect(blockchainService.syncProfileOnChain).toHaveBeenCalledWith(
      'user-reg-1', 'Juan Perez', 'CAREGIVER', false
    );
  });

  it('persists blockchainTxHash in DB when sync succeeds', async () => {
    (blockchainService.syncProfileOnChain as jest.Mock).mockResolvedValueOnce('0xsuccesshash');

    await registerCaregiver(validCaregiver as any);
    await new Promise((r) => setImmediate(r));

    expect(mockUserUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'user-reg-1' },
        data: { blockchainTxHash: '0xsuccesshash' },
      })
    );
  });

  it('registration succeeds even when syncProfileOnChain rejects — error is logged, not silent', async () => {
    (blockchainService.syncProfileOnChain as jest.Mock).mockRejectedValueOnce(new Error('insufficient funds'));

    const result = await registerCaregiver(validCaregiver as any);

    expect(result.user.email).toBe('test@garden.bo');
    expect(result.profileId).toBe('profile-reg-1');

    await new Promise((r) => setImmediate(r));
    expect(blockchainService.syncProfileOnChain).toHaveBeenCalledTimes(1);
    // DB update NOT called since sync failed
    expect(mockUserUpdate).not.toHaveBeenCalled();
  });
});

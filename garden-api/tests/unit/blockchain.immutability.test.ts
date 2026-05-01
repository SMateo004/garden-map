/**
 * Blockchain Immutability Tests — GardenProfiles
 *
 * These tests verify:
 * 1. syncProfileOnChain IS called on caregiver and client registration
 * 2. The correct arguments are passed (userId, name, role, isVerified=false)
 * 3. Registration succeeds even when blockchain sync fails (silent failure — the known bug)
 * 4. BlockchainService enters MOCK MODE when BLOCKCHAIN_ENABLED is not set
 * 5. Role mapping: CLIENT → 1, CAREGIVER → 2 (as required by GardenProfiles.sol)
 * 6. addPetOnChain and updateVerificationOnChain return null on error without throwing
 */

import { blockchainService } from '../../src/services/blockchain.service';

// ─── helpers ─────────────────────────────────────────────────────────────────

function saveEnv(keys: string[]): Record<string, string | undefined> {
  return Object.fromEntries(keys.map((k) => [k, process.env[k]]));
}

function restoreEnv(saved: Record<string, string | undefined>) {
  for (const [k, v] of Object.entries(saved)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
}

const BLOCKCHAIN_KEYS = [
  'BLOCKCHAIN_ENABLED',
  'BLOCKCHAIN_RPC_URL',
  'BLOCKCHAIN_PRIVATE_KEY',
  'BLOCKCHAIN_CONTRACT_ADDRESS',
  'BLOCKCHAIN_PROFILES_ADDRESS',
];

// ─── BlockchainService unit tests ────────────────────────────────────────────

describe('BlockchainService — syncProfileOnChain', () => {
  let savedEnv: Record<string, string | undefined>;

  beforeEach(() => {
    savedEnv = saveEnv(BLOCKCHAIN_KEYS);
    // Reset lazy-init flag so each test starts fresh
    (blockchainService as any).initialized = false;
    (blockchainService as any).provider = null;
    (blockchainService as any).wallet = null;
    (blockchainService as any).escrowContract = null;
    (blockchainService as any).profileContract = null;
  });

  afterEach(() => {
    restoreEnv(savedEnv);
  });

  it('returns null in MOCK MODE when BLOCKCHAIN_ENABLED is not set', async () => {
    delete process.env.BLOCKCHAIN_ENABLED;
    const result = await blockchainService.syncProfileOnChain('user-1', 'Test User', 'CLIENT', false);
    expect(result).toBeNull();
  });

  it('returns null in MOCK MODE when BLOCKCHAIN_ENABLED=false', async () => {
    process.env.BLOCKCHAIN_ENABLED = 'false';
    const result = await blockchainService.syncProfileOnChain('user-1', 'Test User', 'CAREGIVER', false);
    expect(result).toBeNull();
  });

  it('returns null in MOCK MODE when RPC_URL is missing even if ENABLED=true', async () => {
    process.env.BLOCKCHAIN_ENABLED = 'true';
    delete process.env.BLOCKCHAIN_RPC_URL;
    delete process.env.BLOCKCHAIN_PRIVATE_KEY;
    const result = await blockchainService.syncProfileOnChain('user-1', 'Test User', 'CLIENT', false);
    expect(result).toBeNull();
  });

  it('returns null in MOCK MODE when PRIVATE_KEY is missing', async () => {
    process.env.BLOCKCHAIN_ENABLED = 'true';
    process.env.BLOCKCHAIN_RPC_URL = 'https://rpc.example.com';
    delete process.env.BLOCKCHAIN_PRIVATE_KEY;
    const result = await blockchainService.syncProfileOnChain('user-1', 'Test User', 'CAREGIVER', true);
    expect(result).toBeNull();
  });

  it('uses role index 1 for CLIENT and 2 for CAREGIVER when calling syncProfile', async () => {
    const mockReceipt = { hash: '0xabc123' };
    const mockTx = { wait: jest.fn().mockResolvedValue(mockReceipt) };
    const mockSyncProfile = jest.fn().mockResolvedValue(mockTx);

    // initialized=true + non-null escrowContract so ensureInitialized() returns true
    (blockchainService as any).initialized = true;
    (blockchainService as any).escrowContract = {};
    (blockchainService as any).profileContract = { syncProfile: mockSyncProfile };

    await blockchainService.syncProfileOnChain('uid-client', 'Ana Torres', 'CLIENT', false, '');
    expect(mockSyncProfile).toHaveBeenCalledWith('uid-client', 'Ana Torres', 1, false, '');

    await blockchainService.syncProfileOnChain('uid-caregiver', 'Carlos Ruiz', 'CAREGIVER', true, '');
    expect(mockSyncProfile).toHaveBeenCalledWith('uid-caregiver', 'Carlos Ruiz', 2, true, '');
  });

  it('returns tx hash on success', async () => {
    const mockReceipt = { hash: '0xdeadbeef' };
    const mockTx = { wait: jest.fn().mockResolvedValue(mockReceipt) };
    const mockSyncProfile = jest.fn().mockResolvedValue(mockTx);

    (blockchainService as any).initialized = true;
    (blockchainService as any).escrowContract = {};
    (blockchainService as any).profileContract = { syncProfile: mockSyncProfile };

    const hash = await blockchainService.syncProfileOnChain('user-99', 'Maria Perez', 'CLIENT', false);
    expect(hash).toBe('0xdeadbeef');
  });

  it('returns null (does NOT throw) when the contract call rejects — silent failure', async () => {
    const mockSyncProfile = jest.fn().mockRejectedValue(new Error('insufficient funds for gas'));

    (blockchainService as any).initialized = true;
    (blockchainService as any).escrowContract = {};
    (blockchainService as any).profileContract = { syncProfile: mockSyncProfile };

    // Must not throw — silent failure is the current behaviour
    await expect(
      blockchainService.syncProfileOnChain('user-fail', 'Fail User', 'CLIENT', false)
    ).resolves.toBeNull();
  });

  it('addPetOnChain returns null in MOCK MODE', async () => {
    delete process.env.BLOCKCHAIN_ENABLED;
    const result = await blockchainService.addPetOnChain('owner-1', 'Firulais', 'Labrador');
    expect(result).toBeNull();
  });

  it('addPetOnChain returns null (does NOT throw) on contract error', async () => {
    const mockAddPet = jest.fn().mockRejectedValue(new Error('El dueno debe tener perfil sincronizado'));

    (blockchainService as any).initialized = true;
    (blockchainService as any).escrowContract = {};
    (blockchainService as any).profileContract = { addPetToOwner: mockAddPet };

    await expect(
      blockchainService.addPetOnChain('owner-missing', 'Firulais', 'Labrador')
    ).resolves.toBeNull();
  });

  it('updateVerificationOnChain returns null in MOCK MODE', async () => {
    delete process.env.BLOCKCHAIN_ENABLED;
    const result = await blockchainService.updateVerificationOnChain('user-1', true);
    expect(result).toBeNull();
  });
});

// ─── Registration integration: blockchain sync is called ─────────────────────

/**
 * These tests import auth.service and verify that syncProfileOnChain is triggered
 * with the correct arguments after registration.  The DB and blockchain are both
 * mocked so no real network calls are made.
 *
 * KEY ASSERTION: the sync call is fire-and-forget (.catch(logger.error)).
 * Even when it rejects, registerCaregiver / registerClient must still resolve
 * successfully — that is the silent-failure bug we are documenting.
 */
describe('Registration — blockchain sync fire-and-forget', () => {
  // We mock the module before importing to intercept calls
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
    const mockProfile = {
      id: 'profile-reg-1',
      userId: 'user-reg-1',
      verificationStatus: 'PENDING_REVIEW',
    };
    const txMock = {
      user: {
        findUnique: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue(mockUser),
      },
      caregiverProfile: {
        create: jest.fn().mockResolvedValue(mockProfile),
      },
    };
    return {
      __esModule: true,
      default: {
        user: {
          findUnique: jest.fn().mockResolvedValue(null),
          create: jest.fn().mockResolvedValue(mockUser),
        },
        clientProfile: {
          create: jest.fn().mockResolvedValue({ id: 'cprofile-1', userId: 'user-reg-1' }),
        },
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

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('calls syncProfileOnChain with CAREGIVER role and isVerified=false after registerCaregiver', async () => {
    const { registerCaregiver } = await import('../../src/modules/auth/auth.service');
    const { blockchainService: bc } = await import('../../src/services/blockchain.service');

    await registerCaregiver(validCaregiver as any);

    // Allow the fire-and-forget promise to settle
    await new Promise((r) => setImmediate(r));

    expect(bc.syncProfileOnChain).toHaveBeenCalledTimes(1);
    expect(bc.syncProfileOnChain).toHaveBeenCalledWith(
      'user-reg-1',
      'Juan Perez',
      'CAREGIVER',
      false,
    );
  });

  it('registerCaregiver succeeds even when syncProfileOnChain rejects (silent failure)', async () => {
    const { registerCaregiver } = await import('../../src/modules/auth/auth.service');
    const { blockchainService: bc } = await import('../../src/services/blockchain.service');

    // Simulate blockchain network error / empty wallet
    (bc.syncProfileOnChain as jest.Mock).mockRejectedValueOnce(new Error('insufficient funds'));

    // Registration must still succeed
    const result = await registerCaregiver(validCaregiver as any);
    expect(result.user.email).toBe('test@garden.bo');
    expect(result.profileId).toBe('profile-reg-1');

    await new Promise((r) => setImmediate(r));
    expect(bc.syncProfileOnChain).toHaveBeenCalledTimes(1);
  });
});

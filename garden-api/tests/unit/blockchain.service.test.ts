/**
 * Unit tests: BlockchainService
 *
 * Covers all public methods including previously-mocked ones:
 *  - recordWalkExtensionOnChain (now calls extendWalk on contract)
 *  - getCaregiverReputation (now reads getReputation view)
 *  - resolveDispute* (caregiver wins / client wins / partial)
 *  - createBookingOnChain, finalizeBookingOnChain, cancelBookingOnChain
 *  - syncProfileOnChain, updateVerificationOnChain, addPetOnChain
 *
 * Strategy: mock ethers so no real RPC connection is made.
 */

// ── Mock ethers before importing the service ────────────────────────────────

const mockContractCall = jest.fn();
const mockWait = jest.fn().mockResolvedValue({ hash: '0xabc123TXHASH' });

const mockEscrowContract = {
  createBooking: jest.fn().mockResolvedValue({ wait: mockWait }),
  finalizeBooking: jest.fn().mockResolvedValue({ wait: mockWait }),
  cancelBooking: jest.fn().mockResolvedValue({ wait: mockWait }),
  resolveDisputeCaregiverWins: jest.fn().mockResolvedValue({ wait: mockWait }),
  resolveDisputeClientWins: jest.fn().mockResolvedValue({ wait: mockWait }),
  resolvePartial: jest.fn().mockResolvedValue({ wait: mockWait }),
  extendWalk: jest.fn().mockResolvedValue({ wait: mockWait }),
  getReputation: jest.fn().mockResolvedValue([BigInt(15), BigInt(3)]), // totalRating=15, count=3
};

const mockProfileContract = {
  syncProfile: jest.fn().mockResolvedValue({ wait: mockWait }),
  updateVerificationStatus: jest.fn().mockResolvedValue({ wait: mockWait }),
  addPetToOwner: jest.fn().mockResolvedValue({ wait: mockWait }),
};

jest.mock('ethers', () => ({
  ethers: {
    JsonRpcProvider: jest.fn().mockReturnValue({}),
    Wallet: jest.fn().mockReturnValue({ address: '0xAdminWallet' }),
    Contract: jest.fn().mockImplementation((_address: string, _abi: unknown, _wallet: unknown) => {
      // Return escrow or profile mock based on which is instantiated
      return _abi && Array.isArray(_abi) && (_abi as string[]).some((s: string) => s.includes('extendWalk'))
        ? mockEscrowContract
        : mockProfileContract;
    }),
  },
}));

// ── Force blockchain to initialize in LIVE mode ──────────────────────────────

// We must set env vars BEFORE loading the module (lazy init reads process.env)
const ORIGINAL_ENV = { ...process.env };

function setBlockchainEnv(enabled: boolean = true) {
  process.env.BLOCKCHAIN_ENABLED = enabled ? 'true' : 'false';
  process.env.BLOCKCHAIN_RPC_URL = 'https://fake-rpc.test';
  process.env.BLOCKCHAIN_PRIVATE_KEY = '0x' + 'a'.repeat(64);
  process.env.BLOCKCHAIN_CONTRACT_ADDRESS = '0x' + 'b'.repeat(40);
  process.env.BLOCKCHAIN_PROFILES_ADDRESS = '0x' + 'c'.repeat(40);
}

// ── Import the service (after mocks are set) ─────────────────────────────────

// We import dynamically so we can reset the singleton between env scenarios
let blockchainService: typeof import('../../src/services/blockchain.service.js')['blockchainService'];

describe('BlockchainService', () => {
  beforeAll(() => {
    setBlockchainEnv(true);
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    blockchainService = require('../../src/services/blockchain.service.js').blockchainService;
  });

  afterAll(() => {
    Object.assign(process.env, ORIGINAL_ENV);
  });

  beforeEach(() => {
    jest.clearAllMocks();
    mockWait.mockResolvedValue({ hash: '0xabc123TXHASH' });
    mockEscrowContract.createBooking.mockResolvedValue({ wait: mockWait });
    mockEscrowContract.finalizeBooking.mockResolvedValue({ wait: mockWait });
    mockEscrowContract.cancelBooking.mockResolvedValue({ wait: mockWait });
    mockEscrowContract.resolveDisputeCaregiverWins.mockResolvedValue({ wait: mockWait });
    mockEscrowContract.resolveDisputeClientWins.mockResolvedValue({ wait: mockWait });
    mockEscrowContract.resolvePartial.mockResolvedValue({ wait: mockWait });
    mockEscrowContract.extendWalk.mockResolvedValue({ wait: mockWait });
    mockEscrowContract.getReputation.mockResolvedValue([BigInt(15), BigInt(3)]);
    mockProfileContract.syncProfile.mockResolvedValue({ wait: mockWait });
    mockProfileContract.updateVerificationStatus.mockResolvedValue({ wait: mockWait });
    mockProfileContract.addPetToOwner.mockResolvedValue({ wait: mockWait });
  });

  // ── createBookingOnChain ──────────────────────────────────────────────────

  describe('createBookingOnChain', () => {
    it('returns txHash on success', async () => {
      const hash = await blockchainService.createBookingOnChain(
        'booking-1', 'client-1', 'caregiver-1', 300,
        new Date('2026-06-01'), new Date('2026-06-04'),
        'Max', 'HOSPEDAJE'
      );
      expect(hash).toBe('0xabc123TXHASH');
      expect(mockEscrowContract.createBooking).toHaveBeenCalledWith(
        'booking-1', 'client-1', 'caregiver-1', 300,
        expect.any(Number), expect.any(Number), 'Max', 'HOSPEDAJE'
      );
    });

    it('returns null when booking already exists on-chain (duplicate call)', async () => {
      mockEscrowContract.createBooking.mockRejectedValue(
        new Error('La reserva ya existe on-chain')
      );
      const hash = await blockchainService.createBookingOnChain(
        'booking-dup', 'client-1', 'caregiver-1', 100,
        new Date(), new Date(), 'Rex', 'PASEO'
      );
      expect(hash).toBeNull();
    });

    it('returns null on network error (does not throw)', async () => {
      mockEscrowContract.createBooking.mockRejectedValue(new Error('network timeout'));
      const hash = await blockchainService.createBookingOnChain(
        'booking-2', 'client-1', 'caregiver-1', 100,
        new Date(), new Date(), 'Bolt', 'PASEO'
      );
      expect(hash).toBeNull();
    });
  });

  // ── finalizeBookingOnChain ────────────────────────────────────────────────

  describe('finalizeBookingOnChain', () => {
    it('returns txHash and calls finalizeBooking with correct args', async () => {
      const hash = await blockchainService.finalizeBookingOnChain('booking-1', 5);
      expect(hash).toBe('0xabc123TXHASH');
      expect(mockEscrowContract.finalizeBooking).toHaveBeenCalledWith('booking-1', 5);
    });

    it('returns null on error', async () => {
      mockEscrowContract.finalizeBooking.mockRejectedValue(new Error('execution reverted'));
      const hash = await blockchainService.finalizeBookingOnChain('booking-bad', 4);
      expect(hash).toBeNull();
    });
  });

  // ── cancelBookingOnChain ──────────────────────────────────────────────────

  describe('cancelBookingOnChain', () => {
    it('returns txHash and passes reason to contract', async () => {
      const hash = await blockchainService.cancelBookingOnChain('booking-1', 'Cliente canceló');
      expect(hash).toBe('0xabc123TXHASH');
      expect(mockEscrowContract.cancelBooking).toHaveBeenCalledWith('booking-1', 'Cliente canceló');
    });

    it('uses fallback reason when empty string given', async () => {
      await blockchainService.cancelBookingOnChain('booking-1', '');
      expect(mockEscrowContract.cancelBooking).toHaveBeenCalledWith('booking-1', 'No especificado');
    });

    it('returns null on error', async () => {
      mockEscrowContract.cancelBooking.mockRejectedValue(new Error('reverted'));
      const hash = await blockchainService.cancelBookingOnChain('booking-bad', 'reason');
      expect(hash).toBeNull();
    });
  });

  // ── recordWalkExtensionOnChain (FORMERLY MOCKED) ──────────────────────────

  describe('recordWalkExtensionOnChain', () => {
    it('calls extendWalk on the contract and returns txHash', async () => {
      const hash = await blockchainService.recordWalkExtensionOnChain('booking-walk-1', 30, 150);
      expect(hash).toBe('0xabc123TXHASH');
      expect(mockEscrowContract.extendWalk).toHaveBeenCalledWith('booking-walk-1', 30, 150);
    });

    it('rounds float additionalMinutes and amount to integers', async () => {
      await blockchainService.recordWalkExtensionOnChain('booking-walk-2', 15.7, 120.9);
      expect(mockEscrowContract.extendWalk).toHaveBeenCalledWith('booking-walk-2', 15, 120);
    });

    it('returns null on contract error without throwing', async () => {
      mockEscrowContract.extendWalk.mockRejectedValue(new Error('Reserva no activa'));
      const hash = await blockchainService.recordWalkExtensionOnChain('booking-bad', 30, 100);
      expect(hash).toBeNull();
    });
  });

  // ── getCaregiverReputation (FORMERLY HARDCODED MOCK) ─────────────────────

  describe('getCaregiverReputation', () => {
    it('reads real reputation from getReputation() view and computes average', async () => {
      // totalRating=15, count=3 → average=5.0
      mockEscrowContract.getReputation.mockResolvedValue([BigInt(15), BigInt(3)]);
      const rep = await blockchainService.getCaregiverReputation('caregiver-abc');
      expect(rep).toEqual({ average: 5, count: 3 });
      expect(mockEscrowContract.getReputation).toHaveBeenCalledWith('caregiver-abc');
    });

    it('returns average=0 and count=0 when caregiver has no ratings yet', async () => {
      mockEscrowContract.getReputation.mockResolvedValue([BigInt(0), BigInt(0)]);
      const rep = await blockchainService.getCaregiverReputation('new-caregiver');
      expect(rep).toEqual({ average: 0, count: 0 });
    });

    it('rounds average to 1 decimal place', async () => {
      // totalRating=14, count=3 → 14/3=4.666... → rounds to 4.7
      mockEscrowContract.getReputation.mockResolvedValue([BigInt(14), BigInt(3)]);
      const rep = await blockchainService.getCaregiverReputation('caregiver-xyz');
      expect(rep?.average).toBe(4.7);
      expect(rep?.count).toBe(3);
    });

    it('returns null on contract error without throwing', async () => {
      mockEscrowContract.getReputation.mockRejectedValue(new Error('call failed'));
      const rep = await blockchainService.getCaregiverReputation('bad-id');
      expect(rep).toBeNull();
    });
  });

  // ── resolveDisputeCaregiverWinsOnChain ────────────────────────────────────

  describe('resolveDisputeCaregiverWinsOnChain', () => {
    it('calls contract and returns txHash', async () => {
      const hash = await blockchainService.resolveDisputeCaregiverWinsOnChain('booking-d1', 250);
      expect(hash).toBe('0xabc123TXHASH');
      expect(mockEscrowContract.resolveDisputeCaregiverWins).toHaveBeenCalledWith('booking-d1', 250);
    });

    it('returns null on error', async () => {
      mockEscrowContract.resolveDisputeCaregiverWins.mockRejectedValue(new Error('reverted'));
      expect(await blockchainService.resolveDisputeCaregiverWinsOnChain('bad', 100)).toBeNull();
    });
  });

  // ── resolveDisputeClientWinsOnChain ───────────────────────────────────────

  describe('resolveDisputeClientWinsOnChain', () => {
    it('calls contract and returns txHash', async () => {
      const hash = await blockchainService.resolveDisputeClientWinsOnChain('booking-d2', 300);
      expect(hash).toBe('0xabc123TXHASH');
      expect(mockEscrowContract.resolveDisputeClientWins).toHaveBeenCalledWith('booking-d2', 300);
    });

    it('returns null on error', async () => {
      mockEscrowContract.resolveDisputeClientWins.mockRejectedValue(new Error('reverted'));
      expect(await blockchainService.resolveDisputeClientWinsOnChain('bad', 100)).toBeNull();
    });
  });

  // ── resolvePartialOnChain ─────────────────────────────────────────────────

  describe('resolvePartialOnChain', () => {
    it('calls contract with caregiver and client amounts', async () => {
      const hash = await blockchainService.resolvePartialOnChain('booking-d3', 150, 100);
      expect(hash).toBe('0xabc123TXHASH');
      expect(mockEscrowContract.resolvePartial).toHaveBeenCalledWith('booking-d3', 150, 100);
    });

    it('floors decimal amounts', async () => {
      await blockchainService.resolvePartialOnChain('booking-d3', 149.9, 99.5);
      expect(mockEscrowContract.resolvePartial).toHaveBeenCalledWith('booking-d3', 149, 99);
    });

    it('returns null on error', async () => {
      mockEscrowContract.resolvePartial.mockRejectedValue(new Error('reverted'));
      expect(await blockchainService.resolvePartialOnChain('bad', 100, 50)).toBeNull();
    });
  });

  // ── syncProfileOnChain ────────────────────────────────────────────────────

  describe('syncProfileOnChain', () => {
    it('calls syncProfile with role 2 for CAREGIVER', async () => {
      await blockchainService.syncProfileOnChain('user-1', 'Juan Lopez', 'CAREGIVER', false);
      expect(mockProfileContract.syncProfile).toHaveBeenCalledWith('user-1', 'Juan Lopez', 2, false, '');
    });

    it('calls syncProfile with role 1 for CLIENT', async () => {
      await blockchainService.syncProfileOnChain('user-2', 'Maria P', 'CLIENT', true, 'ipfs://hash');
      expect(mockProfileContract.syncProfile).toHaveBeenCalledWith('user-2', 'Maria P', 1, true, 'ipfs://hash');
    });

    it('returns null on error without throwing', async () => {
      mockProfileContract.syncProfile.mockRejectedValue(new Error('network error'));
      const hash = await blockchainService.syncProfileOnChain('user-bad', 'X', 'CLIENT', false);
      expect(hash).toBeNull();
    });
  });

  // ── updateVerificationOnChain ─────────────────────────────────────────────

  describe('updateVerificationOnChain', () => {
    it('calls updateVerificationStatus and returns txHash', async () => {
      const hash = await blockchainService.updateVerificationOnChain('user-1', true);
      expect(hash).toBe('0xabc123TXHASH');
      expect(mockProfileContract.updateVerificationStatus).toHaveBeenCalledWith('user-1', true);
    });

    it('returns null on error', async () => {
      mockProfileContract.updateVerificationStatus.mockRejectedValue(new Error('profile not found'));
      expect(await blockchainService.updateVerificationOnChain('bad', true)).toBeNull();
    });
  });

  // ── addPetOnChain ─────────────────────────────────────────────────────────

  describe('addPetOnChain', () => {
    it('calls addPetToOwner and returns txHash', async () => {
      const hash = await blockchainService.addPetOnChain('owner-1', 'Max', 'Labrador');
      expect(hash).toBe('0xabc123TXHASH');
      expect(mockProfileContract.addPetToOwner).toHaveBeenCalledWith('owner-1', 'Max', 'Labrador');
    });

    it('returns null on error', async () => {
      mockProfileContract.addPetToOwner.mockRejectedValue(new Error('owner not found'));
      expect(await blockchainService.addPetOnChain('bad', 'X', 'Mix')).toBeNull();
    });
  });
});

// ── MOCK MODE tests (BLOCKCHAIN_ENABLED=false) ────────────────────────────────
// Use jest.isolateModules to avoid polluting the global module registry,
// which would cause cross-test contamination when running in parallel workers.

describe('BlockchainService — MOCK MODE (BLOCKCHAIN_ENABLED=false)', () => {
  let mockModeService: typeof import('../../src/services/blockchain.service.js')['blockchainService'];

  beforeAll(async () => {
    await jest.isolateModulesAsync(async () => {
      process.env.BLOCKCHAIN_ENABLED = 'false';
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const mod = require('../../src/services/blockchain.service.js');
      mockModeService = mod.blockchainService;
    });
  });

  afterAll(() => {
    process.env.BLOCKCHAIN_ENABLED = 'true';
  });

  it('createBookingOnChain returns null in mock mode', async () => {
    const hash = await mockModeService.createBookingOnChain(
      'x', 'c', 'g', 100, new Date(), new Date(), 'Rex', 'PASEO'
    );
    expect(hash).toBeNull();
  });

  it('recordWalkExtensionOnChain returns null in mock mode', async () => {
    expect(await mockModeService.recordWalkExtensionOnChain('x', 30, 100)).toBeNull();
  });

  it('getCaregiverReputation returns null in mock mode', async () => {
    expect(await mockModeService.getCaregiverReputation('cg-1')).toBeNull();
  });

  it('resolveDisputeCaregiverWinsOnChain returns null in mock mode', async () => {
    expect(await mockModeService.resolveDisputeCaregiverWinsOnChain('x', 100)).toBeNull();
  });

  it('resolveDisputeClientWinsOnChain returns null in mock mode', async () => {
    expect(await mockModeService.resolveDisputeClientWinsOnChain('x', 100)).toBeNull();
  });

  it('resolvePartialOnChain returns null in mock mode', async () => {
    expect(await mockModeService.resolvePartialOnChain('x', 50, 50)).toBeNull();
  });
});

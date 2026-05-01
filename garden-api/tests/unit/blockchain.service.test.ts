/**
 * BlockchainService unit tests — prueba el servicio real (sin mocks de módulo)
 *
 * Verifica:
 * - MOCK MODE cuando faltan env vars
 * - Mapeo de roles: CLIENT → 1, CAREGIVER → 2
 * - Retorna txHash en éxito
 * - Retorna null sin lanzar cuando el contrato rechaza
 * - addPetOnChain y updateVerificationOnChain tienen el mismo comportamiento
 */

import { blockchainService } from '../../src/services/blockchain.service';

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

describe('BlockchainService — syncProfileOnChain', () => {
  let savedEnv: Record<string, string | undefined>;

  beforeEach(() => {
    savedEnv = saveEnv(BLOCKCHAIN_KEYS);
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
    expect(await blockchainService.syncProfileOnChain('u1', 'Test', 'CLIENT', false)).toBeNull();
  });

  it('returns null in MOCK MODE when BLOCKCHAIN_ENABLED=false', async () => {
    process.env.BLOCKCHAIN_ENABLED = 'false';
    expect(await blockchainService.syncProfileOnChain('u1', 'Test', 'CAREGIVER', false)).toBeNull();
  });

  it('returns null in MOCK MODE when RPC_URL is missing', async () => {
    process.env.BLOCKCHAIN_ENABLED = 'true';
    delete process.env.BLOCKCHAIN_RPC_URL;
    delete process.env.BLOCKCHAIN_PRIVATE_KEY;
    expect(await blockchainService.syncProfileOnChain('u1', 'Test', 'CLIENT', false)).toBeNull();
  });

  it('returns null in MOCK MODE when PRIVATE_KEY is missing', async () => {
    process.env.BLOCKCHAIN_ENABLED = 'true';
    process.env.BLOCKCHAIN_RPC_URL = 'https://rpc.example.com';
    delete process.env.BLOCKCHAIN_PRIVATE_KEY;
    expect(await blockchainService.syncProfileOnChain('u1', 'Test', 'CAREGIVER', true)).toBeNull();
  });

  it('passes role index 1 for CLIENT and 2 for CAREGIVER to the contract', async () => {
    const mockSyncProfile = jest.fn().mockResolvedValue({ wait: jest.fn().mockResolvedValue({ hash: '0xok' }) });
    (blockchainService as any).initialized = true;
    (blockchainService as any).escrowContract = {};
    (blockchainService as any).profileContract = { syncProfile: mockSyncProfile };

    await blockchainService.syncProfileOnChain('uid-c', 'Ana Torres', 'CLIENT', false, '');
    expect(mockSyncProfile).toHaveBeenCalledWith('uid-c', 'Ana Torres', 1, false, '');

    await blockchainService.syncProfileOnChain('uid-g', 'Carlos Ruiz', 'CAREGIVER', true, '');
    expect(mockSyncProfile).toHaveBeenCalledWith('uid-g', 'Carlos Ruiz', 2, true, '');
  });

  it('returns tx hash on success', async () => {
    const mockSyncProfile = jest.fn().mockResolvedValue({ wait: jest.fn().mockResolvedValue({ hash: '0xdeadbeef' }) });
    (blockchainService as any).initialized = true;
    (blockchainService as any).escrowContract = {};
    (blockchainService as any).profileContract = { syncProfile: mockSyncProfile };

    expect(await blockchainService.syncProfileOnChain('u99', 'Maria', 'CLIENT', false)).toBe('0xdeadbeef');
  });

  it('returns null (does NOT throw) when the contract call rejects', async () => {
    const mockSyncProfile = jest.fn().mockRejectedValue(new Error('insufficient funds for gas'));
    (blockchainService as any).initialized = true;
    (blockchainService as any).escrowContract = {};
    (blockchainService as any).profileContract = { syncProfile: mockSyncProfile };

    await expect(blockchainService.syncProfileOnChain('u-fail', 'Fail', 'CLIENT', false)).resolves.toBeNull();
  });

  it('addPetOnChain returns null in MOCK MODE', async () => {
    delete process.env.BLOCKCHAIN_ENABLED;
    expect(await blockchainService.addPetOnChain('owner-1', 'Firulais', 'Labrador')).toBeNull();
  });

  it('addPetOnChain returns null (does NOT throw) on contract error', async () => {
    const mockAddPet = jest.fn().mockRejectedValue(new Error('El dueno debe tener perfil sincronizado'));
    (blockchainService as any).initialized = true;
    (blockchainService as any).escrowContract = {};
    (blockchainService as any).profileContract = { addPetToOwner: mockAddPet };

    await expect(blockchainService.addPetOnChain('owner-x', 'Firulais', 'Labrador')).resolves.toBeNull();
  });

  it('updateVerificationOnChain returns null in MOCK MODE', async () => {
    delete process.env.BLOCKCHAIN_ENABLED;
    expect(await blockchainService.updateVerificationOnChain('u1', true)).toBeNull();
  });
});

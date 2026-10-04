/**
 * Unit tests: BlockchainService (GardenEscrow v3 / GardenProfiles v2).
 * ethers está mockeado: ninguna llamada sale a una red real.
 */

const mockEscrow: Record<string, jest.Mock | any> = {};
const mockProfiles: Record<string, jest.Mock | any> = {};
const mockProvider = {
  getNetwork: jest.fn(),
  getBlock: jest.fn(),
  getBlockNumber: jest.fn().mockResolvedValue(1000),
  send: jest.fn(),
  getBalance: jest.fn(),
};

jest.mock('ethers', () => {
  const actual = jest.requireActual('ethers');
  return {
    ethers: {
      ...actual.ethers,
      JsonRpcProvider: jest.fn().mockImplementation(() => mockProvider),
      Wallet: jest.fn().mockImplementation(() => ({ address: '0xServerWallet' })),
      Contract: jest.fn().mockImplementation((_addr: string, abi: string[]) =>
        abi.some((s) => s.includes('recordBooking')) ? mockEscrow : mockProfiles),
    },
  };
});

import { ethers } from 'ethers';
import {
  blockchainService,
  ChainRevertError,
  GasTooHighError,
  explorerTxUrl,
  networkInfo,
  toCents,
  uuidToBytes16,
} from '../../src/services/blockchain.service';

const ORIGINAL_ENV = { ...process.env };

function setEnv(extra: Record<string, string | undefined> = {}) {
  Object.assign(process.env, {
    BLOCKCHAIN_ENABLED: 'true',
    BLOCKCHAIN_RPC_URL: 'https://rpc.test',
    BLOCKCHAIN_PRIVATE_KEY: '0x' + 'a'.repeat(64),
    BLOCKCHAIN_CONTRACT_ADDRESS: '0x' + 'b'.repeat(40),
    BLOCKCHAIN_PROFILES_ADDRESS: '0x' + 'c'.repeat(40),
    BLOCKCHAIN_ID_PEPPER: 'p'.repeat(40),
    BLOCKCHAIN_CHAIN_ID: '137',
  });
  delete process.env.BLOCKCHAIN_MAX_FEE_GWEI;
  for (const [k, v] of Object.entries(extra)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  blockchainService.resetForTests();
}

beforeEach(() => {
  jest.clearAllMocks();
  mockProvider.getNetwork.mockResolvedValue({ chainId: 137n });
  mockProvider.getBlock.mockResolvedValue({ baseFeePerGas: ethers.parseUnits('100', 'gwei') });
  mockProvider.send.mockResolvedValue('0x' + ethers.parseUnits('40', 'gwei').toString(16));
  Object.assign(mockEscrow, {
    VERSION: jest.fn().mockResolvedValue(3n),
    recorder: jest.fn().mockResolvedValue('0xServerWallet'),
    getReputation: jest.fn().mockResolvedValue([9n, 2n]),
    interface: new ethers.Interface(['error AlreadyRecorded(bytes16 bookingId)', 'error InvalidInput()']),
  });
  Object.assign(mockProfiles, {
    VERSION: jest.fn().mockResolvedValue(2n),
    recorder: jest.fn().mockResolvedValue('0xServerWallet'),
  });
  setEnv();
});

afterAll(() => {
  process.env = ORIGINAL_ENV;
});

describe('helpers de codificación', () => {
  it('uuidToBytes16 convierte un uuid y rechaza cualquier otra cosa', () => {
    expect(uuidToBytes16('8F14E45F-CEEA-467A-9575-1A2B3C4D5E6F')).toBe('0x8f14e45fceea467a95751a2b3c4d5e6f');
    expect(() => uuidToBytes16('Firulais')).toThrow();
  });

  it('toCents redondea a centavos', () => {
    expect(toCents(31.5)).toBe(3150n);
    expect(toCents('45.555')).toBe(4556n);
  });

  it('red y explorador según chainId', () => {
    expect(networkInfo(137)?.testnet).toBe(false);
    expect(networkInfo(80002)?.testnet).toBe(true);
    expect(explorerTxUrl(137, '0xabc')).toBe('https://polygonscan.com/tx/0xabc');
    expect(explorerTxUrl(80002, '0xabc')).toBe('https://amoy.polygonscan.com/tx/0xabc');
    expect(explorerTxUrl(137, null)).toBeNull();
  });

  it('partyRef es determinista, de 32 bytes y no contiene el id', () => {
    const id = '11111111-2222-4333-8444-555555555555';
    const ref = blockchainService.partyRef(id);
    expect(ref).toMatch(/^0x[0-9a-f]{64}$/);
    expect(blockchainService.partyRef(id)).toBe(ref);
    expect(ref).not.toContain(id.replace(/-/g, ''));
    setEnv({ BLOCKCHAIN_ID_PEPPER: 'q'.repeat(40) });
    expect(blockchainService.partyRef(id)).not.toBe(ref);
  });
});

describe('checkReady', () => {
  it('ok con red, versión y recorder correctos', async () => {
    const r = await blockchainService.checkReady(true);
    expect(r).toMatchObject({ ok: true, chainId: 137, profilesOk: true });
  });

  it('deshabilitado', async () => {
    setEnv({ BLOCKCHAIN_ENABLED: 'false' });
    expect((await blockchainService.checkReady(true)).reason).toBe('DISABLED');
  });

  it('sin pepper no escribe', async () => {
    setEnv({ BLOCKCHAIN_ID_PEPPER: undefined });
    expect((await blockchainService.checkReady(true)).reason).toBe('MISSING_PEPPER');
  });

  it('red distinta de la esperada', async () => {
    mockProvider.getNetwork.mockResolvedValue({ chainId: 80002n });
    expect((await blockchainService.checkReady(true)).reason).toBe('WRONG_NETWORK');
  });

  it('contrato v2 (sin VERSION) queda en pausa', async () => {
    mockEscrow.VERSION.mockRejectedValue(Object.assign(new Error('revert'), { code: 'CALL_EXCEPTION' }));
    expect((await blockchainService.checkReady(true)).reason).toBe('OUTDATED_CONTRACT');
  });

  it('wallet que no es el recorder', async () => {
    mockEscrow.recorder.mockResolvedValue('0xOtro');
    expect((await blockchainService.checkReady(true)).reason).toBe('NOT_RECORDER');
  });

  it('RPC caído', async () => {
    mockProvider.getNetwork.mockRejectedValue(new Error('ECONNREFUSED'));
    expect((await blockchainService.checkReady(true)).reason).toBe('RPC_UNAVAILABLE');
  });
});

describe('comisiones', () => {
  it('aplica la propina mínima de Polygon aunque el RPC sugiera menos', async () => {
    mockProvider.send.mockResolvedValue('0x' + ethers.parseUnits('1', 'gwei').toString(16));
    await blockchainService.checkReady(true);
    const fees = await blockchainService.feeOverrides(137);
    expect(fees.maxPriorityFeePerGas).toBe(ethers.parseUnits('30', 'gwei'));
    expect(fees.maxFeePerGas).toBe(ethers.parseUnits('230', 'gwei'));
  });

  it('posterga si el gas supera BLOCKCHAIN_MAX_FEE_GWEI', async () => {
    setEnv({ BLOCKCHAIN_MAX_FEE_GWEI: '120' });
    await blockchainService.checkReady(true);
    await expect(blockchainService.feeOverrides(137)).rejects.toBeInstanceOf(GasTooHighError);
  });
});

describe('send', () => {
  function stubFunction(fn: { estimateGas: jest.Mock; send: jest.Mock }) {
    mockEscrow.getFunction = jest.fn().mockReturnValue(fn);
  }

  it('estima, envía con comisiones explícitas y devuelve el hash', async () => {
    const fn = { estimateGas: jest.fn().mockResolvedValue(100_000n), send: jest.fn().mockResolvedValue({ hash: '0xhash' }) };
    stubFunction(fn);
    await blockchainService.checkReady(true);
    const res = await blockchainService.send('escrow', 'finalizeBooking', ['0x01', 5], 137);
    expect(res).toEqual({ hash: '0xhash', sentBlock: 1000 });
    const overrides = fn.send.mock.calls[0][2];
    expect(overrides.gasLimit).toBe(120_000n);
    expect(overrides.maxPriorityFeePerGas).toBe(ethers.parseUnits('40', 'gwei'));
  });

  it('traduce el revert del contrato a ChainRevertError sin enviar', async () => {
    const data = mockEscrow.interface.encodeErrorResult('AlreadyRecorded', ['0x' + '11'.repeat(16)]);
    const fn = {
      estimateGas: jest.fn().mockRejectedValue(Object.assign(new Error('execution reverted'), { code: 'CALL_EXCEPTION', data })),
      send: jest.fn(),
    };
    stubFunction(fn);
    await blockchainService.checkReady(true);
    const err = await blockchainService.send('escrow', 'recordBooking', [], 137).catch((e) => e);
    expect(err).toBeInstanceOf(ChainRevertError);
    expect(err.errorName).toBe('AlreadyRecorded');
    expect(fn.send).not.toHaveBeenCalled();
  });

  it('un error de red se propaga tal cual (para reintentar)', async () => {
    const fn = { estimateGas: jest.fn().mockRejectedValue(Object.assign(new Error('timeout'), { code: 'TIMEOUT' })), send: jest.fn() };
    stubFunction(fn);
    await blockchainService.checkReady(true);
    const err = await blockchainService.send('escrow', 'finalizeBooking', [], 137).catch((e) => e);
    expect(err).not.toBeInstanceOf(ChainRevertError);
    expect(err.code).toBe('TIMEOUT');
  });
});

describe('getCaregiverReputation', () => {
  it('lee por la referencia seudónima del cuidador', async () => {
    const rep = await blockchainService.getCaregiverReputation('11111111-2222-4333-8444-555555555555');
    expect(rep).toEqual({ average: 4.5, count: 2 });
    expect(mockEscrow.getReputation).toHaveBeenCalledWith(
      blockchainService.partyRef('11111111-2222-4333-8444-555555555555'));
  });

  it('null si la cadena no está lista', async () => {
    setEnv({ BLOCKCHAIN_ENABLED: 'false' });
    expect(await blockchainService.getCaregiverReputation('x')).toBeNull();
  });
});

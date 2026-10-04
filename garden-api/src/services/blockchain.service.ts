import { createHmac } from 'crypto';
import { ethers } from 'ethers';
import logger from '../shared/logger.js';

// ─────────────────────────────────────────────────────────────────────────────
// E/S con la cadena (Polygon). Solo habla con los contratos; QUÉ se registra y
// cuándo lo decide la cola persistente de services/chain-registry.service.ts.
//
// Contratos: hardhat-garden/contracts — GardenEscrow v3 y GardenProfiles v2.
// Ninguno acepta strings: la reserva va como uuid (bytes16) y las personas como
// una referencia seudónima (HMAC del id interno con BLOCKCHAIN_ID_PEPPER).
// Nunca nombres, teléfonos, correos ni nombres de mascotas (Términos, sección 19).
// ─────────────────────────────────────────────────────────────────────────────

export interface NetworkInfo {
  chainId: number;
  name: string;
  /** Para textos de UI: "red principal de Polygon" / "red de pruebas Amoy". */
  label: string;
  explorer: string;
  testnet: boolean;
  /** Polygon rechaza o deja colgadas las tx con propina menor a esto. */
  minTipGwei: number;
  lowBalancePol: number;
}

const NETWORKS: Record<number, NetworkInfo> = {
  137: {
    chainId: 137, name: 'Polygon PoS', label: 'red principal de Polygon',
    explorer: 'https://polygonscan.com', testnet: false, minTipGwei: 30, lowBalancePol: 3,
  },
  80002: {
    chainId: 80002, name: 'Polygon Amoy', label: 'red de pruebas Amoy (testnet)',
    explorer: 'https://amoy.polygonscan.com', testnet: true, minTipGwei: 25, lowBalancePol: 0.05,
  },
};

export function networkInfo(chainId: number | null | undefined): NetworkInfo | null {
  if (!chainId) return null;
  return NETWORKS[chainId] ?? {
    chainId, name: `Red ${chainId}`, label: `red ${chainId}`, explorer: '', testnet: true, minTipGwei: 2, lowBalancePol: 0.05,
  };
}

export function explorerTxUrl(chainId: number | null | undefined, txHash: string | null | undefined): string | null {
  const net = networkInfo(chainId);
  if (!net?.explorer || !txHash) return null;
  return `${net.explorer}/tx/${txHash}`;
}

// Códigos on-chain (enums de GardenEscrow v3). Cambiarlos rompe la lectura de registros ya escritos.
export const SERVICE_TYPE_CODE: Record<string, number> = { PASEO: 1, HOSPEDAJE: 2, GUARDERIA: 3 };
export const CANCEL_REASON_CODE = {
  UNSPECIFIED: 0, CLIENT: 1, CAREGIVER: 2, REJECTED_BY_CAREGIVER: 3, ADMIN: 4, PAYMENT_TIMEOUT: 5, NO_SHOW: 6, SYSTEM: 7,
} as const;
export const VERDICT_CODE: Record<string, number> = { CAREGIVER_WINS: 1, CLIENT_WINS: 2, PARTIAL: 3 };
export const EXTENSION_UNIT_CODE = { MINUTES: 1, DAYS: 2 } as const;
export const PROFILE_ROLE_CODE: Record<string, number> = { CLIENT: 1, CAREGIVER: 2 };

export const ESCROW_VERSION = 3n;
export const PROFILES_VERSION = 2n;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function uuidToBytes16(id: string): string {
  if (!UUID_RE.test(id)) throw new Error(`Id no es un uuid: ${id}`);
  return '0x' + id.replace(/-/g, '').toLowerCase();
}

export function toCents(amountBs: number | string | { toString(): string }): bigint {
  return BigInt(Math.round(Number(amountBs) * 100));
}

export function toUnix(d: Date): bigint {
  return BigInt(Math.floor(d.getTime() / 1000));
}

const ESCROW_ABI = [
  'function VERSION() view returns (uint256)',
  'function recorder() view returns (address)',
  'function owner() view returns (address)',
  'function totalBookings() view returns (uint256)',
  'function recordBooking(bytes16 bookingId, bytes32 clientRef, bytes32 caregiverRef, uint8 serviceType, uint128 amountCents, uint64 paidAt, uint64 startTime, uint64 endTime)',
  'function finalizeBooking(bytes16 bookingId, uint8 rating)',
  'function cancelBooking(bytes16 bookingId, uint8 reasonCode, uint128 refundCents)',
  'function resolveDispute(bytes16 bookingId, uint8 verdict, uint128 caregiverCents, uint128 clientCents)',
  'function extendBooking(bytes16 bookingId, uint8 unit, uint32 quantity, uint128 newAmountCents)',
  'function getBooking(bytes16 bookingId) view returns (tuple(bytes32 clientRef, bytes32 caregiverRef, uint128 amountCents, uint64 paidAt, uint64 recordedAt, uint64 startTime, uint64 endTime, uint8 serviceType, uint8 status, uint8 rating, uint8 cancelReason, uint8 verdict))',
  'function getReputation(bytes32 caregiverRef) view returns (uint256 totalRating, uint256 ratingCount)',
  'event BookingRecorded(bytes16 indexed bookingId, bytes32 indexed clientRef, bytes32 indexed caregiverRef, uint8 serviceType, uint128 amountCents, uint64 paidAt, uint64 startTime, uint64 endTime)',
  'event BookingFinalized(bytes16 indexed bookingId, uint8 rating)',
  'event BookingCancelled(bytes16 indexed bookingId, uint8 reasonCode, uint128 refundCents)',
  'event DisputeResolved(bytes16 indexed bookingId, uint8 verdict, uint128 caregiverCents, uint128 clientCents)',
  'event BookingExtended(bytes16 indexed bookingId, uint8 unit, uint32 quantity, uint128 newAmountCents, uint64 newEndTime)',
  'error NotRecorder(address caller)',
  'error InvalidInput()',
  'error AlreadyRecorded(bytes16 bookingId)',
  'error UnknownBooking(bytes16 bookingId)',
  'error NotActive(bytes16 bookingId, uint8 status)',
];

const PROFILES_ABI = [
  'function VERSION() view returns (uint256)',
  'function recorder() view returns (address)',
  'function syncProfile(bytes32 userRef, uint8 role, bool verified)',
  'function getProfile(bytes32 userRef) view returns (tuple(uint8 role, bool verified, uint64 joinedAt, uint64 updatedAt))',
  'event ProfileSynced(bytes32 indexed userRef, uint8 role, bool verified)',
  'error NotRecorder(address caller)',
  'error InvalidInput()',
];

/** Evento que deja cada método de escritura — para recuperar un txHash desde los logs. */
export const EVENT_OF_METHOD: Record<string, string> = {
  recordBooking: 'BookingRecorded',
  finalizeBooking: 'BookingFinalized',
  cancelBooking: 'BookingCancelled',
  resolveDispute: 'DisputeResolved',
  extendBooking: 'BookingExtended',
};

/** El contrato rechazó la operación (revert). Reintentar daría lo mismo. */
export class ChainRevertError extends Error {
  constructor(public readonly errorName: string, public readonly errorArgs: unknown[] = [], message?: string) {
    super(message ?? `Revert: ${errorName}`);
    this.name = 'ChainRevertError';
  }
}

/** El gas está por encima de BLOCKCHAIN_MAX_FEE_GWEI: se posterga sin contar como intento. */
export class GasTooHighError extends Error {
  constructor(public readonly gwei: number) {
    super(`Gas demasiado caro ahora (${gwei.toFixed(0)} gwei)`);
    this.name = 'GasTooHighError';
  }
}

export type ChainTarget = 'escrow' | 'profiles';

export type ReadyReason =
  | 'DISABLED' | 'NOT_CONFIGURED' | 'MISSING_PEPPER' | 'WRONG_NETWORK' | 'RPC_UNAVAILABLE'
  | 'OUTDATED_CONTRACT' | 'NOT_RECORDER';

export interface ChainReadiness {
  ok: boolean;
  reason?: ReadyReason;
  detail?: string;
  chainId?: number;
  escrowAddress?: string;
  profilesAddress?: string | null;
  /** GardenProfiles configurado y en la versión esperada. */
  profilesOk?: boolean;
}

export const READY_REASON_LABEL: Record<ReadyReason, string> = {
  DISABLED: 'BLOCKCHAIN_ENABLED no está en true',
  NOT_CONFIGURED: 'Faltan BLOCKCHAIN_RPC_URL, BLOCKCHAIN_PRIVATE_KEY o BLOCKCHAIN_CONTRACT_ADDRESS',
  MISSING_PEPPER: 'Falta BLOCKCHAIN_ID_PEPPER (secreto de las referencias seudónimas)',
  WRONG_NETWORK: 'El RPC apunta a una red distinta de BLOCKCHAIN_CHAIN_ID',
  RPC_UNAVAILABLE: 'El RPC no responde',
  OUTDATED_CONTRACT: 'BLOCKCHAIN_CONTRACT_ADDRESS no es un GardenEscrow v3 (falta desplegar el contrato nuevo)',
  NOT_RECORDER: 'El wallet del servidor no es el recorder del contrato',
};

function readConfig() {
  const e = process.env;
  return {
    enabled: e.BLOCKCHAIN_ENABLED === 'true',
    rpcUrl: e.BLOCKCHAIN_RPC_URL || '',
    privateKey: e.BLOCKCHAIN_PRIVATE_KEY || '',
    escrowAddress: e.BLOCKCHAIN_CONTRACT_ADDRESS || '',
    profilesAddress: e.BLOCKCHAIN_PROFILES_ADDRESS || '',
    expectedChainId: e.BLOCKCHAIN_CHAIN_ID ? Number(e.BLOCKCHAIN_CHAIN_ID) : null,
    pepper: e.BLOCKCHAIN_ID_PEPPER || '',
    maxFeeGwei: Number(e.BLOCKCHAIN_MAX_FEE_GWEI || 1500),
    deployBlock: e.BLOCKCHAIN_DEPLOY_BLOCK ? Number(e.BLOCKCHAIN_DEPLOY_BLOCK) : null,
  };
}

function shortError(err: any): string {
  return String(err?.shortMessage || err?.reason || err?.message || err).slice(0, 300);
}

class BlockchainService {
  private provider: ethers.JsonRpcProvider | null = null;
  private wallet: ethers.Wallet | null = null;
  private escrow: ethers.Contract | null = null;
  private profiles: ethers.Contract | null = null;
  private initialized = false;
  private readiness: { value: ChainReadiness; at: number } | null = null;

  /** Lazy: lee las variables en el primer uso, no al importar el módulo. */
  private ensureInitialized(): boolean {
    if (this.initialized) return !!this.escrow;
    this.initialized = true;
    const cfg = readConfig();
    if (!cfg.enabled || !cfg.rpcUrl || !cfg.privateKey) {
      logger.info('[Blockchain] Deshabilitado', { enabled: cfg.enabled, hasRpc: !!cfg.rpcUrl, hasKey: !!cfg.privateKey });
      return false;
    }
    try {
      this.provider = new ethers.JsonRpcProvider(cfg.rpcUrl, undefined, { staticNetwork: false });
      this.wallet = new ethers.Wallet(cfg.privateKey, this.provider);
      if (cfg.escrowAddress) this.escrow = new ethers.Contract(cfg.escrowAddress, ESCROW_ABI, this.wallet);
      if (cfg.profilesAddress) this.profiles = new ethers.Contract(cfg.profilesAddress, PROFILES_ABI, this.wallet);
      logger.info('[Blockchain] Inicializado', {
        wallet: this.wallet.address, escrow: cfg.escrowAddress || 'none', profiles: cfg.profilesAddress || 'none',
      });
    } catch (err) {
      logger.error('[Blockchain] No se pudo inicializar', { error: shortError(err) });
      this.provider = null; this.wallet = null; this.escrow = null; this.profiles = null;
    }
    return !!this.escrow;
  }

  /** Solo para tests: vuelve a leer las variables de entorno. */
  resetForTests(): void {
    this.initialized = false;
    this.readiness = null;
    this.provider = null; this.wallet = null; this.escrow = null; this.profiles = null;
  }

  /**
   * ¿Se puede escribir? Verifica configuración, red, versión del contrato y que
   * el wallet sea el recorder. Cachea 5 min si está bien, 1 min si no.
   */
  async checkReady(force = false): Promise<ChainReadiness> {
    const now = Date.now();
    if (!force && this.readiness && now - this.readiness.at < (this.readiness.value.ok ? 300_000 : 60_000)) {
      return this.readiness.value;
    }
    const value = await this.computeReadiness();
    this.readiness = { value, at: now };
    return value;
  }

  private async computeReadiness(): Promise<ChainReadiness> {
    const cfg = readConfig();
    if (!cfg.enabled) return { ok: false, reason: 'DISABLED' };
    this.ensureInitialized();
    if (!this.provider || !this.wallet || !this.escrow) return { ok: false, reason: 'NOT_CONFIGURED' };
    if (!cfg.pepper || cfg.pepper.length < 32) return { ok: false, reason: 'MISSING_PEPPER' };

    let chainId: number;
    try {
      chainId = Number((await this.provider.getNetwork()).chainId);
    } catch (err) {
      return { ok: false, reason: 'RPC_UNAVAILABLE', detail: shortError(err) };
    }
    const base = { chainId, escrowAddress: cfg.escrowAddress, profilesAddress: cfg.profilesAddress || null };
    if (cfg.expectedChainId && cfg.expectedChainId !== chainId) {
      return { ok: false, reason: 'WRONG_NETWORK', detail: `RPC=${chainId}, esperado=${cfg.expectedChainId}`, ...base };
    }

    try {
      const version: bigint = await (this.escrow as any).VERSION();
      if (version !== ESCROW_VERSION) return { ok: false, reason: 'OUTDATED_CONTRACT', detail: `versión ${version}`, ...base };
      const recorder: string = await (this.escrow as any).recorder();
      if (recorder.toLowerCase() !== this.wallet.address.toLowerCase()) {
        return { ok: false, reason: 'NOT_RECORDER', detail: `recorder=${recorder}`, ...base };
      }
    } catch (err: any) {
      // Un contrato v2 no tiene VERSION(): la llamada revierte (CALL_EXCEPTION / BAD_DATA).
      if (err?.code === 'CALL_EXCEPTION' || err?.code === 'BAD_DATA') {
        return { ok: false, reason: 'OUTDATED_CONTRACT', detail: 'el contrato no expone VERSION()', ...base };
      }
      return { ok: false, reason: 'RPC_UNAVAILABLE', detail: shortError(err), ...base };
    }

    let profilesOk = false;
    if (this.profiles) {
      try {
        const v: bigint = await (this.profiles as any).VERSION();
        const rec: string = await (this.profiles as any).recorder();
        profilesOk = v === PROFILES_VERSION && rec.toLowerCase() === this.wallet.address.toLowerCase();
      } catch {
        profilesOk = false;
      }
    }
    return { ok: true, profilesOk, ...base };
  }

  /** Referencia seudónima on-chain de un usuario: HMAC-SHA256(pepper, id). Irreversible sin el secreto. */
  partyRef(userId: string): string {
    const pepper = readConfig().pepper;
    if (!pepper) throw new Error('BLOCKCHAIN_ID_PEPPER no configurado');
    return '0x' + createHmac('sha256', pepper).update(`garden:user:${userId}`).digest('hex');
  }

  private contract(target: ChainTarget): ethers.Contract {
    this.ensureInitialized();
    const c = target === 'escrow' ? this.escrow : this.profiles;
    if (!c) throw new Error(`Contrato ${target} no configurado`);
    return c;
  }

  /** Comisiones EIP-1559 con la propina mínima que exige Polygon. */
  async feeOverrides(chainId: number): Promise<{ maxFeePerGas: bigint; maxPriorityFeePerGas: bigint }> {
    const provider = this.provider!;
    const net = networkInfo(chainId)!;
    const block = await provider.getBlock('latest');
    const baseFee = block?.baseFeePerGas ?? ethers.parseUnits('30', 'gwei');
    let tip = ethers.parseUnits(String(net.minTipGwei), 'gwei');
    try {
      const suggested = BigInt(await provider.send('eth_maxPriorityFeePerGas', []));
      if (suggested > tip) tip = suggested;
    } catch { /* RPC sin ese método: queda el mínimo */ }
    const maxFeePerGas = baseFee * 2n + tip;
    const expectedGwei = Number(ethers.formatUnits(baseFee + tip, 'gwei'));
    if (expectedGwei > readConfig().maxFeeGwei) throw new GasTooHighError(expectedGwei);
    return { maxFeePerGas, maxPriorityFeePerGas: tip };
  }

  /** Traduce un error de ethers a ChainRevertError si fue un revert del contrato. */
  private asRevert(target: ChainTarget, err: any): ChainRevertError | null {
    if (err?.revert?.name) return new ChainRevertError(err.revert.name, [...(err.revert.args ?? [])]);
    const data: string | undefined = err?.data ?? err?.info?.error?.data ?? err?.error?.data;
    if (typeof data === 'string' && data.startsWith('0x') && data.length >= 10) {
      try {
        const parsed = this.contract(target).interface.parseError(data);
        if (parsed) return new ChainRevertError(parsed.name, [...parsed.args]);
      } catch { /* datos que no son de nuestro ABI */ }
    }
    if (err?.code === 'CALL_EXCEPTION' && err?.reason) return new ChainRevertError(String(err.reason));
    return null;
  }

  /**
   * Simula (estimateGas: si el contrato revertiría, lanza ChainRevertError sin
   * gastar gas) y envía. Devuelve el hash apenas la tx sale — la confirmación
   * se espera aparte para poder guardar el hash antes.
   */
  async send(target: ChainTarget, method: string, args: unknown[], chainId: number): Promise<{ hash: string; sentBlock: number }> {
    const c = this.contract(target);
    const fn = c.getFunction(method);
    let gas: bigint;
    try {
      gas = await fn.estimateGas(...args);
    } catch (err) {
      throw this.asRevert(target, err) ?? err;
    }
    const fees = await this.feeOverrides(chainId);
    const sentBlock = await this.provider!.getBlockNumber();
    try {
      const tx = await fn.send(...args, { ...fees, gasLimit: (gas * 12n) / 10n });
      logger.info('[Blockchain] tx enviada', { method, hash: tx.hash });
      return { hash: tx.hash, sentBlock };
    } catch (err) {
      throw this.asRevert(target, err) ?? err;
    }
  }

  async waitForReceipt(hash: string, confirmations = 2, timeoutMs = 90_000): Promise<ethers.TransactionReceipt | null> {
    this.ensureInitialized();
    try {
      return await this.provider!.waitForTransaction(hash, confirmations, timeoutMs);
    } catch (err: any) {
      if (err?.code === 'TIMEOUT') return null;
      throw err;
    }
  }

  async getReceipt(hash: string): Promise<ethers.TransactionReceipt | null> {
    this.ensureInitialized();
    return this.provider!.getTransactionReceipt(hash);
  }

  async getConfirmations(receipt: ethers.TransactionReceipt): Promise<number> {
    return receipt.confirmations();
  }

  async isKnownTransaction(hash: string): Promise<boolean> {
    this.ensureInitialized();
    return !!(await this.provider!.getTransaction(hash));
  }

  /**
   * Busca la tx que emitió el evento de `method` para una reserva (cuando el
   * contrato dice que ya está hecho pero no tenemos el hash: un reinicio justo
   * después de enviar, o una tx que se creyó perdida). Recorre en tramos de
   * 2.000 bloques desde `fromBlock`, BLOCKCHAIN_DEPLOY_BLOCK o los últimos ~2 días.
   */
  async findEventTx(method: string, bookingIdBytes16: string, fromBlock?: number | null): Promise<{ hash: string; blockNumber: number } | null> {
    const eventName = EVENT_OF_METHOD[method];
    if (!eventName) return null;
    const c = this.contract('escrow');
    const latest = await this.provider!.getBlockNumber();
    let start = fromBlock ?? readConfig().deployBlock ?? Math.max(0, latest - 90_000);
    const filter = (c.filters as any)[eventName](bookingIdBytes16);
    let last: { hash: string; blockNumber: number } | null = null;
    for (let i = 0; start <= latest && i < 200; i++) {
      const end = Math.min(start + 1_999, latest);
      const logs = await c.queryFilter(filter, start, end);
      for (const log of logs) last = { hash: log.transactionHash, blockNumber: log.blockNumber };
      start = end + 1;
    }
    return last;
  }

  /** Estado para GET /api/admin/blockchain/status. */
  async getStatus(): Promise<{
    enabled: boolean;
    ready: boolean;
    reason: string | null;
    reasonLabel: string | null;
    network: NetworkInfo | null;
    walletAddress: string | null;
    balancePol: number | null;
    lowBalancePol: number | null;
    escrowAddress: string | null;
    profilesAddress: string | null;
    hasEscrowContract: boolean;
    hasProfileContract: boolean;
    profilesReady: boolean;
    totalBookingsOnChain: number | null;
  }> {
    const cfg = readConfig();
    const readiness = await this.checkReady(true);
    const network = networkInfo(readiness.chainId ?? cfg.expectedChainId);
    let balancePol: number | null = null;
    let totalOnChain: number | null = null;
    if (this.wallet && this.provider) {
      try {
        balancePol = parseFloat(ethers.formatEther(await this.provider.getBalance(this.wallet.address)));
      } catch (err) {
        logger.error('[Blockchain] No se pudo leer el saldo del wallet', { error: shortError(err) });
      }
      if (readiness.ok) {
        try { totalOnChain = Number(await (this.escrow as any).totalBookings()); } catch { /* sin dato */ }
      }
    }
    const lowEnv = process.env.BLOCKCHAIN_LOW_BALANCE_POL ? Number(process.env.BLOCKCHAIN_LOW_BALANCE_POL) : null;
    return {
      enabled: cfg.enabled,
      ready: readiness.ok,
      reason: readiness.reason ?? null,
      reasonLabel: readiness.reason ? `${READY_REASON_LABEL[readiness.reason]}${readiness.detail ? ` (${readiness.detail})` : ''}` : null,
      network,
      walletAddress: this.wallet?.address ?? null,
      balancePol,
      lowBalancePol: lowEnv ?? network?.lowBalancePol ?? null,
      escrowAddress: cfg.escrowAddress || null,
      profilesAddress: cfg.profilesAddress || null,
      hasEscrowContract: !!this.escrow,
      hasProfileContract: !!this.profiles,
      profilesReady: !!readiness.profilesOk,
      totalBookingsOnChain: totalOnChain,
    };
  }

  /** Saldo del wallet y red, para el heartbeat. null si no está configurado. */
  async getWalletBalance(): Promise<{ address: string; balancePol: number; chainId: number; gasPriceWei: bigint } | null> {
    if (!readConfig().enabled || !this.ensureInitializedWallet()) return null;
    const [balance, net, fee] = await Promise.all([
      this.provider!.getBalance(this.wallet!.address),
      this.provider!.getNetwork(),
      this.provider!.getFeeData(),
    ]);
    return {
      address: this.wallet!.address,
      balancePol: parseFloat(ethers.formatEther(balance)),
      chainId: Number(net.chainId),
      gasPriceWei: fee.maxFeePerGas ?? fee.gasPrice ?? ethers.parseUnits('100', 'gwei'),
    };
  }

  private ensureInitializedWallet(): boolean {
    this.ensureInitialized();
    return !!(this.provider && this.wallet);
  }

  /**
   * Reputación on-chain del cuidador (suma y cantidad de calificaciones de
   * reservas finalizadas). `caregiverUserId` es el User.id del cuidador.
   */
  async getCaregiverReputation(caregiverUserId: string): Promise<{ average: number; count: number } | null> {
    const readiness = await this.checkReady();
    if (!readiness.ok) return null;
    try {
      const [totalRating, ratingCount]: [bigint, bigint] =
        await (this.escrow as any).getReputation(this.partyRef(caregiverUserId));
      const count = Number(ratingCount);
      if (count === 0) return null;
      return { average: Math.round((Number(totalRating) / count) * 10) / 10, count };
    } catch (err) {
      logger.warn('[Blockchain] No se pudo leer la reputación', { caregiverUserId, error: shortError(err) });
      return null;
    }
  }
}

export const blockchainService = new BlockchainService();

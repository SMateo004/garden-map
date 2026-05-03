import { ethers } from 'ethers';
import logger from '../shared/logger.js';

// ABI — GardenEscrow v2
// Synced with hardhat-garden/contracts/GardenEscrow.sol
const GARDEN_ESCROW_ABI = [
    "function createBooking(string _bookingId, string _clientId, string _caregiverId, uint256 _amountBs, uint256 _startTime, uint256 _endTime, string _petName, string _serviceType) external",
    "function finalizeBooking(string _bookingId, uint8 _rating) external",
    "function cancelBooking(string _bookingId, string _reason) external",
    "function resolveDisputeCaregiverWins(string _bookingId, uint256 _caregiverAmountBs) external",
    "function resolveDisputeClientWins(string _bookingId, uint256 _refundAmountBs) external",
    "function resolvePartial(string _bookingId, uint256 _caregiverAmountBs, uint256 _clientDiscountBs) external",
    "function extendWalk(string _bookingId, uint256 _additionalMinutes, uint256 _newAmountBs) external",
    "function getReputation(string _caregiverId) external view returns (uint256 totalRating, uint256 ratingCount)",
    "function getBooking(string _bookingId) external view returns (tuple(string bookingId, string clientId, string caregiverId, uint256 amountBs, uint256 startTime, uint256 endTime, bool isActive, bool isCompleted, uint8 rating, string petName, string serviceType))",
    "function totalBookings() external view returns (uint256)",
    "event BookingCreated(string indexed bookingId, string petName, uint256 amountBs)",
    "event PaymentConfirmed(string indexed bookingId, uint256 timestamp)",
    "event ServiceFinalized(string indexed bookingId, uint8 rating, uint256 timestamp)",
    "event ServiceCancelled(string indexed bookingId, string reason, uint256 timestamp)",
    "event DisputeResolved(string indexed bookingId, string verdict, uint256 caregiverAmountBs, uint256 clientDiscountBs, uint256 timestamp)",
    "event WalkExtended(string indexed bookingId, uint256 additionalMinutes, uint256 newAmountBs, uint256 timestamp)"
];

// ABI — GardenProfiles (unchanged)
const GARDEN_PROFILES_ABI = [
    "function syncProfile(string _userId, string _name, uint8 _role, bool _isVerified, string _metadataHash) external",
    "function updateVerificationStatus(string _userId, bool _status) external",
    "function addPetToOwner(string _ownerId, string _petName, string _breed) external",
    "function isUserVerified(string _userId) external view returns (bool)",
    "function profiles(string _userId) external view returns (tuple(string userId, string name, uint8 role, bool isVerified, uint256 joinedAt, string metadataHash, bool exists))",
    "function getOwnerPetsCount(string _ownerId) external view returns (uint256)"
];

class BlockchainService {
    private provider: ethers.Provider | null = null;
    private wallet: ethers.Wallet | null = null;
    private escrowContract: ethers.Contract | null = null;
    private profileContract: ethers.Contract | null = null;
    private initialized: boolean = false;

    /**
     * Lazy initialization: reads env vars at first use, not at import time.
     * This prevents MOCK MODE when the module loads before dotenv.config().
     */
    private ensureInitialized(): boolean {
        if (this.initialized) return !!this.escrowContract;

        this.initialized = true;

        const enabled = process.env.BLOCKCHAIN_ENABLED === 'true';
        const rpcUrl = process.env.BLOCKCHAIN_RPC_URL;
        const privateKey = process.env.BLOCKCHAIN_PRIVATE_KEY;
        const contractAddress = process.env.BLOCKCHAIN_CONTRACT_ADDRESS;
        const profileAddress = process.env.BLOCKCHAIN_PROFILES_ADDRESS;

        if (!enabled || !rpcUrl || !privateKey) {
            logger.info('[Blockchain] Service initialized (MOCK MODE)', {
                enabled,
                hasRpc: !!rpcUrl,
                hasKey: !!privateKey,
            });
            return false;
        }

        try {
            this.provider = new ethers.JsonRpcProvider(rpcUrl);
            this.wallet = new ethers.Wallet(privateKey, this.provider);

            if (contractAddress) {
                this.escrowContract = new ethers.Contract(contractAddress, GARDEN_ESCROW_ABI, this.wallet);
            }

            if (profileAddress) {
                this.profileContract = new ethers.Contract(profileAddress, GARDEN_PROFILES_ABI, this.wallet);
            }

            logger.info('[Blockchain] Service initialized (ENABLED)', {
                walletAddress: this.wallet.address,
                escrow: contractAddress ?? 'none',
                profiles: profileAddress ?? 'none',
            });
            return !!this.escrowContract;
        } catch (err) {
            logger.error('[Blockchain] Failed to initialize', { err });
            return false;
        }
    }

    // ─── RESERVAS (GardenEscrow) ──────────────────────────────────────────────

    async createBookingOnChain(
        bookingId: string,
        clientId: string,
        caregiverId: string,
        amountBs: number,
        startTime: Date,
        endTime: Date,
        petName: string,
        serviceType: string
    ): Promise<string | null> {
        if (!this.ensureInitialized() || !this.escrowContract) {
            logger.info('[Blockchain] Mock: createBooking', { bookingId, petName, amountBs });
            return null;
        }

        try {
            const startTimestamp = Math.floor(startTime.getTime() / 1000);
            const endTimestamp = Math.floor(endTime.getTime() / 1000);

            logger.info('[Blockchain] Sending createBooking tx...', { bookingId, amountBs, petName, serviceType });

            const tx = await (this.escrowContract as any).createBooking(
                bookingId, clientId, caregiverId, Math.floor(amountBs),
                startTimestamp, endTimestamp, petName, serviceType
            );

            const receipt = await tx.wait();
            logger.info('[Blockchain] Escrow created on-chain', { txHash: receipt.hash, bookingId, blockNumber: receipt.blockNumber });
            return receipt.hash;
        } catch (err: any) {
            if (err?.reason?.includes('ya existe') || err?.message?.includes('ya existe')) {
                logger.warn('[Blockchain] Booking already exists on-chain (duplicate call ignored)', { bookingId });
                return null;
            }
            logger.error('[Blockchain] Error creating booking on-chain', {
                bookingId,
                error: err?.reason || err?.message || err,
                code: err?.code,
            });
            return null;
        }
    }

    async finalizeBookingOnChain(bookingId: string, rating: number): Promise<string | null> {
        if (!this.ensureInitialized() || !this.escrowContract) return null;
        try {
            logger.info('[Blockchain] Sending finalizeBooking tx...', { bookingId, rating });
            const tx = await (this.escrowContract as any).finalizeBooking(bookingId, Math.floor(rating));
            const receipt = await tx.wait();
            logger.info('[Blockchain] Booking finalized on-chain', { txHash: receipt.hash, bookingId });
            return receipt.hash;
        } catch (err: any) {
            logger.error('[Blockchain] Error finalizing booking', { bookingId, error: err?.reason || err?.message });
            return null;
        }
    }

    async cancelBookingOnChain(bookingId: string, reason: string): Promise<string | null> {
        if (!this.ensureInitialized() || !this.escrowContract) return null;
        try {
            logger.info('[Blockchain] Sending cancelBooking tx...', { bookingId, reason });
            const tx = await (this.escrowContract as any).cancelBooking(bookingId, reason || 'No especificado');
            const receipt = await tx.wait();
            logger.info('[Blockchain] Booking cancelled on-chain', { txHash: receipt.hash, bookingId });
            return receipt.hash;
        } catch (err: any) {
            logger.error('[Blockchain] Error cancelling booking', { bookingId, error: err?.reason || err?.message });
            return null;
        }
    }

    // ─── PASEOS: extensión de tiempo ──────────────────────────────────────────

    /**
     * Registra la extensión de un paseo en GardenEscrow v2.
     * Llama a extendWalk(bookingId, additionalMinutes, newAmountBs).
     */
    async recordWalkExtensionOnChain(
        bookingId: string,
        additionalMinutes: number,
        newTotalAmountBs: number
    ): Promise<string | null> {
        if (!this.ensureInitialized() || !this.escrowContract) {
            logger.info('[Blockchain] Mock: recordWalkExtension (no contract)', { bookingId, additionalMinutes, newTotalAmountBs });
            return null;
        }

        try {
            logger.info('[Blockchain] Sending extendWalk tx...', { bookingId, additionalMinutes, newTotalAmountBs });
            const tx = await (this.escrowContract as any).extendWalk(
                bookingId,
                Math.floor(additionalMinutes),
                Math.floor(newTotalAmountBs)
            );
            const receipt = await tx.wait();
            logger.info('[Blockchain] Walk extended on-chain', { txHash: receipt.hash, bookingId, additionalMinutes });
            return receipt.hash;
        } catch (err: any) {
            logger.error('[Blockchain] Error extending walk on-chain', {
                bookingId,
                additionalMinutes,
                error: err?.reason || err?.message,
            });
            return null;
        }
    }

    // ─── PERFILES (GardenProfiles) ────────────────────────────────────────────

    async syncProfileOnChain(
        userId: string,
        name: string,
        role: 'CLIENT' | 'CAREGIVER',
        isVerified: boolean,
        metadata: string = ''
    ): Promise<string | null> {
        if (!this.ensureInitialized() || !this.profileContract) {
            logger.info('[Blockchain] Mock: syncProfile', { userId, name, role, isVerified });
            return null;
        }

        try {
            const roleIdx = role === 'CLIENT' ? 1 : 2;
            const tx = await (this.profileContract as any).syncProfile(userId, name, roleIdx, isVerified, metadata);
            const receipt = await tx.wait();
            logger.info('[Blockchain] Profile synced on-chain', { userId, txHash: receipt.hash });
            return receipt.hash;
        } catch (err: any) {
            logger.error('[Blockchain] Error syncing profile', { userId, error: err?.reason || err?.message });
            return null;
        }
    }

    async updateVerificationOnChain(userId: string, status: boolean): Promise<string | null> {
        if (!this.ensureInitialized() || !this.profileContract) return null;
        try {
            const tx = await (this.profileContract as any).updateVerificationStatus(userId, status);
            const receipt = await tx.wait();
            logger.info('[Blockchain] Verification updated on-chain', { userId, status, txHash: receipt.hash });
            return receipt.hash;
        } catch (err: any) {
            logger.error('[Blockchain] Error updating verification', { userId, error: err?.reason || err?.message });
            return null;
        }
    }

    async addPetOnChain(ownerId: string, petName: string, breed: string): Promise<string | null> {
        if (!this.ensureInitialized() || !this.profileContract) return null;
        try {
            const tx = await (this.profileContract as any).addPetToOwner(ownerId, petName, breed);
            const receipt = await tx.wait();
            logger.info('[Blockchain] Pet added on-chain', { ownerId, petName, txHash: receipt.hash });
            return receipt.hash;
        } catch (err: any) {
            logger.error('[Blockchain] Error adding pet on-chain', { ownerId, petName, error: err?.reason || err?.message });
            return null;
        }
    }

    // ─── DISPUTAS (GardenEscrow) ──────────────────────────────────────────────

    async resolveDisputeCaregiverWinsOnChain(bookingId: string, caregiverAmountBs: number): Promise<string | null> {
        if (!this.ensureInitialized() || !this.escrowContract) {
            logger.info('[Blockchain] Mock: resolveDisputeCaregiverWins', { bookingId, caregiverAmountBs });
            return null;
        }
        try {
            const tx = await (this.escrowContract as any).resolveDisputeCaregiverWins(
                bookingId, Math.floor(caregiverAmountBs)
            );
            const receipt = await tx.wait();
            logger.info('[Blockchain] Dispute resolved (CAREGIVER_WINS)', { txHash: receipt.hash, bookingId });
            return receipt.hash;
        } catch (err: any) {
            logger.error('[Blockchain] Error resolving dispute (caregiver wins)', { bookingId, error: err?.reason || err?.message });
            return null;
        }
    }

    async resolveDisputeClientWinsOnChain(bookingId: string, refundAmountBs: number): Promise<string | null> {
        if (!this.ensureInitialized() || !this.escrowContract) {
            logger.info('[Blockchain] Mock: resolveDisputeClientWins', { bookingId, refundAmountBs });
            return null;
        }
        try {
            const tx = await (this.escrowContract as any).resolveDisputeClientWins(
                bookingId, Math.floor(refundAmountBs)
            );
            const receipt = await tx.wait();
            logger.info('[Blockchain] Dispute resolved (CLIENT_WINS)', { txHash: receipt.hash, bookingId });
            return receipt.hash;
        } catch (err: any) {
            logger.error('[Blockchain] Error resolving dispute (client wins)', { bookingId, error: err?.reason || err?.message });
            return null;
        }
    }

    async resolvePartialOnChain(
        bookingId: string,
        caregiverAmountBs: number,
        clientDiscountBs: number
    ): Promise<string | null> {
        if (!this.ensureInitialized() || !this.escrowContract) {
            logger.info('[Blockchain] Mock: resolvePartial', { bookingId, caregiverAmountBs, clientDiscountBs });
            return null;
        }
        try {
            const tx = await (this.escrowContract as any).resolvePartial(
                bookingId,
                Math.floor(caregiverAmountBs),
                Math.floor(clientDiscountBs)
            );
            const receipt = await tx.wait();
            logger.info('[Blockchain] Dispute resolved (PARTIAL)', { txHash: receipt.hash, bookingId });
            return receipt.hash;
        } catch (err: any) {
            logger.error('[Blockchain] Error resolving partial dispute', { bookingId, error: err?.reason || err?.message });
            return null;
        }
    }

    // ─── REPUTACIÓN ───────────────────────────────────────────────────────────

    /**
     * Lee la reputación real del cuidador desde la blockchain.
     * Usa getReputation() view function de GardenEscrow v2.
     * @returns { average, count } o null si no hay datos o la blockchain no está disponible.
     */
    async getCaregiverReputation(
        caregiverId: string
    ): Promise<{ average: number; count: number } | null> {
        if (!this.ensureInitialized() || !this.escrowContract) {
            logger.info('[Blockchain] Mock: getCaregiverReputation (no contract)', { caregiverId });
            return null;
        }

        try {
            const [totalRating, ratingCount]: [bigint, bigint] =
                await (this.escrowContract as any).getReputation(caregiverId);

            const count = Number(ratingCount);
            const average = count > 0 ? Number(totalRating) / count : 0;

            logger.info('[Blockchain] Caregiver reputation read', { caregiverId, average, count });
            return { average: Math.round(average * 10) / 10, count };
        } catch (err: any) {
            logger.error('[Blockchain] Error reading caregiver reputation', {
                caregiverId,
                error: err?.reason || err?.message,
            });
            return null;
        }
    }
}

export const blockchainService = new BlockchainService();

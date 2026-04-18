import { ethers } from 'ethers';
import logger from '../shared/logger.js';

// ABI para GardenEscrow.sol
const GARDEN_ESCROW_ABI = [
    "function createBooking(string _bookingId, string _clientId, string _caregiverId, uint256 _amountBs, uint256 _startTime, uint256 _endTime, string _petName, string _serviceType) external",
    "function finalizeBooking(string _bookingId, uint8 _rating) external",
    "function cancelBooking(string _bookingId, string _reason) external",
    "function resolveDisputeCaregiverWins(string _bookingId, uint256 _caregiverAmountBs) external",
    "function resolveDisputeClientWins(string _bookingId, uint256 _refundAmountBs) external",
    "function resolvePartial(string _bookingId, uint256 _caregiverAmountBs, uint256 _clientDiscountBs) external",
    "function getBooking(string _bookingId) external view returns (tuple(string bookingId, string clientId, string caregiverId, uint256 amountBs, uint256 startTime, uint256 endTime, bool isActive, bool isCompleted, uint8 rating, string petName, string serviceType))",
    "function totalBookings() external view returns (uint256)",
    "event BookingCreated(string indexed bookingId, string petName, uint256 amountBs)",
    "event PaymentConfirmed(string indexed bookingId, uint256 timestamp)",
    "event ServiceFinalized(string indexed bookingId, uint8 rating, uint256 timestamp)",
    "event ServiceCancelled(string indexed bookingId, string reason, uint256 timestamp)",
    "event DisputeResolved(string indexed bookingId, string verdict, uint256 caregiverAmountBs, uint256 clientDiscountBs, uint256 timestamp)"
];

// ABI para GardenProfiles.sol
const GARDEN_PROFILES_ABI = [
    "function syncProfile(string _userId, string _name, uint8 _role, bool _isVerified, string _metadataHash) external",
    "function updateVerificationStatus(string _userId, bool _status) external",
    "function addPetToOwner(string _ownerId, string _petName, string _breed) external",
    "function isUserVerified(string _userId) external view returns (bool)",
    "function profiles(string _userId) external view returns (tuple(string userId, string name, uint8 role, bool isVerified, uint256 joinedAt, string metadataHash, bool exists))"
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

        // Read directly from process.env to avoid import-order issues with env.ts
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

    // --- LOGICA DE RESERVAS (GardenEscrow) ---

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
                bookingId, clientId, caregiverId, Math.floor(amountBs), startTimestamp, endTimestamp, petName, serviceType
            );

            const receipt = await tx.wait();
            logger.info('[Blockchain] Escrow created on-chain', { txHash: receipt.hash, bookingId, blockNumber: receipt.blockNumber });
            return receipt.hash;
        } catch (err: any) {
            // Check if the booking already exists on-chain (duplicate call)
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

    // --- LOGICA DE PERFILES (GardenProfiles) ---

    async syncProfileOnChain(userId: string, name: string, role: 'CLIENT' | 'CAREGIVER', isVerified: boolean, metadata: string = '') {
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

    async updateVerificationOnChain(userId: string, status: boolean) {
        if (!this.ensureInitialized() || !this.profileContract) return null;
        try {
            const tx = await (this.profileContract as any).updateVerificationStatus(userId, status);
            const receipt = await tx.wait();
            return receipt.hash;
        } catch (err: any) {
            logger.error('[Blockchain] Error updating verification', { userId, error: err?.reason || err?.message });
            return null;
        }
    }

    async addPetOnChain(ownerId: string, petName: string, breed: string) {
        if (!this.ensureInitialized() || !this.profileContract) return null;
        try {
            const tx = await (this.profileContract as any).addPetToOwner(ownerId, petName, breed);
            const receipt = await tx.wait();
            return receipt.hash;
        } catch (err: any) {
            logger.error('[Blockchain] Error adding pet on-chain', { ownerId, petName, error: err?.reason || err?.message });
            return null;
        }
    }

    async resolveDisputeCaregiverWinsOnChain(bookingId: string, caregiverAmountBs: number) {
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

    async resolveDisputeClientWinsOnChain(bookingId: string, refundAmountBs: number) {
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

    async resolvePartialOnChain(bookingId: string, caregiverAmountBs: number, clientDiscountBs: number) {
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

    /**
     * Registra la extensión de un paseo en la blockchain.
     * El contrato GardenEscrow no tiene todavía un método extendWalk;
     * por ahora se registra como log informativo (mock) y se actualiza el
     * monto total mediante cancelBooking + createBooking si es necesario.
     * Para el MVP se deja en mock mode: registra en los logs del servidor
     * y retorna null hasta que se despliegue la versión del contrato con extendWalk.
     */
    async recordWalkExtensionOnChain(
        bookingId: string,
        additionalMinutes: number,
        newTotalAmountBs: number
    ): Promise<string | null> {
        // MOCK MODE: el contrato actual no tiene extendWalk.
        // Cuando se despliegue GardenEscrow v2 con `extendWalk(string _bookingId, uint256 _additionalMinutes, uint256 _newAmountBs)`
        // se podrá usar escrowContract.extendWalk(...) aquí.
        logger.info('[Blockchain] Mock: recordWalkExtension', {
            bookingId,
            additionalMinutes,
            newTotalAmountBs,
            note: 'Pending GardenEscrow v2 deployment with extendWalk()',
        });
        return null;
    }

    async getCaregiverReputation(id: string) {
        if (!this.ensureInitialized()) return null;
        return { average: 5.0, count: 0 };
    }
}

export const blockchainService = new BlockchainService();

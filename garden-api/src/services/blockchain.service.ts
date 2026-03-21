import { ethers } from 'ethers';
import { env } from '../config/env.js';
import logger from '../shared/logger.js';

// ABI para GardenEscrow.sol
const GARDEN_ESCROW_ABI = [
    "function createBooking(string _bookingId, string _clientId, string _caregiverId, uint256 _amountBs, uint256 _startTime, uint256 _endTime, string _petName, string _serviceType) external",
    "function finalizeBooking(string _bookingId, uint8 _rating) external",
    "function cancelBooking(string _bookingId, string _reason) external",
    "function getBooking(string _bookingId) external view returns (tuple(string bookingId, string clientId, string caregiverId, uint256 amountBs, uint256 startTime, uint256 endTime, bool isActive, bool isCompleted, uint8 rating, string petName, string serviceType))",
    "event BookingCreated(string indexed bookingId, string petName, uint256 amountBs)",
    "event PaymentConfirmed(string indexed bookingId, uint256 timestamp)",
    "event ServiceFinalized(string indexed bookingId, uint8 rating, uint256 timestamp)",
    "event ServiceCancelled(string indexed bookingId, string reason, uint256 timestamp)"
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
    private enabled: boolean = false;

    constructor() {
        this.enabled = env.BLOCKCHAIN_ENABLED === true;

        if (this.enabled && env.BLOCKCHAIN_RPC_URL && env.BLOCKCHAIN_PRIVATE_KEY) {
            try {
                this.provider = new ethers.JsonRpcProvider(env.BLOCKCHAIN_RPC_URL);
                this.wallet = new ethers.Wallet(env.BLOCKCHAIN_PRIVATE_KEY, this.provider);

                if (env.BLOCKCHAIN_CONTRACT_ADDRESS) {
                    this.escrowContract = new ethers.Contract(env.BLOCKCHAIN_CONTRACT_ADDRESS, GARDEN_ESCROW_ABI, this.wallet);
                }

                // Usamos una nueva variable de entorno para el contrato de perfiles
                const profileAddress = process.env.BLOCKCHAIN_PROFILES_ADDRESS;
                if (profileAddress) {
                    this.profileContract = new ethers.Contract(profileAddress, GARDEN_PROFILES_ABI, this.wallet);
                }

                logger.info('Blockchain Service initialized (ENABLED)', {
                    escrow: !!this.escrowContract,
                    profiles: !!this.profileContract
                });
            } catch (err) {
                logger.error('Failed to initialize Blockchain Service', { err });
                this.enabled = false;
            }
        } else {
            logger.info('Blockchain Service initialized (MOCK MODE)');
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
    ) {
        if (!this.enabled || !this.escrowContract || !this.wallet) {
            logger.info('[Blockchain] Mock: createBooking (Escrow Virtual)', { bookingId, petName, amountBs });
            return null;
        }

        try {
            const startTimestamp = Math.floor(startTime.getTime() / 1000);
            const endTimestamp = Math.floor(endTime.getTime() / 1000);

            const tx = await (this.escrowContract as any).createBooking(
                bookingId, clientId, caregiverId, Math.floor(amountBs), startTimestamp, endTimestamp, petName, serviceType
            );

            const receipt = await tx.wait();
            logger.info('[Blockchain] Escrow Virtual created', { txHash: receipt.hash, bookingId });
            return receipt.hash;
        } catch (err) {
            logger.error('[Blockchain] Error creating booking', { bookingId, err });
            return null;
        }
    }

    async finalizeBookingOnChain(bookingId: string, rating: number) {
        if (!this.enabled || !this.escrowContract) return null;
        try {
            const tx = await (this.escrowContract as any).finalizeBooking(bookingId, Math.floor(rating));
            const receipt = await tx.wait();
            return receipt.hash;
        } catch (err) {
            logger.error('[Blockchain] Error finalizing booking', { bookingId, err });
            return null;
        }
    }

    async cancelBookingOnChain(bookingId: string, reason: string) {
        if (!this.enabled || !this.escrowContract) return null;
        try {
            const tx = await (this.escrowContract as any).cancelBooking(bookingId, reason || 'No especificado');
            const receipt = await tx.wait();
            return receipt.hash;
        } catch (err) {
            logger.error('[Blockchain] Error cancelling booking', { bookingId, err });
            return null;
        }
    }

    // --- LOGICA DE PERFILES (GardenProfiles) ---

    async syncProfileOnChain(userId: string, name: string, role: 'CLIENT' | 'CAREGIVER', isVerified: boolean, metadata: string = '') {
        if (!this.enabled || !this.profileContract) {
            logger.info('[Blockchain] Mock: syncProfile', { userId, name, role, isVerified });
            return null;
        }

        try {
            const roleIdx = role === 'CLIENT' ? 1 : 2;
            const tx = await (this.profileContract as any).syncProfile(userId, name, roleIdx, isVerified, metadata);
            const receipt = await tx.wait();
            logger.info('[Blockchain] Profile synced on-chain', { userId, txHash: receipt.hash });
            return receipt.hash;
        } catch (err) {
            logger.error('[Blockchain] Error syncing profile', { userId, err });
            return null;
        }
    }

    async updateVerificationOnChain(userId: string, status: boolean) {
        if (!this.enabled || !this.profileContract) return null;
        try {
            const tx = await (this.profileContract as any).updateVerificationStatus(userId, status);
            const receipt = await tx.wait();
            return receipt.hash;
        } catch (err) {
            logger.error('[Blockchain] Error updating verification', { userId, err });
            return null;
        }
    }

    async addPetOnChain(ownerId: string, petName: string, breed: string) {
        if (!this.enabled || !this.profileContract) return null;
        try {
            const tx = await (this.profileContract as any).addPetToOwner(ownerId, petName, breed);
            const receipt = await tx.wait();
            return receipt.hash;
        } catch (err) {
            logger.error('[Blockchain] Error adding pet on-chain', { ownerId, petName, err });
            return null;
        }
    }

    async getCaregiverReputation(id: string) {
        if (!this.enabled) return null;
        return { average: 5.0, count: 0 };
    }
}

export const blockchainService = new BlockchainService();

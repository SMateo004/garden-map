/**
 * backfill-profiles.ts
 * Syncs all existing users from the DB to GardenProfiles on-chain.
 * Run: npx ts-node scripts/backfill-profiles.ts
 */
import { ethers } from 'ethers';
import { PrismaClient } from '@prisma/client';
import * as dotenv from 'dotenv';
import * as path from 'path';

dotenv.config({ path: path.resolve(__dirname, '../../.env') });

const PROFILES_ABI = [
  "function syncProfile(string _userId, string _name, uint8 _role, bool _isVerified, string _metadataHash)",
  "function updateVerificationStatus(string _userId, bool _status)",
  "function profiles(string) view returns (string, string, uint8, bool, uint256, string, bool)",
  "function getOwnerPetsCount(string) view returns (uint256)",
  "function addPetToOwner(string _ownerId, string _petName, string _breed)",
];

const ROLE_MAP: Record<string, number> = { CLIENT: 1, CAREGIVER: 2, ADMIN: 0 };

async function main() {
  const RPC = process.env.BLOCKCHAIN_RPC_URL!;
  const PK  = process.env.BLOCKCHAIN_PRIVATE_KEY!;
  const ADDR = process.env.BLOCKCHAIN_PROFILES_ADDRESS!;

  if (!RPC || !PK || !ADDR) {
    throw new Error('Missing BLOCKCHAIN_RPC_URL / BLOCKCHAIN_PRIVATE_KEY / BLOCKCHAIN_PROFILES_ADDRESS');
  }

  const provider = new ethers.JsonRpcProvider(RPC);
  const wallet   = new ethers.Wallet(PK, provider);
  const contract = new ethers.Contract(ADDR, PROFILES_ABI, wallet);
  const prisma   = new PrismaClient();

  const balance = await provider.getBalance(wallet.address);
  console.log(`Wallet: ${wallet.address} — ${ethers.formatEther(balance)} MATIC\n`);

  // Fetch all non-deleted users
  const users = await prisma.user.findMany({
    where: { isDeleted: false },
    select: {
      id: true, firstName: true, lastName: true, role: true,
      caregiverProfile: { select: { verified: true } },
    },
    orderBy: { createdAt: 'asc' },
  });

  console.log(`Found ${users.length} users in DB. Syncing to blockchain...\n`);

  for (const user of users) {
    const name      = `${user.firstName} ${user.lastName}`;
    const roleNum   = ROLE_MAP[user.role] ?? 0;
    const verified  = user.caregiverProfile?.verified ?? false;

    // Check if already synced
    const existing = await contract.profiles(user.id);
    if (existing[6] === true) {
      console.log(`  ⏭  ${name} (${user.role}) — already on-chain, checking verification...`);
      // Update verification if needed
      const onChainVerified = existing[3];
      if (verified !== onChainVerified && user.role === 'CAREGIVER') {
        const tx = await contract.updateVerificationStatus(user.id, verified);
        const receipt = await tx.wait();
        console.log(`     🔄 Updated isVerified=${verified} — tx: ${receipt.hash}`);
      }
      continue;
    }

    try {
      console.log(`  ⬆  Syncing ${name} (${user.role}, verified=${verified})...`);
      const tx = await contract.syncProfile(user.id, name, roleNum, verified, '');
      const receipt = await tx.wait();
      console.log(`     ✅ Synced — block ${receipt.blockNumber}, tx: ${receipt.hash}`);
    } catch (err: any) {
      console.error(`     ❌ Failed: ${err?.reason || err?.message}`);
    }
  }

  // Also sync pets for CLIENT users
  console.log('\nSyncing pets...');
  const clients = users.filter(u => u.role === 'CLIENT');
  const petData = await prisma.pet.findMany({
    where: { owner: { role: 'CLIENT', isDeleted: false } },
    select: { id: true, name: true, breed: true, ownerId: true },
  });

  console.log(`Found ${petData.length} pets in DB.`);
  for (const pet of petData) {
    try {
      const petCount = await contract.getOwnerPetsCount(pet.ownerId);
      // Check if pet already registered (by checking existing slots)
      let alreadyExists = false;
      for (let i = 0; i < Number(petCount); i++) {
        const onChainPet = await contract.ownerPets(pet.ownerId, i);
        if (onChainPet[0] === pet.name) { alreadyExists = true; break; }
      }
      if (alreadyExists) {
        console.log(`  ⏭  Pet "${pet.name}" already on-chain for owner ${pet.ownerId.substring(0, 8)}...`);
        continue;
      }
      console.log(`  🐾 Adding pet "${pet.name}" (${pet.breed || 'Unknown'}) for owner ${pet.ownerId.substring(0, 8)}...`);
      const tx = await contract.addPetToOwner(pet.ownerId, pet.name, pet.breed || 'Unknown');
      const receipt = await tx.wait();
      console.log(`     ✅ Added — block ${receipt.blockNumber}, tx: ${receipt.hash}`);
    } catch (err: any) {
      console.error(`     ❌ Failed: ${err?.reason || err?.message}`);
    }
  }

  await prisma.$disconnect();

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('  Backfill complete! Run verify-profiles.ts to confirm.');
  console.log('═══════════════════════════════════════════════════════════');
}

main().catch(err => { console.error(err); process.exit(1); });

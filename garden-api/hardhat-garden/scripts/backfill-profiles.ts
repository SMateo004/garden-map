/**
 * backfill-profiles.ts
 *
 * Re-sincroniza en GardenProfiles todos los usuarios que no tienen blockchainTxHash
 * registrado en la DB (sync fallido silenciosamente en registros anteriores).
 *
 * Uso:
 *   cd garden-api/hardhat-garden
 *   npx ts-node --esm scripts/backfill-profiles.ts
 *
 * Variables de entorno requeridas (en garden-api/.env):
 *   DATABASE_URL, BLOCKCHAIN_RPC_URL, BLOCKCHAIN_PRIVATE_KEY, BLOCKCHAIN_PROFILES_ADDRESS
 */

import 'dotenv/config';
import { ethers } from 'ethers';
import { PrismaClient } from '@prisma/client';

const PROFILES_ABI = [
  'function syncProfile(string _userId, string _name, uint8 _role, bool _isVerified, string _metadataHash) external',
  'function addPetToOwner(string _ownerId, string _petName, string _breed) external',
  'function profiles(string _userId) external view returns (tuple(string userId, string name, uint8 role, bool isVerified, uint256 joinedAt, string metadataHash, bool exists))',
];

function roleIndex(role: string): number {
  return role === 'CLIENT' ? 1 : 2;
}

async function profileExists(contract: ethers.Contract, userId: string): Promise<boolean> {
  try {
    const p = await contract.profiles(userId);
    return p.exists === true;
  } catch {
    return false;
  }
}

async function main() {
  const rpcUrl = process.env.BLOCKCHAIN_RPC_URL;
  const privateKey = process.env.BLOCKCHAIN_PRIVATE_KEY;
  const profilesAddress = process.env.BLOCKCHAIN_PROFILES_ADDRESS;

  if (!rpcUrl || !privateKey || !profilesAddress) {
    console.error('❌  Faltan variables: BLOCKCHAIN_RPC_URL, BLOCKCHAIN_PRIVATE_KEY, BLOCKCHAIN_PROFILES_ADDRESS');
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);
  const contract = new ethers.Contract(profilesAddress, PROFILES_ABI, wallet);

  const balance = await provider.getBalance(wallet.address);
  console.log(`\n🔑  Wallet: ${wallet.address}`);
  console.log(`💰  Balance: ${ethers.formatEther(balance)} MATIC\n`);

  if (balance < ethers.parseEther('0.005')) {
    console.warn('⚠️   Balance bajo (< 0.005 MATIC). Recarga en https://faucet.polygon.technology\n');
  }

  const prisma = new PrismaClient();

  // Usuarios sin blockchainTxHash = sync nunca fue confirmado
  let unsynced: { id: string; firstName: string; lastName: string; role: string; emailVerified: boolean }[];
  try {
    unsynced = await prisma.user.findMany({
      where: { blockchainTxHash: null, isDeleted: false },
      select: { id: true, firstName: true, lastName: true, role: true, emailVerified: true },
      orderBy: { createdAt: 'asc' },
    });
  } catch (err) {
    console.error('❌  Error consultando la DB:', err);
    await prisma.$disconnect();
    process.exit(1);
  }

  console.log(`📋  ${unsynced.length} usuario(s) sin blockchainTxHash en la DB.\n`);

  const stats = { synced: 0, alreadyOnChain: 0, failed: 0 };

  for (const user of unsynced) {
    const name = `${user.firstName} ${user.lastName}`;

    // Verificar si ya existe en blockchain (pudo haberse sincronizado sin guardar el hash)
    const onChain = await profileExists(contract, user.id);
    if (onChain) {
      console.log(`  ⚠️   ${name} (${user.role}) — ya existe on-chain pero sin hash en DB. Actualizando...`);
      // Guardar un marcador para que no vuelva a aparecer en futuros backfills
      await prisma.user.update({ where: { id: user.id }, data: { blockchainTxHash: 'backfill-already-existed' } });
      stats.alreadyOnChain++;
      continue;
    }

    try {
      console.log(`  ⏳  Sincronizando ${name} (${user.role})...`);
      const tx = await (contract as any).syncProfile(
        user.id,
        name,
        roleIndex(user.role),
        user.emailVerified,
        ''
      );
      const receipt = await tx.wait();
      await prisma.user.update({ where: { id: user.id }, data: { blockchainTxHash: receipt.hash } });
      console.log(`  ✅  ${name} — tx: ${receipt.hash}`);
      stats.synced++;
    } catch (err: any) {
      console.error(`  ❌  ${name} — ERROR: ${err?.reason ?? err?.message ?? err}`);
      stats.failed++;
    }
  }

  console.log(`\nSincronizados: ${stats.synced} | Ya existían on-chain: ${stats.alreadyOnChain} | Fallidos: ${stats.failed}\n`);

  if (stats.failed > 0) {
    console.log('💡  Recarga MATIC y vuelve a ejecutar el script para reintentar los fallidos.');
    await prisma.$disconnect();
    process.exit(1);
  }

  await prisma.$disconnect();
}

async function backfillPets() {
  const rpcUrl = process.env.BLOCKCHAIN_RPC_URL;
  const privateKey = process.env.BLOCKCHAIN_PRIVATE_KEY;
  const profilesAddress = process.env.BLOCKCHAIN_PROFILES_ADDRESS;
  if (!rpcUrl || !privateKey || !profilesAddress) return;

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);
  const contract = new ethers.Contract(profilesAddress, PROFILES_ABI, wallet);
  const prisma = new PrismaClient();

  let pets: { id: string; name: string; breed: string | null; ownerId: string }[];
  try {
    pets = await (prisma as any).pet.findMany({
      select: { id: true, name: true, breed: true, ownerId: true },
    });
  } catch {
    await prisma.$disconnect();
    return;
  }
  await prisma.$disconnect();

  if (pets.length === 0) return;
  console.log(`\n🐾  ${pets.length} mascota(s). Sincronizando...\n`);

  for (const pet of pets) {
    if (!(await profileExists(contract, pet.ownerId))) {
      console.warn(`  ⚠️  ${pet.name} — dueño ${pet.ownerId} sin perfil on-chain. Ejecuta backfill de usuarios primero.`);
      continue;
    }
    try {
      const tx = await (contract as any).addPetToOwner(pet.ownerId, pet.name, pet.breed ?? '');
      const receipt = await tx.wait();
      console.log(`  ✅  ${pet.name} — tx: ${receipt.hash}`);
    } catch (err: any) {
      console.error(`  ❌  ${pet.name} — ERROR: ${err?.reason ?? err?.message ?? err}`);
    }
  }
}

main().then(() => backfillPets()).catch((err) => { console.error('Error fatal:', err); process.exit(1); });

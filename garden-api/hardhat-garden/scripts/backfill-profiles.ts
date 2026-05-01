/**
 * backfill-profiles.ts
 *
 * Sincroniza en blockchain todos los usuarios registrados en la base de datos
 * que todavía no tengan un perfil on-chain en GardenProfiles.
 *
 * Uso:
 *   npx ts-node --esm scripts/backfill-profiles.ts
 *   (o via hardhat: npx hardhat run scripts/backfill-profiles.ts --network amoy)
 *
 * Variables de entorno requeridas (.env en garden-api/):
 *   BLOCKCHAIN_RPC_URL, BLOCKCHAIN_PRIVATE_KEY, BLOCKCHAIN_PROFILES_ADDRESS, DATABASE_URL
 *
 * El script:
 *   1. Consulta la DB para obtener todos los User con su role y nombre.
 *   2. Por cada usuario, consulta el contrato GardenProfiles para ver si ya existe.
 *   3. Si no existe → llama syncProfile() en-cadena.
 *   4. Reporta resultado por usuario y al final imprime un resumen.
 *
 * Mascotas pendientes (addPetToOwner):
 *   Se sincronizan sólo si el dueño ya tiene perfil on-chain.
 *   Requiere MATIC adicional en la wallet.
 */

import 'dotenv/config';
import { ethers } from 'ethers';
import { PrismaClient } from '@prisma/client';

// ─── ABI mínimo ──────────────────────────────────────────────────────────────

const PROFILES_ABI = [
  'function syncProfile(string _userId, string _name, uint8 _role, bool _isVerified, string _metadataHash) external',
  'function addPetToOwner(string _ownerId, string _petName, string _breed) external',
  'function profiles(string _userId) external view returns (tuple(string userId, string name, uint8 role, bool isVerified, uint256 joinedAt, string metadataHash, bool exists))',
];

// ─── Helpers ─────────────────────────────────────────────────────────────────

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

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const rpcUrl = process.env.BLOCKCHAIN_RPC_URL;
  const privateKey = process.env.BLOCKCHAIN_PRIVATE_KEY;
  const profilesAddress = process.env.BLOCKCHAIN_PROFILES_ADDRESS;

  if (!rpcUrl || !privateKey || !profilesAddress) {
    console.error(
      '❌  Faltan variables de entorno: BLOCKCHAIN_RPC_URL, BLOCKCHAIN_PRIVATE_KEY, BLOCKCHAIN_PROFILES_ADDRESS'
    );
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);
  const contract = new ethers.Contract(profilesAddress, PROFILES_ABI, wallet);

  const balance = await provider.getBalance(wallet.address);
  console.log(`\n🔑  Wallet: ${wallet.address}`);
  console.log(`💰  Balance: ${ethers.formatEther(balance)} MATIC\n`);

  if (balance < ethers.parseEther('0.005')) {
    console.warn(
      '⚠️   Balance bajo (< 0.005 MATIC). Las transacciones pueden fallar.\n' +
        '    Recarga en https://faucet.polygon.technology\n'
    );
  }

  const prisma = new PrismaClient();

  let users: { id: string; firstName: string; lastName: string; role: string; emailVerified: boolean }[];
  try {
    users = await prisma.user.findMany({
      select: { id: true, firstName: true, lastName: true, role: true, emailVerified: true },
      orderBy: { createdAt: 'asc' },
    });
  } finally {
    await prisma.$disconnect();
  }

  console.log(`📋  ${users.length} usuario(s) encontrados en la DB.\n`);

  const stats = { synced: 0, alreadyExists: 0, failed: 0 };

  for (const user of users) {
    const name = `${user.firstName} ${user.lastName}`;
    const alreadyOnChain = await profileExists(contract, user.id);

    if (alreadyOnChain) {
      console.log(`  ✅  ${name} (${user.role}) — ya existe on-chain, omitiendo.`);
      stats.alreadyExists++;
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
      console.log(`  ✅  ${name} — tx: ${receipt.hash}`);
      stats.synced++;
    } catch (err: any) {
      console.error(`  ❌  ${name} — ERROR: ${err?.reason ?? err?.message ?? err}`);
      stats.failed++;
    }
  }

  console.log('\n─────────────────────────────────────────');
  console.log(`Resumen:`);
  console.log(`  Sincronizados:    ${stats.synced}`);
  console.log(`  Ya existían:      ${stats.alreadyExists}`);
  console.log(`  Fallidos:         ${stats.failed}`);
  console.log('─────────────────────────────────────────\n');

  if (stats.failed > 0) {
    console.log('💡  Para los fallidos, recarga MATIC y vuelve a ejecutar el script.');
    process.exit(1);
  }
}

// ─── Mascotas pendientes ──────────────────────────────────────────────────────

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
    // Pet model may not exist in all schema versions
    await prisma.$disconnect();
    return;
  }
  await prisma.$disconnect();

  if (pets.length === 0) return;

  console.log(`\n🐾  ${pets.length} mascota(s) encontradas. Sincronizando...\n`);

  for (const pet of pets) {
    const ownerOnChain = await profileExists(contract, pet.ownerId);
    if (!ownerOnChain) {
      console.warn(
        `  ⚠️   Mascota ${pet.name} — dueño ${pet.ownerId} no tiene perfil on-chain. Ejecuta el backfill de usuarios primero.`
      );
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

main()
  .then(() => backfillPets())
  .catch((err) => {
    console.error('Error fatal:', err);
    process.exit(1);
  });

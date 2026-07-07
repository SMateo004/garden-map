/**
 * Crea cuentas de prueba en producción (sin reservas ni mascotas de test).
 * Ejecutar: npx tsx scripts/create-test-users.ts
 */

import { PrismaClient, UserRole, CaregiverStatus, ServiceType, Zone } from '@prisma/client';
import bcrypt from 'bcrypt';
import dotenv from 'dotenv';
dotenv.config();

const prisma = new PrismaClient();
const SALT_ROUNDS = 12;
const PASSWORD = process.env.SEED_PASSWORD ?? 'GardenSeed2024!';

async function main() {
  const hash = await bcrypt.hash(PASSWORD, SALT_ROUNDS);

  // Cliente de prueba
  const client = await prisma.user.upsert({
    where: { email: 'cliente@garden.bo' },
    update: { passwordHash: hash },
    create: {
      email: 'cliente@garden.bo', passwordHash: hash,
      role: UserRole.CLIENT, firstName: 'Juan', lastName: 'Pérez',
      phone: '78889990', country: 'Bolivia', city: 'Santa Cruz', isOver18: true,
    },
  });
  await prisma.clientProfile.upsert({
    where: { userId: client.id },
    update: {},
    create: { userId: client.id, address: 'Calle Falsa 123, Santa Cruz' },
  });
  console.log(`✅ Cliente: ${client.email}`);

  // Cuidador APPROVED
  const caregiver = await prisma.user.upsert({
    where: { email: 'cuidador@garden.bo' },
    update: { passwordHash: hash },
    create: {
      email: 'cuidador@garden.bo', passwordHash: hash,
      role: UserRole.CAREGIVER, firstName: 'Sofía', lastName: 'Méndez',
      phone: '75556667', country: 'Bolivia', city: 'Santa Cruz', isOver18: true,
    },
  });
  await prisma.caregiverProfile.upsert({
    where: { userId: caregiver.id },
    update: { status: CaregiverStatus.APPROVED },
    create: {
      userId: caregiver.id, status: CaregiverStatus.APPROVED, verified: true,
      servicesOffered: [ServiceType.HOSPEDAJE, ServiceType.PASEO],
      zone: Zone.URBARI,
      bio: 'Cuidadora certificada con amplia experiencia en razas grandes y pequeñas.',
      address: 'Barrio Urbari, Santa Cruz',
      termsAccepted: true, privacyAccepted: true, verificationAccepted: true,
      ciNumber: '7654321-TEST',
      pricePerWalk30: 30, pricePerWalk60: 50, pricePerDay: 120,
    },
  });
  console.log(`✅ Cuidador APPROVED: ${caregiver.email}`);

  // Cuidador DRAFT
  const draft = await prisma.user.upsert({
    where: { email: 'cuidador.draft@garden.bo' },
    update: { passwordHash: hash },
    create: {
      email: 'cuidador.draft@garden.bo', passwordHash: hash,
      role: UserRole.CAREGIVER, firstName: 'María', lastName: 'García',
      phone: '71234567', country: 'Bolivia', city: 'Santa Cruz', isOver18: true,
    },
  });
  await prisma.caregiverProfile.upsert({
    where: { userId: draft.id },
    update: {},
    create: {
      userId: draft.id, status: CaregiverStatus.DRAFT,
      servicesOffered: [ServiceType.HOSPEDAJE],
      zone: Zone.EQUIPETROL,
      bio: 'En proceso de completar mi perfil.',
      address: 'Zona Equipetrol, Santa Cruz',
    },
  });
  console.log(`✅ Cuidador DRAFT: ${draft.email}`);

  console.log(`\n🔑 Contraseña de todas las cuentas: ${PASSWORD}`);
}

main()
  .catch(e => { console.error('❌ Error:', e); process.exit(1); })
  .finally(() => prisma.$disconnect());

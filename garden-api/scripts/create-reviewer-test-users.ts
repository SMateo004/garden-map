/**
 * Cuentas de prueba para revisores de App Store / Play Store.
 * Ejecutar: npx tsx scripts/create-reviewer-test-users.ts
 */
import { PrismaClient, UserRole, CaregiverStatus, ServiceType, Zone } from '@prisma/client';
import bcrypt from 'bcrypt';
import dotenv from 'dotenv';
dotenv.config();

const prisma = new PrismaClient();
const SALT_ROUNDS = 12;
const PASSWORD = 'ReviewGarden2026!';

async function main() {
  const hash = await bcrypt.hash(PASSWORD, SALT_ROUNDS);

  const client = await prisma.user.upsert({
    where: { email: 'reviewer.cliente@gardenbo.com' },
    update: { passwordHash: hash },
    create: {
      email: 'reviewer.cliente@gardenbo.com', passwordHash: hash,
      role: UserRole.CLIENT, firstName: 'Reviewer', lastName: 'Cliente',
      phone: '70099902', country: 'Bolivia', city: 'Santa Cruz', isOver18: true,
    },
  });
  await prisma.clientProfile.upsert({
    where: { userId: client.id },
    update: {},
    create: { userId: client.id, address: 'Av. San Martín, Equipetrol, Santa Cruz' },
  });
  console.log(`✅ Cliente reviewer: ${client.email}`);

  const caregiver = await prisma.user.upsert({
    where: { email: 'reviewer.cuidador@gardenbo.com' },
    update: { passwordHash: hash },
    create: {
      email: 'reviewer.cuidador@gardenbo.com', passwordHash: hash,
      role: UserRole.CAREGIVER, firstName: 'Reviewer', lastName: 'Cuidador',
      phone: '70099903', country: 'Bolivia', city: 'Santa Cruz', isOver18: true,
    },
  });
  await prisma.caregiverProfile.upsert({
    where: { userId: caregiver.id },
    update: { status: CaregiverStatus.APPROVED, verified: true },
    create: {
      userId: caregiver.id, status: CaregiverStatus.APPROVED, verified: true,
      servicesOffered: [ServiceType.HOSPEDAJE, ServiceType.PASEO],
      zone: Zone.URBARI,
      bio: 'Cuenta de prueba para revisión de App Store / Play Store.',
      address: 'Barrio Urbari, Santa Cruz',
      termsAccepted: true, privacyAccepted: true, verificationAccepted: true,
      ciNumber: '9999999-REVIEWER',
      pricePerWalk30: 30, pricePerWalk60: 50, pricePerDay: 120,
    },
  });
  console.log(`✅ Cuidador reviewer (APPROVED): ${caregiver.email}`);

  console.log(`\n🔑 Contraseña de las 3 cuentas reviewer: ${PASSWORD}`);
}

main().catch(e => { console.error('❌ Error:', e); process.exit(1); }).finally(() => prisma.$disconnect());

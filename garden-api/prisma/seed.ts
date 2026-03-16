/**
 * Seed GARDEN MVP: 1 admin, 2 cuidadores (DRAFT + PENDING_REVIEW).
 * Ejecutar: npx prisma db seed
 */

import { PrismaClient, UserRole, CaregiverStatus, ServiceType, Zone } from '@prisma/client';
import bcrypt from 'bcrypt';

const prisma = new PrismaClient();

const SALT_ROUNDS = 10;
const SEED_PASSWORD = 'GardenSeed2024!';

async function main() {
  const hash = await bcrypt.hash(SEED_PASSWORD, SALT_ROUNDS);

  // 1. Admin (update passwordHash para que re-ejecutar seed restablezca la contraseña)
  const admin = await prisma.user.upsert({
    where: { email: 'admin@garden.bo' },
    update: { passwordHash: hash },
    create: {
      email: 'admin@garden.bo',
      passwordHash: hash,
      role: UserRole.ADMIN,
      firstName: 'Admin',
      lastName: 'GARDEN',
      phone: '+59170000000',
      country: 'Bolivia',
      city: 'Santa Cruz',
      isOver18: true,
    },
  });
  console.log('Admin:', admin.email);

  // 2. Cuidador DRAFT (datos parciales)
  const userDraft = await prisma.user.upsert({
    where: { email: 'cuidador.draft@garden.bo' },
    update: { passwordHash: hash },
    create: {
      email: 'cuidador.draft@garden.bo',
      passwordHash: hash,
      role: UserRole.CAREGIVER,
      firstName: 'María',
      lastName: 'García',
      phone: '+59171234567',
      country: 'Bolivia',
      city: 'Santa Cruz',
      isOver18: true,
    },
  });

  await prisma.caregiverProfile.upsert({
    where: { userId: userDraft.id },
    update: {},
    create: {
      userId: userDraft.id,
      status: CaregiverStatus.DRAFT,
      servicesOffered: [ServiceType.HOSPEDAJE, ServiceType.PASEO],
      photos: [
        'https://placehold.co/800x600/4ade80/166534?text=Foto+1',
        'https://placehold.co/800x600/4ade80/166534?text=Foto+2',
        'https://placehold.co/800x600/4ade80/166534?text=Foto+3',
        'https://placehold.co/800x600/4ade80/166534?text=Foto+4',
      ],
      zone: Zone.EQUIPETROL,
      bio: 'Me encantan los perros y tengo espacio en casa. En proceso de completar mi perfil.',
      address: 'Zona Equipetrol, Santa Cruz',
    },
  });
  console.log('Cuidador DRAFT:', userDraft.email);

  // 3. Cuidador PENDING_REVIEW
  const userPending = await prisma.user.upsert({
    where: { email: 'cuidador.pending@garden.bo' },
    update: { passwordHash: hash },
    create: {
      email: 'cuidador.pending@garden.bo',
      passwordHash: hash,
      role: UserRole.CAREGIVER,
      firstName: 'Carlos',
      lastName: 'López',
      phone: '+59172223334',
      country: 'Bolivia',
      city: 'La Paz',
      isOver18: true,
    },
  });

  await prisma.caregiverProfile.upsert({
    where: { userId: userPending.id },
    update: {
      status: CaregiverStatus.PENDING_REVIEW,
      photos: [
        'https://placehold.co/800x600/4ade80/166534?text=Foto+1',
        'https://placehold.co/800x600/4ade80/166534?text=Foto+2',
        'https://placehold.co/800x600/4ade80/166534?text=Foto+3',
        'https://placehold.co/800x600/4ade80/166534?text=Foto+4',
      ],
      ciAnversoUrl: 'https://placehold.co/800x500/166534/white/png?text=CI+Anverso',
      ciReversoUrl: 'https://placehold.co/800x500/166534/white/png?text=CI+Reverso',
      ciNumber: '1234567-TEST',
      termsAccepted: true,
      privacyAccepted: true,
      verificationAccepted: true,
    },
    create: {
      userId: userPending.id,
      status: CaregiverStatus.PENDING_REVIEW,
      servicesOffered: [ServiceType.PASEO],
      photos: [
        'https://placehold.co/800x600/4ade80/166534?text=Foto+1',
        'https://placehold.co/800x600/4ade80/166534?text=Foto+2',
        'https://placehold.co/800x600/4ade80/166534?text=Foto+3',
        'https://placehold.co/800x600/4ade80/166534?text=Foto+4',
      ],
      zone: Zone.EQUIPETROL,
      bio: 'Paseos y cuidado de mascotas con experiencia. Más de 50 caracteres para cumplir validación del formulario de registro.',
      address: 'Equipetrol, Santa Cruz',
      ciAnversoUrl: 'https://placehold.co/800x500/166534/white/png?text=CI+Anverso',
      ciReversoUrl: 'https://placehold.co/800x500/166534/white/png?text=CI+Reverso',
      ciNumber: '1234567-TEST',
      termsAccepted: true,
      privacyAccepted: true,
      verificationAccepted: true,
    },
  });
  console.log('Cuidador PENDING_REVIEW:', userPending.email);

  console.log('Seed completado. Contraseña de prueba:', SEED_PASSWORD);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });

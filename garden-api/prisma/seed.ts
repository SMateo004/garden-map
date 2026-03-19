/**
 * Seed GARDEN MVP: 1 admin, 2 cuidadores (DRAFT + PENDING_REVIEW).
 * Ejecutar: npx prisma db seed
 */

import { PrismaClient, UserRole, CaregiverStatus, ServiceType, Zone, PetSize, BookingStatus } from '@prisma/client';
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

  console.log('Cuidador PENDING_REVIEW:', userPending.email);

  // 4. CLIENTE
  const userClient = await prisma.user.upsert({
    where: { email: 'cliente@garden.bo' },
    update: { passwordHash: hash },
    create: {
      email: 'cliente@garden.bo',
      passwordHash: hash,
      role: UserRole.CLIENT,
      firstName: 'Juan',
      lastName: 'Pérez',
      phone: '+59178889990',
      country: 'Bolivia',
      city: 'Santa Cruz',
      isOver18: true,
    },
  });

  const clientProfile = await prisma.clientProfile.upsert({
    where: { userId: userClient.id },
    update: { isComplete: true },
    create: {
      userId: userClient.id,
      isComplete: true,
      address: 'Calle Falsa 123, Santa Cruz'
    }
  });
  console.log('Cliente:', userClient.email);

  // 5. CUIDADOR APPROVED
  const userVerified = await prisma.user.upsert({
    where: { email: 'cuidador@garden.bo' },
    update: { passwordHash: hash },
    create: {
      email: 'cuidador@garden.bo',
      passwordHash: hash,
      role: UserRole.CAREGIVER,
      firstName: 'Sofía',
      lastName: 'Méndez',
      phone: '+59175556667',
      country: 'Bolivia',
      city: 'Santa Cruz',
      isOver18: true,
    },
  });

  const approvedProfile = await prisma.caregiverProfile.upsert({
    where: { userId: userVerified.id },
    update: {
      status: CaregiverStatus.APPROVED,
      verified: true,
      profilePhoto: 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&q=80&w=200&h=200',
      photos: [
        'https://images.unsplash.com/photo-1548191265-cc70d3d45e1a?auto=format&fit=crop&q=80&w=800&h=600',
        'https://images.unsplash.com/photo-1516734212186-a967f81ad0d7?auto=format&fit=crop&q=80&w=800&h=600',
        'https://images.unsplash.com/photo-1537151608828-ea2b11777ee8?auto=format&fit=crop&q=80&w=800&h=600',
      ],
      pricePerWalk30: 30,
      pricePerWalk60: 50,
      pricePerDay: 120,
    },
    create: {
      userId: userVerified.id,
      status: CaregiverStatus.APPROVED,
      verified: true,
      profilePhoto: 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&q=80&w=200&h=200',
      photos: [
        'https://images.unsplash.com/photo-1548191265-cc70d3d45e1a?auto=format&fit=crop&q=80&w=800&h=600',
        'https://images.unsplash.com/photo-1516734212186-a967f81ad0d7?auto=format&fit=crop&q=80&w=800&h=600',
        'https://images.unsplash.com/photo-1537151608828-ea2b11777ee8?auto=format&fit=crop&q=80&w=800&h=600',
      ],
      servicesOffered: [ServiceType.HOSPEDAJE, ServiceType.PASEO],
      zone: Zone.URBARI,
      bio: 'Cuidadora certificada con amplia experiencia en razas grandes y pequeñas.',
      address: 'Barrio Urbari, Santa Cruz',
      termsAccepted: true,
      privacyAccepted: true,
      verificationAccepted: true,
      ciNumber: '7654321-TEST',
      pricePerWalk30: 30,
      pricePerWalk60: 50,
      pricePerDay: 120,
    },
  });
  console.log('Cuidador APPROVED:', userVerified.email);

  // 6. MASCOTA
  const pet = await prisma.pet.create({
    data: {
      clientProfileId: clientProfile.id,
      name: 'Firulais',
      breed: 'Golden Retriever',
      age: 2,
      size: PetSize.LARGE,
      notes: 'Muy juguetón y sociable. Le encanta el agua.',
    },
  });

  // 7. BOOKING (para probar Chat)
  await prisma.booking.create({
    data: {
      clientId: userClient.id,
      caregiverId: approvedProfile.id,
      petId: pet.id,
      petName: pet.name,
      petBreed: pet.breed,
      petAge: pet.age,
      petSize: pet.size,
      serviceType: ServiceType.PASEO,
      status: BookingStatus.CONFIRMED,
      totalAmount: 50.0,
      pricePerUnit: 50.0,
      commissionAmount: 7.5, // 15%
      walkDate: new Date(),
      startTime: '10:00',
      duration: 60,
    }
  });

  console.log('Seed completado con datos de prueba (Mascota + Reserva).');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });

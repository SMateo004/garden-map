/**
 * Crea (o restablece la contraseña de) el usuario ADMIN en producción.
 * Ejecutar: npx tsx scripts/create-admin.ts
 * Usa DATABASE_URL y ADMIN_PASSWORD del entorno.
 */

import { PrismaClient, UserRole } from '@prisma/client';
import bcrypt from 'bcrypt';
import dotenv from 'dotenv';
dotenv.config();

const prisma = new PrismaClient();
const SALT_ROUNDS = 12;

const ADMIN_EMAIL    = process.env.ADMIN_EMAIL    ?? 'admin@garden.bo';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'GardenSeed2024!';

async function main() {
  if (!process.env.ADMIN_PASSWORD) {
    console.warn('⚠️  ADMIN_PASSWORD no está definido — usando contraseña por defecto (solo para desarrollo).');
  }

  const hash = await bcrypt.hash(ADMIN_PASSWORD, SALT_ROUNDS);

  const admin = await prisma.user.upsert({
    where: { email: ADMIN_EMAIL },
    update: { passwordHash: hash, role: UserRole.ADMIN },
    create: {
      email:        ADMIN_EMAIL,
      passwordHash: hash,
      role:         UserRole.ADMIN,
      firstName:    'Admin',
      lastName:     'GARDEN',
      phone:        '70000000',
      country:      'Bolivia',
      city:         'Santa Cruz',
      isOver18:     true,
    },
  });

  console.log(`✅ Admin listo: ${admin.email} (id: ${admin.id})`);
  console.log(`   Contraseña: ${ADMIN_PASSWORD}`);
}

main()
  .catch(e => { console.error('❌ Error:', e); process.exit(1); })
  .finally(() => prisma.$disconnect());

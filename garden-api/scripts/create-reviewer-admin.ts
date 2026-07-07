import { PrismaClient, UserRole } from '@prisma/client';
import bcrypt from 'bcrypt';
import dotenv from 'dotenv';
dotenv.config();

const prisma = new PrismaClient();
const SALT_ROUNDS = 12;
const EMAIL = 'reviewer.admin@gardenbo.com';
const PASSWORD = 'ReviewGarden2026!';

async function main() {
  const hash = await bcrypt.hash(PASSWORD, SALT_ROUNDS);
  const admin = await prisma.user.upsert({
    where: { email: EMAIL },
    update: { passwordHash: hash, role: UserRole.ADMIN },
    create: {
      email: EMAIL, passwordHash: hash, role: UserRole.ADMIN,
      firstName: 'Reviewer', lastName: 'GARDEN',
      phone: '70099901', country: 'Bolivia', city: 'Santa Cruz', isOver18: true,
    },
  });
  console.log(`✅ Admin reviewer listo: ${admin.email} (id: ${admin.id})`);
  console.log(`   Contraseña: ${PASSWORD}`);
}
main().catch(e => { console.error('❌ Error:', e); process.exit(1); }).finally(() => prisma.$disconnect());

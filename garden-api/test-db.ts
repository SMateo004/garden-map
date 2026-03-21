import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
async function main() {
  console.log('Connecting...');
  await prisma.$connect();
  console.log('Connected!');
  const users = await prisma.user.count();
  console.log('Users count:', users);
  await prisma.$disconnect();
}
main().catch(console.error);

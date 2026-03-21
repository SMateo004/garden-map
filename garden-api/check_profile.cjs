const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
async function run() {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { userId: 'c78ef370-7110-47bb-b770-6e03ec00694b' }
  });
  console.log(JSON.stringify(profile, null, 2));
}
run().finally(() => prisma.$disconnect());

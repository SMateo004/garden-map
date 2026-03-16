import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
async function main() {
    const av = await prisma.availability.findMany({ take: 10, orderBy: { createdAt: 'desc' } });
    console.log(JSON.stringify(av, null, 2));
}
main().finally(() => prisma.$disconnect());

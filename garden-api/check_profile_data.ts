import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
    const profiles = await prisma.caregiverProfile.findMany({
        include: {
            user: true
        },
        take: 1,
        orderBy: { updatedAt: 'desc' }
    });
    console.log(JSON.stringify(profiles, null, 2));
}

main().catch(console.error).finally(() => prisma.$disconnect());

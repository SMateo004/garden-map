import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
    const profile = await prisma.caregiverProfile.findFirst({
        where: { userId: '79587d31-a7e2-40db-a78c-79ae46b367fa' },
        select: { id: true, userId: true, identityVerificationStatus: true, identityVerificationScore: true }
    });
    console.log(JSON.stringify(profile, null, 2));
}

main()
    .catch((e) => {
        console.error(e);
        process.exit(1);
    })
    .finally(async () => {
        await prisma.$disconnect();
    });

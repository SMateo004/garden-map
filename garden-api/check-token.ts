import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
    const profile = await prisma.caregiverProfile.findFirst({
        where: {
            OR: [
                { id: '361cecbd-bb7e-42d5-9e70-b108c51ced20' },
                { userId: '361cecbd-bb7e-42d5-9e70-b108c51ced20' }
            ]
        },
        select: { id: true, userId: true, identityVerificationToken: true, user: { select: { firstName: true, lastName: true, identityVerified: true } } }
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

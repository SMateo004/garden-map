import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
    const caregivers = await prisma.user.findMany({
        where: { role: 'CAREGIVER' },
        select: { id: true, email: true, firstName: true, lastName: true },
        take: 5
    });
    console.log(JSON.stringify(caregivers, null, 2));
}

main()
    .catch((e) => {
        console.error(e);
        process.exit(1);
    })
    .finally(async () => {
        await prisma.$disconnect();
    });

import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function checkApprovedCaregivers() {
    const caregivers = await prisma.caregiverProfile.findMany({
        where: { status: 'APPROVED' },
        select: {
            id: true,
            status: true,
            user: {
                select: { firstName: true, lastName: true }
            },
            availability: {
                where: { date: { gte: new Date() } },
                take: 3
            }
        }
    });

    console.log(JSON.stringify(caregivers, null, 2));
    await prisma.$disconnect();
}

checkApprovedCaregivers();

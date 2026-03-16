import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function checkAvailability() {
    const caregivers = await prisma.caregiverProfile.findMany({
        take: 5,
        select: {
            id: true,
            user: {
                select: {
                    firstName: true,
                    lastName: true,
                }
            },
            defaultAvailabilitySchedule: true,
            availability: {
                take: 5,
                orderBy: { date: 'asc' }
            }
        }
    });

    console.log(JSON.stringify(caregivers, null, 2));
    await prisma.$disconnect();
}

checkAvailability();

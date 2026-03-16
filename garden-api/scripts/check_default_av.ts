import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
    const caregiverId = '361cecbd-bb7e-42d5-9e70-b108c51ced20';
    const profile = await prisma.caregiverProfile.findUnique({
        where: { id: caregiverId },
        select: { defaultAvailabilitySchedule: true }
    });
    console.log('DefaultSchedule:', JSON.stringify(profile?.defaultAvailabilitySchedule, null, 2));
}

main().finally(() => prisma.$disconnect());

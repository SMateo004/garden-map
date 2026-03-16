import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
    const caregiverId = '361cecbd-bb7e-42d5-9e70-b108c51ced20';
    const walkDate = new Date('2026-02-28T00:00:00.000Z');

    const avail = await prisma.availability.findUnique({
        where: {
            caregiverId_date: { caregiverId, date: walkDate }
        },
    });

    console.log(`--- AVAILABILITY for Feb 28 ---`);
    if (avail) {
        console.log(`ID: ${avail.id}`);
        console.log(`IsAvailable: ${avail.isAvailable}`);
        console.log(`TimeBlocks: ${JSON.stringify(avail.timeBlocks)}`);
    } else {
        const profile = await prisma.caregiverProfile.findUnique({
            where: { id: caregiverId },
            select: { defaultAvailabilitySchedule: true }
        });
        console.log(`NO explicit avail. Default: ${JSON.stringify(profile?.defaultAvailabilitySchedule)}`);
    }
}

main().catch(err => console.error(err));

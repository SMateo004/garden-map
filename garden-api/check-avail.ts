import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
    const avails = await prisma.availability.findMany({
        take: 5,
        orderBy: { createdAt: 'desc' },
    });
    console.log('--- RECENT AVAILABILITY OVERRIDES ---');
    for (const a of avails) {
        console.log(`Caregiver: ${a.caregiverId} | Date: ${a.date.toISOString().slice(0, 10)} | isAvailable: ${a.isAvailable}`);
        console.log('timeBlocks:', JSON.stringify(a.timeBlocks, null, 2));
        console.log('---');
    }

    const caregivers = await prisma.caregiverProfile.findMany({
        take: 5,
        select: { id: true, defaultAvailabilitySchedule: true },
    });
    console.log('--- CAREGIVER DEFAULT SCHEDULES ---');
    for (const c of caregivers) {
        console.log(`Caregiver: ${c.id}`);
        console.log('defaultSchedule:', JSON.stringify(c.defaultAvailabilitySchedule, null, 2));
        console.log('---');
    }
}

main().catch(err => console.error(err));

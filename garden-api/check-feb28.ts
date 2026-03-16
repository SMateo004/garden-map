import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
    const caregiverId = '361cecbd-bb7e-42d5-9e70-b108c51ced20';
    const walkDate = new Date('2026-02-28T00:00:00.000Z');

    const bookings = await prisma.booking.findMany({
        where: {
            caregiverId,
            serviceType: 'PASEO',
            walkDate,
            status: { not: 'CANCELLED' }
        },
    });

    console.log(`--- ACTIVE BOOKINGS for Feb 28 ---`);
    for (const b of bookings) {
        console.log(`ID: ${b.id}`);
        console.log(`StartTime: [${b.startTime}] (Type: ${typeof b.startTime})`);
        console.log(`TimeSlot: ${b.timeSlot}`);
        console.log(`Duration: ${b.duration}`);
        console.log(`Status: ${b.status}`);
        console.log('---');
    }
}

main().catch(err => console.error(err));

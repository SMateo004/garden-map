import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
    const caregiverId = '361cecbd-bb7e-42d5-9e70-b108c51ced20';
    const bookings = await prisma.booking.findMany({
        where: {
            caregiverId,
            serviceType: 'PASEO',
            status: { not: 'CANCELLED' }
        },
        orderBy: { walkDate: 'desc' },
    });

    console.log(`--- BOOKINGS for Caregiver ${caregiverId} ---`);
    for (const b of bookings) {
        console.log(`ID: ${b.id}`);
        console.log(`Date: ${b.walkDate} | Slot: ${b.timeSlot}`);
        console.log(`Start: "${b.startTime}" (${typeof b.startTime}) | Duration: ${b.duration} | Status: ${b.status}`);
        console.log('---');
    }
}

main().catch(err => console.error(err));

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
    });

    console.log(`--- ALL ACTIVE PASEO BOOKINGS summary ---`);
    for (const b of bookings) {
        console.log(`ID: ${b.id} | Date: ${b.walkDate?.toISOString()} | Start: "${b.startTime}" | Slot: ${b.timeSlot}`);
    }
}

main().catch(err => console.error(err));

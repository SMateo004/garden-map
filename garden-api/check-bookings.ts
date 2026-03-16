import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
    const bookings = await prisma.booking.findMany({
        where: { serviceType: 'PASEO' },
        orderBy: { createdAt: 'desc' },
        take: 10,
    });

    console.log('--- RECENT PASEO BOOKINGS ---');
    for (const b of bookings) {
        console.log(`Booking ID: ${b.id}`);
        console.log(`Caregiver: ${b.caregiverId} | Date: ${b.walkDate} | Slot: ${b.timeSlot}`);
        console.log(`Start: ${b.startTime} | Duration: ${b.duration} | Status: ${b.status}`);
        console.log('---');
    }
}

main().catch(err => console.error(err));

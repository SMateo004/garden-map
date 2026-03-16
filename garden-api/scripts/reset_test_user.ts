import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
    const password = await bcrypt.hash('Garden123!', 10);
    const user = await prisma.user.update({
        where: { email: 'mateo@test.com' }, // Assuming this exists or I'll find one
        data: { password }
    });
    console.log('Password reset for:', user.email);
    process.exit(0);
}

main().catch(console.error);

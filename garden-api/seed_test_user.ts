import prisma from './src/config/database.js';
import bcrypt from 'bcrypt';

async function main() {
    const hash = await bcrypt.hash('test1234', 10);
    const user = await prisma.user.upsert({
        where: { email: 'test@garden.com' },
        update: { passwordHash: hash },
        create: {
            email: 'test@garden.com',
            passwordHash: hash,
            firstName: 'Usuario',
            lastName: 'Test',
            phone: '76543210',
            role: 'CLIENT',
            emailVerified: true,
        },
    });
    console.log('✅ Usuario listo:', user.id, user.email, user.role);
    await prisma.$disconnect();
}

main().catch((e) => { console.error(e); process.exit(1); });

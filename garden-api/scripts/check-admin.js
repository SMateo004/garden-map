
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
    const users = await prisma.user.findMany({
        where: { role: 'ADMIN' },
        select: { email: true }
    });
    console.log('Admins:', users);
}

main()
    .catch(console.error)
    .finally(() => prisma.$disconnect());

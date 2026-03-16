import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
    const users = await prisma.user.findMany({
        where: { email: { contains: 'draft' } },
        select: { email: true, id: true }
    });
    console.log('Draft users:', users);

    const caregiver = await prisma.caregiverProfile.findFirst({
        where: { user: { email: 'cuidador.draft@garden.bo' } },
        include: { user: true }
    });
    if (caregiver) {
        console.log('Caregiver Draft:', {
            email: caregiver.user.email,
            bio: caregiver.bio,
            photos: caregiver.photos,
            status: caregiver.status,
            profileStatus: caregiver.profileStatus
        });
    } else {
        console.log('Caregiver draft not found');
    }
}

main().catch(console.error).finally(() => prisma.$disconnect());

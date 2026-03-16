
import { PrismaClient } from '@prisma/client';
import { getMissingRequiredFieldsForSubmit } from './src/modules/caregiver-profile/caregiver-profile.validation.js';

const prisma = new PrismaClient();

async function main() {
    const profile = await prisma.caregiverProfile.findFirst({
        where: { user: { email: 'cuidador.draft@garden.bo' } }
    });
    if (!profile) return;

    const missing = getMissingRequiredFieldsForSubmit({
        bio: profile.bio,
        zone: profile.zone,
        servicesOffered: profile.servicesOffered,
        photos: profile.photos,
        termsAccepted: profile.termsAccepted,
        privacyAccepted: profile.privacyAccepted,
        verificationAccepted: profile.verificationAccepted,
        identityVerificationStatus: profile.identityVerificationStatus,
    });

    console.log('Missing:', missing);
}

main().finally(() => prisma.$disconnect());

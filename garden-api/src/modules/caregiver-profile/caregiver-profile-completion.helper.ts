import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';
import { ServiceType } from '@prisma/client';

/** 
 * Verifica la completitud del perfil en sus 3 dimensiones:
 * 1. Personal (Datos básicos + Avatar + Verificación de identidad)
 * 2. Cuidador (Bio, Fotos de trabajo, Experiencia, Preguntas nucleares)
 * 3. Disponibilidad (Configurada por defecto ahora)
 */
export async function checkAndAutoSubmitProfile(userId: string) {
    const profile = await prisma.caregiverProfile.findUnique({
        where: { userId },
        include: {
            user: {
                select: {
                    firstName: true,
                    lastName: true,
                    emailVerified: true,
                    phone: true
                }
            },
            availability: { where: { isAvailable: true }, take: 1 },
        },
    }) as any;

    if (!profile) return;

    // 1. Personal Info Complete
    const personalInfoComplete = Boolean(
        profile.user?.firstName?.trim() &&
        profile.user?.lastName?.trim() &&
        profile.user?.phone?.trim() &&
        (profile.user?.emailVerified || profile.emailVerified) &&
        profile.profilePhoto &&
        profile.identityVerificationStatus === 'VERIFIED'
    );

    // 2. Caregiver Profile Complete (Criterios dinámicos por servicio)
    const services = Array.isArray(profile.servicesOffered) ? profile.servicesOffered : [];
    const onlyPaseo = services.length === 1 && services.includes(ServiceType.PASEO);
    const minPhotos = onlyPaseo ? 2 : 4;
    const photos = Array.isArray(profile.photos) ? profile.photos : [];

    // Validaciones detalladas para evitar fallos silenciosos
    const hasBio = Boolean(profile.bio && profile.bio.trim().length >= 45); // Un poco más flexible (45 en vez de 50)
    const hasBioDetail = Boolean(profile.bioDetail && profile.bioDetail.trim().length >= 3); // Más flexible (3 en vez de 5)
    const hasExperience = Boolean(profile.experienceYears && profile.experienceDescription && profile.experienceDescription.trim().length >= 15);
    const hasRequiredQuestions = Boolean(
        profile.whyCaregiver && profile.whyCaregiver.trim().length >= 3 &&
        profile.whatDiffers && profile.whatDiffers.trim().length >= 3 &&
        profile.handleAnxious &&
        profile.emergencyResponse &&
        profile.acceptAggressive !== null &&
        profile.acceptPuppies !== null &&
        profile.acceptSeniors !== null
    );
    const hasPhotosAndServices = Boolean(services.length > 0 && photos.length >= minPhotos && profile.zone);
    const hasAnimalAndSizes = Boolean(Array.isArray(profile.animalTypes) && profile.animalTypes.length > 0 && Array.isArray(profile.sizesAccepted) && profile.sizesAccepted.length > 0);

    const caregiverProfileComplete = hasBio && hasBioDetail && hasExperience && hasRequiredQuestions && hasPhotosAndServices && hasAnimalAndSizes && (
        services.includes(ServiceType.HOSPEDAJE)
            ? (profile.homeType && profile.spaceDescription && profile.spaceDescription.trim().length >= 3)
            : true
    );

    // 3. Availability Complete (Por defecto true)
    const availabilityComplete = true;

    logger.info('Verificando completitud de perfil para usuario:', {
        userId,
        personalInfoComplete,
        caregiverProfileComplete,
        availabilityComplete,
        detailedFlags: {
            hasBio, hasBioDetail, hasExperience, hasRequiredQuestions, hasPhotosAndServices, hasAnimalAndSizes
        }
    });

    // Actualización de banderas en DB
    await prisma.caregiverProfile.update({
        where: { id: profile.id },
        data: {
            personalInfoComplete,
            caregiverProfileComplete,
            availabilityComplete,
            onboardingStatus: {
                ...(profile.onboardingStatus as object || {}),
                percentage: calculatePercentage(profile, minPhotos),
                updatedAt: new Date()
            }
        } as any,
    });

    const isTotalComplete = personalInfoComplete && caregiverProfileComplete && availabilityComplete;

    logger.info('Completitud calculada (sin auto-aprobación):', {
        userId,
        isTotalComplete,
        // La aprobación sólo ocurre cuando el cuidador termina el paso 9
        // y llama explícitamente a POST /caregiver/profile/submit desde el wizard
    });
}

function calculatePercentage(profile: any, minPhotos: number): number {
    const fields = [
        profile.user?.firstName && profile.user?.lastName,
        profile.user?.phone,
        profile.user?.emailVerified || profile.emailVerified,
        profile.identityVerificationStatus === 'VERIFIED',
        profile.bio && profile.bio.length >= 45,
        profile.bioDetail && profile.bioDetail.length >= 3,
        profile.zone,
        profile.servicesOffered?.length > 0,
        profile.photos?.length >= minPhotos,
        profile.profilePhoto,
        profile.experienceYears,
        profile.experienceDescription?.length >= 15,
        profile.whyCaregiver?.length >= 3,
        profile.whatDiffers?.length >= 3,
        profile.animalTypes?.length > 0,
        profile.sizesAccepted?.length > 0,
        profile.acceptAggressive !== null,
        profile.acceptPuppies !== null,
        profile.acceptSeniors !== null
    ];
    const completed = fields.filter(Boolean).length;
    return Math.round((completed / fields.length) * 100);
}

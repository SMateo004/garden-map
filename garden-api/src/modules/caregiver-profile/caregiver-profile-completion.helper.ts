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
    // profile.photos es un campo legacy que ya no escribe el wizard (usa
    // caregiverPhotos) — con "photos" esto siempre daba length 0 sin importar
    // cuántas fotos subiera el cuidador, dejando caregiverProfileComplete mal.
    const photos = Array.isArray(profile.caregiverPhotos) ? profile.caregiverPhotos : [];

    // Validaciones detalladas para evitar fallos silenciosos
    const hasBio = Boolean(profile.bio && profile.bio.trim().length >= 50); // Matches submitProfile minimum (50 chars)
    const hasBioDetail = Boolean(profile.bioDetail && profile.bioDetail.trim().length >= 3);
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

    const caregiverProfileComplete = Boolean(hasBio && hasBioDetail && hasExperience && hasRequiredQuestions && hasPhotosAndServices && hasAnimalAndSizes && (
        services.includes(ServiceType.HOSPEDAJE)
            ? (profile.homeType && profile.spaceDescription && profile.spaceDescription.trim().length >= 3)
            : true
    ));

    // 3. Availability Complete — caregiver must have at least a price set for each offered service
    const hasPaseoPrice = Boolean(profile.pricePerWalk30 != null || profile.pricePerWalk60 != null);
    const hasHospedajePrice = Boolean(profile.pricePerDay != null);
    const offersHospedaje = services.includes(ServiceType.HOSPEDAJE);
    const offersPaseo = services.includes(ServiceType.PASEO);
    const availabilityComplete = Boolean(
      services.length > 0 &&
      (!offersHospedaje || hasHospedajePrice) &&
      (!offersPaseo || hasPaseoPrice)
    );

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
    const services: string[] = Array.isArray(profile.servicesOffered) ? profile.servicesOffered : [];
    const offersPaseo     = services.includes('PASEO');
    const offersHospedaje = services.includes('HOSPEDAJE');
    const offersGuarderia = services.includes('GUARDERIA');
    const needsSpace      = offersHospedaje || offersGuarderia;

    // Precio según servicio
    const hasPaseoPrice     = offersPaseo     ? (profile.pricePerWalk30 != null || profile.pricePerWalk60 != null) : true;
    const hasHospedajePrice = offersHospedaje ? (profile.pricePerDay != null && profile.pricePerDay > 0)           : true;
    const hasGuarderiaPrice = offersGuarderia ? (profile.pricePerGuarderia != null && profile.pricePerGuarderia > 0) : true;

    // Fotos del lugar (solo si ofrece hospedaje/guarderia)
    const placePhotos = profile.placePhotos ?? {};
    const hasPlacePhotos = needsSpace
        ? (['sala', 'descanso', 'alimentacion'].every((s: string) => Array.isArray(placePhotos[s]) && placePhotos[s].length > 0))
        : true;

    // Fotos del cuidador en acción (campo nuevo)
    const caregiverPhotos = Array.isArray(profile.caregiverPhotos) ? profile.caregiverPhotos : [];
    const hasPhotos = caregiverPhotos.length >= minPhotos;

    // Cuidador principiante (0 años) — no se le exige descripción larga de experiencia,
    // igual que en la UI de "Datos del cuidador" donde ese campo ni se muestra.
    const isAmateur = profile.experienceYears === 0;
    const hasExperienceDesc = isAmateur || (profile.experienceDescription?.length >= 15);

    const fields = [
        // Descripción
        (profile.bioDetail && profile.bioDetail.length >= 3) || (profile.bio && profile.bio.length >= 10),
        // Servicios
        // Nota: no se exige profile.zone aquí — no es un campo editable dentro
        // de "Datos del cuidador" (vive en "Editar perfil" → Ubicación), así que
        // no debe contar para la completitud de esta sección.
        services.length > 0,
        // Precios según servicio
        hasPaseoPrice,
        hasHospedajePrice,
        hasGuarderiaPrice,
        // Fotos
        hasPhotos,
        hasPlacePhotos,
        // Experiencia
        profile.experienceYears != null,
        hasExperienceDesc,
        // Preguntas clave
        profile.whyCaregiver?.length >= 3,
        profile.whatDiffers?.length >= 3,
        // Tipos y tamaños
        Array.isArray(profile.animalTypes) && profile.animalTypes.length > 0,
        Array.isArray(profile.sizesAccepted) && profile.sizesAccepted.length > 0,
        // Políticas
        profile.acceptAggressive !== null && profile.acceptAggressive !== undefined,
        profile.acceptPuppies   !== null && profile.acceptPuppies   !== undefined,
        profile.acceptSeniors   !== null && profile.acceptSeniors   !== undefined,
    ];
    const completed = fields.filter(Boolean).length;
    return Math.round((completed / fields.length) * 100);
}

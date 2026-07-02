import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  const email = process.argv[2];
  if (!email) {
    console.error('Uso: npx tsx scripts/debug-completion.ts <email>');
    process.exit(1);
  }

  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) {
    console.error('Usuario no encontrado:', email);
    process.exit(1);
  }

  const profile = await prisma.caregiverProfile.findUnique({ where: { userId: user.id } }) as any;
  if (!profile) {
    console.error('No tiene perfil de cuidador');
    process.exit(1);
  }

  const services: string[] = Array.isArray(profile.servicesOffered) ? profile.servicesOffered : [];
  const offersPaseo = services.includes('PASEO');
  const offersHospedaje = services.includes('HOSPEDAJE');
  const offersGuarderia = services.includes('GUARDERIA');
  const needsSpace = offersHospedaje || offersGuarderia;
  const onlyPaseo = services.length === 1 && offersPaseo;
  const minPhotos = onlyPaseo ? 2 : 4;

  const hasPaseoPrice = offersPaseo ? (profile.pricePerWalk30 != null || profile.pricePerWalk60 != null) : true;
  const hasHospedajePrice = offersHospedaje ? (profile.pricePerDay != null && profile.pricePerDay > 0) : true;
  const hasGuarderiaPrice = offersGuarderia ? (profile.pricePerGuarderia != null && profile.pricePerGuarderia > 0) : true;

  const placePhotos = profile.placePhotos ?? {};
  const hasPlacePhotos = needsSpace
    ? (['sala', 'descanso', 'alimentacion'].every((s) => Array.isArray(placePhotos[s]) && placePhotos[s].length > 0))
    : true;

  const caregiverPhotos = Array.isArray(profile.caregiverPhotos) ? profile.caregiverPhotos : [];
  const hasPhotos = caregiverPhotos.length >= minPhotos;

  const isAmateur = profile.experienceYears === 0;
  const hasExperienceDesc = isAmateur || (profile.experienceDescription?.length >= 15);

  const checks: Record<string, boolean> = {
    'bio/bioDetail': (profile.bioDetail && profile.bioDetail.length >= 3) || (profile.bio && profile.bio.length >= 10),
    'services.length > 0': services.length > 0,
    hasPaseoPrice,
    hasHospedajePrice,
    hasGuarderiaPrice,
    hasPhotos,
    hasPlacePhotos,
    'experienceYears != null': profile.experienceYears != null,
    hasExperienceDesc,
    'whyCaregiver >= 3': profile.whyCaregiver?.length >= 3,
    'whatDiffers >= 3': profile.whatDiffers?.length >= 3,
    'animalTypes.length > 0': Array.isArray(profile.animalTypes) && profile.animalTypes.length > 0,
    'sizesAccepted.length > 0': Array.isArray(profile.sizesAccepted) && profile.sizesAccepted.length > 0,
    'acceptAggressive defined': profile.acceptAggressive !== null && profile.acceptAggressive !== undefined,
    'acceptPuppies defined': profile.acceptPuppies !== null && profile.acceptPuppies !== undefined,
    'acceptSeniors defined': profile.acceptSeniors !== null && profile.acceptSeniors !== undefined,
  };

  console.log('\n=== RAW VALUES ===');
  console.log({
    servicesOffered: profile.servicesOffered,
    bioDetail: profile.bioDetail,
    bio: profile.bio,
    pricePerWalk30: profile.pricePerWalk30,
    pricePerWalk60: profile.pricePerWalk60,
    pricePerDay: profile.pricePerDay,
    pricePerGuarderia: profile.pricePerGuarderia,
    caregiverPhotos: profile.caregiverPhotos,
    placePhotos: profile.placePhotos,
    experienceYears: profile.experienceYears,
    experienceDescription: profile.experienceDescription,
    whyCaregiver: profile.whyCaregiver,
    whatDiffers: profile.whatDiffers,
    animalTypes: profile.animalTypes,
    sizesAccepted: profile.sizesAccepted,
    acceptAggressive: profile.acceptAggressive,
    acceptPuppies: profile.acceptPuppies,
    acceptSeniors: profile.acceptSeniors,
    onboardingStatus: profile.onboardingStatus,
  });

  console.log('\n=== CHECKS ===');
  let failedAny = false;
  for (const [name, val] of Object.entries(checks)) {
    console.log(`${val ? '✅' : '❌'} ${name}`);
    if (!val) failedAny = true;
  }

  const total = Object.keys(checks).length;
  const passed = Object.values(checks).filter(Boolean).length;
  console.log(`\n${passed}/${total} → ${Math.round((passed / total) * 100)}%`);
  console.log(failedAny ? '\n⚠️  Hay campos incompletos.' : '\n✅ Todo completo.');

  await prisma.$disconnect();
}

main().catch((e) => { console.error(e); process.exit(1); });

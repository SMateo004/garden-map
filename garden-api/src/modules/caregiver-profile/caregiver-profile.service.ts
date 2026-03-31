/**
 * Servicio: flujo de registro cuidador con guardado progresivo.
 * - getMyProfile: datos para rellenar wizard.
 * - patchProfile: actualización parcial; 403 si status APPROVED; mantiene/cambia a DRAFT.
 * - submitProfile: validar campos obligatorios, status → PENDING_REVIEW, notificar admin.
 */

import { randomBytes } from 'crypto';
import prisma from '../../config/database.js';
import { CaregiverStatus } from '@prisma/client';
import { BadRequestError, ForbiddenError, ConflictError, AvailabilityConflictError } from '../../shared/errors.js';
import { getCache, delByPrefix } from '../../shared/cache.js';
import { ensureAbsoluteUrl, ensureAbsoluteUrls } from '../../shared/upload-utils.js';
import type { PatchCaregiverProfileBody, PatchAvailabilityBody } from './caregiver-profile.validation.js';
import {
  getMissingRequiredFieldsForSubmit,
  type RequiredSubmitField,
} from './caregiver-profile.validation.js';
import logger from '../../shared/logger.js';
import { checkAndAutoSubmitProfile } from './caregiver-profile-completion.helper.js';
import { blockchainService } from '../../services/blockchain.service.js';

const ADMIN_NOTIFICATION_TYPE_SUBMIT = 'CAREGIVER_SUBMIT';

/** PATCH user-info: actualiza nombre, email, teléfono. Si cambia el email → emailVerified = false. */
export async function patchUserInfo(
  userId: string,
  body: { firstName?: string; lastName?: string; phone?: string; email?: string }
) {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { userId },
    select: { id: true, profileStatus: true },
  });
  if (!profile) throw new BadRequestError('No tienes perfil de cuidador', 'CAREGIVER_PROFILE_NOT_FOUND');

  // Se permite editar aunque esté APPROVED (ej: cambio de teléfono).
  if (profile.profileStatus === 'SUBMITTED' || profile.profileStatus === 'UNDER_REVIEW') {
    throw new ForbiddenError(
      'Tu perfil está en revisión y no puede ser editado en este momento.',
      'PROFILE_IN_REVIEW_READONLY'
    );
  }

  const currentUser = await prisma.user.findUnique({
    where: { id: userId },
    select: { email: true, phone: true },
  });

  const userUpdateData: Record<string, unknown> = {};
  if (body.firstName !== undefined && body.firstName.trim()) {
    userUpdateData.firstName = body.firstName.trim();
  }
  if (body.lastName !== undefined && body.lastName.trim()) {
    userUpdateData.lastName = body.lastName.trim();
  }
  // phone is @unique String (not nullable) — only update if non-empty and actually different
  if (body.phone !== undefined && body.phone.trim() && body.phone.trim() !== currentUser?.phone) {
    userUpdateData.phone = body.phone.trim();
  }

  const newEmail = body.email?.trim().toLowerCase();
  const emailChanged = newEmail && newEmail !== currentUser?.email?.toLowerCase();
  if (emailChanged) {
    userUpdateData.email = newEmail;
    // Reset email verification — user must re-verify
    await prisma.caregiverProfile.update({
      where: { id: profile.id },
      data: { emailVerified: false, personalInfoComplete: false } as any,
    });
    logger.info('Email changed — emailVerified reset', { userId, newEmail });
  }

  if (Object.keys(userUpdateData).length === 0) {
    return { updated: false, emailChanged: false };
  }

  try {
    await prisma.user.update({
      where: { id: userId },
      data: userUpdateData,
    });
  } catch (err: any) {
    // Prisma unique constraint violation (P2002)
    if (err?.code === 'P2002') {
      const targets: string[] = err?.meta?.target ?? [];
      const field = targets.includes('email') ? 'correo electrónico' : 'teléfono';
      throw new ConflictError(`Ese ${field} ya está en uso por otra cuenta.`, 'DUPLICATE_USER_FIELD');
    }
    throw err;
  }

  // Re-check completion flags after update
  await checkAndAutoSubmitProfile(userId);

  // Invalidate cache
  await getCache().del(`caregivers:detail:${profile.id}`);
  await delByPrefix('caregivers:list:');

  return { updated: true, emailChanged: !!emailChanged };
}

/** Genera código 6 dígitos, guarda en EmailVerification, envía email real (Resend/SMTP). 10 min expiry. */
export async function sendEmailVerificationCode(userId: string) {
  const { generateAndSendVerificationCode } = await import('../auth/email.service.js');
  return generateAndSendVerificationCode(userId);
}

/** Verifica el código de email (max 5 intentos, 10 min). Marca user + caregiverProfile como verificados. */
export async function verifyEmailCode(userId: string, code: string) {
  const { verifyCode } = await import('../auth/email.service.js');
  return verifyCode(userId, code);
}

/** GET my-profile: perfil del cuidador logueado con datos de User para el wizard. */
export async function getMyProfile(userId: string) {
  let profile = await prisma.caregiverProfile.findUnique({
    where: { userId },
    include: {
      user: {
        select: {
          id: true,
          email: true,
          firstName: true,
          lastName: true,
          phone: true,
          dateOfBirth: true,
          country: true,
          city: true,
        },
      },
    },
  });
  if (!profile) return null;

  // Initialize profileStatus if missing (for legacy data)
  if (!(profile as any).profileStatus) {
    await prisma.caregiverProfile.update({
      where: { id: profile.id },
      data: { profileStatus: 'INCOMPLETE' } as any,
    });
    (profile as any).profileStatus = 'INCOMPLETE';
  }

  if (!profile.identityVerificationToken) {
    const token = randomBytes(32).toString('hex');
    await prisma.caregiverProfile.update({
      where: { id: profile.id },
      data: {
        identityVerificationToken: token,
        identityVerificationStatus: profile.identityVerificationStatus ?? 'PENDING',
      },
    });
    profile = { ...profile, identityVerificationToken: token } as typeof profile;
  }

  // Trigger check to ensure flags are up to date before returning
  await checkAndAutoSubmitProfile(userId);

  // Re-fetch to get updated flags
  return prisma.caregiverProfile.findUnique({
    where: { userId },
    include: {
      user: {
        select: {
          id: true,
          email: true,
          firstName: true,
          lastName: true,
          phone: true,
          dateOfBirth: true,
          country: true,
          city: true,
          emailVerified: true,
        },
      },
    }
  });
}

/** PATCH profile: actualización parcial. 403 si status APPROVED. Si DRAFT o NEEDS_REVISION → mantiene o fija DRAFT. */
export async function patchProfile(userId: string, body: PatchCaregiverProfileBody) {
  const profile = await prisma.caregiverProfile.findUnique({ where: { userId } }) as any;
  if (!profile) {
    throw new BadRequestError('No tienes perfil de cuidador', 'CAREGIVER_PROFILE_NOT_FOUND');
  }

  // Se permite editar aunque esté APPROVED.

  if (profile.profileStatus === 'SUBMITTED' || profile.profileStatus === 'UNDER_REVIEW') {
    throw new ForbiddenError(
      'Tu perfil está en revisión y no puede ser editado en este momento.',
      'PROFILE_IN_REVIEW_READONLY'
    );
  }

  const updateData: Record<string, unknown> = {};
  if (body.bio !== undefined) updateData.bio = body.bio;
  if (body.bioDetail !== undefined) updateData.bioDetail = body.bioDetail;
  if (body.zone !== undefined) updateData.zone = body.zone;
  if (body.spaceType !== undefined) {
    updateData.spaceType = Array.isArray(body.spaceType) ? body.spaceType : (body.spaceType ? [body.spaceType] : []);
  }
  if (body.spaceDescription !== undefined) updateData.spaceDescription = body.spaceDescription;
  if (body.address !== undefined) updateData.address = body.address;
  if ((body as any).addressLat !== undefined) updateData.addressLat = (body as any).addressLat;
  if ((body as any).addressLng !== undefined) updateData.addressLng = (body as any).addressLng;
  if ((body as any).addressStreet !== undefined) updateData.addressStreet = (body as any).addressStreet;
  if ((body as any).addressNumber !== undefined) updateData.addressNumber = (body as any).addressNumber;
  if ((body as any).addressApartment !== undefined) updateData.addressApartment = (body as any).addressApartment;
  if ((body as any).addressCondominio !== undefined) updateData.addressCondominio = (body as any).addressCondominio;
  if ((body as any).addressReference !== undefined) updateData.addressReference = (body as any).addressReference;
  if ((body as any).addressZone !== undefined) updateData.addressZone = (body as any).addressZone;
  if (body.servicesOffered !== undefined) updateData.servicesOffered = body.servicesOffered;
  if (body.serviceAvailability !== undefined) updateData.serviceAvailability = body.serviceAvailability;
  if (body.pricePerDay !== undefined) updateData.pricePerDay = body.pricePerDay;
  if (body.pricePerWalk30 !== undefined) updateData.pricePerWalk30 = body.pricePerWalk30;
  if (body.pricePerWalk60 !== undefined) updateData.pricePerWalk60 = body.pricePerWalk60;
  if (body.rates !== undefined) updateData.rates = body.rates;
  if (body.termsAccepted !== undefined) updateData.termsAccepted = body.termsAccepted;
  if (body.privacyAccepted !== undefined) updateData.privacyAccepted = body.privacyAccepted;
  if (body.verificationAccepted !== undefined) updateData.verificationAccepted = body.verificationAccepted;
  if (body.photos !== undefined) updateData.photos = ensureAbsoluteUrls(body.photos);
  if (body.profilePhoto !== undefined) updateData.profilePhoto = ensureAbsoluteUrl(body.profilePhoto) ?? null;
  if (body.experienceYears !== undefined) updateData.experienceYears = body.experienceYears;
  if (body.ownPets !== undefined) updateData.ownPets = body.ownPets;
  if (body.currentPetsDetails !== undefined) updateData.currentPetsDetails = body.currentPetsDetails;
  if (body.caredOthers !== undefined) updateData.caredOthers = body.caredOthers;
  if (body.animalTypes !== undefined) updateData.animalTypes = body.animalTypes;
  if (body.experienceDescription !== undefined) updateData.experienceDescription = body.experienceDescription;
  if (body.whyCaregiver !== undefined) updateData.whyCaregiver = body.whyCaregiver;
  if (body.whatDiffers !== undefined) updateData.whatDiffers = body.whatDiffers;
  if (body.handleAnxious !== undefined) updateData.handleAnxious = body.handleAnxious;
  if (body.emergencyResponse !== undefined) updateData.emergencyResponse = body.emergencyResponse;
  if (body.acceptAggressive !== undefined) updateData.acceptAggressive = body.acceptAggressive;
  if (body.acceptMedication !== undefined) updateData.acceptMedication = body.acceptMedication;
  if (body.acceptPuppies !== undefined) updateData.acceptPuppies = body.acceptPuppies;
  if (body.acceptSeniors !== undefined) updateData.acceptSeniors = body.acceptSeniors;
  if (body.sizesAccepted !== undefined) updateData.sizesAccepted = body.sizesAccepted;
  if (body.noAcceptBreeds !== undefined) updateData.noAcceptBreeds = body.noAcceptBreeds;
  if (body.breedsWhy !== undefined) updateData.breedsWhy = body.breedsWhy;
  if (body.homeType !== undefined) updateData.homeType = body.homeType;
  if (body.ownHome !== undefined) updateData.ownHome = body.ownHome;
  if (body.hasYard !== undefined) updateData.hasYard = body.hasYard;
  if (body.yardFenced !== undefined) updateData.yardFenced = body.yardFenced;
  if (body.hasChildren !== undefined) updateData.hasChildren = body.hasChildren;
  if (body.hasOtherPets !== undefined) updateData.hasOtherPets = body.hasOtherPets;
  if (body.petsSleep !== undefined) updateData.petsSleep = body.petsSleep;
  if (body.clientPetsSleep !== undefined) updateData.clientPetsSleep = body.clientPetsSleep;
  if (body.hoursAlone !== undefined) updateData.hoursAlone = body.hoursAlone;
  if (body.workFromHome !== undefined) updateData.workFromHome = body.workFromHome;
  if (body.maxPets !== undefined) updateData.maxPets = body.maxPets;
  if (body.oftenOut !== undefined) updateData.oftenOut = body.oftenOut;
  if (body.typicalDay !== undefined) updateData.typicalDay = body.typicalDay;
  if (body.idDocument !== undefined) updateData.idDocument = body.idDocument;
  if (body.selfie !== undefined) updateData.selfie = body.selfie;
  if (body.ciAnversoUrl !== undefined) updateData.ciAnversoUrl = ensureAbsoluteUrl(body.ciAnversoUrl) ?? null;
  if (body.ciReversoUrl !== undefined) updateData.ciReversoUrl = ensureAbsoluteUrl(body.ciReversoUrl) ?? null;
  if (body.ciNumber !== undefined) updateData.ciNumber = body.ciNumber;
  if (body.onboardingStatus !== undefined) updateData.onboardingStatus = body.onboardingStatus as object;
  if (body.serviceDetails !== undefined) {
    updateData.serviceDetails = body.serviceDetails as object;
    // Sync serviceDetails.availability → defaultAvailabilitySchedule
    const avFromDetails = (body.serviceDetails as any)?.availability;
    if (avFromDetails !== undefined) {
      const s = avFromDetails?.slots ?? {};
      // Preserve existing time ranges (start/end) from the current schedule
      const existingSchedule = (profile.defaultAvailabilitySchedule as Record<string, unknown>) ?? {};
      const existingBlocks = (existingSchedule.paseoTimeBlocks as Record<string, unknown>) ?? {};
      const mergeBlock = (key: string, enabled: boolean, defaultStart: string, defaultEnd: string) => {
        const ex = existingBlocks[key] as Record<string, unknown> | undefined;
        if (ex && typeof ex === 'object' && ex.start) return { ...ex, enabled };
        return { enabled, start: defaultStart, end: defaultEnd };
      };
      updateData.defaultAvailabilitySchedule = {
        ...existingSchedule,
        hospedajeDefault: avFromDetails?.weekdays ?? true,
        weekdays: avFromDetails?.weekdays ?? true,
        weekends: avFromDetails?.weekends ?? false,
        holidays: avFromDetails?.holidays ?? false,
        paseoTimeBlocks: {
          morning:   mergeBlock('morning',   s.morning   ?? true,  '08:00', '11:00'),
          afternoon: mergeBlock('afternoon', s.afternoon ?? true,  '13:00', '17:00'),
          night:     mergeBlock('night',     s.night     ?? false, '19:00', '22:00'),
        },
      };
    }
  }

  // Si estaba DRAFT o NEEDS_REVISION, mantener o establecer DRAFT (actualización de borrador).
  if (
    profile.status === CaregiverStatus.DRAFT ||
    profile.status === CaregiverStatus.NEEDS_REVISION
  ) {
    updateData.status = CaregiverStatus.DRAFT;
  }

  logger.debug('Updating caregiver profile', { userId, updateData });
  const updated = await prisma.caregiverProfile.update({
    where: { id: (profile as any).id },
    data: updateData as any,
  });

  logger.debug('Caregiver profile updated, checking submission', { userId });
  // Trigger auto-submission check
  try {
    await checkAndAutoSubmitProfile(userId);
  } catch (err: any) {
    logger.error('Error in checkAndAutoSubmitProfile after patch', { userId, error: err.message, stack: err.stack });
    // Don't throw if check fails, profile was already updated
  }

  if (body.photos !== undefined && ensureAbsoluteUrls(body.photos).length > 0) {
    logger.info('Foto subida y guardada', {
      url: ensureAbsoluteUrls(body.photos)[0],
      field: 'photos',
      userId,
      count: ensureAbsoluteUrls(body.photos).length,
    });
  }
  if (body.profilePhoto !== undefined && ensureAbsoluteUrl(body.profilePhoto)) {
    logger.info('Foto subida y guardada', { url: ensureAbsoluteUrl(body.profilePhoto), field: 'profilePhoto', userId });
  }
  if (body.ciAnversoUrl !== undefined && ensureAbsoluteUrl(body.ciAnversoUrl)) {
    logger.info('Foto subida y guardada', { url: ensureAbsoluteUrl(body.ciAnversoUrl), field: 'ciAnversoUrl', userId });
  }
  if (body.ciReversoUrl !== undefined && ensureAbsoluteUrl(body.ciReversoUrl)) {
    logger.info('Foto subida y guardada', { url: ensureAbsoluteUrl(body.ciReversoUrl), field: 'ciReversoUrl', userId });
  }

  // Invalidate cache
  await getCache().del(`caregivers:detail:${updated.id}`);
  await delByPrefix('caregivers:list:');

  return { profileId: updated.id, status: updated.status, updatedAt: updated.updatedAt };
}

/** POST submit: enviar solicitud. Valida campos obligatorios, pone PENDING_REVIEW, notifica admin. */
export async function submitProfile(userId: string): Promise<{ success: true; message: string }> {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { userId },
    include: {
      user: {
        select: {
          emailVerified: true,
          firstName: true,
          lastName: true,
        }
      }
    }
  });

  if (!profile) {
    throw new BadRequestError('No tienes perfil de cuidador', 'CAREGIVER_PROFILE_NOT_FOUND');
  }

  if (profile.status === CaregiverStatus.PENDING_REVIEW) {
    throw new ConflictError(
      'Ya enviaste tu solicitud y está en revisión. Te notificaremos por email/WhatsApp.',
      'ALREADY_PENDING_REVIEW'
    );
  }

  if (profile.status === CaregiverStatus.APPROVED) {
    throw new BadRequestError('Tu perfil ya está aprobado.', 'ALREADY_APPROVED');
  }

  const missing = getMissingRequiredFieldsForSubmit(profile);

  if (missing.length > 0) {
    const needsIdentity = missing.includes('identityVerified');
    const message = needsIdentity
      ? 'Debes verificar tu identidad escaneando el código QR antes de enviar la solicitud.'
      : `Completa los siguientes campos antes de enviar: ${missing.join(', ')}`;
    throw new BadRequestError(message, 'MISSING_REQUIRED_FIELDS');
  }

  await prisma.$transaction(async (tx) => {
    await tx.caregiverProfile.update({
      where: { id: (profile as any).id },
      data: {
        status: CaregiverStatus.APPROVED,
        profileStatus: 'APPROVED',
        verified: true,
        verifiedAt: new Date(),
        approvedAt: new Date(),
        termsAcceptedAt: new Date(),
        termsAccepted: true,
        privacyAccepted: true,
        verificationAccepted: true,
      } as any,
    });

    // 1. Welcome Notification
    await tx.notification.create({
      data: {
        userId,
        title: '¡Bienvenido a GARDEN! Tu perfil ha sido aprobado',
        message: 'Felicidades, ya eres parte oficial de nuestra red de cuidadores. Tu perfil ahora es visible para miles de dueños de mascotas. ¡Esperamos que tengas una excelente experiencia en la plataforma!',
        type: 'PROFILE_APPROVED',
      },
    });

    // 2. Terms Notification
    await tx.notification.create({
      data: {
        userId,
        title: 'Términos y Condiciones de Uso',
        message: 'Al ser un cuidador verificado, te comprometes a cumplir con nuestros estándares de cuidado, puntualidad y honestidad. Puedes revisar los términos completos en la sección de configuración de tu cuenta en cualquier momento.',
        type: 'SYSTEM',
      },
    });

    // 3. Company Contacts Notification
    await tx.notification.create({
      data: {
        userId,
        title: 'Contacto y Soporte GARDEN',
        message: 'Estamos aquí para ayudarte. Si tienes alguna duda o emergencia durante un servicio, contáctanos: WhatsApp: +591 75933133, Email: soporte@garden.com. ¡Estamos contigo!',
        type: 'SYSTEM',
      },
    });

    // Admin still gets a notification but for record/welcome, not for action
    await tx.adminNotification.create({
      data: {
        type: ADMIN_NOTIFICATION_TYPE_SUBMIT,
        caregiverId: profile.id,
      },
    });
  });

  // Sincronizar con Blockchain (asíncrono)
  blockchainService.syncProfileOnChain(
    userId,
    `${profile.user.firstName} ${profile.user.lastName}`,
    'CAREGIVER',
    true // APPROVED means verified in this context
  ).catch(err => logger.error('Blockchain sync failed (caregiver)', { userId, err }));

  logger.info('CaregiverProfile: aprobado automáticamente', {
    profileId: profile.id,
    userId,
    message: 'Perfil completo → APROBADO AUTOMATICAMENTE',
  });

  return {
    success: true,
    message: '¡Felicidades! Tu perfil ha sido aprobado automáticamente y ya eres visible en Garden.',
  };
}


/** GET my availability for editing: defaultSchedule + overrides (dates with explicit Availability rows). */
export async function getMyAvailabilityForEdit(
  userId: string,
  fromDate: string,
  toDate: string
): Promise<{
  defaultSchedule: Record<string, unknown> | null;
  dates: Record<string, { isAvailable: boolean; timeBlocks: Record<string, boolean> | null; reason?: string | null }>;
}> {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { userId },
    select: { id: true, defaultAvailabilitySchedule: true },
  });
  if (!profile) {
    throw new BadRequestError('No tienes perfil de cuidador', 'CAREGIVER_PROFILE_NOT_FOUND');
  }
  const start = new Date(fromDate);
  const end = new Date(toDate);
  const rows = await prisma.availability.findMany({
    where: {
      caregiverId: profile.id,
      date: { gte: start, lte: end },
    },
    orderBy: { date: 'asc' },
  });
  const dates: Record<string, { isAvailable: boolean; timeBlocks: Record<string, boolean> | null; reason?: string | null }> = {};
  for (const r of rows) {
    const dateStr = r.date instanceof Date ? r.date.toISOString().slice(0, 10) : String(r.date).slice(0, 10);
    const tb = r.timeBlocks as Record<string, boolean> | null;
    dates[dateStr] = {
      isAvailable: r.isAvailable,
      timeBlocks: tb && typeof tb === 'object' ? tb : null,
      ...(r.overrideReason != null && { reason: r.overrideReason }),
    };
  }
  return {
    defaultSchedule: profile.defaultAvailabilitySchedule as Record<string, unknown> | null,
    dates,
  };
}

/** PATCH availability: guardar defaultSchedule en perfil y upsert overrides en Availability. */
export async function patchAvailability(userId: string, body: PatchAvailabilityBody): Promise<{ success: true }> {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { userId },
    select: { id: true, profileStatus: true, defaultAvailabilitySchedule: true, serviceDetails: true },
  }) as any;
  if (!profile) {
    throw new BadRequestError('No tienes perfil de cuidador', 'CAREGIVER_PROFILE_NOT_FOUND');
  }

  // Se permite editar disponibilidad incluso si está APPROVED.

  // Verificar conflictos: fechas que se quieren bloquear con reservas CONFIRMED/IN_PROGRESS
  if (body.overrides && Object.keys(body.overrides).length > 0) {
    const datesToBlock = Object.entries(body.overrides)
      .filter(([, dayOverride]) => (dayOverride.isAvailable ?? true) === false)
      .map(([dateStr]) => new Date(dateStr + 'T00:00:00.000Z'));

    if (datesToBlock.length > 0) {
      const conflicting = await prisma.booking.findMany({
        where: {
          caregiverId: profile.id,
          status: { in: ['CONFIRMED', 'IN_PROGRESS'] },
          OR: [
            { walkDate: { in: datesToBlock } },
            {
              startDate: { lte: datesToBlock[datesToBlock.length - 1] },
              endDate:   { gte: datesToBlock[0] },
            },
          ],
        },
        select: { walkDate: true, startDate: true, endDate: true },
      });

      if (conflicting.length > 0) {
        const conflictDates = conflicting.flatMap((b) => {
          if (b.walkDate) return [b.walkDate.toISOString().slice(0, 10)];
          const result: string[] = [];
          if (b.startDate && b.endDate) {
            const cur = new Date(b.startDate);
            while (cur <= b.endDate) {
              result.push(cur.toISOString().slice(0, 10));
              cur.setUTCDate(cur.getUTCDate() + 1);
            }
          }
          return result;
        });
        const relevant = [...new Set(conflictDates)].filter((d) =>
          datesToBlock.some((bd) => bd.toISOString().slice(0, 10) === d),
        );
        throw new AvailabilityConflictError(
          `No puedes bloquear fechas con reservas activas: ${relevant.join(', ')}`,
        );
      }
    }
  }

  try {
    if (body.defaultSchedule !== undefined) {
      const existingSchedule = (profile.defaultAvailabilitySchedule as Record<string, unknown>) ?? {};
      const merged = { ...existingSchedule, ...body.defaultSchedule };

      // Reverse sync: keep serviceDetails.availability in sync so Profile Data screen stays current
      const existingSD  = (profile.serviceDetails as Record<string, unknown>) ?? {};
      const existingAv  = (existingSD.availability as Record<string, unknown>) ?? {};
      const existingSl  = (existingAv.slots as Record<string, unknown>) ?? {};
      const newAv: Record<string, unknown> = { ...existingAv };
      const newSlots: Record<string, unknown> = { ...existingSl };

      const ds = body.defaultSchedule as Record<string, unknown>;
      if (ds.weekdays !== undefined) newAv.weekdays = ds.weekdays;
      if (ds.weekends !== undefined) newAv.weekends = ds.weekends;
      if (ds.holidays !== undefined) newAv.holidays = ds.holidays;

      const rawBlocks = ds.paseoTimeBlocks as Record<string, unknown> | undefined;
      if (rawBlocks) {
        for (const [key, val] of Object.entries(rawBlocks)) {
          newSlots[key] = (typeof val === 'object' && val !== null)
            ? (val as Record<string, unknown>).enabled
            : val;
        }
      }
      newAv.slots = newSlots;

      await prisma.caregiverProfile.update({
        where: { id: profile.id },
        data: {
          defaultAvailabilitySchedule: merged,
          serviceDetails: { ...existingSD, availability: newAv } as any,
        },
      });
    }
    if (body.overrides && Object.keys(body.overrides).length > 0) {
      for (const [dateStr, dayOverride] of Object.entries(body.overrides)) {
        const dateObj = new Date(dateStr + 'T00:00:00.000Z');
        const isAvailable = dayOverride.isAvailable ?? true;
        const days = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
        const dayName = days[dateObj.getUTCDay()];

        const rawTb = (dayOverride.timeBlocks as any) || {};
        const actualSlots = rawTb.slots || rawTb;

        const timeBlocks = {
          day: dayName,
          enabled: isAvailable,
          slots: {
            morning: actualSlots.morning || actualSlots.MANANA || null,
            afternoon: actualSlots.afternoon || actualSlots.TARDE || null,
            night: actualSlots.night || actualSlots.NOCHE || null,
          }
        };
        const overrideReason = dayOverride.reason != null ? dayOverride.reason : undefined;
        await prisma.availability.upsert({
          where: {
            caregiverId_date: { caregiverId: profile.id, date: dateObj },
          },
          create: {
            caregiverId: profile.id,
            date: dateObj,
            isAvailable,
            timeBlocks: timeBlocks ?? undefined,
            overrideReason: overrideReason ?? undefined,
          },
          update: {
            isAvailable,
            ...(timeBlocks !== undefined && { timeBlocks }),
            ...(overrideReason !== undefined && { overrideReason: overrideReason || null }),
          },
        });
      }
    }
  } catch (err: any) {
    logger.error('Error in patchAvailability', { userId, error: err.message, stack: err.stack });
    throw err;
  }

  // Trigger auto-submission check
  await checkAndAutoSubmitProfile(userId);

  // Invalidate cache
  await getCache().del(`caregivers:detail:${profile.id}`);
  await delByPrefix('caregivers:list:');

  return { success: true };
}

/** GET notifications for the logged-in caregiver (inbox). */
export async function getNotifications(userId: string) {
  const list = await prisma.notification.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
    take: 50,
  });
  return list.map((n) => ({
    id: n.id,
    title: n.title,
    message: n.message,
    type: n.type,
    read: n.read,
    readAt: n.readAt?.toISOString() ?? null,
    createdAt: n.createdAt.toISOString(),
  }));
}

/** PATCH mark one notification as read. */
export async function markNotificationRead(userId: string, notificationId: string) {
  await prisma.notification.updateMany({
    where: { id: notificationId, userId },
    data: { read: true, readAt: new Date() },
  });
  return { success: true };
}

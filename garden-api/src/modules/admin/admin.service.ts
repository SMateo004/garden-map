import { BookingStatus, CaregiverStatus, Prisma, VerificationStatus } from '@prisma/client';
import prisma from '../../config/database.js';
import * as bookingService from '../booking-service/booking.service.js';
import { applyResolution as applyDisputeResolution } from '../dispute/dispute.routes.js';
import { BadRequestError, CaregiverNotFoundError, NotFoundError, UnauthorizedError } from '../../shared/errors.js';
import * as caregiverProfileService from '../caregiver-profile/caregiver-profile.service.js';
import { checkAndAutoSubmitProfile } from '../caregiver-profile/caregiver-profile-completion.helper.js';
import { getCache, delByPrefix } from '../../shared/cache.js';
import { getBoolSetting } from '../../utils/settings-cache.js';
import logger from '../../shared/logger.js';
import { track } from '../../shared/analytics.js';
import type {
  PendingCaregiversResult,
  PendingCaregiverItem,
  PendingPaymentItem,
  PendingPaymentsResult,
  AdminReservationItem,
  AdminReservationsResult,
  AdminCaregiverDetailDto,
} from './admin.types.js';
import type { ReviewCaregiverBody, ListCaregiversQuery } from './admin.validation.js';
import * as notificationService from '../../services/notification.service.js';
import { sendPushToUser } from '../../services/firebase.service.js';

function toIso(date: Date | null): string | null {
  return date ? date.toISOString() : null;
}

/** GET /api/admin/caregivers/:id/detail — todos los datos del perfil + usuario para revisión. 404 si no existe. */
export async function getCaregiverDetailForAdmin(profileId: string): Promise<AdminCaregiverDetailDto> {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { id: profileId },
    include: {
      user: true,
      availability: { orderBy: { date: 'asc' }, take: 100 },
    },
  });
  if (!profile) throw new CaregiverNotFoundError(profileId);

  const lastSession = await prisma.identityVerificationSession.findFirst({
    where: { userId: profile.userId },
    orderBy: { createdAt: 'desc' },
    select: { id: true, selfieUrl: true }
  });

  // Visibilidad permanente del OTP vigente (email + teléfono) para el admin,
  // gateada por switch — distinta del fallback PHONE_OTP_MANUAL_HELP /
  // EMAIL_OTP_MANUAL_HELP que solo aparece cuando el envío automático falla.
  const otpVisibleToAdmin = await getBoolSetting('otpVisibleToAdminEnabled', true);
  const latestEmailVerification = otpVisibleToAdmin
    ? await prisma.emailVerification.findFirst({
        where: { userId: profile.userId, verified: false },
        orderBy: { createdAt: 'desc' },
      })
    : null;

  const u = profile.user;
  const dto: AdminCaregiverDetailDto = {
    id: profile.id,
    userId: profile.userId,
    createdAt: profile.createdAt.toISOString(),
    updatedAt: profile.updatedAt.toISOString(),
    status: profile.status,
    verified: profile.verified,
    verifiedAt: toIso(profile.verifiedAt),
    verifiedBy: profile.verifiedBy,
    verificationNotes: profile.verificationNotes,
    verificationStatus: profile.verificationStatus,
    rejectionReason: profile.rejectionReason,
    adminNotes: profile.adminNotes,
    approvedAt: toIso(profile.approvedAt),
    approvedBy: profile.approvedBy,
    reviewedAt: toIso(profile.reviewedAt),
    suspended: profile.suspended,
    suspendedAt: toIso(profile.suspendedAt),
    suspensionReason: profile.suspensionReason,
    rating: profile.rating,
    reviewCount: profile.reviewCount,
    user: {
      id: u.id,
      email: u.email,
      role: u.role,
      firstName: u.firstName,
      lastName: u.lastName,
      phone: u.phone,
      profilePicture: u.profilePicture,
      country: u.country,
      city: u.city,
      isOver18: u.isOver18,
      createdAt: u.createdAt.toISOString(),
      updatedAt: u.updatedAt.toISOString(),
      phoneOtp: otpVisibleToAdmin ? (u.phoneOtp ?? null) : null,
      phoneOtpExpiresAt: otpVisibleToAdmin && u.phoneOtpExpiresAt ? u.phoneOtpExpiresAt.toISOString() : null,
    },
    emailOtpCode: latestEmailVerification?.plainCode ?? null,
    emailOtpExpiresAt: latestEmailVerification?.expiresAt.toISOString() ?? null,
    bio: profile.bio,
    bioDetail: profile.bioDetail,
    zone: profile.zone,
    spaceType: Array.isArray(profile.spaceType) ? profile.spaceType : (profile.spaceType ? [profile.spaceType] : []),
    spaceDescription: profile.spaceDescription,
    address: profile.address,
    photos: profile.photos ?? [],
    servicesOffered: profile.servicesOffered ?? [],
    serviceAvailability: profile.serviceAvailability as Record<string, unknown> | null,
    pricePerDay: profile.pricePerDay,
    pricePerWalk30: profile.pricePerWalk30,
    pricePerWalk60: profile.pricePerWalk60,
    rates: profile.rates as Record<string, unknown> | null,
    termsAccepted: profile.termsAccepted,
    privacyAccepted: profile.privacyAccepted,
    verificationAccepted: profile.verificationAccepted,
    termsAcceptedAt: toIso(profile.termsAcceptedAt),
    experienceYears: profile.experienceYears,
    ownPets: profile.ownPets,
    currentPetsDetails: profile.currentPetsDetails,
    caredOthers: profile.caredOthers,
    animalTypes: profile.animalTypes ?? [],
    experienceDescription: profile.experienceDescription,
    whyCaregiver: profile.whyCaregiver,
    whatDiffers: profile.whatDiffers,
    handleAnxious: profile.handleAnxious,
    emergencyResponse: profile.emergencyResponse,
    acceptAggressive: profile.acceptAggressive,
    acceptMedication: profile.acceptMedication ?? [],
    acceptPuppies: profile.acceptPuppies,
    acceptSeniors: profile.acceptSeniors,
    sizesAccepted: profile.sizesAccepted ?? [],
    noAcceptBreeds: profile.noAcceptBreeds,
    breedsWhy: profile.breedsWhy,
    homeType: profile.homeType,
    ownHome: profile.ownHome,
    hasYard: profile.hasYard,
    yardFenced: profile.yardFenced,
    hasChildren: profile.hasChildren,
    hasOtherPets: profile.hasOtherPets,
    petsSleep: profile.petsSleep,
    clientPetsSleep: profile.clientPetsSleep,
    hoursAlone: profile.hoursAlone,
    workFromHome: profile.workFromHome,
    maxPets: profile.maxPets,
    oftenOut: profile.oftenOut,
    typicalDay: profile.typicalDay,
    profilePhoto: profile.profilePhoto ?? u.profilePicture,
    idDocumentUrl: profile.ciAnversoUrl,
    selfieUrl: lastSession?.selfieUrl ?? null,
    ciAnversoUrl: profile.ciAnversoUrl,
    ciReversoUrl: profile.ciReversoUrl,
    identityVerificationStatus: profile.identityVerificationStatus ?? 'PENDING',
    identityVerificationScore: profile.identityVerificationScore,
    identityVerificationSubmittedAt: toIso(profile.identityVerificationSubmittedAt),
    lastIdentityVerificationSessionId: lastSession?.id,
    defaultAvailabilitySchedule: profile.defaultAvailabilitySchedule as Record<string, unknown> | null,
    availability: profile.availability?.map((a) => ({
      date: a.date.toISOString().slice(0, 10),
      isAvailable: a.isAvailable,
      timeBlocks: a.timeBlocks,
    })) ?? [],
    ciNumber: profile.ciNumber,
    emailVerified: u.emailVerified,
    reviewChecklist: Array.isArray((profile as any).reviewChecklist) ? (profile as any).reviewChecklist : null,
    isProfessional: (profile as any).isProfessional ?? false,
    // Compute completeness from actual profile data (not stale stored flags)
    personalInfoComplete: Boolean(u.firstName?.trim() && u.lastName?.trim() && u.phone?.trim()),
    caregiverProfileComplete: Boolean(
      (profile.servicesOffered as string[])?.length > 0 && profile.zone
    ),
    availabilityComplete: Boolean(
      profile.serviceAvailability || (profile as any).defaultAvailabilitySchedule
    ),
    verificationAttempts: (profile as any).verificationAttempts ?? 0,
    verificationLockUntil: (profile as any).verificationLockUntil
      ? new Date((profile as any).verificationLockUntil).toISOString()
      : null,
  };
  return dto;
}

export async function verifyEmail(profileId: string): Promise<{ emailVerified: boolean }> {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { id: profileId },
    select: { userId: true },
  });

  if (!profile) throw new CaregiverNotFoundError(profileId);

  await prisma.$transaction([
    prisma.caregiverProfile.update({
      where: { id: profileId },
      data: { emailVerified: true },
    }),
    prisma.user.update({
      where: { id: profile.userId },
      data: { emailVerified: true },
    }),
  ]);

  // Recalcular completitud tras verificar email
  await checkAndAutoSubmitProfile(profile.userId);

  return { emailVerified: true };
}

export async function toggleVerify(caregiverId: string, adminId: string): Promise<{ verified: boolean; verifiedAt: Date | null }> {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { id: caregiverId },
    include: { user: { select: { id: true } } },
  });
  if (!profile) throw new CaregiverNotFoundError(caregiverId);

  const newVerified = !profile.verified;

  // Si se va a activar, validar los mismos requisitos que el flujo de aprobación
  if (newVerified) {
    const identityVerified = (profile as any).identityVerificationStatus === 'VERIFIED';
    const emailVerified = (profile as any).emailVerified === true;
    const hasPhoto = !!(profile as any).profilePhoto;
    const hasBio = !!(profile as any).bio && ((profile as any).bio as string).length >= 50;
    const hasZone = !!(profile as any).zone;
    const hasServices = Array.isArray((profile as any).servicesOffered) && (profile as any).servicesOffered.length > 0;
    const availabilityCount = await prisma.availability.count({ where: { caregiverId } });
    const hasAvailability = availabilityCount > 0 || (profile as any).defaultAvailabilitySchedule != null;

    const missing: string[] = [];
    if (!emailVerified) missing.push('verificación de correo');
    if (!identityVerified) missing.push('verificación de identidad');
    if (!hasPhoto) missing.push('foto de perfil');
    if (!hasBio) missing.push('bio completa (mín. 50 caracteres)');
    if (!hasZone) missing.push('zona');
    if (!hasServices) missing.push('servicios ofrecidos');
    if (!hasAvailability) missing.push('disponibilidad');

    if (missing.length > 0) {
      throw new BadRequestError(
        `No se puede aprobar: faltan ${missing.join(', ')}.`,
        'PROFILE_INCOMPLETE'
      );
    }
  }

  const now = new Date();
  const updated = await prisma.caregiverProfile.update({
    where: { id: caregiverId },
    data: {
      verified: newVerified,
      status: newVerified ? CaregiverStatus.APPROVED : CaregiverStatus.PENDING_REVIEW,
      verificationStatus: newVerified ? VerificationStatus.APPROVED : VerificationStatus.PENDING_REVIEW,
      verifiedAt: newVerified ? now : null,
      verifiedBy: newVerified ? adminId : null,
      approvedAt: newVerified ? now : null,
      approvedBy: newVerified ? adminId : null,
      verificationNotes: null,
      suspended: newVerified ? false : profile.suspended,
    },
  });

  await prisma.adminAction.create({
    data: {
      adminId,
      actionType: 'VERIFY_TOGGLE',
      targetId: caregiverId,
      notes: newVerified ? 'Badge verificado' : 'Badge desactivado',
    },
  });

  await getCache().del(`caregivers:detail:${caregiverId}`);
  await delByPrefix('caregivers:list:');

  return { verified: updated.verified, verifiedAt: updated.verifiedAt };
}

/**
 * Toggle isProfessional para un cuidador existente.
 * No cambia su status ni verified — solo actualiza el flag.
 */
export async function toggleProfessional(
  caregiverId: string,
  adminId: string
): Promise<{ isProfessional: boolean }> {
  const profile = await prisma.caregiverProfile.findUnique({ where: { id: caregiverId } });
  if (!profile) throw new CaregiverNotFoundError(caregiverId);

  const newValue = !(profile as any).isProfessional;

  await prisma.caregiverProfile.update({
    where: { id: caregiverId },
    data: { isProfessional: newValue } as any,
  });

  await prisma.adminAction.create({
    data: {
      adminId,
      actionType: 'TOGGLE_PROFESSIONAL',
      targetId: caregiverId,
      notes: newValue ? 'Marcado como profesional' : 'Profesional removido',
    },
  });

  await getCache().del(`caregivers:detail:${caregiverId}`);
  await delByPrefix('caregivers:list:');

  return { isProfessional: newValue };
}

/** Lista TODOS los cuidadores con filtro opcional por status. status=pendientes → PENDING_REVIEW + NEEDS_REVISION. */
export async function listCaregivers(
  page: number,
  limit: number,
  status?: string
): Promise<PendingCaregiversResult> {
  const skip = (page - 1) * limit;
  const where: { status?: { in?: CaregiverStatus[]; equals?: CaregiverStatus } } = {};
  if (status === 'pendientes') {
    where.status = { in: [CaregiverStatus.PENDING_REVIEW, CaregiverStatus.NEEDS_REVISION] };
  } else if (status && Object.values(CaregiverStatus).includes(status as CaregiverStatus)) {
    where.status = { equals: status as CaregiverStatus };
  }
  const [caregivers, total] = await Promise.all([
    prisma.caregiverProfile.findMany({
      where,
      select: {
        id: true,
        status: true,
        createdAt: true,
        updatedAt: true,
        rejectionReason: true,
        user: {
          select: { email: true, phone: true, firstName: true, lastName: true },
        },
      },
      orderBy: { createdAt: 'desc' },
      skip,
      take: limit,
    }),
    prisma.caregiverProfile.count({ where }),
  ]);
  const items: PendingCaregiverItem[] = caregivers.map((c) => ({
    id: c.id,
    email: c.user.email,
    phone: c.user.phone,
    fullName: [c.user.firstName, c.user.lastName].filter(Boolean).join(' ').trim() || '—',
    status: c.status,
    createdAt: c.createdAt,
    updatedAt: c.updatedAt,
    rejectionReason: c.rejectionReason,
    isProfessional: (c as any).isProfessional ?? false,
  }));
  return { caregivers: items, total, page, limit };
}

/** Lista perfiles con status PENDING_REVIEW o NEEDS_REVISION, paginado, newest first. */
export async function listPendingCaregivers(
  page: number,
  limit: number
): Promise<PendingCaregiversResult> {
  const skip = (page - 1) * limit;
  const [caregivers, total] = await Promise.all([
    prisma.caregiverProfile.findMany({
      where: {
        status: { in: [CaregiverStatus.PENDING_REVIEW, CaregiverStatus.NEEDS_REVISION] },
      },
      select: {
        id: true,
        status: true,
        createdAt: true,
        updatedAt: true,
        rejectionReason: true,
        user: {
          select: { email: true, phone: true, firstName: true, lastName: true },
        },
      },
      orderBy: { createdAt: 'desc' },
      skip,
      take: limit,
    }),
    prisma.caregiverProfile.count({
      where: {
        status: { in: [CaregiverStatus.PENDING_REVIEW, CaregiverStatus.NEEDS_REVISION] },
      },
    }),
  ]);

  const items: PendingCaregiverItem[] = caregivers.map((c) => ({
    id: c.id,
    email: c.user.email,
    phone: c.user.phone,
    fullName: [c.user.firstName, c.user.lastName].filter(Boolean).join(' ').trim() || '—',
    status: c.status,
    createdAt: c.createdAt,
    updatedAt: c.updatedAt,
    rejectionReason: c.rejectionReason,
    isProfessional: (c as any).isProfessional ?? false,
  }));

  return { caregivers: items, total, page, limit };
}

/**
 * Aplica acción de revisión: approve | reject | request_revision.
 * - approve: status APPROVED, verified=true, approvedAt/approvedBy → visible en listado público.
 * - reject: status REJECTED, rejectionReason obligatorio (validado en schema).
 * - request_revision: status NEEDS_REVISION, rejectionReason opcional.
 */
export async function reviewCaregiver(
  profileId: string,
  adminId: string,
  body: ReviewCaregiverBody
): Promise<{ id: string; status: string; action: typeof body.action }> {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { id: profileId },
    include: { user: { select: { email: true, firstName: true, lastName: true } } },
  });
  if (!profile) throw new CaregiverNotFoundError(profileId);

  if (
    profile.status !== CaregiverStatus.PENDING_REVIEW &&
    profile.status !== CaregiverStatus.NEEDS_REVISION &&
    profile.status !== CaregiverStatus.DRAFT
  ) {
    logger.warn('Admin review: perfil no elegible', {
      profileId,
      currentStatus: profile.status,
      action: body.action,
    });
    throw new BadRequestError(
      `El perfil no está pendiente de revisión (status: ${profile.status})`,
      'INVALID_STATUS_FOR_REVIEW'
    );
  }

  const now = new Date();
  const { action, reason, adminMessage, checklist } = body;
  const caregiverUserId = profile.userId;

  if (action === 'approve') {
    const fullProfile = await prisma.caregiverProfile.findUnique({
      where: { id: profileId },
      select: {
        bio: true,
        zone: true,
        servicesOffered: true,
        profilePhoto: true,
        identityVerificationStatus: true,
        emailVerified: true,
      } as any,
    });
    const hasPersonalInfo = fullProfile?.profilePhoto && fullProfile.bio && fullProfile.zone;
    const hasQuestionnaire =
      fullProfile?.bio && fullProfile.bio.length >= 50 &&
      fullProfile.zone &&
      Array.isArray(fullProfile.servicesOffered) && fullProfile.servicesOffered.length > 0;
    const identityVerified = (fullProfile as any)?.identityVerificationStatus === 'VERIFIED';
    const emailVerified = (fullProfile as any)?.emailVerified === true;
    const availabilityCount = await prisma.availability.count({ where: { caregiverId: profileId } });
    const hasAvailability =
      availabilityCount > 0 || profile.defaultAvailabilitySchedule != null;

    const isComplete = hasPersonalInfo && hasQuestionnaire && hasAvailability && identityVerified && emailVerified;

    if (!isComplete && !body.force) {
      const missing: string[] = [];
      if (!hasPersonalInfo) missing.push('información personal');
      if (!hasQuestionnaire) missing.push('cuestionario');
      if (!hasAvailability) missing.push('disponibilidad');
      if (!identityVerified) missing.push('verificación de identidad (QR)');
      if (!emailVerified) missing.push('verificación de correo');
      throw new BadRequestError(
        `No se puede aprobar: faltan ${missing.join(', ')}. isComplete debe ser true. (Usa force: true para saltar esta validación)`,
        'PROFILE_INCOMPLETE'
      );
    }

    const updated = await prisma.caregiverProfile.update({
      where: { id: profileId },
      data: {
        status: CaregiverStatus.APPROVED,
        profileStatus: 'APPROVED',
        verified: true,
        verificationStatus: VerificationStatus.APPROVED,
        approvedAt: now,
        approvedBy: adminId,
        verifiedAt: now,
        verifiedBy: adminId,
        rejectionReason: null,
        reviewedAt: now,
      } as any,
    });

    await prisma.adminAction.create({
      data: {
        adminId,
        actionType: 'REVIEW_APPROVE',
        targetId: profileId,
        notes: 'Solicitud aprobada; perfil visible en listado público.',
      },
    });

    await prisma.notification.create({
      data: {
        userId: caregiverUserId,
        title: 'Verificación aprobada',
        message: 'Tu verificación fue aprobada. Ahora eres un cuidador verificado.',
        type: 'APPROVED',
      },
    });
    await prisma.verificationAudit.create({
      data: {
        userId: caregiverUserId,
        action: 'REVIEW_APPROVE',
        status: 'APPROVED',
        notes: `Profile ${profileId} approved by admin`,
      },
    });

    await getCache().del(`caregivers:detail:${profileId}`);
    await delByPrefix('caregivers:list:');

    notificationService.onCaregiverApproved(caregiverUserId).catch(() => {});
    sendPushToUser(caregiverUserId, '¡Perfil aprobado! 🎉', 'Tu perfil de cuidador fue aprobado. ¡Ya eres parte de GARDEN!').catch(() => {});

    logger.info('Admin: cuidador aprobado', {
      profileId,
      adminId,
      caregiverEmail: profile.user?.email,
      message: 'Perfil verificado y visible en GET /api/caregivers',
    });
    track(caregiverUserId, 'caregiver_approved', { profileId, adminId });

    return { id: updated.id, status: updated.status, action: 'approve' };
  }

  if (action === 'reject') {
    const reasonText = (reason ?? '').trim();
    const messageToUser = (adminMessage ?? reason ?? '').trim();
    if (!reasonText) {
      throw new BadRequestError('El motivo (reason) es obligatorio al rechazar.', 'REASON_REQUIRED');
    }

    const updated = await prisma.caregiverProfile.update({
      where: { id: profileId },
      data: {
        status: CaregiverStatus.REJECTED,
        profileStatus: 'INCOMPLETE',
        verificationStatus: VerificationStatus.REJECTED,
        rejectionReason: reasonText,
        reviewedAt: now,
      } as any,
    });

    await prisma.adminAction.create({
      data: {
        adminId,
        actionType: 'REVIEW_REJECT',
        targetId: profileId,
        notes: reasonText,
      },
    });

    await prisma.notification.create({
      data: {
        userId: caregiverUserId,
        title: 'Solicitud rechazada',
        message: messageToUser || reasonText,
        type: 'REJECTED',
      },
    });
    await prisma.verificationAudit.create({
      data: {
        userId: caregiverUserId,
        action: 'REVIEW_REJECT',
        status: 'REJECTED',
        notes: reasonText.slice(0, 500),
      },
    });

    await getCache().del(`caregivers:detail:${profileId}`);

    notificationService.onCaregiverRejected(caregiverUserId, reasonText, messageToUser || undefined).catch(() => {});
    sendPushToUser(caregiverUserId, 'Solicitud revisada', 'Tu perfil necesita ajustes. Revisa los detalles en la app.').catch(() => {});

    logger.info('Admin: solicitud rechazada', {
      profileId,
      adminId,
      caregiverEmail: profile.user?.email,
      reasonLength: reasonText.length,
    });

    return { id: updated.id, status: updated.status, action: 'reject' };
  }

  if (action === 'force_submit') {
    const updated = await prisma.caregiverProfile.update({
      where: { id: profileId },
      data: {
        status: CaregiverStatus.PENDING_REVIEW,
        profileStatus: 'SUBMITTED',
      } as any,
    });

    await prisma.adminAction.create({
      data: {
        adminId,
        actionType: 'REVIEW_FORCE_SUBMIT',
        targetId: profileId,
        notes: 'Administrador sacó el perfil de borrador (force_submit).',
      },
    });

    await getCache().del(`caregivers:detail:${profileId}`);
    return { id: updated.id, status: updated.status, action: 'force_submit' };
  }

  // request_revision: verificationStatus = REVIEW, store checklist
  const checklistItems = Array.isArray(checklist) ? checklist.filter((s): s is string => typeof s === 'string' && s.trim().length > 0) : [];
  const updated = await prisma.caregiverProfile.update({
    where: { id: profileId },
    data: {
      status: CaregiverStatus.NEEDS_REVISION,
      profileStatus: 'INCOMPLETE',
      verificationStatus: VerificationStatus.REVIEW,
      rejectionReason: reason?.trim() ?? null,
      reviewChecklist: checklistItems.length > 0 ? checklistItems : null,
      reviewedAt: now,
    } as any,
  });

  await prisma.adminAction.create({
    data: {
      adminId,
      actionType: 'REVIEW_REQUEST_REVISION',
      targetId: profileId,
      notes: reason ?? (checklistItems.length ? checklistItems.join('; ') : undefined),
    },
  });

  const reviewMessage = checklistItems.length > 0
    ? `Se solicita revisión. Puntos a corregir:\n${checklistItems.map((item, i) => `${i + 1}. ${item}`).join('\n')}`
    : (reason?.trim() || 'Se solicita revisión de tu solicitud.');
  await prisma.notification.create({
    data: {
      userId: caregiverUserId,
      title: 'Revisión solicitada',
      message: reviewMessage,
      type: 'REVIEW',
    },
  });
  await prisma.verificationAudit.create({
    data: {
      userId: caregiverUserId,
      action: 'REVIEW_REQUEST_REVISION',
      status: 'REVIEW',
      notes: checklistItems.length ? checklistItems.join('; ') : (reason ?? '')?.slice(0, 500),
    },
  });

  await getCache().del(`caregivers:detail:${profileId}`);

  logger.info('Admin: pedido de revisión', {
    profileId,
    adminId,
    caregiverEmail: profile.user?.email,
    hasReason: Boolean(reason?.trim()),
    checklistLength: checklistItems.length,
  });

  return { id: updated.id, status: updated.status, action: 'request_revision' };
}

// ---------------------------------------------------------------------------
// Pagos pendientes de aprobación manual (Subfase 2.3)
// ---------------------------------------------------------------------------

/** GET /api/admin/payments-pending — reservas en PAYMENT_PENDING_APPROVAL, paginadas. */
export async function getPaymentsPending(
  page = 1,
  limit = 50
): Promise<PendingPaymentsResult & { pagination: { page: number; limit: number; total: number; pages: number } }> {
  const where = {
    OR: [
      { status: BookingStatus.PAYMENT_PENDING_APPROVAL },
      // PENDING_PAYMENT solo si tiene qrId activo (QR generado pero no aprobado aún)
      // Si qrId es null, el pago fue rechazado y el cliente debe reiniciar el flujo
      { status: BookingStatus.PENDING_PAYMENT, qrId: { not: null } },
    ],
  };
  const skip = (page - 1) * limit;

  const [bookings, total] = await Promise.all([
    prisma.booking.findMany({
      where,
      include: {
        client: { select: { email: true } },
        caregiver: {
          select: { user: { select: { firstName: true, lastName: true } } },
        },
      },
      orderBy: { createdAt: 'desc' },
      skip,
      take: limit,
    }),
    prisma.booking.count({ where }),
  ]);

  const items: PendingPaymentItem[] = bookings.map((b) => ({
    id: b.id,
    clientId: b.clientId,
    caregiverId: b.caregiverId,
    serviceType: b.serviceType,
    totalAmount: String(b.totalAmount),
    donationAmount: Number(b.donationAmount ?? 0),
    walletPaymentAmount: Number(b.walletPaymentAmount ?? 0),
    petName: b.petName,
    startDate: b.startDate?.toISOString().slice(0, 10) ?? null,
    endDate: b.endDate?.toISOString().slice(0, 10) ?? null,
    walkDate: b.walkDate?.toISOString().slice(0, 10) ?? null,
    timeSlot: b.timeSlot,
    createdAt: b.createdAt.toISOString(),
    clientEmail: b.client?.email,
    caregiverName:
      b.caregiver?.user != null
        ? `${b.caregiver.user.firstName} ${b.caregiver.user.lastName}`.trim()
        : undefined,
  }));

  return {
    bookings: items,
    total,
    pagination: { page, limit, total, pages: Math.ceil(total / limit) || 1 },
  };
}

/** POST /api/admin/bookings/:id/reject-payment — rechazar pago; vuelve a PENDING_PAYMENT y limpia QR.
 *  Si el cliente había usado billetera para cubrir parte del pago, se le reembolsa automáticamente. */
export async function rejectPayment(bookingId: string, adminId: string): Promise<{ id: string; status: string }> {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    select: { id: true, clientId: true, status: true, walletPaymentAmount: true },
  });
  if (!booking) throw new NotFoundError('Reserva no encontrada');
  if (booking.status !== BookingStatus.PAYMENT_PENDING_APPROVAL && booking.status !== BookingStatus.PENDING_PAYMENT) {
    throw new BadRequestError(
      'Solo se puede rechazar una reserva en espera de aprobación de pago.'
    );
  }

  const walletContrib = Number(booking.walletPaymentAmount ?? 0);

  const updated = await prisma.$transaction(async (tx) => {
    // 1. Limpiar QR y resetear contribución de billetera
    const result = await tx.booking.update({
      where: { id: bookingId },
      data: {
        status: BookingStatus.PENDING_PAYMENT,
        qrId: null,
        qrImageUrl: null,
        qrExpiresAt: null,
        ...(walletContrib > 0 ? { walletPaymentAmount: 0 } : {}),
      },
    });

    // 2. Si el cliente había pagado con billetera, reembolsar
    if (walletContrib > 0) {
      const updatedUser = await tx.user.update({
        where: { id: booking.clientId },
        data: { balance: { increment: walletContrib } },
        select: { balance: true },
      });
      await tx.walletTransaction.create({
        data: {
          userId: booking.clientId,
          type: 'REFUND',
          amount: walletContrib,
          balance: Number(updatedUser.balance),
          description: `Reembolso de billetera — pago rechazado (reserva ${bookingId.slice(0, 8)})`,
          bookingId,
          status: 'COMPLETED',
        },
      });
      logger.info('Admin: reembolso de billetera por rechazo de pago', {
        bookingId,
        adminId,
        walletContrib,
        newBalance: Number(updatedUser.balance),
      });
    }

    return result;
  });

  // Notificar al cliente (fire-and-forget)
  const notifMessage = walletContrib > 0
    ? `Tu pago fue rechazado. Se reembolsaron Bs ${walletContrib.toFixed(2)} a tu billetera Garden. Por favor intenta el pago nuevamente.`
    : 'Tu pago fue rechazado. Verifica que hayas realizado el pago correctamente e intenta de nuevo, o solicita una revisión manual desde la app.';

  prisma.notification.create({
    data: {
      userId: booking.clientId,
      title: 'Pago rechazado',
      message: notifMessage,
      type: 'PAYMENT',
    },
  }).catch((err) => {
    logger.warn('Failed to notify client of payment rejection', { bookingId, err });
  });

  logger.info('Admin: pago rechazado; QR limpiado; cliente notificado', { bookingId, adminId });
  return { id: updated.id, status: updated.status };
}

// ---------------------------------------------------------------------------
// Control de casos especiales — aprobar pago (con contraseña + ventana 24h) y reembolso
// ---------------------------------------------------------------------------

export async function assertAdminPassword(adminId: string, adminPassword: string): Promise<void> {
  const admin = await prisma.user.findUnique({ where: { id: adminId } });
  if (!admin) throw new UnauthorizedError('Admin no encontrado');
  const { comparePassword } = await import('../auth/auth.service.js');
  const isValid = await comparePassword(adminPassword, admin.passwordHash);
  if (!isValid) throw new UnauthorizedError('Contraseña de administrador incorrecta', 'INVALID_ADMIN_PASSWORD');
}

const APPROVAL_WINDOW_MS = 24 * 60 * 60 * 1000;

/** POST /api/admin/bookings/:id/approve-payment-secure — mismo efecto que approvePayment
 *  (booking.controller aprueba directo, sin contraseña, desde la pestaña Pagos), pero
 *  accesible también desde el detalle de la reserva, exige contraseña de admin, y solo
 *  dentro de las 24h desde que el pago quedó pendiente de aprobación (control de casos
 *  especiales — evita aprobar algo "viejo" sin refrescar el contexto primero). */
export async function approvePaymentSecure(
  bookingId: string,
  adminId: string,
  adminPassword: string
): Promise<{ id: string; status: string }> {
  await assertAdminPassword(adminId, adminPassword);

  const booking = await prisma.booking.findUnique({ where: { id: bookingId } });
  if (!booking) throw new NotFoundError('Reserva no encontrada');
  if (booking.status !== BookingStatus.PAYMENT_PENDING_APPROVAL && booking.status !== BookingStatus.PENDING_PAYMENT) {
    throw new BadRequestError('La reserva no está en un estado válido para aprobación de pago');
  }
  if (!booking.paymentApprovalRequestedAt) {
    throw new BadRequestError('Esta reserva no tiene una solicitud de pago con ventana de aprobación registrada.');
  }
  const elapsed = Date.now() - booking.paymentApprovalRequestedAt.getTime();
  if (elapsed > APPROVAL_WINDOW_MS) {
    throw new BadRequestError('La ventana de 24 horas para aprobar este pago ya expiró.');
  }

  const caregiverProfile = await prisma.caregiverProfile.findUnique({
    where: { id: booking.caregiverId },
    select: { userId: true },
  });

  await prisma.$transaction(async (tx) => {
    await tx.booking.update({
      where: { id: bookingId },
      data: { status: BookingStatus.WAITING_CAREGIVER_APPROVAL, paidAt: new Date() },
    });
    await tx.adminAction.create({
      data: {
        adminId,
        actionType: 'APPROVE_PAYMENT_SECURE',
        targetId: bookingId,
        notes: `Pago aprobado (control de casos especiales, con contraseña) desde detalle de reserva. Booking ${bookingId} → WAITING_CAREGIVER_APPROVAL`,
      },
    });
    if (caregiverProfile) {
      await tx.notification.create({
        data: {
          userId: caregiverProfile.userId,
          title: 'Nueva reserva confirmada',
          message: 'El pago fue verificado. Tienes una nueva reserva esperando tu aceptación.',
          type: 'NEW_BOOKING',
        },
      });
    }
  });

  if (caregiverProfile) {
    sendPushToUser(
      caregiverProfile.userId,
      'Nueva reserva confirmada',
      'El pago fue verificado. Tienes una nueva reserva esperando tu aceptación.'
    ).catch(() => {});
  }

  logger.info('Admin: pago aprobado (secure, con contraseña)', { bookingId, adminId });
  return { id: bookingId, status: BookingStatus.WAITING_CAREGIVER_APPROVAL };
}

export type RefundDestination = 'WALLET' | 'COUPON' | 'MANUAL_TRANSACTION';

/** POST /api/admin/bookings/:id/refund — reembolsa el precio del SERVICIO (no la
 *  donación voluntaria, que no se revierte) al dueño, por el destino elegido, y
 *  cancela la reserva (el dinero ya no corresponde a un servicio que va a ocurrir).
 *  Exige contraseña de admin; se desactiva sola una vez refundStatus queda PROCESSED. */
export async function refundBooking(
  bookingId: string,
  adminId: string,
  adminPassword: string,
  destination: RefundDestination
): Promise<{ id: string; status: string; refundAmount: number; destination: RefundDestination; couponCode?: string }> {
  await assertAdminPassword(adminId, adminPassword);

  const booking = await prisma.booking.findUnique({ where: { id: bookingId } });
  if (!booking) throw new NotFoundError('Reserva no encontrada');
  if (booking.status === BookingStatus.COMPLETED) {
    throw new BadRequestError('No se puede reembolsar una reserva cuyo servicio ya se completó.');
  }
  if (booking.refundStatus === 'PROCESSED') {
    throw new BadRequestError('Esta reserva ya fue reembolsada.');
  }
  // El pago debe haber pasado por aprobación (paidAt seteado por approvePayment/
  // approvePaymentSecure o por confirmación automática de Stripe/QR) antes de poder
  // reembolsarse — evita acreditar dinero que Garden nunca llegó a cobrar.
  if (!booking.paidAt) {
    throw new BadRequestError('Debes aprobar el pago antes de poder reembolsarlo.');
  }
  // Refund = precio del servicio (totalAmount) — la donación voluntaria no se revierte.
  const refundAmount = Number(booking.totalAmount);
  if (refundAmount <= 0) {
    throw new BadRequestError('Esta reserva no tiene un monto de servicio pagado para reembolsar.');
  }

  let couponCode: string | undefined;

  await prisma.$transaction(async (tx) => {
    if (destination === 'WALLET') {
      const updatedUser = await tx.user.update({
        where: { id: booking.clientId },
        data: { balance: { increment: refundAmount } },
        select: { balance: true },
      });
      await tx.walletTransaction.create({
        data: {
          userId: booking.clientId,
          type: 'REFUND',
          amount: refundAmount,
          balance: Number(updatedUser.balance),
          description: `Reembolso admin — reserva ${bookingId.slice(0, 8)} (control de casos especiales)`,
          bookingId,
          status: 'COMPLETED',
        },
      });
    } else if (destination === 'COUPON') {
      couponCode = `REEMBOLSO-${bookingId.slice(0, 6).toUpperCase()}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`;
      await tx.giftCode.create({
        data: {
          code: couponCode,
          amount: refundAmount,
          maxUses: 1,
        },
      });
    }
    // MANUAL_TRANSACTION: sin movimiento de dinero en el sistema — el admin ya
    // transfirió por fuera; esto solo deja la marca contable (refundStatus/refundAmount).

    await tx.booking.update({
      where: { id: bookingId },
      data: {
        refundStatus: 'PROCESSED',
        refundAmount,
        status: BookingStatus.CANCELLED,
        cancelledAt: new Date(),
        cancellationReason: `Reembolso procesado por admin (${destination === 'WALLET' ? 'billetera' : destination === 'COUPON' ? 'cupón' : 'transacción manual'})`,
        cancellationSource: 'ADMIN_REFUND',
      },
    });

    await tx.adminAction.create({
      data: {
        adminId,
        actionType: 'REFUND_BOOKING',
        targetId: bookingId,
        notes: `Reembolso de Bs ${refundAmount.toFixed(2)} vía ${destination}${couponCode ? ` (código ${couponCode})` : ''}. Reserva cancelada.`,
      },
    });
  });

  const notifMessage = destination === 'WALLET'
    ? `Se reembolsaron Bs ${refundAmount.toFixed(2)} a tu billetera Garden.`
    : destination === 'COUPON'
      ? `Tu reembolso de Bs ${refundAmount.toFixed(2)} está disponible como cupón: ${couponCode}.`
      : `Tu reembolso de Bs ${refundAmount.toFixed(2)} fue procesado por transferencia.`;
  prisma.notification.create({
    data: { userId: booking.clientId, title: 'Reembolso procesado', message: notifMessage, type: 'PAYMENT' },
  }).catch((err) => logger.warn('Failed to notify client of refund', { bookingId, err }));

  logger.info('Admin: reembolso procesado', { bookingId, adminId, refundAmount, destination, couponCode });
  return { id: bookingId, status: BookingStatus.CANCELLED, refundAmount, destination, couponCode };
}

/** POST /api/admin/disputes/:bookingId/resolve-manual — resolución manual forzada
 *  (a favor de dueño o cuidador), para casos donde el agente de IA no decide claro
 *  o el admin necesita anular el resultado. Reutiliza applyResolution() (mismo
 *  código que usa la resolución automática) para que el efecto de dinero/estado
 *  sea IDÉNTICO a un veredicto normal — solo cambia quién decide. Exige contraseña. */
export async function resolveDisputeManually(
  bookingId: string,
  adminId: string,
  adminPassword: string,
  verdict: 'CLIENT_WINS' | 'CAREGIVER_WINS',
  notes?: string
): Promise<{ id: string; verdict: string }> {
  await assertAdminPassword(adminId, adminPassword);

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId },
    include: { caregiver: { include: { user: true } }, dispute: true } as any,
  });
  if (!booking) throw new NotFoundError('Reserva no encontrada');
  if (!(booking as any).dispute) throw new BadRequestError('Esta reserva no tiene una disputa activa');
  if ((booking as any).dispute.status === 'RESOLVED') throw new BadRequestError('Esta disputa ya fue resuelta');

  const resolution = {
    verdict,
    analysis: `Resolución manual forzada por administración${notes ? `: ${notes}` : '.'}`,
    recommendations: [],
  };

  try {
    await applyDisputeResolution(bookingId, resolution, booking);
  } catch (err: any) {
    if (err.code === 'DISPUTE_ALREADY_RESOLVED') {
      throw new BadRequestError('La disputa ya fue resuelta o el pago ya no está retenido');
    }
    throw err;
  }

  await prisma.adminAction.create({
    data: {
      adminId,
      actionType: 'DISPUTE_RESOLVED_MANUAL',
      targetId: bookingId,
      notes: `Disputa resuelta manualmente: ${verdict}${notes ? ` — ${notes}` : ''}`,
    },
  });

  logger.info('Admin: disputa resuelta manualmente', { bookingId, adminId, verdict });
  return { id: bookingId, verdict };
}

// ---------------------------------------------------------------------------
// Apelaciones de disputas — Sección 13 de los Términos y Condiciones.
// Una persona del equipo de Garden (nunca el sistema automatizado) revisa la
// apelación y su decisión es definitiva.
// ---------------------------------------------------------------------------

/** GET /api/admin/disputes/appeals — todas las disputas con status='APPEALED'. */
export async function listDisputeAppeals(): Promise<any[]> {
  const disputes = await prisma.dispute.findMany({
    where: { status: 'APPEALED' } as any,
    include: {
      booking: {
        include: {
          client: { select: { firstName: true, lastName: true, email: true } },
          caregiver: { include: { user: { select: { firstName: true, lastName: true, email: true } } } },
        },
      },
    },
    orderBy: { appealedAt: 'desc' } as any,
  });

  return disputes.map((d: any) => {
    let aiRecommendations: string[] = [];
    try { aiRecommendations = JSON.parse(d.aiRecommendations ?? '[]'); } catch { /* no-op */ }
    return {
      id: d.id,
      bookingId: d.bookingId,
      status: d.status,
      clientReasons: d.clientReasons,
      caregiverResponse: d.caregiverResponse,
      aiVerdict: d.aiVerdict,
      aiAnalysis: d.aiAnalysis,
      aiRecommendations,
      resolution: d.resolution,
      appealedBy: d.appealedBy,
      appealReason: d.appealReason,
      appealedAt: d.appealedAt,
      createdAt: d.createdAt,
      updatedAt: d.updatedAt,
      clientName: `${d.booking.client.firstName} ${d.booking.client.lastName}`,
      clientEmail: d.booking.client.email,
      caregiverName: `${d.booking.caregiver.user.firstName} ${d.booking.caregiver.user.lastName}`,
      serviceType: d.booking.serviceType,
      petName: d.booking.petName,
      amount: d.booking.totalAmount,
    };
  });
}

/** Monto que cada parte recibió/recibe bajo un veredicto dado, en función del
 *  monto total y neto de la reserva. Se usa tanto para aplicar el veredicto
 *  original de la IA como para calcular la diferencia (delta) al resolver una
 *  apelación con un veredicto distinto. */
function amountsForVerdict(verdict: string, totalAmount: number, netAmount: number): {
  caregiverAmount: number; clientCashAmount: number; clientDiscountAmount: number;
} {
  if (verdict === 'CAREGIVER_WINS') {
    return { caregiverAmount: netAmount, clientCashAmount: 0, clientDiscountAmount: 0 };
  }
  if (verdict === 'CLIENT_WINS') {
    return { caregiverAmount: 0, clientCashAmount: totalAmount, clientDiscountAmount: 0 };
  }
  // PARTIAL
  const caregiverPayout = parseFloat((netAmount * 0.80).toFixed(2));
  const clientDiscountAmount = parseFloat((netAmount * 0.20).toFixed(2));
  return { caregiverAmount: caregiverPayout, clientCashAmount: 0, clientDiscountAmount };
}

/**
 * POST /api/admin/disputes/:bookingId/resolve-appeal — decisión final de un
 * admin humano sobre una disputa apelada. Puede confirmar el veredicto de la
 * IA o revertirlo. Cuando el veredicto cambia, esta función revierte el pago
 * original y aplica el nuevo, dejando WalletTransaction como rastro completo
 * de ambos movimientos (nunca se borra el historial, solo se ajusta).
 */
export async function resolveDisputeAppeal(
  bookingId: string,
  adminId: string,
  verdict: 'CLIENT_WINS' | 'CAREGIVER_WINS' | 'PARTIAL',
  resolutionText: string
): Promise<{ id: string; verdict: string }> {
  if (!resolutionText || resolutionText.trim().length < 5) {
    throw new BadRequestError('Escribe la resolución de la apelación.');
  }

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId },
    include: { caregiver: { include: { user: true } }, dispute: true } as any,
  });
  if (!booking) throw new NotFoundError('Reserva no encontrada');
  const dispute = (booking as any).dispute;
  if (!dispute) throw new BadRequestError('Esta reserva no tiene una disputa');
  if (dispute.status !== 'APPEALED') throw new BadRequestError('Esta disputa no está en apelación');

  const totalAmount = Number(booking.totalAmount);
  const commission = Number((booking as any).commissionAmount ?? totalAmount * 0.10);
  const netAmount = totalAmount - commission;
  const caregiverUserId = (booking as any).caregiver.userId;
  const clientId = booking.clientId;

  const oldVerdict = dispute.aiVerdict as string;
  const oldAmounts = amountsForVerdict(oldVerdict, totalAmount, netAmount);
  const newAmounts = amountsForVerdict(verdict, totalAmount, netAmount);

  const caregiverDelta = parseFloat((newAmounts.caregiverAmount - oldAmounts.caregiverAmount).toFixed(2));
  const clientCashDelta = parseFloat((newAmounts.clientCashAmount - oldAmounts.clientCashAmount).toFixed(2));

  await prisma.$transaction(async (tx) => {
    // Atomic claim — la apelación solo puede resolverse UNA vez.
    const claimed = await (tx as any).dispute.updateMany({
      where: { bookingId, status: 'APPEALED' },
      data: { status: 'RESOLVED' },
    });
    if (claimed.count === 0) {
      throw new BadRequestError('Esta apelación ya fue resuelta');
    }

    // ── Ajuste al cuidador (si cambia lo que le corresponde) ────────────────
    if (caregiverDelta !== 0) {
      // Balance unificado vive en User (CaregiverProfile.balance está @deprecated)
      const before = await tx.user.findUnique({ where: { id: caregiverUserId }, select: { balance: true } });
      const balanceBefore = Number(before?.balance ?? 0);
      await tx.user.update({ where: { id: caregiverUserId }, data: { balance: { increment: caregiverDelta } } });
      await tx.walletTransaction.create({
        data: {
          userId: caregiverUserId,
          type: caregiverDelta > 0 ? 'EARNING' : 'ADJUSTMENT',
          amount: caregiverDelta,
          balance: balanceBefore + caregiverDelta,
          description: `Ajuste por apelación de disputa — Reserva #${bookingId.slice(0, 8).toUpperCase()}`,
          status: 'COMPLETED',
        },
      });
    }

    // ── Ajuste al dueño (si cambia el reembolso en efectivo) ────────────────
    if (clientCashDelta !== 0) {
      // Balance unificado vive en User (ClientProfile.balance está @deprecated)
      const before = await tx.user.findUnique({ where: { id: clientId }, select: { balance: true } });
      const balanceBefore = Number(before?.balance ?? 0);
      await tx.user.update({ where: { id: clientId }, data: { balance: { increment: clientCashDelta } } });
      await tx.walletTransaction.create({
        data: {
          userId: clientId,
          type: clientCashDelta > 0 ? 'REFUND' : 'ADJUSTMENT',
          amount: clientCashDelta,
          balance: balanceBefore + clientCashDelta,
          description: `Ajuste por apelación de disputa — Reserva #${bookingId.slice(0, 8).toUpperCase()}`,
          status: 'COMPLETED',
        },
      });
    }

    // ── Código de descuento (PARTIAL) ────────────────────────────────────────
    let discountCodeId = dispute.discountCodeId as string | null;
    if (verdict === 'PARTIAL' && oldVerdict !== 'PARTIAL') {
      // Nuevo veredicto parcial: emitir código nuevo
      const discountCode = `GDN-APL-${bookingId.slice(0, 6).toUpperCase()}-${Date.now().toString(36).toUpperCase().slice(-4)}`;
      const giftCode = await tx.giftCode.create({
        data: { code: discountCode, amount: newAmounts.clientDiscountAmount, maxUses: 1, active: true },
      });
      discountCodeId = giftCode.id;
    } else if (verdict !== 'PARTIAL' && oldVerdict === 'PARTIAL' && discountCodeId) {
      // Ya no aplica el split: desactivar el código anterior (best-effort — si
      // ya fue usado por el dueño, ese uso no se puede revertir).
      await tx.giftCode.update({ where: { id: discountCodeId }, data: { active: false } }).catch(() => {});
    }

    // ── Estado final de la reserva según el veredicto de la apelación ───────
    const bookingData = verdict === 'CLIENT_WINS'
      ? { status: BookingStatus.CANCELLED, payoutStatus: 'REFUNDED' }
      : { status: BookingStatus.COMPLETED, payoutStatus: 'PAID' };
    await tx.booking.update({ where: { id: bookingId }, data: bookingData as any });

    const resolutionSummary = verdict === 'CAREGIVER_WINS'
      ? `Apelación resuelta: pago completo al cuidador (Bs ${netAmount.toFixed(2)})`
      : verdict === 'CLIENT_WINS'
        ? `Apelación resuelta: reembolso completo al cliente (Bs ${totalAmount.toFixed(2)})`
        : `Apelación resuelta: parcial — cuidador Bs ${newAmounts.caregiverAmount.toFixed(2)} (80%) | descuento dueño Bs ${newAmounts.clientDiscountAmount.toFixed(2)} (20%)`;

    await (tx as any).dispute.update({
      where: { bookingId },
      data: {
        appealVerdict: verdict,
        appealResolution: resolutionText.trim(),
        appealResolvedByAdminId: adminId,
        appealResolvedAt: new Date(),
        resolution: resolutionSummary,
        discountCodeId,
      },
    });
  });

  const verdictChanged = verdict !== oldVerdict;
  const clientMsg = verdictChanged
    ? `Un miembro de nuestro equipo revisó tu apelación y cambió el resultado. ${resolutionText.trim()}`
    : `Un miembro de nuestro equipo revisó tu apelación y confirmó la decisión anterior. ${resolutionText.trim()}`;
  const caregiverMsg = clientMsg;

  await prisma.notification.create({
    data: { userId: clientId, title: '⚖️ Resultado de tu apelación', message: clientMsg, type: 'SYSTEM' },
  }).catch(() => {});
  await prisma.notification.create({
    data: { userId: caregiverUserId, title: '⚖️ Resultado de la apelación', message: caregiverMsg, type: 'SYSTEM' },
  }).catch(() => {});
  sendPushToUser(clientId, '⚖️ Resultado de tu apelación', 'Un miembro de nuestro equipo revisó tu caso. Toca para ver el resultado.').catch(() => {});
  sendPushToUser(caregiverUserId, '⚖️ Resultado de la apelación', 'Un miembro de nuestro equipo revisó tu caso. Toca para ver el resultado.').catch(() => {});

  await prisma.adminAction.create({
    data: {
      adminId,
      actionType: 'DISPUTE_APPEAL_RESOLVED',
      targetId: bookingId,
      notes: `Apelación resuelta: ${verdict}${verdictChanged ? ` (cambió de ${oldVerdict})` : ' (confirmó veredicto de IA)'}`,
    },
  });

  logger.info('Admin: apelación de disputa resuelta', { bookingId, adminId, verdict, oldVerdict, caregiverDelta, clientCashDelta });
  return { id: bookingId, verdict };
}

// ---------------------------------------------------------------------------
// Incidentes/emergencias en servicio activo
// ---------------------------------------------------------------------------

/** POST /api/admin/bookings/:id/resolve-incident — el admin también puede
 *  resolver una emergencia (además del cuidador, desde su app) — lo que
 *  llegue primero. Reanuda el reloj del servicio y avisa a ambas partes. */
export async function resolveIncidentAdmin(
  bookingId: string,
  adminId: string
): Promise<{ id: string; totalPausedMinutes: number }> {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: { caregiver: { select: { userId: true } } },
  });
  if (!booking) throw new NotFoundError('Reserva no encontrada');
  if (!booking.pausedAt) throw new BadRequestError('Esta reserva no tiene ninguna emergencia activa');

  const pausedAtSnapshot = booking.pausedAt;
  const pausedMinutes = Math.round((Date.now() - pausedAtSnapshot.getTime()) / 60000);
  const totalPausedMinutes = booking.totalPausedMinutes + pausedMinutes;

  const events = (booking.serviceEvents as any[]) || [];
  events.push({
    type: 'INCIDENT_RESOLVED',
    description: 'Emergencia marcada como resuelta por un administrador',
    photoUrl: null,
    videoUrl: null,
    incidentType: null,
    timestamp: new Date().toISOString(),
  });

  // Claim atómico — evita que esto se aplique dos veces si el cuidador resuelve
  // la misma emergencia (addServiceEvent INCIDENT_RESOLVED) casi al mismo tiempo:
  // solo gana quien encuentre pausedAt todavía igual al que acabamos de leer.
  const claimed = await prisma.booking.updateMany({
    where: { id: bookingId, pausedAt: pausedAtSnapshot },
    data: { pausedAt: null, totalPausedMinutes, serviceEvents: events },
  });
  if (claimed.count === 0) {
    throw new BadRequestError('Esta emergencia ya fue resuelta (probablemente por el cuidador) justo antes de esta acción.');
  }

  await prisma.adminAction.create({
    data: { adminId, actionType: 'INCIDENT_RESOLVED_ADMIN', targetId: bookingId, notes: `${pausedMinutes} min pausados` },
  });

  sendPushToUser(booking.clientId, '✅ Todo en orden', 'La novedad reportada durante el servicio ya fue resuelta. El servicio continúa con normalidad.').catch(() => {});
  if (booking.caregiver?.userId) {
    sendPushToUser(booking.caregiver.userId, '✅ Emergencia resuelta', 'Garden marcó la emergencia como resuelta. Puedes continuar o concluir el servicio.').catch(() => {});
  }

  logger.info('Admin: incidente resuelto', { bookingId, adminId, pausedMinutes });
  return { id: bookingId, totalPausedMinutes };
}

/** GET /api/admin/bookings/:id/track — track GPS de un paseo, sin restricción
 *  de ownership (a diferencia de getGpsTrack, que solo deja ver al cliente o
 *  cuidador de esa reserva) — para que el admin pueda ubicar al cuidador en
 *  tiempo real durante una emergencia. */
export async function getBookingGpsTrackAdmin(bookingId: string): Promise<any[]> {
  const booking = await prisma.booking.findUnique({ where: { id: bookingId } });
  if (!booking) throw new NotFoundError('Reserva no encontrada');
  return (booking.serviceTrackingData as any[]) || [];
}

// ---------------------------------------------------------------------------
// Pagos de extensión de paseo — aprobación/rechazo manual
// ---------------------------------------------------------------------------

/** GET /api/admin/extension-payments-pending — extensiones pendientes de aprobación.
 *  Consulta directamente los bookings PASEO recientes (30 días) sin filtrar por status,
 *  para cubrir walks que ya terminaron pero tienen extensiones aún pendientes.
 */
export async function getExtensionPaymentsPending(): Promise<{ items: any[] }> {
  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const bookings = await prisma.booking.findMany({
    where: {
      serviceType: 'PASEO',
      createdAt: { gte: since },
    },
    include: {
      client: { select: { email: true, firstName: true, lastName: true } },
      caregiver: { select: { user: { select: { firstName: true, lastName: true } } } },
    },
    orderBy: { createdAt: 'desc' },
    take: 200,
  });

  const items: any[] = [];
  for (const booking of bookings) {
    const events: any[] = Array.isArray(booking.serviceEvents) ? booking.serviceEvents as any[] : [];
    // Buscar eventos EXTENSION_PENDING_PAYMENT de cualquier método que no tengan ya un EXTENSION_CONFIRMED/REJECTED con el mismo extensionId
    const confirmedIds = new Set(
      events
        .filter((e: any) => e.type === 'EXTENSION_CONFIRMED' || e.type === 'EXTENSION_REJECTED')
        .map((e: any) => e.extensionId)
    );
    const pending = events.filter(
      (e: any) => e.type === 'EXTENSION_PENDING_PAYMENT' && !confirmedIds.has(e.extensionId)
    );
    for (const evt of pending) {
      items.push({
        bookingId: booking.id,
        extensionId: evt.extensionId,
        paymentId: evt.paymentId ?? evt.qrId ?? '—',
        method: evt.method,
        additionalMinutes: evt.additionalMinutes,
        extraAmount: evt.extraAmount,
        petName: booking.petName,
        walkDate: booking.walkDate?.toISOString().slice(0, 10) ?? null,
        clientEmail: booking.client?.email,
        clientName: booking.client ? `${booking.client.firstName} ${booking.client.lastName}`.trim() : null,
        caregiverName: booking.caregiver?.user ? `${booking.caregiver.user.firstName} ${booking.caregiver.user.lastName}`.trim() : null,
        timestamp: evt.timestamp,
      });
    }
  }
  return { items };
}

/** POST /api/admin/bookings/:id/approve-extension-payment — aprueba extensión de paseo o hospedaje. */
export async function approveExtensionPayment(
  bookingId: string,
  extensionId: string,
  adminId: string
): Promise<{ success: boolean }> {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: { caregiver: { select: { userId: true } } },
  });
  if (!booking) throw new NotFoundError('Reserva no encontrada');

  const events: any[] = Array.isArray(booking.serviceEvents) ? [...(booking.serviceEvents as any[])] : [];
  const idx = events.findIndex((e: any) => e.type === 'EXTENSION_PENDING_PAYMENT' && e.extensionId === extensionId);
  if (idx === -1) throw new BadRequestError('Extensión no encontrada o ya procesada');

  const evt = events[idx];
  const { extraAmount } = evt;
  const commissionPct = await (await import('../../utils/settings-cache.js')).getNumericSetting('platformCommissionPct', 10);
  const COMMISSION_RATE = commissionPct / 100;
  const pricePerUnitClient = Number(booking.pricePerUnit);
  const pricePerUnitCaregiver = Math.round(pricePerUnitClient / (1 + COMMISSION_RATE));
  const newTotal = Number(booking.totalAmount) + extraAmount;
  const newCommission = Number(booking.commissionAmount);

  const isHospedaje = booking.serviceType === 'HOSPEDAJE';
  let bookingUpdate: Record<string, any>;
  let clientMsg: string;
  let caregiverMsg: string;

  if (isHospedaje) {
    const { additionalDays } = evt;
    const extraCommission = extraAmount - pricePerUnitCaregiver * additionalDays;
    const newEndDate = new Date(booking.endDate!);
    newEndDate.setDate(newEndDate.getDate() + additionalDays);
    bookingUpdate = {
      endDate: newEndDate,
      totalDays: (booking.totalDays ?? 1) + additionalDays,
      totalAmount: new Prisma.Decimal(newTotal),
      commissionAmount: new Prisma.Decimal(newCommission + extraCommission),
    };
    const n = additionalDays === 1 ? 'noche' : 'noches';
    clientMsg = `Se aprobó tu extensión de +${additionalDays} ${n} de hospedaje.`;
    caregiverMsg = `El pago de la extensión (+${additionalDays} ${n} · Bs ${extraAmount}) fue aprobado.`;
    events[idx] = {
      type: 'EXTENSION_CONFIRMED', extensionId, additionalDays, extraAmount,
      method: 'manual', approvedBy: adminId,
      paidAt: new Date().toISOString(), timestamp: new Date().toISOString(),
    };
  } else {
    const { additionalMinutes } = evt;
    const extraCommission = extraAmount - Math.round((pricePerUnitCaregiver / 60) * additionalMinutes);
    bookingUpdate = {
      duration: (booking.duration ?? 60) + additionalMinutes,
      totalAmount: new Prisma.Decimal(newTotal),
      commissionAmount: new Prisma.Decimal(newCommission + extraCommission),
    };
    clientMsg = `Se aprobó tu extensión de +${additionalMinutes} min. Ya fueron agregados al paseo.`;
    caregiverMsg = `El pago de la extensión (+${additionalMinutes} min · Bs ${extraAmount}) fue aprobado.`;
    events[idx] = {
      type: 'EXTENSION_CONFIRMED', extensionId, additionalMinutes, extraAmount,
      method: 'manual', approvedBy: adminId,
      paidAt: new Date().toISOString(), timestamp: new Date().toISOString(),
    };
  }

  bookingUpdate.serviceEvents = events;

  await prisma.$transaction(async (tx) => {
    await tx.booking.update({ where: { id: bookingId }, data: bookingUpdate });
    await tx.adminNotification.updateMany({
      where: { type: 'EXTENSION_PAYMENT_APPROVAL', bookingId, readAt: null },
      data: { readAt: new Date() },
    });
    await tx.notification.create({
      data: { userId: booking.clientId, title: isHospedaje ? '🏠 Extensión aprobada' : '⏱️ Extensión aprobada', message: clientMsg, type: 'SERVICE_EXTENSION' },
    });
    if (booking.caregiver?.userId) {
      await tx.notification.create({
        data: { userId: booking.caregiver.userId, title: isHospedaje ? '🏠 Hospedaje extendido' : '⏱️ Extensión de paseo aprobada', message: caregiverMsg, type: 'SERVICE_EXTENSION' },
      });
    }
  });

  const { sendPushToUser } = await import('../../services/firebase.service.js');
  sendPushToUser(booking.clientId, isHospedaje ? '🏠 Extensión aprobada' : '⏱️ Extensión aprobada', clientMsg).catch(() => {});
  if (booking.caregiver?.userId) {
    sendPushToUser(booking.caregiver.userId, isHospedaje ? '🏠 Hospedaje extendido' : '⏱️ Extensión aprobada', caregiverMsg).catch(() => {});
  }

  logger.info('Admin: extensión aprobada', { bookingId, extensionId, adminId, isHospedaje });
  return { success: true };
}

/** POST /api/admin/bookings/:id/reject-extension-payment — rechaza extensión; elimina el evento pendiente. */
export async function rejectExtensionPayment(
  bookingId: string,
  extensionId: string,
  adminId: string
): Promise<{ success: boolean }> {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: { caregiver: { select: { userId: true } } },
  });
  if (!booking) throw new NotFoundError('Reserva no encontrada');

  const events: any[] = Array.isArray(booking.serviceEvents) ? [...(booking.serviceEvents as any[])] : [];
  const idx = events.findIndex((e: any) => e.type === 'EXTENSION_PENDING_PAYMENT' && e.extensionId === extensionId);
  if (idx === -1) throw new BadRequestError('Extensión no encontrada o ya procesada');

  const evt = events[idx];
  const label = evt.additionalDays != null
    ? `+${evt.additionalDays} noche${evt.additionalDays === 1 ? '' : 's'}`
    : `+${evt.additionalMinutes} min`;
  events[idx] = {
    type: 'EXTENSION_REJECTED',
    extensionId,
    ...(evt.additionalDays != null ? { additionalDays: evt.additionalDays } : { additionalMinutes: evt.additionalMinutes }),
    rejectedBy: adminId,
    timestamp: new Date().toISOString(),
  };

  await prisma.$transaction(async (tx) => {
    await tx.booking.update({ where: { id: bookingId }, data: { serviceEvents: events } });
    await tx.adminNotification.updateMany({
      where: { type: 'EXTENSION_PAYMENT_APPROVAL', bookingId, readAt: null },
      data: { readAt: new Date() },
    });
    await tx.notification.create({
      data: {
        userId: booking.clientId,
        title: '❌ Extensión rechazada',
        message: `Tu solicitud de extensión (${label}) no pudo ser aprobada.`,
        type: 'SERVICE_EXTENSION',
      },
    });
  });

  logger.info('Admin: extensión de paseo rechazada', { bookingId, extensionId, adminId });
  return { success: true };
}

// ---------------------------------------------------------------------------
// Listado de reservas (admin) con filtro por estado
// ---------------------------------------------------------------------------

const VALID_BOOKING_STATUSES = [
  'PENDING_PAYMENT',
  'PAYMENT_PENDING_APPROVAL',
  'WAITING_CAREGIVER_APPROVAL',
  'CONFIRMED',
  'IN_PROGRESS',
  'COMPLETED',
  'CANCELLED',
] as const;

/** GET /api/admin/reservations — listado de reservas con paginación, opcional ?status= */
export async function getReservations(
  status?: string,
  page = 1,
  limit = 50
): Promise<AdminReservationsResult & { pagination: { page: number; limit: number; total: number; pages: number } }> {
  const where: { status?: BookingStatus } = {};
  if (status && VALID_BOOKING_STATUSES.includes(status as (typeof VALID_BOOKING_STATUSES)[number])) {
    where.status = status as BookingStatus;
  }

  const whereClause = Object.keys(where).length ? where : undefined;
  const skip = (page - 1) * limit;

  const [bookings, total] = await Promise.all([
    prisma.booking.findMany({
      where: whereClause,
      include: {
        client: { select: { email: true } },
        caregiver: {
          select: { user: { select: { firstName: true, lastName: true } } },
        },
      },
      orderBy: { createdAt: 'desc' },
      skip,
      take: limit,
    }),
    prisma.booking.count({ where: whereClause }),
  ]);

  const reservations: AdminReservationItem[] = bookings.map((b) => ({
    id: b.id,
    status: b.status,
    serviceType: b.serviceType,
    totalAmount: String(b.totalAmount),
    petName: b.petName,
    startDate: b.startDate?.toISOString().slice(0, 10) ?? null,
    endDate: b.endDate?.toISOString().slice(0, 10) ?? null,
    walkDate: b.walkDate?.toISOString().slice(0, 10) ?? null,
    timeSlot: b.timeSlot,
    duration: b.duration,
    clientId: b.clientId,
    caregiverId: b.caregiverId,
    createdAt: b.createdAt.toISOString(),
    clientEmail: b.client?.email,
    donationAmount: Number(b.donationAmount ?? 0),
    walletPaymentAmount: Number(b.walletPaymentAmount ?? 0),
    hasActiveIncident: b.pausedAt != null,
    caregiverName:
      b.caregiver?.user != null
        ? `${b.caregiver.user.firstName} ${b.caregiver.user.lastName}`.trim()
        : undefined,
  }));

  return {
    reservations,
    total,
    pagination: { page, limit, total, pages: Math.ceil(total / limit) || 1 },
  };
}

const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;

/** GET /api/admin/reservations/:id — detalle completo de una reserva para admin */
export async function getReservationDetail(bookingId: string) {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: {
      client: {
        include: {
          clientProfile: { include: { pets: true } },
        },
      },
      caregiver: {
        include: { user: true },
      },
      review: true,
      dispute: true,
      pet: true,
      messages: {
        include: {
          sender: { select: { id: true, firstName: true, lastName: true, role: true } },
        },
        orderBy: { createdAt: 'asc' },
      },
    },
  });
  if (!booking) throw new NotFoundError('Reserva no encontrada');

  // Wallet transactions linked to this booking
  const walletTxs = await prisma.walletTransaction.findMany({
    where: { bookingId: booking.id },
    include: { user: { select: { id: true, firstName: true, lastName: true, email: true, role: true } } },
    orderBy: { createdAt: 'asc' },
  });

  // Chat availability: 7 days after service ended (or completion)
  const chatBaseDate = booking.serviceEndedAt ?? (booking.status === 'COMPLETED' ? booking.updatedAt : null);
  const chatAvailable = chatBaseDate
    ? Date.now() - new Date(chatBaseDate).getTime() < SEVEN_DAYS_MS
    : ['IN_PROGRESS', 'CONFIRMED', 'WAITING_CAREGIVER_APPROVAL'].includes(booking.status);
  const chatExpiresAt = chatBaseDate
    ? new Date(new Date(chatBaseDate).getTime() + SEVEN_DAYS_MS).toISOString()
    : null;

  const totalAmount = Number(booking.totalAmount);
  const commissionAmount = Number(booking.commissionAmount);
  const caregiverPayout = totalAmount - commissionAmount;

  const u = booking.caregiver.user;
  const c = booking.client;

  return {
    id: booking.id,
    status: booking.status,
    serviceType: booking.serviceType,
    // Dates & time
    startDate: booking.startDate?.toISOString().slice(0, 10) ?? null,
    endDate: booking.endDate?.toISOString().slice(0, 10) ?? null,
    walkDate: booking.walkDate?.toISOString().slice(0, 10) ?? null,
    timeSlot: booking.timeSlot,
    startTime: booking.startTime,
    duration: booking.duration,
    totalDays: booking.totalDays,
    createdAt: booking.createdAt.toISOString(),
    updatedAt: booking.updatedAt.toISOString(),
    // Service execution
    serviceStartedAt: booking.serviceStartedAt?.toISOString() ?? null,
    serviceEndedAt: booking.serviceEndedAt?.toISOString() ?? null,
    serviceStartPhoto: booking.serviceStartPhoto,
    serviceEndPhoto: booking.serviceEndPhoto,
    serviceTrackingData: booking.serviceTrackingData,
    serviceEvents: booking.serviceEvents,
    pausedAt: booking.pausedAt?.toISOString() ?? null,
    totalPausedMinutes: booking.totalPausedMinutes,
    // Pet
    petId: booking.petId,
    petName: booking.petName,
    petBreed: booking.petBreed,
    petAge: booking.petAge,
    petSize: booking.petSize,
    specialNeeds: booking.specialNeeds,
    petPhotoUrl: (booking.pet as any)?.photoUrl ?? null,
    // Payment
    totalAmount,
    pricePerUnit: Number(booking.pricePerUnit),
    commissionAmount,
    commissionPercent: 10,
    caregiverPayoutAmount: caregiverPayout,
    walletPaymentAmount: Number((booking as any).walletPaymentAmount ?? 0),
    donationAmount: Number(booking.donationAmount ?? 0),
    paidAt: booking.paidAt?.toISOString() ?? null,
    paymentMethod: (booking as any).paymentMethod ?? null,
    payoutStatus: booking.payoutStatus,
    qrId: booking.qrId,
    paymentApprovalRequestedAt: booking.paymentApprovalRequestedAt?.toISOString() ?? null,
    refundAmount: booking.refundAmount ? Number(booking.refundAmount) : null,
    refundStatus: booking.refundStatus,
    cancelledAt: booking.cancelledAt?.toISOString() ?? null,
    cancellationReason: booking.cancellationReason,
    // Client
    clientId: booking.clientId,
    clientEmail: c.email,
    clientName: `${c.firstName} ${c.lastName}`.trim(),
    clientPhone: c.phone ?? null,
    clientProfileId: (booking.client.clientProfile as any)?.id ?? null,
    // Caregiver
    caregiverId: booking.caregiverId,
    caregiverName: `${u.firstName} ${u.lastName}`.trim(),
    caregiverEmail: u.email,
    caregiverPhone: u.phone ?? null,
    caregiverUserId: u.id,
    // Ratings
    ownerRated: booking.ownerRated,
    ownerRating: booking.ownerRating,
    ownerComment: booking.ownerComment,
    caregiverRated: booking.caregiverRated,
    caregiverRating: booking.caregiverRating,
    caregiverComment: booking.caregiverComment,
    review: booking.review ? {
      id: booking.review.id,
      rating: booking.review.rating,
      comment: booking.review.comment,
      photo: booking.review.photo,
      caregiverResponse: booking.review.caregiverResponse,
      respondedAt: booking.review.respondedAt?.toISOString() ?? null,
      createdAt: booking.review.createdAt.toISOString(),
    } : null,
    // Dispute
    dispute: booking.dispute ? {
      id: booking.dispute.id,
      status: booking.dispute.status,
      clientReasons: booking.dispute.clientReasons,
      caregiverResponse: booking.dispute.caregiverResponse,
      aiVerdict: booking.dispute.aiVerdict,
      aiAnalysis: booking.dispute.aiAnalysis,
      aiRecommendations: booking.dispute.aiRecommendations,
      resolution: booking.dispute.resolution,
      createdAt: booking.dispute.createdAt.toISOString(),
      updatedAt: booking.dispute.updatedAt.toISOString(),
    } : null,
    // Chat
    chatAvailable,
    chatExpiresAt,
    messages: chatAvailable ? booking.messages.map((m) => ({
      id: m.id,
      senderId: m.senderId,
      senderName: `${m.sender.firstName} ${m.sender.lastName}`.trim(),
      senderRole: m.senderRole,
      message: m.message,
      read: m.read,
      createdAt: m.createdAt.toISOString(),
    })) : [],
    // Wallet transactions
    walletTransactions: walletTxs.map((tx) => ({
      id: tx.id,
      type: tx.type,
      amount: Number(tx.amount),
      balance: Number(tx.balance),
      description: tx.description,
      status: tx.status,
      userEmail: tx.user.email,
      userName: `${tx.user.firstName} ${tx.user.lastName}`.trim(),
      userRole: tx.user.role,
      createdAt: tx.createdAt.toISOString(),
    })),
  };
}

/** GET lista de sesiones de identidad — por defecto solo REVIEW, pasa status='ALL' para todas */
export async function listIdentityReviews(status?: string) {
  const whereStatus = (!status || status === 'ALL') ? undefined : status;
  const sessions = await prisma.identityVerificationSession.findMany({
    where: whereStatus ? { status: whereStatus as any } : {},
    orderBy: { completedAt: 'asc' },
    include: {
      user: {
        select: {
          id: true,
          email: true,
          firstName: true,
          lastName: true,
        },
      },
    },
  });
  return sessions.map((s) => ({
    id: s.id,
    userId: s.userId,
    user: s.user,
    status: s.status,
    similarity: s.similarity,
    similarityScore: s.similarityScore,
    // @ts-ignore
    trustScore: s.trustScore,
    livenessScore: s.livenessScore,
    completedAt: s.completedAt,
    createdAt: s.createdAt,
    reviewedAt: (s as any).reviewedAt ?? null,
    reviewedBy: (s as any).reviewedBy ?? null,
  }));
}

/** GET /api/admin/payments-history — pagos confirmados (paidAt != null), paginados. */
export async function getPaymentsHistory(page = 1, limit = 50) {
  const where = {
    paidAt: { not: null },
    status: { notIn: ['PENDING_PAYMENT', 'PAYMENT_PENDING_APPROVAL'] as any[] },
  };
  const skip = (page - 1) * limit;

  const [bookings, total] = await Promise.all([
    prisma.booking.findMany({
      where,
      select: {
        id: true,
        status: true,
        petName: true,
        totalAmount: true,
        commissionAmount: true,
        paidAt: true,
        serviceType: true,
        startDate: true,
        endDate: true,
        walkDate: true,
        qrId: true,
        stripePaymentIntentId: true,
        payoutStatus: true,
        clientId: true,
        refundStatus: true,
        refundAmount: true,
        client: { select: { firstName: true, lastName: true, email: true } },
        caregiver: { include: { user: { select: { firstName: true, lastName: true } } } },
      },
      orderBy: { paidAt: 'desc' },
      skip,
      take: limit,
    }),
    prisma.booking.count({ where }),
  ]);

  const items = bookings.map((b) => {
    // Inferir método de pago: QR manual vs Stripe
    const paymentMethod = b.qrId ? 'QR/Transferencia' : b.stripePaymentIntentId ? 'Stripe' : 'Manual';
    return {
      id: b.id,
      status: b.status,
      petName: b.petName,
      totalAmount: Number(b.totalAmount),
      commissionAmount: Number(b.commissionAmount),
      paidAt: b.paidAt?.toISOString() ?? null,
      paymentMethod,
      serviceType: b.serviceType,
      startDate: b.startDate?.toISOString() ?? null,
      endDate: b.endDate?.toISOString() ?? null,
      walkDate: b.walkDate?.toISOString() ?? null,
      payoutStatus: b.payoutStatus,
      // El admin necesita saber si esto fue reembolsado para no contarlo
      // como ingreso real en el resumen financiero (ver admin_panel_screen.dart).
      refundStatus: b.refundStatus,
      refundAmount: b.refundAmount ? Number(b.refundAmount) : null,
      clientName: `${b.client.firstName} ${b.client.lastName}`,
      clientEmail: b.client.email,
      caregiverName: `${b.caregiver.user.firstName} ${b.caregiver.user.lastName}`,
    };
  });

  return {
    payments: items,
    total,
    pagination: { page, limit, total, pages: Math.ceil(total / limit) || 1 },
  };
}

/** GET detalles sesión identidad con URLs firmadas para imágenes */
export async function getIdentityVerificationDetail(sessionId: string) {
  const { resolveUrlForAdmin } = await import('../verification/verification-upload.js');
  const session = await prisma.identityVerificationSession.findUnique({
    where: { id: sessionId },
    include: { user: { include: { caregiverProfile: true } } },
  });
  if (!session) throw new NotFoundError('Sesión de verificación no encontrada');

  const urls = (session.livenessFrameUrls as string[] | null) ?? [];
  const livenessUrlsSigned = await Promise.all(urls.map((u) => resolveUrlForAdmin(u)));

  const [selfieUrl, ciFrontUrl, ciBackUrl, faceCroppedSelfieUrl, faceCroppedDocumentUrl] = await Promise.all([
    resolveUrlForAdmin(session.selfieUrl),
    resolveUrlForAdmin(session.ciFrontUrl),
    resolveUrlForAdmin(session.ciBackUrl),
    resolveUrlForAdmin(session.faceCroppedSelfieUrl),
    resolveUrlForAdmin(session.faceCroppedDocumentUrl),
  ]);

  return {
    ...session,
    selfieUrlSigned: selfieUrl,
    ciFrontUrlSigned: ciFrontUrl,
    ciBackUrlSigned: ciBackUrl,
    faceCroppedSelfieUrlSigned: faceCroppedSelfieUrl,
    faceCroppedDocumentUrlSigned: faceCroppedDocumentUrl,
    livenessFrameUrlsSigned: livenessUrlsSigned,
    ocrData: session.ocrData,
    similarityScore: session.similarityScore ?? session.similarity,
    livenessScore: session.livenessScore,
    documentConfidence: session.documentConfidence,
    identityScore: session.identityScore,
    // @ts-ignore
    faceScore: session.faceScore,
    // @ts-ignore
    ocrScore: session.ocrScore,
    // @ts-ignore
    docScore: session.docScore,
    // @ts-ignore
    qualityScore: session.qualityScore,
    // @ts-ignore
    behaviorScore: session.behaviorScore,
    // @ts-ignore
    trustScore: session.trustScore,
    // @ts-ignore
    ipAddress: session.ipAddress,
    // @ts-ignore
    userAgent: session.userAgent,
    // @ts-ignore
    deviceFingerprint: session.deviceFingerprint,
    // @ts-ignore
    deviceDetails: session.deviceDetails,
    // @ts-ignore
    locationData: session.locationData,
  };
}

/** Aprobar manualmente verificación de identidad */
export async function approveIdentityVerification(sessionId: string, adminId: string) {
  const session = await prisma.identityVerificationSession.findUnique({
    where: { id: sessionId },
  });
  if (!session) throw new NotFoundError('Sesión de verificación no encontrada');

  await prisma.$transaction([
    prisma.identityVerificationSession.update({
      where: { id: sessionId },
      data: {
        status: 'VERIFIED',
        reviewedBy: adminId,
        reviewedAt: new Date(),
      } as any,
    }),
    prisma.user.update({
      where: { id: session.userId },
      data: { identityVerified: true } as any
    }),
    prisma.caregiverProfile.update({
      where: { userId: session.userId },
      data: {
        identityVerificationStatus: 'VERIFIED',
      },
    }),
  ]);
  return { success: true };
}

/** Rechazar manualmente verificación de identidad */
export async function rejectIdentityVerification(sessionId: string, adminId: string) {
  const session = await prisma.identityVerificationSession.findUnique({
    where: { id: sessionId },
  });
  if (!session) throw new NotFoundError('Sesión de verificación no encontrada');

  await prisma.$transaction([
    prisma.identityVerificationSession.update({
      where: { id: sessionId },
      data: {
        status: 'REJECTED',
        reviewedBy: adminId,
        reviewedAt: new Date(),
      } as any,
    }),
    prisma.user.update({
      where: { id: session.userId },
      data: { identityVerified: false } as any
    }),
    prisma.caregiverProfile.update({
      where: { userId: session.userId },
      data: {
        identityVerificationStatus: 'REJECTED',
      },
    }),
  ]);
  return { success: true };
}

/** Suspender cuidador (fuera del aire temporalmente) */
export async function suspendCaregiver(
  profileId: string,
  adminId: string,
  reason: string
) {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { id: profileId },
    include: { user: true },
  });
  if (!profile) throw new CaregiverNotFoundError(profileId);

  const updated = await prisma.caregiverProfile.update({
    where: { id: profileId },
    data: {
      suspended: true,
      suspendedAt: new Date(),
      suspensionReason: reason,
      status: CaregiverStatus.SUSPENDED,
    },
  });

  await prisma.notification.create({
    data: {
      userId: profile.userId,
      title: 'Tu perfil ha sido suspendido',
      message: `Hola ${profile.user.firstName}, tu perfil ha sido suspendido temporalmente por el siguiente motivo: ${reason}. Por favor contáctanos para más información.`,
      type: 'ACCOUNT_SUSPENDED',
    },
  });

  await prisma.adminAction.create({
    data: {
      adminId,
      actionType: 'CAREGIVER_SUSPEND',
      targetId: profileId,
      notes: reason,
    },
  });

  await getCache().del(`caregivers:detail:${profileId}`);
  await delByPrefix('caregivers:list:');

  return { success: true, suspended: true };
}

/**
 * Poner un perfil APROBADO bajo revisión temporal por actividad sospechosa.
 * - Oculta al cuidador del marketplace (suspended=true, status=SUSPENDED).
 * - Notifica al cuidador con el motivo.
 * - El admin puede reactivar con activateCaregiver().
 */
export async function flagCaregiverForReview(
  profileId: string,
  adminId: string,
  reason: string
) {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { id: profileId },
    include: { user: true },
  });
  if (!profile) throw new CaregiverNotFoundError(profileId);

  await prisma.caregiverProfile.update({
    where: { id: profileId },
    data: {
      suspended: true,
      suspendedAt: new Date(),
      suspensionReason: reason,
      status: CaregiverStatus.SUSPENDED,
    },
  });

  await prisma.notification.create({
    data: {
      userId: profile.userId,
      title: 'Tu perfil está bajo revisión temporal',
      message: `Hola ${profile.user.firstName}, hemos detectado actividad inusual en tu cuenta y tu perfil ha sido puesto temporalmente bajo revisión. Motivo: ${reason}. Tu perfil no es visible en el marketplace mientras dure la revisión. Te notificaremos cuando se resuelva. Si tienes dudas, contáctanos.`,
      type: 'PROFILE_UNDER_REVIEW',
    },
  });

  await prisma.adminAction.create({
    data: {
      adminId,
      actionType: 'CAREGIVER_FLAG_REVIEW',
      targetId: profileId,
      notes: reason,
    },
  });

  await getCache().del(`caregivers:detail:${profileId}`);
  await delByPrefix('caregivers:list:');

  logger.info('Admin: perfil marcado para revisión', { profileId, adminId, reason });
  return { success: true, underReview: true };
}

/** Activar cuidador (revertir suspensión) */
export async function activateCaregiver(
  profileId: string,
  adminId: string,
  notes?: string
) {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { id: profileId },
  });
  if (!profile) throw new CaregiverNotFoundError(profileId);

  const updated = await prisma.caregiverProfile.update({
    where: { id: profileId },
    data: {
      suspended: false,
      // suspendedAt/suspensionReason YA NO se borran — se conservan como
      // registro histórico de la última suspensión (auditoría visible en el
      // detalle del cuidador, no solo en logs). El flag `suspended: false`
      // ya es suficiente para saber que está activo hoy.
      status: CaregiverStatus.APPROVED, // Asumimos que vuelve a aprobado si se activa
    },
  });

  await prisma.notification.create({
    data: {
      userId: profile.userId,
      title: 'Perfil activado',
      message: '¡Buenas noticias! Tu perfil ha sido activado nuevamente.',
      type: 'ACCOUNT_ACTIVATED',
    },
  });

  await prisma.adminAction.create({
    data: {
      adminId,
      actionType: 'CAREGIVER_ACTIVATE',
      targetId: profileId,
      notes,
    },
  });

  await getCache().del(`caregivers:detail:${profileId}`);
  await delByPrefix('caregivers:list:');

  return { success: true, suspended: false };
}

/** Eliminar cuidador completamente (requiere contraseña admin) */
export async function deleteCaregiver(
  profileId: string,
  adminId: string,
  payload: { reason: string; adminPassword: string }
) {
  const { reason, adminPassword } = payload;
  const admin = await prisma.user.findUnique({ where: { id: adminId } });
  if (!admin) throw new UnauthorizedError('Admin no encontrado');

  const { comparePassword } = await import('../auth/auth.service.js');
  const isValid = await comparePassword(adminPassword, admin.passwordHash);
  if (!isValid) throw new UnauthorizedError('Contraseña de administrador incorrecta', 'INVALID_ADMIN_PASSWORD');

  const profile = await prisma.caregiverProfile.findUnique({
    where: { id: profileId },
    select: { userId: true },
  });
  if (!profile) throw new CaregiverNotFoundError(profileId);

  await prisma.adminAction.create({
    data: {
      adminId,
      actionType: 'CAREGIVER_DELETE',
      targetId: profileId,
      notes: reason,
    },
  });

  const userId = profile.userId;

  // Collect booking IDs to clean up child records that lack onDelete:Cascade
  const bookings = await prisma.booking.findMany({
    where: { caregiverId: profileId },
    select: { id: true },
  });
  const bookingIds = bookings.map((b) => b.id);

  // Delete child records of Booking without cascade
  if (bookingIds.length > 0) {
    await prisma.dispute.deleteMany({ where: { bookingId: { in: bookingIds } } });
    await prisma.meetAndGreet.deleteMany({ where: { bookingId: { in: bookingIds } } });
    await prisma.chatMessage.deleteMany({ where: { bookingId: { in: bookingIds } } });
  }
  // ChatMessages sent by the caregiver user (senderId FK — no cascade)
  await prisma.chatMessage.deleteMany({ where: { senderId: userId } });
  // SugerenciaPrecio references CaregiverProfile without cascade
  await prisma.sugerenciaPrecio.deleteMany({ where: { caregiverId: profileId } });
  // WalletTransaction references User without cascade
  await prisma.walletTransaction.deleteMany({ where: { userId } });

  // Delete user — Prisma cascades: User → CaregiverProfile → Availability, Booking, Review
  await prisma.user.delete({ where: { id: userId } });

  await getCache().del(`caregivers:detail:${profileId}`);
  await delByPrefix('caregivers:list:');

  return { success: true };
}

export async function unlockVerification(profileId: string, adminId: string) {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { id: profileId },
    select: { id: true },
  });
  if (!profile) throw new CaregiverNotFoundError(profileId);

  await (prisma.caregiverProfile as any).update({
    where: { id: profileId },
    data: { verificationAttempts: 0, verificationLockUntil: null },
  });

  await prisma.adminAction.create({
    data: {
      adminId,
      actionType: 'UNLOCK_VERIFICATION',
      targetId: profileId,
      notes: 'Bloqueo de verificación de identidad eliminado por admin',
    },
  });

  await getCache().del(`caregivers:detail:${profileId}`);
  return { success: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// OWNERS (CLIENTES / DUEÑOS DE MASCOTAS)
// ─────────────────────────────────────────────────────────────────────────────

export async function listOwners(page = 1, limit = 30, search?: string) {
  const skip = (page - 1) * limit;

  const where: any = { role: 'CLIENT' };
  if (search) {
    where.OR = [
      { firstName: { contains: search, mode: 'insensitive' } },
      { email: { contains: search, mode: 'insensitive' } },
    ];
  }

  const [users, total] = await Promise.all([
    prisma.user.findMany({
      where,
      skip,
      take: limit,
      orderBy: { createdAt: 'desc' },
      include: {
        clientProfile: { include: { pets: true } },
        clientBookings: {
          select: { id: true, status: true, totalAmount: true },
        },
      },
    }),
    prisma.user.count({ where }),
  ]);

  const owners = users.map((u) => {
    const bookings = u.clientBookings;
    const completed = bookings.filter((b) => b.status === 'COMPLETED');
    const totalSpent = completed.reduce((acc, b) => acc + Number(b.totalAmount ?? 0), 0);
    return {
      id: u.id,
      name: `${u.firstName} ${u.lastName}`,
      email: u.email,
      phone: u.phone,
      photoUrl: u.profilePicture,
      createdAt: u.createdAt.toISOString(),
      emailVerified: u.emailVerified,
      petsCount: u.clientProfile?.pets.length ?? 0,
      bookingsCount: bookings.length,
      completedBookings: completed.length,
      totalSpent,
      isComplete: u.clientProfile?.isComplete ?? false,
    };
  });

  return { owners, total, page, limit, pages: Math.ceil(total / limit) };
}

export async function getOwnerDetail(userId: string) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: {
      clientProfile: { include: { pets: true } },
      clientBookings: {
        orderBy: { createdAt: 'desc' },
        take: 20,
        include: {
          caregiver: { select: { profilePhoto: true, user: { select: { firstName: true, lastName: true } } } },
          pet: { select: { name: true, size: true } },
        },
      },
    },
  });
  if (!user) throw new NotFoundError('Owner not found');

  const bookings = user.clientBookings;
  const completed = bookings.filter((b) => b.status === 'COMPLETED');
  const totalSpent = completed.reduce((acc, b) => acc + Number((b as any).totalAmount ?? 0), 0);

  return {
    id: user.id,
    name: `${user.firstName} ${user.lastName}`,
    email: user.email,
    phone: user.phone,
    photoUrl: user.profilePicture,
    createdAt: user.createdAt.toISOString(),
    emailVerified: user.emailVerified,
    clientProfile: user.clientProfile
      ? {
          id: user.clientProfile.id,
          isComplete: user.clientProfile.isComplete,
          address: user.clientProfile.address,
          zone: null,
          pets: user.clientProfile.pets.map((p) => ({
            id: p.id,
            name: p.name,
            breed: p.breed,
            size: p.size,
            photoUrl: p.photoUrl,
            birthDate: null,
            notes: p.notes,
          })),
        }
      : null,
    bookings: bookings.map((b) => ({
      id: b.id,
      status: b.status,
      serviceType: b.serviceType,
      totalPrice: Number((b as any).totalAmount ?? 0),
      walkDate: (b as any).walkDate?.toISOString() ?? null,
      createdAt: b.createdAt.toISOString(),
      caregiverName: b.caregiver?.user ? `${(b.caregiver.user as any).firstName} ${(b.caregiver.user as any).lastName}` : null,
      petName: b.pet?.name ?? null,
      caregiverRated: (b as any).caregiverRated ?? false,
      caregiverRating: (b as any).caregiverRating ?? null,
      caregiverComment: (b as any).caregiverComment ?? null,
    })),
    stats: {
      totalBookings: bookings.length,
      completedBookings: completed.length,
      totalSpent,
      avgCaregiverRating: (() => {
        const rated = bookings.filter((b) => (b as any).caregiverRating != null);
        if (rated.length === 0) return null;
        const sum = rated.reduce((acc, b) => acc + Number((b as any).caregiverRating), 0);
        return Math.round((sum / rated.length) * 10) / 10;
      })(),
      caregiverRatingsCount: bookings.filter((b) => (b as any).caregiverRated).length,
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// LIVE STATS
// ─────────────────────────────────────────────────────────────────────────────

export async function getLiveStats() {
  const now = new Date();
  const last5min = new Date(now.getTime() - 5 * 60 * 1000);
  const last24h = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const last7d = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

  const [
    activeBookings,
    pendingPayments,
    pendingWithdrawals,
    pendingDisputes,
    pendingCaregivers,
    recentBookings24h,
    recentBookings7d,
    newUsers7d,
    newUsers24h,
    totalClients,
    totalCaregivers,
    totalBookings,
  ] = await Promise.all([
    prisma.booking.count({ where: { status: 'IN_PROGRESS' } }),
    prisma.booking.count({ where: { status: 'PAYMENT_PENDING_APPROVAL' } }),
    prisma.walletTransaction.count({ where: { type: 'WITHDRAWAL', status: 'PENDING' } }),
    prisma.dispute.count({ where: { status: { not: 'RESOLVED' } } }),
    prisma.caregiverProfile.count({ where: { status: { in: ['PENDING_REVIEW', 'NEEDS_REVISION'] } } }),
    prisma.booking.count({ where: { createdAt: { gte: last24h } } }),
    prisma.booking.count({ where: { createdAt: { gte: last7d } } }),
    prisma.user.count({ where: { createdAt: { gte: last7d } } }),
    prisma.user.count({ where: { createdAt: { gte: last24h } } }),
    prisma.user.count({ where: { role: 'CLIENT' } }),
    prisma.caregiverProfile.count(),
    prisma.booking.count(),
  ]);

  // Recent activity feed (last 24h)
  const recentActivity = await prisma.booking.findMany({
    where: { createdAt: { gte: last24h } },
    orderBy: { createdAt: 'desc' },
    take: 10,
    select: {
      id: true,
      status: true,
      serviceType: true,
      createdAt: true,
      client: { select: { firstName: true, lastName: true } },
      caregiver: { select: { user: { select: { firstName: true, lastName: true } } } },
    },
  });

  return {
    realtime: {
      activeServices: activeBookings,
      pendingPayments,
      pendingWithdrawals,
      pendingDisputes,
      pendingCaregivers,
    },
    today: {
      newBookings: recentBookings24h,
      newUsers: newUsers24h,
    },
    week: {
      newBookings: recentBookings7d,
      newUsers: newUsers7d,
    },
    totals: {
      clients: totalClients,
      caregivers: totalCaregivers,
      bookings: totalBookings,
    },
    recentActivity: recentActivity.map((b) => ({
      id: b.id,
      type: b.serviceType,
      status: b.status,
      clientName: b.client ? `${b.client.firstName} ${b.client.lastName}` : '—',
      caregiverName: b.caregiver?.user ? `${(b.caregiver.user as any).firstName} ${(b.caregiver.user as any).lastName}` : '—',
      createdAt: b.createdAt.toISOString(),
    })),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// FINANCIAL STATS
// ─────────────────────────────────────────────────────────────────────────────

export async function getFinancialStats() {
  /**
   * MODELO FINANCIERO GARDEN
   * ─────────────────────────────────────────────────────────────
   * El cuidador fija su precio P (pricePerUnit × días/duración).
   * GARDEN añade 10% encima → el cliente paga totalAmount = P × 1.10
   * commissionAmount = P × 0.10  ← ganancia real de GARDEN (ya guardada en DB)
   * Cuidador recibe  = totalAmount − commissionAmount = P
   *
   * Devoluciones (refundAmount procesadas) → dinero del dueño que
   * se regresa; NO es ganancia de GARDEN, se muestra separado.
   *
   * Códigos de regalo → gasto de marketing de GARDEN; se descuenta
   * del neto como inversión en adquisición de usuarios.
   * ─────────────────────────────────────────────────────────────
   */
  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const startOfLastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const endOfLastMonth = new Date(now.getFullYear(), now.getMonth(), 0);
  const startOfYear = new Date(now.getFullYear(), 0, 1);

  // ── Reservas completadas ─────────────────────────────────────
  // commissionAmount = ganancia GARDEN por reserva (10% del precio del cuidador)
  // totalAmount      = lo que pagó el cliente
  // totalAmount - commissionAmount = lo que recibe el cuidador
  const [allCompleted, monthCompleted, lastMonthCompleted, yearCompleted] = await Promise.all([
    prisma.booking.aggregate({
      where: { status: 'COMPLETED' },
      _sum: { totalAmount: true, commissionAmount: true },
      _count: true,
    }),
    prisma.booking.aggregate({
      where: { status: 'COMPLETED', serviceEndedAt: { gte: startOfMonth } },
      _sum: { totalAmount: true, commissionAmount: true },
      _count: true,
    }),
    prisma.booking.aggregate({
      where: { status: 'COMPLETED', serviceEndedAt: { gte: startOfLastMonth, lte: endOfLastMonth } },
      _sum: { totalAmount: true, commissionAmount: true },
      _count: true,
    }),
    prisma.booking.aggregate({
      where: { status: 'COMPLETED', serviceEndedAt: { gte: startOfYear } },
      _sum: { totalAmount: true, commissionAmount: true },
      _count: true,
    }),
  ]);

  // ── Devoluciones procesadas (dinero que volvió al dueño) ─────
  const refundStats = await prisma.booking.aggregate({
    where: { refundStatus: 'PROCESSED' },
    _sum: { refundAmount: true, commissionAmount: true },
    _count: true,
  });

  // ── Retiros de cuidadores ────────────────────────────────────
  const [withdrawalStats, withdrawalMonthly] = await Promise.all([
    prisma.walletTransaction.groupBy({
      by: ['status'],
      where: { type: 'WITHDRAWAL' },
      _sum: { amount: true },
      _count: true,
    }),
    prisma.walletTransaction.aggregate({
      where: { type: 'WITHDRAWAL', status: 'COMPLETED', createdAt: { gte: startOfMonth } },
      _sum: { amount: true },
    }),
  ]);

  // ── Códigos de regalo usados (gasto de marketing) ────────────
  const giftCodes = await prisma.giftCode.findMany({
    select: { amount: true, usedBy: true },
  });
  const totalGiftCodeMarketing = giftCodes.reduce(
    (acc, gc) => acc + Number(gc.amount) * gc.usedBy.length,
    0,
  );
  // Gasto real de marketing este mes: transacciones de tipo GIFT (códigos de regalo canjeados)
  const monthGiftCodeTxns = await prisma.walletTransaction.aggregate({
    where: {
      type: 'GIFT',
      createdAt: { gte: startOfMonth },
    },
    _sum: { amount: true },
  });
  const monthGiftCodes = Number(monthGiftCodeTxns._sum.amount ?? 0);

  // ── Gráfica mensual (últimos 6 meses) ────────────────────────
  // Mostramos: comisión GARDEN (ganancia real) y facturación total al cliente
  const monthlyData: Array<{
    month: string; commission: number; billedToClient: number; bookings: number;
  }> = [];
  for (let i = 5; i >= 0; i--) {
    const mStart = new Date(now.getFullYear(), now.getMonth() - i, 1);
    const mEnd = new Date(now.getFullYear(), now.getMonth() - i + 1, 0);
    const agg = await prisma.booking.aggregate({
      where: { status: 'COMPLETED', serviceEndedAt: { gte: mStart, lte: mEnd } },
      _sum: { totalAmount: true, commissionAmount: true },
      _count: true,
    });
    monthlyData.push({
      month: mStart.toLocaleString('es', { month: 'short', year: '2-digit' }),
      commission: Number(agg._sum.commissionAmount ?? 0),
      billedToClient: Number(agg._sum.totalAmount ?? 0),
      bookings: agg._count,
    });
  }

  // ── Desglose por tipo de servicio ────────────────────────────
  const [paseoStats, hospedajeStats] = await Promise.all([
    prisma.booking.aggregate({
      where: { status: 'COMPLETED', serviceType: 'PASEO' },
      _sum: { totalAmount: true, commissionAmount: true },
      _count: true,
    }),
    prisma.booking.aggregate({
      where: { status: 'COMPLETED', serviceType: 'HOSPEDAJE' },
      _sum: { totalAmount: true, commissionAmount: true },
      _count: true,
    }),
  ]);

  // ── Cálculos finales ─────────────────────────────────────────
  const grossBilled        = Number(allCompleted._sum.totalAmount ?? 0);      // total facturado a clientes
  const gardenCommissions  = Number(allCompleted._sum.commissionAmount ?? 0); // ganancia real GARDEN (10%)
  const caregiverPayouts   = grossBilled - gardenCommissions;                  // lo que reciben cuidadores
  const refundsToClients   = Number(refundStats._sum.refundAmount ?? 0);      // devoluciones (≠ ganancia)
  const refundCommLost     = Number(refundStats._sum.commissionAmount ?? 0);  // comisiones perdidas por cancelaciones
  // netGardenIncome: solo resta marketing real (gift codes). refundCommLost son comisiones
  // de reservas CANCELADAS que nunca se contabilizaron en gardenCommissions, así que
  // restarlas provocaría ingresos negativos falsos. Se muestran como dato informativo.
  const netGardenIncome    = gardenCommissions - totalGiftCodeMarketing;

  const thisMonthGardenInc = Number(monthCompleted._sum.commissionAmount ?? 0);
  const lastMonthGardenInc = Number(lastMonthCompleted._sum.commissionAmount ?? 0);
  const yearGardenInc      = Number(yearCompleted._sum.commissionAmount ?? 0);

  const pendingWd    = withdrawalStats.find((w) => w.status === 'PENDING');
  const completedWd  = withdrawalStats.find((w) => w.status === 'COMPLETED');
  const processingWd = withdrawalStats.find((w) => w.status === 'PROCESSING');

  return {
    /**
     * summary: KPIs principales del dashboard
     * - grossBilled: total cobrado a clientes (incluye comisión GARDEN)
     * - gardenCommissions: 10% sobre precio cuidador = ganancia bruta GARDEN
     * - caregiverPayouts: lo que reciben los cuidadores (90% del total)
     * - netGardenIncome: ganancia neta tras devoluciones y marketing
     */
    summary: {
      grossBilled,
      gardenCommissions,
      caregiverPayouts,
      netGardenIncome,
      thisMonthGardenIncome: thisMonthGardenInc,
      lastMonthGardenIncome: lastMonthGardenInc,
      yearGardenIncome: yearGardenInc,
      totalBookingsCompleted: allCompleted._count,
      thisMonthBookings: monthCompleted._count,
      // growth vs mes anterior (%)
      monthGrowth: lastMonthGardenInc > 0
        ? ((thisMonthGardenInc - lastMonthGardenInc) / lastMonthGardenInc) * 100
        : 0,
    },
    refunds: {
      count: refundStats._count,
      totalReturnedToClients: refundsToClients,
      commissionLost: refundCommLost,
    },
    marketing: {
      giftCodeSpend: totalGiftCodeMarketing,
      giftCodesIssued: giftCodes.length,
      giftCodeRedemptions: giftCodes.reduce((acc, gc) => acc + gc.usedBy.length, 0),
    },
    withdrawals: {
      pending:    { count: pendingWd?._count    ?? 0, amount: Number(pendingWd?._sum.amount    ?? 0) },
      processing: { count: processingWd?._count ?? 0, amount: Number(processingWd?._sum.amount ?? 0) },
      completed:  { count: completedWd?._count  ?? 0, amount: Number(completedWd?._sum.amount  ?? 0) },
      thisMonth:  Number(withdrawalMonthly._sum.amount ?? 0),
    },
    serviceBreakdown: {
      paseo: {
        count: paseoStats._count,
        billedToClient: Number(paseoStats._sum.totalAmount ?? 0),
        gardenEarnings: Number(paseoStats._sum.commissionAmount ?? 0),
        caregiverEarnings: Number(paseoStats._sum.totalAmount ?? 0) - Number(paseoStats._sum.commissionAmount ?? 0),
      },
      hospedaje: {
        count: hospedajeStats._count,
        billedToClient: Number(hospedajeStats._sum.totalAmount ?? 0),
        gardenEarnings: Number(hospedajeStats._sum.commissionAmount ?? 0),
        caregiverEarnings: Number(hospedajeStats._sum.totalAmount ?? 0) - Number(hospedajeStats._sum.commissionAmount ?? 0),
      },
    },
    monthlyChart: monthlyData,
    /**
     * Estado de Resultados (Income Statement)
     * Ingresos: comisiones cobradas (10% por servicio)
     * Egresos: devoluciones de comisiones + inversión marketing
     * Utilidad neta = comisiones − marketing (gift codes)
     * refundCommLost: informativo — comisiones potenciales perdidas por cancelaciones,
     * NO se restan del neto porque esas reservas nunca fueron COMPLETED.
     */
    incomeStatement: {
      revenues: {
        commissionsEarned: gardenCommissions,
        description: 'GARDEN cobra 10% sobre el precio del cuidador por cada servicio completado',
      },
      expenses: {
        refundedCommissions: refundCommLost,
        marketingGiftCodes: totalGiftCodeMarketing,
        total: totalGiftCodeMarketing,
      },
      netIncome: netGardenIncome,
      companyFeeRate: 0.10,
      note: 'Si cuidador cobra Bs 30 → cliente paga Bs 33 → GARDEN gana Bs 3',
    },
    /**
     * Balance General
     * Activos: comisiones acumuladas + fondos en tránsito
     * Pasivos: retiros pendientes de cuidadores
     */
    balanceSheet: {
      assets: {
        accumulatedCommissions: gardenCommissions,
        pendingCaregiverFunds: caregiverPayouts - Number(completedWd?._sum.amount ?? 0),
        total: grossBilled - Number(completedWd?._sum.amount ?? 0),
      },
      liabilities: {
        pendingWithdrawals: Number(pendingWd?._sum.amount ?? 0),
        processingWithdrawals: Number(processingWd?._sum.amount ?? 0),
        total: Number(pendingWd?._sum.amount ?? 0) + Number(processingWd?._sum.amount ?? 0),
      },
      equity: {
        retainedEarnings: netGardenIncome,
        note: 'Utilidad neta acumulada de GARDEN',
      },
    },
    /**
     * Estado de Flujo
     * Entradas: comisiones cobradas este mes
     * Salidas: retiros pagados este mes + marketing
     */
    cashFlow: {
      inflows: {
        commissionsThisMonth: thisMonthGardenInc,
      },
      outflows: {
        withdrawalsPaidThisMonth: Number(withdrawalMonthly._sum.amount ?? 0),
        marketingEstimate: monthGiftCodes,
        total: Number(withdrawalMonthly._sum.amount ?? 0) + monthGiftCodes,
      },
      netCashFlow: thisMonthGardenInc - Number(withdrawalMonthly._sum.amount ?? 0) - monthGiftCodes,
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// ZONES CONFIG — persistido en AppSettings como JSON array (clave: blockedZones)
// ─────────────────────────────────────────────────────────────────────────────

const ALL_ZONES = [
  'EQUIPETROL', 'URBARI', 'NORTE', 'LAS_PALMAS', 'CENTRO',
  'REMANZO', 'SUR', 'URUBO_NORTE', 'URUBO_SUR', 'OTROS',
] as const;

async function _getBlockedZones(): Promise<Set<string>> {
  try {
    const setting = await prisma.appSettings.findUnique({ where: { key: 'blockedZones' } });
    if (!setting || setting.value === 'null' || setting.value === '[]') return new Set();
    const parsed = JSON.parse(setting.value);
    return new Set(Array.isArray(parsed) ? parsed : []);
  } catch {
    return new Set();
  }
}

async function _saveBlockedZones(blocked: Set<string>): Promise<void> {
  const value = JSON.stringify([...blocked]);
  await prisma.appSettings.upsert({
    where: { key: 'blockedZones' },
    update: { value },
    create: { key: 'blockedZones', value },
  });
}

export async function getZonesConfig() {
  const blocked = await _getBlockedZones();
  return ALL_ZONES.map((z) => ({ zone: z, blocked: blocked.has(z) }));
}

export async function toggleZone(zone: string) {
  const blocked = await _getBlockedZones();
  if (blocked.has(zone)) {
    blocked.delete(zone);
  } else {
    blocked.add(zone);
  }
  await _saveBlockedZones(blocked);
  // Invalidar caché del listado de cuidadores para que el cambio sea inmediato
  await delByPrefix('caregivers:list:');
  return { zone, blocked: blocked.has(zone) };
}

export async function isZoneBlocked(zone: string): Promise<boolean> {
  const blocked = await _getBlockedZones();
  return blocked.has(zone);
}

export async function getBlockedZonesList(): Promise<string[]> {
  const blocked = await _getBlockedZones();
  return [...blocked];
}

// ═══════════════════════════════════════════════════════════════════════════
// REPORTES DE CHAT (App Store 1.2 UGC / Google Play — moderación)
// ═══════════════════════════════════════════════════════════════════════════

/** GET /api/admin/chat-reports — listado de reportes de chat, filtro opcional por status. */
export async function listChatReports(status?: string) {
  const reports = await prisma.chatReport.findMany({
    where: status ? { status } : {},
    include: {
      booking: { select: { id: true, serviceType: true, petName: true } },
      reporter: { select: { id: true, firstName: true, lastName: true, email: true } },
      reportedUser: { select: { id: true, firstName: true, lastName: true, email: true } },
    },
    orderBy: { createdAt: 'desc' },
    take: 300,
  });

  return reports.map((r) => {
    let messages: any[] = [];
    try { messages = JSON.parse(r.messagesSnapshot); } catch { /* no-op */ }
    return {
      id: r.id,
      bookingId: r.bookingId,
      reason: r.reason,
      details: r.details,
      status: r.status,
      adminNotes: r.adminNotes,
      reviewedByAdminId: r.reviewedByAdminId,
      reviewedAt: toIso(r.reviewedAt),
      createdAt: r.createdAt.toISOString(),
      messagesSnapshot: messages,
      reporter: {
        id: r.reporter.id,
        name: `${r.reporter.firstName} ${r.reporter.lastName}`.trim(),
        email: r.reporter.email,
      },
      reportedUser: {
        id: r.reportedUser.id,
        name: `${r.reportedUser.firstName} ${r.reportedUser.lastName}`.trim(),
        email: r.reportedUser.email,
      },
      booking: {
        id: r.booking.id,
        serviceType: r.booking.serviceType,
        petName: r.booking.petName,
      },
    };
  });
}

/**
 * POST /api/admin/chat-reports/:id/resolve — decisión del admin sobre un reporte de chat.
 * Si suspendUser=true y el usuario reportado tiene perfil de cuidador, se suspende ese perfil
 * (reutiliza la misma lógica que suspendCaregiver). Para clientes no hay mecanismo de
 * suspensión de cuenta hoy — se registra en adminNotes.
 */
export async function resolveChatReport(
  reportId: string,
  adminId: string,
  status: 'ACTION_TAKEN' | 'DISMISSED',
  adminNotes: string,
  suspendUser: boolean
) {
  const report = await prisma.chatReport.findUnique({
    where: { id: reportId },
    include: { reportedUser: { include: { caregiverProfile: true } } },
  });
  if (!report) throw new NotFoundError('Reporte de chat no encontrado');
  if (report.status !== 'PENDING' && report.status !== 'REVIEWED') {
    throw new BadRequestError('Este reporte ya fue resuelto');
  }

  let suspended = false;
  let suspendNote = '';

  if (suspendUser && status === 'ACTION_TAKEN') {
    if (report.reportedUser.caregiverProfile) {
      await suspendCaregiver(
        report.reportedUser.caregiverProfile.id,
        adminId,
        `Reportado en chat (motivo: ${report.reason}) — reporte ${reportId.slice(0, 8).toUpperCase()}`
      );
      suspended = true;
    } else {
      suspendNote = ' [No se pudo suspender: el usuario reportado no tiene perfil de cuidador — no existe mecanismo de suspensión para cuentas de cliente todavía.]';
    }
  }

  const updated = await prisma.chatReport.update({
    where: { id: reportId },
    data: {
      status,
      adminNotes: `${adminNotes}${suspendNote}`,
      reviewedByAdminId: adminId,
      reviewedAt: new Date(),
    },
  });

  await prisma.adminAction.create({
    data: {
      adminId,
      actionType: 'CHAT_REPORT_RESOLVED',
      targetId: reportId,
      notes: `${status} — ${adminNotes}${suspendNote}`,
    },
  });

  return { success: true, status: updated.status, suspended };
}

// ═══════════════════════════════════════════════════════════════════════════
// VERIFICACIÓN TELEFÓNICA MANUAL (fallback mientras WhatsApp/SMS no son
// 100% confiables — ver otp-delivery.service.ts). El admin ve el mensaje
// listo para copiar/enviar por su propio WhatsApp. Cada entrada permanece
// en la lista hasta que el usuario verifica su teléfono exitosamente.
// Esto es DISTINTO de la visibilidad permanente del código vigente que se
// expone en getCaregiverDetailForAdmin (campo phoneOtp), gateada por el
// switch otpVisibleToAdminEnabled — ese mecanismo no depende de que el envío
// automático haya fallado, siempre muestra el último código solicitado.
// ═══════════════════════════════════════════════════════════════════════════

/** GET /api/admin/phone-otp-requests — cuidadores que pidieron un código y
 * todavía NO verificaron su teléfono. Desaparece de la lista solo cuando
 * phoneVerified pasa a true. */
export async function listPendingPhoneOtpRequests() {
  const notifications = await prisma.adminNotification.findMany({
    where: { type: 'PHONE_OTP_MANUAL_HELP' },
    orderBy: { createdAt: 'desc' },
    take: 500,
  });

  // Última solicitud por usuario (puede haber pedido el código varias veces)
  const latestByUser = new Map<string, Date>();
  for (const n of notifications) {
    if (!latestByUser.has(n.caregiverId)) latestByUser.set(n.caregiverId, n.createdAt);
  }

  const userIds = [...latestByUser.keys()];
  if (userIds.length === 0) return [];

  const users = await prisma.user.findMany({
    where: { id: { in: userIds } },
    select: {
      id: true, firstName: true, lastName: true, phone: true,
      caregiverProfile: { select: { phoneVerified: true } },
    },
  });

  return users
    .filter((u) => (u as any).caregiverProfile?.phoneVerified !== true)
    .map((u) => ({
      userId: u.id,
      name: `${u.firstName} ${u.lastName}`.trim(),
      phone: u.phone,
      requestedAt: latestByUser.get(u.id)?.toISOString(),
    }))
    .sort((a, b) => (b.requestedAt ?? '').localeCompare(a.requestedAt ?? ''));
}

/**
 * POST /api/admin/phone-otp-requests/:userId/message — (re)genera un código
 * de 6 dígitos fresco (10 min de vigencia desde AHORA) y devuelve el mensaje
 * exacto listo para copiar/pegar, para que el admin lo envíe manualmente por
 * su propio WhatsApp sin depender de que el envío automático haya llegado.
 */
export async function generatePhoneOtpMessage(userId: string) {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { phone: true } });
  if (!user || !user.phone) {
    throw new BadRequestError('Este usuario no tiene teléfono registrado');
  }

  const otp = String(Math.floor(100000 + Math.random() * 900000));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000);
  await prisma.user.update({
    where: { id: userId },
    data: { phoneOtp: otp, phoneOtpExpiresAt: expiresAt },
  });

  const toPhone = user.phone.startsWith('+') ? user.phone : `+591${user.phone}`;
  const message = `GARDEN: tu código de verificación es ${otp}. Vence en 10 minutos. No lo compartas con nadie.`;

  return { phone: toPhone, message, expiresAt: expiresAt.toISOString() };
}

// ═══════════════════════════════════════════════════════════════════════════
// VERIFICACIÓN DE CORREO MANUAL (fallback — SOLO aparece cuando Resend
// realmente falla al enviar. Ver email.service.ts sendVerificationEmail — el
// catch de EMAIL_SEND_FAILED es lo único que crea estas notificaciones).
// Esto es DISTINTO de la visibilidad permanente del código vigente que se
// expone en getCaregiverDetailForAdmin (campos emailOtpCode/
// emailOtpExpiresAt, leídos de EmailVerification.plainCode), gateada por el
// switch otpVisibleToAdminEnabled — no depende de que el envío haya fallado.
// ═══════════════════════════════════════════════════════════════════════════

/** GET /api/admin/email-otp-requests — usuarios a los que Resend NO pudo
 * enviarles el código y que todavía no verifican su correo. Desaparece de
 * la lista solo cuando emailVerified pasa a true. */
export async function listPendingEmailOtpRequests() {
  const notifications = await prisma.adminNotification.findMany({
    where: { type: 'EMAIL_OTP_MANUAL_HELP' },
    orderBy: { createdAt: 'desc' },
    take: 500,
  });

  const latestByUser = new Map<string, Date>();
  for (const n of notifications) {
    if (!latestByUser.has(n.caregiverId)) latestByUser.set(n.caregiverId, n.createdAt);
  }

  const userIds = [...latestByUser.keys()];
  if (userIds.length === 0) return [];

  const users = await prisma.user.findMany({
    where: { id: { in: userIds } },
    select: { id: true, firstName: true, lastName: true, email: true, emailVerified: true },
  });

  return users
    .filter((u) => u.emailVerified !== true)
    .map((u) => ({
      userId: u.id,
      name: `${u.firstName} ${u.lastName}`.trim(),
      email: u.email,
      requestedAt: latestByUser.get(u.id)?.toISOString(),
    }))
    .sort((a, b) => (b.requestedAt ?? '').localeCompare(a.requestedAt ?? ''));
}

/**
 * POST /api/admin/email-otp-requests/:userId/message — genera un código
 * fresco (10 min de vigencia desde AHORA), lo guarda hasheado como una
 * EmailVerification normal (así el flujo de verificación del usuario sigue
 * funcionando igual), y devuelve el código EN TEXTO PLANO + el mensaje listo
 * para que el admin lo copie o lo mande por correo/WhatsApp manualmente.
 * NO reintenta enviar por Resend — si el admin está aquí es porque Resend
 * ya falló una vez para este usuario.
 */
export async function generateEmailOtpMessage(userId: string) {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { email: true } });
  if (!user || !user.email) {
    throw new BadRequestError('Este usuario no tiene correo registrado');
  }

  const { createHash, randomInt } = await import('crypto');
  const code = randomInt(100000, 999999).toString();
  const codeHash = createHash('sha256').update(code).digest('hex');
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

  // Invalida códigos previos sin verificar antes de crear el nuevo — mismo
  // criterio que generateAndSendVerificationCode en email.service.ts.
  await prisma.emailVerification.deleteMany({ where: { userId, verified: false } });
  await prisma.emailVerification.create({
    data: { userId, codeHash, expiresAt, attempts: 0 },
  });

  const message = `GARDEN: tu código de verificación es ${code}. Vence en 10 minutos. No lo compartas con nadie.`;

  return { email: user.email, message, code, expiresAt: expiresAt.toISOString() };
}

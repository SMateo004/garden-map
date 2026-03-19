import { BookingStatus, CaregiverStatus, VerificationStatus } from '@prisma/client';
import prisma from '../../config/database.js';
import * as bookingService from '../booking-service/booking.service.js';
import { BadRequestError, CaregiverNotFoundError, NotFoundError, UnauthorizedError } from '../../shared/errors.js';
import * as caregiverProfileService from '../caregiver-profile/caregiver-profile.service.js';
import { checkAndAutoSubmitProfile } from '../caregiver-profile/caregiver-profile-completion.helper.js';
import { getCache, delByPrefix } from '../../shared/cache.js';
import logger from '../../shared/logger.js';
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
    select: { id: true }
  });

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
    },
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
    idDocumentUrl: profile.idDocument,
    selfieUrl: profile.selfie,
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
    emailVerified: (profile as any).emailVerified,
    reviewChecklist: Array.isArray((profile as any).reviewChecklist) ? (profile as any).reviewChecklist : null,
    personalInfoComplete: (profile as any).personalInfoComplete ?? false,
    caregiverProfileComplete: (profile as any).caregiverProfileComplete ?? false,
    availabilityComplete: (profile as any).availabilityComplete ?? false,
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
  const profile = await prisma.caregiverProfile.findUnique({ where: { id: caregiverId } });
  if (!profile) throw new CaregiverNotFoundError(caregiverId);

  const newVerified = !profile.verified;
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

  return { verified: updated.verified, verifiedAt: updated.verifiedAt };
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

    logger.info('Admin: cuidador aprobado', {
      profileId,
      adminId,
      caregiverEmail: profile.user?.email,
      message: 'Perfil verificado y visible en GET /api/caregivers',
    });

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

/** GET /api/admin/payments-pending — reservas en PAYMENT_PENDING_APPROVAL. */
export async function getPaymentsPending(): Promise<PendingPaymentsResult> {
  const bookings = await prisma.booking.findMany({
    where: { status: BookingStatus.PAYMENT_PENDING_APPROVAL },
    include: {
      client: { select: { email: true } },
      caregiver: {
        select: {
          user: {
            select: { firstName: true, lastName: true },
          },
        },
      },
    },
    orderBy: { createdAt: 'desc' },
  });

  const items: PendingPaymentItem[] = bookings.map((b) => ({
    id: b.id,
    clientId: b.clientId,
    caregiverId: b.caregiverId,
    serviceType: b.serviceType,
    totalAmount: String(b.totalAmount),
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

  return { bookings: items, total: items.length };
}

/** POST /api/admin/bookings/:id/reject-payment — rechazar pago manual; vuelve a PENDING_PAYMENT. */
export async function rejectPayment(bookingId: string, adminId: string): Promise<{ id: string; status: string }> {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
  });
  if (!booking) throw new NotFoundError('Reserva no encontrada');
  if (booking.status !== BookingStatus.PAYMENT_PENDING_APPROVAL) {
    throw new BadRequestError(
      'Solo se puede rechazar una reserva en espera de aprobación de pago manual.'
    );
  }

  const updated = await prisma.booking.update({
    where: { id: bookingId },
    data: { status: BookingStatus.PENDING_PAYMENT },
  });

  logger.info('Admin: pago manual rechazado', { bookingId, adminId });
  return { id: updated.id, status: updated.status };
}

// ---------------------------------------------------------------------------
// Listado de reservas (admin) con filtro por estado
// ---------------------------------------------------------------------------

const VALID_BOOKING_STATUSES = [
  'PENDING_PAYMENT',
  'PAYMENT_PENDING_APPROVAL',
  'CONFIRMED',
  'IN_PROGRESS',
  'COMPLETED',
  'CANCELLED',
] as const;

/** GET /api/admin/reservations — todas las reservas, opcional ?status= */
export async function getReservations(status?: string): Promise<AdminReservationsResult> {
  const where: { status?: BookingStatus } = {};
  if (status && VALID_BOOKING_STATUSES.includes(status as (typeof VALID_BOOKING_STATUSES)[number])) {
    where.status = status as BookingStatus;
  }

  const bookings = await prisma.booking.findMany({
    where: Object.keys(where).length ? where : undefined,
    include: {
      client: { select: { email: true } },
      caregiver: {
        select: {
          user: { select: { firstName: true, lastName: true } },
        },
      },
    },
    orderBy: { createdAt: 'desc' },
  });

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
    caregiverName:
      b.caregiver?.user != null
        ? `${b.caregiver.user.firstName} ${b.caregiver.user.lastName}`.trim()
        : undefined,
  }));

  return { reservations, total: reservations.length };
}


/** GET lista de sesiones en REVIEW para revisión manual */
export async function listIdentityReviews() {
  const sessions = await prisma.identityVerificationSession.findMany({
    where: { status: 'REVIEW' },
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
    similarity: s.similarity,
    // @ts-ignore
    trustScore: s.trustScore,
    completedAt: s.completedAt,
  }));
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
      suspendedAt: null,
      suspensionReason: null,
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

  // Prisma cascade deletes the profile if we delete the user
  await prisma.user.delete({ where: { id: profile.userId } });

  await getCache().del(`caregivers:detail:${profileId}`);
  await delByPrefix('caregivers:list:');

  return { success: true };
}

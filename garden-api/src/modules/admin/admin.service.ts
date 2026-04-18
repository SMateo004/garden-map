import { BookingStatus, CaregiverStatus, VerificationStatus } from '@prisma/client';
import prisma from '../../config/database.js';
import * as bookingService from '../booking-service/booking.service.js';
import { BadRequestError, CaregiverNotFoundError, NotFoundError, UnauthorizedError } from '../../shared/errors.js';
import * as caregiverProfileService from '../caregiver-profile/caregiver-profile.service.js';
import { checkAndAutoSubmitProfile } from '../caregiver-profile/caregiver-profile-completion.helper.js';
import { getCache, delByPrefix } from '../../shared/cache.js';
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
    status: { in: [BookingStatus.PAYMENT_PENDING_APPROVAL, BookingStatus.PENDING_PAYMENT] },
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

/** POST /api/admin/bookings/:id/reject-payment — rechazar pago manual; vuelve a PENDING_PAYMENT. */
export async function rejectPayment(bookingId: string, adminId: string): Promise<{ id: string; status: string }> {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
  });
  if (!booking) throw new NotFoundError('Reserva no encontrada');
  if (booking.status !== BookingStatus.PAYMENT_PENDING_APPROVAL && booking.status !== BookingStatus.PENDING_PAYMENT) {
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
    paidAt: booking.paidAt?.toISOString() ?? null,
    paymentMethod: (booking as any).paymentMethod ?? null,
    payoutStatus: booking.payoutStatus,
    qrId: booking.qrId,
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
      totalPrice: Number(b.totalAmount ?? 0),
      walkDate: b.walkDate?.toISOString() ?? null,
      createdAt: b.createdAt.toISOString(),
      caregiverName: b.caregiver?.user ? `${(b.caregiver.user as any).firstName} ${(b.caregiver.user as any).lastName}` : null,
      petName: b.pet?.name ?? null,
    })),
    stats: {
      totalBookings: bookings.length,
      completedBookings: completed.length,
      totalSpent,
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
  // Gasto real de marketing este mes: transacciones de tipo REFUND por código de regalo
  const monthGiftCodeTxns = await prisma.walletTransaction.aggregate({
    where: {
      type: 'REFUND',
      description: { contains: 'Código de regalo' },
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
  const netGardenIncome    = gardenCommissions - refundCommLost - totalGiftCodeMarketing;

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
     * Utilidad neta = comisiones − pérdidas por devoluciones − marketing
     */
    incomeStatement: {
      revenues: {
        commissionsEarned: gardenCommissions,
        description: 'GARDEN cobra 10% sobre el precio del cuidador por cada servicio completado',
      },
      expenses: {
        refundedCommissions: refundCommLost,
        marketingGiftCodes: totalGiftCodeMarketing,
        total: refundCommLost + totalGiftCodeMarketing,
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

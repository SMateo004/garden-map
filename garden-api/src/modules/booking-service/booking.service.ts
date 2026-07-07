import {
  BookingStatus,
  CaregiverStatus,
  RefundStatus,
  ServiceType,
  type TimeSlot,
} from '@prisma/client';
import { Prisma } from '@prisma/client';
import type { Booking } from '@prisma/client';
import prisma from '../../config/database.js';
import {
  AppError,
  AvailabilityConflictError,
  BadRequestError,
  BookingNotFoundError,
  BookingValidationError,
  ForbiddenError,
} from '../../shared/errors.js';
import logger from '../../shared/logger.js';
import { track } from '../../shared/analytics.js';
import { auditLog } from '../../services/audit.service.js';
import * as notificationService from '../../services/notification.service.js';
import { blockchainService } from '../../services/blockchain.service.js';
import { sendPushToUser, sendPushToAdmins } from '../../services/firebase.service.js';
import { getIO } from '../../services/socket.service.js';
import * as sipService from '../../services/sip.service.js';
import * as paymentQrService from '../../services/payment-qr.service.js';
import { env } from '../../config/env.js';
import type {
  CreateBookingBody,
  InitPaymentBody,
  MgDataInput,
} from './booking.validation.js';
import type { BookingCreateResult } from './booking.types.js';
import { bookingToResponse } from './booking.types.js';
import { parseTimeBlocks, BOLIVIA_HOLIDAYS } from '../../shared/availability-utils.js';

/** Helper: HH:mm strings to minutes since midnight. */
function timeToMins(t: string | null | undefined): number {
  if (!t) return 0;
  const parts = t.split(':');
  const h = Number(parts[0] || 0);
  const m = Number(parts[1] || 0);
  return h * 60 + m;
}

/** Check if two time ranges [s1, e1] and [s2, e2] overlap. */
function rangesOverlap(s1: number, e1: number, s2: number, e2: number): boolean {
  return s1 < e2 && s2 < e1;
}

/** Tipos de notificación admin (booking flow). */
const ADMIN_NOTIFICATION_PAYMENT_APPROVAL = 'PAYMENT_APPROVAL_REQUEST';
const ADMIN_NOTIFICATION_CANCELLATION_REQUEST = 'CANCELLATION_REQUEST';

import { getNumericSetting } from '../../utils/settings-cache.js';

/** Lee los parámetros del negocio desde AppSettings (con cache 30s). */
async function getBookingSettings() {
    const [
        commissionPct,
        hospedajeAdminFee,
        hospedaje100h,
        hospedaje50h,
        paseo100h,
        paseo50h,
        qrValidityMinutes,
        hospedajeMaxExtensionDays,
    ] = await Promise.all([
        getNumericSetting('platformCommissionPct',         10),
        getNumericSetting('hospedajeRefundAdminFeeBS',     10),
        getNumericSetting('hospedajeRefund100Horas',       48),
        getNumericSetting('hospedajeRefund50Horas',        24),
        getNumericSetting('paseoRefund100Horas',           12),
        getNumericSetting('paseoRefund50Horas',             6),
        getNumericSetting('qrValidityMinutes',             15),
        getNumericSetting('hospedajeMaxExtensionDays',     30),
    ]);
    return {
        COMMISSION_RATE:                commissionPct / 100,
        HOSPEDAJE_REFUND_ADMIN_FEE_BS:  hospedajeAdminFee,
        HOSPEDAJE_REFUND_100_HOURS:     hospedaje100h,
        HOSPEDAJE_REFUND_50_HOURS:      hospedaje50h,
        PASEO_REFUND_100_HOURS:         paseo100h,
        PASEO_REFUND_50_HOURS:          paseo50h,
        QR_VALIDITY_MINUTES_PAYMENT:    qrValidityMinutes,
        HOSPEDAJE_MAX_EXTENSION_DAYS:   hospedajeMaxExtensionDays,
    };
}

/**
 * Crea una reserva (hospedaje o paseo) en transacción:
 * - Valida cuidador APPROVED y precios.
 * - Comprueba disponibilidad (Availability) y solapamiento con otras reservas.
 * - Calcula total, comisión, genera QR placeholder.
 * - Status inicial PENDING_PAYMENT.
 */
export async function createBooking(
  clientId: string,
  body: CreateBookingBody,
  mgData?: MgDataInput
): Promise<BookingCreateResult> {
  // Leer configuración dinámica fuera de la transacción
  const cfg = await getBookingSettings();
  return prisma.$transaction(async (tx) => {
    const clientProfile = await tx.clientProfile.findUnique({
      where: { userId: clientId },
      include: {
        pets: { select: { id: true } },
        user: { select: { phone: true, dateOfBirth: true } },
      },
    });

    if (!clientProfile) {
      throw new ForbiddenError(
        'Debes completar el perfil de tu mascota primero',
        'CLIENT_PROFILE_INCOMPLETE'
      );
    }

    if (!clientProfile.pets.length) {
      throw new ForbiddenError(
        'Debes completar el perfil de tu mascota primero',
        'CLIENT_PROFILE_INCOMPLETE'
      );
    }

    if (!clientProfile.isComplete) {
      throw new ForbiddenError(
        'Debes completar el perfil de tu mascota primero',
        'CLIENT_PROFILE_INCOMPLETE'
      );
    }

    // Datos personales (separado de la mascota arriba) — cuentas creadas vía
    // login social pre-registran solo nombre/email; teléfono real, fecha de
    // nacimiento y dirección se completan después en Mi Perfil.
    const hasRealPhone = !!clientProfile.user.phone && /^[67][0-9]{7}$/.test(clientProfile.user.phone);
    if (!hasRealPhone || !clientProfile.user.dateOfBirth || !clientProfile.addressStreet) {
      throw new ForbiddenError(
        'Completa tu teléfono, fecha de nacimiento y dirección en Mi Perfil antes de reservar.',
        'CLIENT_PERSONAL_DATA_INCOMPLETE'
      );
    }

    // Block new reservations if client has a completed service pending review (within 24h window)
    const pendingReview = await tx.booking.findFirst({
      where: {
        clientId,
        status: BookingStatus.COMPLETED,
        ownerRated: false,
        payoutStatus: 'PENDING',
        serviceEndedAt: { gte: new Date(Date.now() - 24 * 60 * 60 * 1000) },
      },
      select: { id: true },
    });
    if (pendingReview) {
      throw new ForbiddenError(
        'Debes calificar el servicio anterior antes de hacer una nueva reserva.',
        'PENDING_REVIEW'
      );
    }

    // Validate petIds — all must belong to the requesting client
    const petIdsInput: string[] = (body as any).petIds ?? [(body as any).petId].filter(Boolean);
    if (!petIdsInput || petIdsInput.length === 0) {
      throw new BadRequestError('Debes seleccionar al menos una mascota.', 'PET_NOT_OWNED', 'petIds');
    }
    if (petIdsInput.length > 3) {
      throw new BadRequestError('Máximo 3 mascotas por reserva.', 'MAX_PETS_EXCEEDED', 'petIds');
    }
    // Remove duplicates just in case
    const uniquePetIds = [...new Set(petIdsInput)];

    const petsData = await tx.pet.findMany({
      where: {
        id: { in: uniquePetIds },
        clientProfile: { userId: clientId },
      },
      select: { id: true, name: true, breed: true, age: true, size: true, specialNeeds: true, animalType: true, isAggressive: true },
    });

    if (petsData.length !== uniquePetIds.length) {
      throw new BadRequestError(
        'Una o más mascotas no fueron encontradas o no te pertenecen. Elige mascotas de tu perfil.',
        'PET_NOT_OWNED',
        'petIds'
      );
    }

    // Keep pets in the order the client sent (so petIndex matches the discount order)
    const orderedPets = uniquePetIds.map(id => petsData.find(p => p.id === id)!);
    const pet = orderedPets[0]!; // primary pet (backward compat) — at least 1 validated above
    // petCount is used in availability checks below — declare early
    const petCount = orderedPets.length;

    const caregiver = await tx.caregiverProfile.findFirst({
      where: {
        id: body.caregiverId,
        status: CaregiverStatus.APPROVED,
        suspended: false,
      },
      select: {
        id: true,
        userId: true,
        pricePerDay: true,
        pricePerWalk30: true,
        pricePerWalk60: true,
        pricePerGuarderia: true,
        servicesOffered: true,
        maxPets: true,
        sizesAccepted: true,
        animalTypes: true,
        acceptAggressive: true,
        acceptPuppies: true,
        acceptSeniors: true,
        requireMeetAndGreet: true,
      },
    });

    if (!caregiver) {
      throw new BadRequestError(
        'Cuidador no encontrado o no disponible para reservas',
        'CAREGIVER_NOT_FOUND',
        'caregiverId'
      );
    }

    // Validate pet count against caregiver's maxPets capacity
    const caregiverMaxPets = caregiver.maxPets ?? 1;
    if (uniquePetIds.length > caregiverMaxPets) {
      throw new BadRequestError(
        `Este cuidador acepta como máximo ${caregiverMaxPets} mascota${caregiverMaxPets > 1 ? 's' : ''} simultánea${caregiverMaxPets > 1 ? 's' : ''}. Has seleccionado ${uniquePetIds.length}.`,
        'MAX_PETS_EXCEEDED',
        'petIds'
      );
    }

    // Validar que el cuidador acepte el TAMAÑO de cada mascota seleccionada —
    // antes no se validaba ninguna, así que se podía reservar una mascota
    // GIANT con un cuidador que solo aceptaba SMALL/MEDIUM, y este se
    // enteraba recién al ver la reserva ya confirmada. Solo se aplica si el
    // cuidador configuró sizesAccepted (evita romper perfiles antiguos que
    // nunca llenaron ese campo).
    const sizesAccepted = Array.isArray(caregiver.sizesAccepted) ? caregiver.sizesAccepted : [];
    if (sizesAccepted.length > 0) {
      const incompatiblePet = orderedPets.find((p) => p.size && !sizesAccepted.includes(p.size));
      if (incompatiblePet) {
        throw new BadRequestError(
          `Este cuidador no acepta mascotas de tamaño ${incompatiblePet.size} (${incompatiblePet.name}). Elige otro cuidador o revisa el tamaño registrado de tu mascota.`,
          'PET_SIZE_NOT_ACCEPTED',
          'petIds'
        );
      }
    }

    // Validar ESPECIE (perro/gato) contra CaregiverProfile.animalTypes — solo
    // si el cuidador configuró tipos aceptados y la mascota tiene especie
    // registrada (evita romper mascotas antiguas que nunca la llenaron).
    const animalTypesAccepted = Array.isArray(caregiver.animalTypes) ? caregiver.animalTypes : [];
    if (animalTypesAccepted.length > 0) {
      const wrongSpeciesPet = orderedPets.find((p) => p.animalType && !animalTypesAccepted.includes(p.animalType));
      if (wrongSpeciesPet) {
        const speciesLabel = wrongSpeciesPet.animalType === 'DOGS' ? 'perros' : 'gatos';
        throw new BadRequestError(
          `Este cuidador no acepta ${speciesLabel} (${wrongSpeciesPet.name}). Elige otro cuidador para esta mascota.`,
          'PET_TYPE_NOT_ACCEPTED',
          'petIds'
        );
      }
    }

    // Validar políticas especiales: mascota agresiva, cachorro (< 1 año) o
    // mayor (>= 8 años) contra lo que el cuidador acepta. Antes ninguna de
    // estas políticas se verificaba al crear la reserva — el cuidador solo
    // se enteraba de la incompatibilidad al ver la reserva ya confirmada.
    if (caregiver.acceptAggressive === false) {
      const aggressivePet = orderedPets.find((p) => p.isAggressive);
      if (aggressivePet) {
        throw new BadRequestError(
          `Este cuidador no acepta mascotas agresivas (${aggressivePet.name}). Elige otro cuidador.`,
          'PET_AGGRESSIVE_NOT_ACCEPTED',
          'petIds'
        );
      }
    }
    if (caregiver.acceptPuppies === false) {
      const puppyPet = orderedPets.find((p) => p.age != null && p.age < 1);
      if (puppyPet) {
        throw new BadRequestError(
          `Este cuidador no acepta cachorros (${puppyPet.name}, menos de 1 año). Elige otro cuidador.`,
          'PET_PUPPY_NOT_ACCEPTED',
          'petIds'
        );
      }
    }
    if (caregiver.acceptSeniors === false) {
      const seniorPet = orderedPets.find((p) => p.age != null && p.age >= 8);
      if (seniorPet) {
        throw new BadRequestError(
          `Este cuidador no acepta mascotas mayores (${seniorPet.name}, 8+ años). Elige otro cuidador.`,
          'PET_SENIOR_NOT_ACCEPTED',
          'petIds'
        );
      }
    }

    // Meet & Greet obligatorio: si el cuidador lo exige, la reserva debe
    // incluir mgData (propuesta de M&G) — no se puede crear una reserva
    // "directa" saltándose ese paso.
    if (caregiver.requireMeetAndGreet && !mgData) {
      throw new BadRequestError(
        'Este cuidador requiere completar un Meet & Greet antes de confirmar el servicio. Actívalo para continuar con la reserva.',
        'MEET_AND_GREET_REQUIRED',
        'mgData'
      );
    }

    // Restricción: un cuidador no puede reservarse a sí mismo
    if (caregiver.userId === clientId) {
      throw new ForbiddenError(
        'No puedes reservar tus propios servicios.',
        'SELF_BOOKING_FORBIDDEN'
      );
    }

    // VALIDACIÓN: Mínimo 1 día de anticipación (no se puede reservar hoy ni fechas pasadas)
    const now = new Date();
    const BOLIVIA_OFFSET_MS = 4 * 60 * 60 * 1000;
    const todayStr = new Date(now.getTime() - BOLIVIA_OFFSET_MS).toISOString().split('T')[0] || '';
    const tomorrowDate = new Date(now.getTime() - BOLIVIA_OFFSET_MS + 24 * 60 * 60 * 1000);
    const tomorrowStr = tomorrowDate.toISOString().split('T')[0] || '';
    if (body.serviceType === ServiceType.HOSPEDAJE) {
      const requestedDate = body.startDate;
      if (requestedDate && requestedDate <= todayStr) {
        throw new BookingValidationError(
          'Las reservas deben realizarse con al menos un día de anticipación. Por favor, selecciona una fecha a partir de mañana.',
          'BOOKING_VALIDATION',
          'startDate'
        );
      }
    } else {
      const walkDays = (body as any).walkDays as Array<{ date: string; timeSlot: string; startTime?: string }> | undefined;
      const singleDate = (body as any).walkDate as string | undefined;
      const datesToCheck = walkDays ? walkDays.map((d) => d.date) : singleDate ? [singleDate] : [];
      for (const d of datesToCheck) {
        if (d <= todayStr) {
          throw new BookingValidationError(
            'Las reservas deben realizarse con al menos un día de anticipación. Por favor, selecciona fechas a partir de mañana.',
            'BOOKING_VALIDATION',
            'walkDate'
          );
        }
      }
    }

    const hasService = caregiver.servicesOffered.includes(body.serviceType as ServiceType);
    if (!hasService) {
      throw new BookingValidationError(
        `El cuidador no ofrece el servicio ${body.serviceType}`,
        'BOOKING_VALIDATION',
        'serviceType'
      );
    }

    if (body.serviceType === ServiceType.HOSPEDAJE) {
      await assertHospedajeAvailability(tx, body.caregiverId, body.startDate, body.endDate, petCount);
    } else if (body.serviceType === ServiceType.GUARDERIA) {
      await assertPaseoAvailability(
        tx,
        body.caregiverId,
        (body as any).walkDate,
        (body as any).timeSlot,
        (body as any).startTime,
        (body as any).duration,
        petCount
      );
    } else {
      const walkDays = (body as any).walkDays as Array<{ date: string; timeSlot: string; startTime?: string }> | undefined;
      if (walkDays && walkDays.length > 0) {
        // Multi-day: validate each day individually
        for (const day of walkDays) {
          await assertPaseoAvailability(
            tx,
            body.caregiverId,
            day.date,
            day.timeSlot as any,
            day.startTime,
            (body as any).duration,
            petCount
          );
        }
      } else {
        await assertPaseoAvailability(
          tx,
          body.caregiverId,
          (body as any).walkDate,
          (body as any).timeSlot,
          (body as any).startTime,
          (body as any).duration,
          petCount
        );
      }
    }

    let pricePerUnit: number;
    let totalDays: number | null = null;
    let totalAmount: number;

    // Multi-pet discount multipliers (applied to base price per additional pet of the SAME owner):
    // Pet 1: 100%, Pet 2: 75%, Pet 3: 50%
    const petDiscountFactors = [1.0, 0.75, 0.50];
    // Total multiplier = sum of discount factors for each pet slot used
    const petMultiplier = petDiscountFactors.slice(0, petCount).reduce((a, b) => a + b, 0);

    if (body.serviceType === ServiceType.HOSPEDAJE) {
      const perDay = caregiver.pricePerDay ?? 0;
      if (perDay <= 0) {
        throw new BookingValidationError(
          'El cuidador no tiene precio de hospedaje configurado',
          'BOOKING_VALIDATION',
          'caregiverId'
        );
      }
      pricePerUnit = perDay;
      // Always compute totalDays server-side from dates — NEVER trust the client value.
      // This prevents a client from paying for 1 night while reserving 10.
      const computedDays = Math.ceil(
        (new Date(body.endDate).getTime() - new Date(body.startDate).getTime()) /
          (24 * 60 * 60 * 1000)
      );
      if (computedDays < 1) {
        throw new BookingValidationError('Las fechas no son válidas', 'BOOKING_VALIDATION', 'endDate');
      }
      totalDays = computedDays;
      totalAmount = Math.round(totalDays * pricePerUnit * petMultiplier);
    } else if (body.serviceType === ServiceType.GUARDERIA) {
      const duration = (body as any).duration as number;
      const p60 = caregiver.pricePerWalk60 ?? 0;
      const priceGuarderia = (caregiver as any).pricePerGuarderia ?? p60;
      if (priceGuarderia <= 0) {
        throw new BookingValidationError('El cuidador no tiene precio de guardería configurado', 'BOOKING_VALIDATION', 'caregiverId');
      }
      // Precio por hora de guardería × horas solicitadas × descuento multi-mascota
      pricePerUnit = Math.round(priceGuarderia * (duration / 60));
      totalAmount = Math.round(pricePerUnit * petMultiplier);
    } else {
      const duration = (body as any).duration;
      const p60 = caregiver.pricePerWalk60 ?? 0;
      const walkDays = (body as any).walkDays as Array<{ date: string; timeSlot: string; startTime?: string }> | undefined;

      if (p60 <= 0) {
        throw new BookingValidationError('El cuidador no tiene precio de paseo configurado', 'BOOKING_VALIDATION', 'caregiverId');
      }

      // 30 min = mitad del precio de 60 min (sin campo separado en BD)
      pricePerUnit = duration === 30 ? Math.round(p60 / 2) : p60;
      // Multi-day: multiply by number of days; Multi-pet: apply discount multiplier
      const numDays = walkDays && walkDays.length > 0 ? walkDays.length : 1;
      totalAmount = Math.round(pricePerUnit * numDays * petMultiplier);
    }

    // ── Validar límites de precio configurados por admin ──────────────────────
    const [minKey, maxKey] = body.serviceType === ServiceType.HOSPEDAJE
      ? ['hospedajeMinPrice', 'hospedajeMaxPrice']
      : body.serviceType === ServiceType.GUARDERIA
        ? ['guarderiaMinPrice', 'guarderiaMaxPrice']
        : ['paseoMinPrice', 'paseoMaxPrice'];
    const priceMin = await getNumericSetting(minKey, 10);
    const priceMax = await getNumericSetting(maxKey, 9999);
    // pricePerUnit aquí es el precio SIN comisión — comparamos contra la tarifa base del cuidador
    if (pricePerUnit < priceMin) {
      throw new BookingValidationError(
        `El precio del cuidador (Bs ${pricePerUnit}) está por debajo del mínimo permitido (Bs ${priceMin}).`,
        'BOOKING_VALIDATION', 'pricePerUnit'
      );
    }
    if (pricePerUnit > priceMax) {
      throw new BookingValidationError(
        `El precio del cuidador (Bs ${pricePerUnit}) supera el máximo permitido (Bs ${priceMax}).`,
        'BOOKING_VALIDATION', 'pricePerUnit'
      );
    }

    const subtotal = totalAmount;
    totalAmount = Math.round(subtotal * (1 + cfg.COMMISSION_RATE));
    const commissionAmount = totalAmount - subtotal;
    // Client sees the unit price with markup
    pricePerUnit = Math.round(pricePerUnit * (1 + cfg.COMMISSION_RATE));

    const allPetNames = orderedPets.map(p => p.name).join(', ');

    const bookingData: Prisma.BookingCreateInput = {
      client: { connect: { id: clientId } },
      caregiver: { connect: { id: body.caregiverId } },
      pet: pet.id ? { connect: { id: pet.id } } : undefined,
      serviceType: body.serviceType as ServiceType,
      status: mgData ? BookingStatus.PENDING_MG : BookingStatus.PENDING_PAYMENT,
      totalAmount: new Prisma.Decimal(totalAmount),
      pricePerUnit: new Prisma.Decimal(pricePerUnit),
      commissionAmount: new Prisma.Decimal(commissionAmount),
      petCount,
      petName: allPetNames, // comma-separated for display in notifications/lists
      petBreed: pet.breed ?? null,
      petAge: pet.age ?? null,
      petSize: pet.size ?? undefined,
      specialNeeds: pet.specialNeeds ?? null,
      ...(body.serviceType === ServiceType.HOSPEDAJE
        ? {
          startDate: new Date(body.startDate),
          endDate: new Date(body.endDate),
          totalDays,
        }
        : body.serviceType === ServiceType.GUARDERIA
        ? {
          walkDate: new Date((body as any).walkDate),
          timeSlot: (body as any).timeSlot,
          startTime: (body as any).startTime,
          duration: (body as any).duration,
        }
        : (() => {
          const walkDays = (body as any).walkDays as Array<{ date: string; timeSlot: string; startTime?: string }> | undefined;
          const isMultiDay = walkDays && walkDays.length > 0;
          // walkDate = first day (for backward compat / display)
          const firstDate = isMultiDay ? walkDays![0]!.date : (body as any).walkDate;
          const firstSlot = isMultiDay ? walkDays![0]!.timeSlot : (body as any).timeSlot;
          const firstStart = isMultiDay ? walkDays![0]!.startTime : (body as any).startTime;
          return {
            walkDate: new Date(firstDate),
            timeSlot: firstSlot,
            startTime: firstStart,
            duration: (body as any).duration,
            ...(isMultiDay ? { walkDays: walkDays as any } : {}),
          };
        })()),
    };

    const booking = await tx.booking.create({
      data: bookingData,
    });

    // Create one BookingPet row per pet
    await tx.bookingPet.createMany({
      data: orderedPets.map((p, idx) => ({
        bookingId: booking.id,
        petId: p.id,
        petIndex: idx + 1,
        petName: p.name,
        petBreed: p.breed ?? null,
        petAge: p.age ?? null,
        petSize: p.size ?? null,
        specialNeeds: p.specialNeeds ?? null,
      })),
    });

    // If M&G data provided: create MeetAndGreet record and notify caregiver immediately
    if (mgData) {
      await tx.meetAndGreet.create({
        data: {
          bookingId: booking.id,
          proposedBy: clientId,
          modalidad: mgData.modalidad ?? 'IN_PERSON',
          proposedDate: new Date(mgData.proposedDate),
          meetingPoint: mgData.meetingPoint ?? null,
          status: 'PROPOSED',
        },
      });
      // Notify caregiver about the M&G request
      setImmediate(() => {
        prisma.notification.create({
          data: {
            userId: caregiver.userId,
            type: 'INFO',
            title: '📅 Solicitud de Meet & Greet',
            message: `Un cliente quiere conocerte antes de reservar. Revisa la fecha propuesta.`,
          },
        }).catch(() => {});
        sendPushToUser(caregiver.userId, '📅 Meet & Greet solicitado', `Un cliente quiere conocerte antes de la reserva.`).catch(() => {});
      });
    }

    // No notificamos al cuidador aquí para reservas normales — solo cuando el pago sea confirmado
    // (onBookingWaitingApproval se dispara al pasar a WAITING_CAREGIVER_APPROVAL).

    logger.info('Cliente seleccionó mascotas para reserva', {
      userId: clientId,
      petIds: body.petIds,
      bookingId: booking.id,
    });
    logger.info('Booking created', {
      bookingId: booking.id,
      clientId,
      caregiverId: body.caregiverId,
      serviceType: body.serviceType,
      totalAmount: String(booking.totalAmount),
    });
    // Analytics: booking created
    track(clientId, 'booking_created', {
      bookingId: booking.id,
      serviceType: body.serviceType,
      totalAmount: Number(booking.totalAmount),
      caregiverId: body.caregiverId,
    });

    auditLog({
      userId: clientId,
      action: 'BOOKING_CREATED',
      entity: 'Booking',
      entityId: booking.id,
      details: { serviceType: body.serviceType, totalAmount: Number(booking.totalAmount), caregiverId: body.caregiverId },
    });

    return bookingToResponse(booking);
  });
}

/**
 * Returns true if the given date is allowed by the caregiver's day-type flags
 * (weekdays / weekends / holidays). An explicit Availability row with isAvailable=true
 * always overrides these defaults, so pass hasExplicitOverride=true to skip the check.
 */
function isDayTypeAllowed(
  date: Date,
  schedule: Record<string, unknown>,
  hasExplicitOverride: boolean
): boolean {
  if (hasExplicitOverride) return true;
  const dateStr = date.toISOString().slice(0, 10);
  const dow = date.getUTCDay(); // 0=Sun … 6=Sat
  const isWeekend = dow === 0 || dow === 6;
  const isHoliday = BOLIVIA_HOLIDAYS.has(dateStr);

  if (isHoliday) return schedule['holidays'] !== false;
  if (isWeekend) return schedule['weekends'] !== false;
  return schedule['weekdays'] !== false;
}

/** Hospedaje: bloquea solo si hay fila explícita isAvailable=false o si se supera maxPets simultáneas (por total de mascotas). */
async function assertHospedajeAvailability(
  tx: Prisma.TransactionClient,
  caregiverId: string,
  startDate: string,
  endDate: string,
  newPetCount = 1
): Promise<void> {
  const start = new Date(startDate);
  const end = new Date(endDate);

  // 30-day advance booking limit
  const maxBookingDate = new Date();
  maxBookingDate.setUTCHours(0, 0, 0, 0);
  maxBookingDate.setUTCDate(maxBookingDate.getUTCDate() + 30);
  if (start > maxBookingDate) {
    throw new AvailabilityConflictError(
      'Solo puedes hacer reservas con un máximo de 30 días de anticipación.',
      'startDate'
    );
  }
  const dates: Date[] = [];
  for (let d = new Date(start); d < end; d.setDate(d.getDate() + 1)) {
    dates.push(new Date(d));
  }

  // Para hospedaje solo se bloquean días con fila explícita isAvailable=false.
  // No se requieren franjas horarias configuradas ni flags de horario default.
  // El cuidador siempre puede confirmar o rechazar la reserva.
  const blockedRows = await tx.availability.findMany({
    where: { caregiverId, date: { in: dates }, isAvailable: false },
  });
  if (blockedRows.length > 0) {
    const blockedDates = blockedRows.map((r) => r.date.toISOString().slice(0, 10));
    logger.warn('Hospedaje availability conflict — blocked dates', { caregiverId, startDate, endDate, blockedDates });
    throw new AvailabilityConflictError(
      `El cuidador no está disponible en: ${blockedDates.join(', ')}. Elige otras fechas.`,
      'startDate'
    );
  }

  // Reservas que bloquean: CONFIRMED, IN_PROGRESS, PAYMENT_PENDING_APPROVAL,
  // WAITING_CAREGIVER_APPROVAL, PENDING_MG, o PENDING_PAYMENT reciente (<15 min).
  const expirationDate = new Date(Date.now() - 15 * 60 * 1000);

  // Fetch maxPets to determine how many simultaneous bookings are allowed
  const profileForMaxPets = await tx.caregiverProfile.findUnique({
    where: { id: caregiverId },
    select: { maxPets: true },
  });
  const maxPets = profileForMaxPets?.maxPets ?? 1;

  // For maxPets > 1, we need to check per-day capacity, not just total count.
  // Find all overlapping bookings and count how many cover each date.
  const overlappingBookings = await tx.booking.findMany({
    where: {
      caregiverId,
      serviceType: 'HOSPEDAJE',
      OR: [
        {
          status: { in: [BookingStatus.PAYMENT_PENDING_APPROVAL, BookingStatus.WAITING_CAREGIVER_APPROVAL, BookingStatus.CONFIRMED, BookingStatus.IN_PROGRESS, BookingStatus.PENDING_MG] },
        },
        {
          status: BookingStatus.PENDING_PAYMENT,
          createdAt: { gte: expirationDate },
        }
      ],
      startDate: { lte: end },
      endDate: { gt: start },
    },
    select: { startDate: true, endDate: true, petCount: true },
  });

  // Count total pets (not bookings) per day — block when pets + newPetCount > maxPets
  const datePetCounts = new Map<string, number>();
  for (const b of overlappingBookings) {
    let d = new Date(b.startDate!);
    const bPetCount = b.petCount ?? 1;
    while (d < b.endDate!) {
      const ds = d.toISOString().slice(0, 10);
      datePetCounts.set(ds, (datePetCounts.get(ds) ?? 0) + bPetCount);
      d.setDate(d.getDate() + 1);
    }
  }
  let cur = new Date(start);
  while (cur < end) {
    const ds = cur.toISOString().slice(0, 10);
    const occupiedPets = datePetCounts.get(ds) ?? 0;
    if (occupiedPets + newPetCount > maxPets) {
      throw new AvailabilityConflictError(
        `El cuidador ya tiene ${occupiedPets} mascota${occupiedPets !== 1 ? 's' : ''} hospedada${occupiedPets !== 1 ? 's' : ''} el ${ds} (máx. ${maxPets}). Elige otras fechas.`,
        'startDate'
      );
    }
    cur.setDate(cur.getDate() + 1);
  }
}

/** Paseo: la fecha debe estar disponible (fila con timeBlocks[slot]=true o defaultSchedule.paseoTimeBlocks[slot]). */
async function assertPaseoAvailability(
  tx: Prisma.TransactionClient,
  caregiverId: string,
  walkDate: string,
  timeSlot: TimeSlot,
  startTime?: string | null,
  duration?: number | null,
  newPetCount = 1
): Promise<void> {
  const date = new Date(walkDate);

  // 30-day advance booking limit
  const maxBookingDate = new Date();
  maxBookingDate.setUTCHours(0, 0, 0, 0);
  maxBookingDate.setUTCDate(maxBookingDate.getUTCDate() + 30);
  if (date > maxBookingDate) {
    throw new AvailabilityConflictError(
      'Solo puedes hacer reservas con un máximo de 30 días de anticipación.',
      'walkDate'
    );
  }

  const profile = await tx.caregiverProfile.findUnique({
    where: { id: caregiverId },
    select: { defaultAvailabilitySchedule: true, maxPets: true },
  });
  const defaultSchedule = (profile?.defaultAvailabilitySchedule as Record<string, unknown>) ?? {};
  const defaultBlocks = defaultSchedule['paseoTimeBlocks'] as Record<string, boolean> | undefined;
  const maxPets = profile?.maxPets ?? 1;

  const avail = await tx.availability.findUnique({
    where: {
      caregiverId_date: { caregiverId, date },
    },
  });

  // Check weekdays/weekends/holidays flags unless there's an explicit override row with isAvailable=true
  const hasExplicitAvailable = avail?.isAvailable === true;
  if (!isDayTypeAllowed(date, defaultSchedule, hasExplicitAvailable)) {
    throw new AvailabilityConflictError(
      `El cuidador no trabaja los ${date.getUTCDay() === 0 || date.getUTCDay() === 6 ? 'fines de semana' : 'días laborables'} el ${walkDate}. Elige otra fecha.`,
      'walkDate'
    );
  }

  let slotAvailable = false;
  if (avail) {
    if (!avail.isAvailable) {
      throw new AvailabilityConflictError(
        `El cuidador no está disponible el ${walkDate}. Elige otra fecha.`,
        'walkDate'
      );
    }
    const slots = parseTimeBlocks(avail.timeBlocks);
    slotAvailable = slots.some(s => s.slot === timeSlot && s.enabled);
  } else if (defaultBlocks) {
    const slots = parseTimeBlocks(defaultBlocks);
    slotAvailable = slots.some(s => s.slot === timeSlot && s.enabled);
  }
  if (!slotAvailable) {
    throw new AvailabilityConflictError(
      `Horario no disponible: el cuidador no tiene el bloque ${timeSlot} el ${walkDate}. Elige otra fecha u horario.`,
      'timeSlot'
    );
  }

  const expirationDate = new Date(Date.now() - 15 * 60 * 1000);

  // Fetch ALL active bookings for this date and caregiver
  const existingBookings = await tx.booking.findMany({
    where: {
      caregiverId,
      walkDate: date,
      OR: [
        {
          status: { in: [BookingStatus.PAYMENT_PENDING_APPROVAL, BookingStatus.WAITING_CAREGIVER_APPROVAL, BookingStatus.CONFIRMED, BookingStatus.IN_PROGRESS, BookingStatus.PENDING_MG] },
        },
        {
          status: BookingStatus.PENDING_PAYMENT,
          createdAt: { gte: expirationDate }
        }
      ]
    },
    select: { startTime: true, duration: true, timeSlot: true, petCount: true },
  });

  // Un bloque 'legacy' es aquel que no tiene hora de inicio (bloquea todo el slot)
  const legacyBookings = existingBookings.filter(b => (!b.startTime || b.startTime === '') && b.timeSlot === timeSlot);
  const timedBookings = existingBookings.filter(b => !!b.startTime && b.startTime !== '');

  // Helper: total pets in a list of bookings
  const sumPets = (bArr: typeof existingBookings) => bArr.reduce((s, b) => s + (b.petCount ?? 1), 0);

  const isSpecific = !!startTime && startTime !== '';
  logger.info('Check-Paseo-Avail', { walkDate, timeSlot, startTime, isSpecific, foundCount: existingBookings.length, newPetCount });

  // 1. Si las reservas legacy en este bloque ya llenaron la capacidad (por mascotas), bloquear.
  const legacyPets = sumPets(legacyBookings);
  if (legacyPets + newPetCount > maxPets) {
    throw new AvailabilityConflictError(
      `El bloque ${timeSlot} ya tiene ${legacyPets} mascota${legacyPets !== 1 ? 's' : ''} que ocupa${legacyPets !== 1 ? 'n' : ''} todo el horario (máx. ${maxPets}).`,
      'timeSlot'
    );
  }

  // 2. Si la NUEVA reserva no tiene hora y ya se llenó la capacidad del bloque, bloqueamos
  const slotPets = sumPets(existingBookings.filter(b => b.timeSlot === timeSlot));
  if (!isSpecific && slotPets + newPetCount > maxPets) {
    throw new AvailabilityConflictError(
      `El bloque ${timeSlot} ya tiene ${slotPets} mascota${slotPets !== 1 ? 's' : ''} (máx. ${maxPets}). Por favor, selecciona una hora específica para buscar disponibilidad.`,
      'timeSlot'
    );
  }

  // 3. Validación por rangos con buffer de descanso (30 min) si tenemos hora de inicio
  if (isSpecific) {
    const requestedStart = timeToMins(startTime as string);
    const requestedDuration = duration || 60;
    const requestedEnd = requestedStart + requestedDuration;
    const requestedEndWithBuffer = requestedEnd + 30;

    // Verificar límites del bloque del cuidador.
    // Misma lógica que getCaregiverAvailability: si avail.timeBlocks tiene slots en null
    // (formato "sin override real"), lo ignoramos y usamos defaultSchedule.paseoTimeBlocks
    // que contiene los rangos personalizados del cuidador.
    let rawRangeBlocks: any = avail?.timeBlocks ?? null;
    if (
      rawRangeBlocks?.slots &&
      typeof rawRangeBlocks.slots === 'object' &&
      Object.values(rawRangeBlocks.slots as object).every((v) => v === null || v === undefined)
    ) {
      rawRangeBlocks = null; // slots todos null → sin override real → usar defaultSchedule
    }
    let rangeSlots = rawRangeBlocks ? parseTimeBlocks(rawRangeBlocks) : [];
    if (rangeSlots.length === 0 && defaultBlocks) {
      rangeSlots = parseTimeBlocks(defaultBlocks);
    }
    const currentBlock = rangeSlots.find(s => s.slot === timeSlot);
    if (currentBlock?.start && currentBlock?.end) {
      const blockStart = timeToMins(currentBlock.start);
      const blockEnd = timeToMins(currentBlock.end);
      if (requestedStart < blockStart || requestedEnd > blockEnd) {
        throw new AvailabilityConflictError(
          `El horario seleccionado (${startTime}) está fuera del rango atendido por el cuidador (${currentBlock.start} - ${currentBlock.end})`,
          'startTime'
        );
      }
    }

    // Sumar mascotas de reservas que se solapan en tiempo con la nueva.
    // Solo bloquear cuando totalPets + newPetCount > maxPets.
    let overlapPets = 0;
    let overlapExample: { startTime: string; endFormatted: string } | null = null;
    for (const b of timedBookings) {
      const bStart = timeToMins(b.startTime as string);
      const bDuration = b.duration || 60;
      const bEndWithBuffer = bStart + bDuration + 30;

      if (rangesOverlap(requestedStart, requestedEndWithBuffer, bStart, bEndWithBuffer)) {
        overlapPets += b.petCount ?? 1;
        if (!overlapExample) {
          overlapExample = {
            startTime: b.startTime as string,
            endFormatted: `${Math.floor((bStart + bDuration) / 60)}:${String((bStart + bDuration) % 60).padStart(2, '0')}`,
          };
        }
      }
    }
    if (overlapPets + newPetCount > maxPets) {
      logger.warn('Overlap capacity exceeded in PASEO booking', { requestedStart, overlapPets, newPetCount, maxPets });
      throw new AvailabilityConflictError(
        `Conflicto: El horario solicitado (${startTime}) se solapa con ${overlapPets} mascota${overlapPets !== 1 ? 's' : ''} existente${overlapPets !== 1 ? 's' : ''} (máx. ${maxPets} simultánea${maxPets > 1 ? 's' : ''}).`,
        'startTime'
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Walk extension availability check
// ---------------------------------------------------------------------------

/**
 * Devuelve cuántos minutos puede extenderse un paseo IN_PROGRESS según:
 *  - Próximas reservas del cuidador ese mismo día (buffer de 30 min)
 *  - Slots bloqueados (MANANA/TARDE/NOCHE) del cuidador en el calendario
 *  - Horas personalizadas bloqueadas (inicio/fin de cada bloque)
 *
 * Reglas de disponibilidad progresiva:
 *  - próxima reserva en < 60 min → 0 min (no puede extender)
 *  - próxima reserva en 60-89 min → 15 min
 *  - próxima reserva en 90-149 min → 30 min
 *  - próxima reserva en ≥ 150 min, o sin reservas → 60 min
 *  Además se limita por el final del bloque horario del cuidador.
 */
export async function checkExtensionAvailability(
  bookingId: string,
  clientId: string
): Promise<{ allowedMinutes: number; reason: string }> {
  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, clientId },
    select: {
      id: true, serviceType: true, status: true,
      caregiverId: true, walkDate: true, startTime: true,
      duration: true, timeSlot: true,
    },
  });

  if (!booking) return { allowedMinutes: 0, reason: 'Reserva no encontrada' };
  if (booking.serviceType !== ServiceType.PASEO) return { allowedMinutes: 0, reason: 'Solo paseos pueden extenderse (no guardería ni hospedaje)' };
  if (booking.status !== BookingStatus.IN_PROGRESS) return { allowedMinutes: 0, reason: 'El paseo no está en curso' };

  const now = new Date();
  const startTimeParts = (booking.startTime ?? '00:00').split(':');
  const startMins = parseInt(startTimeParts[0] ?? '0') * 60 + parseInt(startTimeParts[1] ?? '0');
  const currentDuration = booking.duration ?? 60;
  const serviceEndMins = startMins + currentDuration; // minuto del día en que termina el servicio actual

  // 1. Próximas reservas del cuidador ese día (excluyendo la actual)
  const dayStart = new Date(booking.walkDate!);
  dayStart.setHours(0, 0, 0, 0);
  const dayEnd = new Date(dayStart);
  dayEnd.setHours(23, 59, 59, 999);

  const nextBookings = await prisma.booking.findMany({
    where: {
      caregiverId: booking.caregiverId,
      id: { not: bookingId },
      status: { in: [BookingStatus.CONFIRMED, BookingStatus.IN_PROGRESS, BookingStatus.WAITING_CAREGIVER_APPROVAL, BookingStatus.PAYMENT_PENDING_APPROVAL] },
      walkDate: booking.walkDate,
      startTime: { not: null },
    },
    select: { startTime: true, duration: true },
    orderBy: { startTime: 'asc' },
  });

  // Minutos hasta la próxima reserva (desde el fin actual, incluyendo buffer 30 min)
  let minutesToNextBooking = Infinity;
  for (const nb of nextBookings) {
    if (!nb.startTime) continue;
    const parts = nb.startTime.split(':');
    const nbStart = parseInt(parts[0] ?? '0') * 60 + parseInt(parts[1] ?? '0');
    const gap = nbStart - serviceEndMins - 30; // descontar buffer de descanso
    if (gap < minutesToNextBooking) minutesToNextBooking = gap;
  }

  // 2. Límite del bloque horario del cuidador
  const profile = await prisma.caregiverProfile.findUnique({
    where: { id: booking.caregiverId },
    select: { defaultAvailabilitySchedule: true },
  });
  const avail = await prisma.availability.findUnique({
    where: { caregiverId_date: { caregiverId: booking.caregiverId, date: booking.walkDate! } },
  });
  let blockEndMins = Infinity;
  const schedule = (avail?.timeBlocks ?? (profile?.defaultAvailabilitySchedule as any)?.paseoTimeBlocks) as Record<string, any> | null;
  if (schedule && booking.timeSlot) {
    const slots = parseTimeBlocks(schedule);
    const currentSlot = slots.find(s => s.slot === booking.timeSlot);
    if (currentSlot?.end) {
      const ep = currentSlot.end.split(':');
      blockEndMins = parseInt(ep[0] ?? '0') * 60 + parseInt(ep[1] ?? '0');
    }
  }
  const minsUntilBlockEnd = blockEndMins - serviceEndMins;

  // 3. Máximo posible considerando ambas restricciones
  const maxByCalendar = Math.min(
    minutesToNextBooking === Infinity ? 60 : minutesToNextBooking,
    minsUntilBlockEnd === Infinity ? 60 : minsUntilBlockEnd
  );

  let allowedMinutes: number;
  let reason: string;

  if (maxByCalendar < 15) {
    allowedMinutes = 0;
    reason = 'El cuidador tiene otra reserva muy pronto';
  } else if (minutesToNextBooking < 60) {
    allowedMinutes = 0;
    reason = 'No hay tiempo suficiente antes de la próxima reserva';
  } else if (minutesToNextBooking < 90) {
    allowedMinutes = Math.min(15, Math.floor(maxByCalendar / 15) * 15);
    reason = '15 min disponibles';
  } else if (minutesToNextBooking < 150) {
    allowedMinutes = Math.min(30, Math.floor(maxByCalendar / 15) * 15);
    reason = '30 min disponibles';
  } else {
    allowedMinutes = Math.min(60, Math.floor(maxByCalendar / 15) * 15);
    reason = '60 min disponibles';
  }

  return { allowedMinutes, reason };
}

// ---------------------------------------------------------------------------
// Pago: generación de QR (SIP bancario o placeholder local) e iniciar pago
// ---------------------------------------------------------------------------

export interface GenerateQRResult {
  qrId: string;
  qrImageUrl: string;  // Base64 "data:image/png;base64,..." con SIP, URL de Cloudinary (o placeholder) sin SIP
  qrImageType: 'base64' | 'url' | 'generated';
  qrExpiresAt: Date;
  sipQrId?: string;          // idQr de SIP (solo cuando SIP_ENABLED=true)
  sipTransaccionId?: string; // idTransaccion de SIP (solo cuando SIP_ENABLED=true)
}

/**
 * Genera QR de pago.
 * - Con SIP_ENABLED=true: llama a la API bancaria SIP y devuelve imagen Base64 real.
 * - Con SIP_ENABLED=false: usa el QR provisional subido por un admin para ese
 *   tipo de servicio (imagen real de una cuenta bancaria, pero SIN conexión al
 *   riel SIP) — o cae a un placeholder si el admin aún no subió ninguno.
 *
 * El alias enviado a SIP es el bookingId, que SIP nos devolverá en el callback
 * para que podamos identificar qué reserva se pagó.
 */
export async function generateQR(
  bookingId: string,
  validityMinutes: number = 24 * 60,
  monto?: number,
  serviceType?: ServiceType
): Promise<GenerateQRResult> {
  const qrExpiresAt = new Date(Date.now() + validityMinutes * 60 * 1000);

  if (env.SIP_ENABLED) {
    try {
      const callbackUrl = `${env.API_PUBLIC_URL}/api/payments/confirmarPago`;
      const result = await sipService.generateQr(
        bookingId,
        monto ?? 0,
        qrExpiresAt,
        callbackUrl,
        'Pago GARDEN'
      );
      logger.info('[SIP] QR generado via API bancaria', { bookingId, idQr: result.idQr });
      return {
        qrId: bookingId,                             // alias = bookingId
        qrImageUrl: `data:image/png;base64,${result.imagenQr}`,
        qrImageType: 'base64',
        qrExpiresAt,
        sipQrId: result.idQr,
        sipTransaccionId: result.idTransaccion,
      };
    } catch (err) {
      // SIP está activo pero falló (red, credenciales, banco caído, etc.).
      // Antes esto caía en silencio a un QR placeholder falso — el cliente
      // veía un código que no conecta a ningún riel bancario real, sin que
      // nadie se enterara de que el banco falló. Ahora bloqueamos el pago
      // con un error claro y alertamos a los admins, igual que hace el
      // propio banco cuando su callback de confirmación falla.
      logger.error('[SIP] Error generando QR — bloqueando pago (no se usa placeholder en producción)', { bookingId, err });
      sipService.notifyAdminsSipFailure('generarQr', bookingId, err).catch(() => {});
      throw new AppError(
        'No pudimos generar tu código de pago en este momento. Intenta nuevamente en unos minutos.',
        503,
        'SIP_UNAVAILABLE'
      );
    }
  }

  // Modo local / fallback — SOLO cuando SIP_ENABLED=false (dev/CI)
  const qrId = crypto.randomUUID();
  const uploadedQrUrl = serviceType ? await paymentQrService.getPaymentQrImageUrl(serviceType) : null;
  if (uploadedQrUrl) {
    logger.info('QR generado (provisional subido por admin)', { bookingId, qrId, serviceType });
    return { qrId, qrImageUrl: uploadedQrUrl, qrImageType: 'url', qrExpiresAt };
  }
  const qrImageUrl = `https://api.garden.bo/qr/placeholder/${qrId}`;
  logger.info('QR generado (placeholder local, sin QR provisional subido)', { bookingId, qrId, validityMinutes, serviceType });
  return { qrId, qrImageUrl, qrImageType: 'generated', qrExpiresAt };
}

/**
 * Inicia el flujo de pago: genera QR (placeholder) o marca reserva para aprobación manual por admin.
 * Solo cliente titular; reserva debe estar PENDING_PAYMENT.
 */
/**
 * Transitions a PENDING_MG booking to PENDING_PAYMENT.
 * Validates: booking belongs to client, status is PENDING_MG, M&G date has already passed.
 */
export async function proceedToPayment(
  bookingId: string,
  clientId: string
): Promise<BookingCreateResult> {
  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, clientId },
    include: { meetAndGreet: true },
  });
  if (!booking) throw new BookingNotFoundError(bookingId);
  if (booking.status !== BookingStatus.PENDING_MG) {
    throw new BookingValidationError('La reserva no está en estado de espera de Meet & Greet');
  }
  const mg = (booking as any).meetAndGreet;
  if (!mg || !mg.proposedDate) {
    throw new BookingValidationError('No hay Meet & Greet asociado a esta reserva');
  }
  // Antes solo se validaba que la FECHA propuesta ya hubiera pasado, sin
  // importar si el cuidador realmente aceptó el Meet & Greet — un cliente
  // podía simplemente esperar a que pasara la fecha (sin que el cuidador
  // respondiera nunca) y avanzar al pago igual, como si el M&G hubiera
  // ocurrido. Ahora se exige que el estado sea ACCEPTED explícitamente.
  if (mg.status === 'CANCELLED') {
    throw new BookingValidationError('El Meet & Greet fue cancelado. Esta reserva ya no puede continuar — cancélala para liberar el pago.');
  }
  if (mg.status !== 'ACCEPTED') {
    throw new BookingValidationError('El cuidador aún no aceptó tu propuesta de Meet & Greet. Espera su respuesta antes de continuar con el pago.');
  }
  if (new Date(mg.proposedDate) > new Date()) {
    throw new BookingValidationError('El Meet & Greet aún no ha ocurrido. Podrás continuar con el pago después de la fecha programada.');
  }
  const updated = await prisma.booking.update({
    where: { id: bookingId },
    data: { status: BookingStatus.PENDING_PAYMENT },
  });
  return bookingToResponse(updated);
}

/**
 * Cancels a PENDING_MG booking after the M&G date has passed.
 * Can be called by either the client or the caregiver (userId is checked against both).
 */
export async function cancelMGBooking(bookingId: string, userId: string): Promise<void> {
  await prisma.$transaction(async (tx) => {
    const booking = await tx.booking.findFirst({
      where: {
        id: bookingId,
        status: BookingStatus.PENDING_MG,
        OR: [{ clientId: userId }, { caregiverId: userId }],
      },
      include: { meetAndGreet: true },
    });
    if (!booking) throw new BookingNotFoundError(bookingId);

    const mg = (booking as any).meetAndGreet;
    if (!mg || !mg.proposedDate) {
      throw new BookingValidationError('Esta reserva no tiene Meet & Greet programado');
    }
    if (new Date(mg.proposedDate) > new Date()) {
      throw new BookingValidationError('Solo puedes cancelar después de la fecha del Meet & Greet');
    }

    await tx.booking.update({
      where: { id: bookingId },
      data: {
        status: BookingStatus.CANCELLED,
        cancelledAt: new Date(),
        cancellationReason: 'Meet & Greet no resultó exitoso',
        refundAmount: new Prisma.Decimal(0),
        refundStatus: RefundStatus.REJECTED,
      },
    });

    const otherId = booking.clientId === userId ? booking.caregiverId : booking.clientId;
    await tx.notification.create({
      data: {
        userId: otherId,
        title: 'Reserva cancelada',
        message: 'La reserva fue cancelada después del Meet & Greet.',
        type: 'BOOKING_CANCELLED',
      },
    });
  });
}

export async function initPayment(
  bookingId: string,
  clientId: string,
  method: InitPaymentBody['method'],
  walletContribution: number = 0,
  donationAmount: number = 0
): Promise<{
  qrId?: string; qrImageUrl?: string; qrImageType?: string; qrExpiresAt?: string; status: string;
  walletDeducted?: number; remainingAmount?: number; paidWithWallet?: boolean;
}> {
  const cfg = await getBookingSettings();
  const result = await prisma.$transaction(async (tx) => {
    const booking = await tx.booking.findFirst({
      where: { id: bookingId, clientId },
      select: {
        id: true,
        status: true,
        caregiverId: true,
        totalAmount: true,
        commissionAmount: true,
        serviceType: true,
      },
    });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.status !== BookingStatus.PENDING_PAYMENT) {
      throw new BookingValidationError(
        'Solo se puede iniciar pago en reservas pendientes de pago'
      );
    }

    const totalAmount = Number(booking.totalAmount);
    // Tope de seguridad (debe coincidir con el límite del frontend en
    // payment_screen.dart): sin esto, un request directo al API (bypaseando
    // la UI) podía donar cualquier monto sin límite, incluyendo typos como
    // "5000" en vez de "50" que vacían la wallet del cliente por accidente.
    const effectiveDonation = Math.min(Math.max(0, donationAmount), 500);

    // ── Deuda previa del cliente (saldo negativo) ─────────────────────────────
    // Si el cliente tiene saldo negativo (por cargo de overtime de un servicio anterior),
    // la deuda se incorpora al pago actual y se recupera cuando el pago se confirme.
    const clientUser = await tx.user.findUnique({ where: { id: clientId }, select: { balance: true } });
    const clientBalance = Number(clientUser?.balance ?? 0);
    const debtAmount = clientBalance < 0 ? Math.abs(clientBalance) : 0;

    // ── Helper: saldo disponible (descuenta retiros pendientes) ───────────────
    // Reutilizado en todas las rutas de pago con billetera para que un retiro
    // pendiente no se pueda usar simultáneamente para pagar una reserva.
    const _getAvailableBalance = async (): Promise<{ balance: number; available: number }> => {
      const user = await tx.user.findUnique({ where: { id: clientId }, select: { balance: true } });
      const balance = Number(user?.balance ?? 0);
      const pendingAgg = await tx.walletTransaction.aggregate({
        where: { userId: clientId, type: 'WITHDRAWAL', status: { in: ['PENDING', 'PROCESSING'] } },
        _sum: { amount: true },
      });
      const pendingWithdrawals = Number(pendingAgg._sum.amount ?? 0);
      return { balance, available: Math.max(0, balance - pendingWithdrawals) };
    };

    // ── Helper: crear registro de donación + tx de billetera ──────────────────
    const _recordDonation = async (balanceAfterService: number) => {
      if (effectiveDonation <= 0) return balanceAfterService;
      const updatedDonation = await tx.user.update({
        where: { id: clientId },
        data: { balance: { decrement: effectiveDonation } },
        select: { balance: true },
      });
      const balanceAfterDonation = Number(updatedDonation.balance);
      await tx.walletTransaction.create({
        data: {
          userId: clientId,
          type: 'DONATION',
          amount: effectiveDonation,
          balance: balanceAfterDonation,
          description: `Donación voluntaria — reserva ${bookingId.slice(0, 8)}`,
          bookingId,
          status: 'COMPLETED',
        },
      });
      await tx.donation.upsert({
        where: { bookingId },
        create: { bookingId, clientId, amount: effectiveDonation },
        update: {},
      });
      return balanceAfterDonation;
    };

    // ── PAGO COMPLETO CON BILLETERA ────────────────────────────────────────────
    if (method === 'wallet') {
      const { balance, available } = await _getAvailableBalance();
      // Incluir deuda previa en el total a cobrar por billetera
      const totalCharge = totalAmount + effectiveDonation + debtAmount;
      if (available < totalCharge) {
        throw new BookingValidationError(
          `Saldo disponible insuficiente. Disponible: Bs ${available.toFixed(2)}, total: Bs ${totalCharge.toFixed(2)}${effectiveDonation > 0 ? ` (incluye Bs ${effectiveDonation.toFixed(2)} de donación)` : ''}${debtAmount > 0 ? ` + Bs ${debtAmount.toFixed(2)} de deuda previa` : ''}.`
        );
      }
      void balance; // used only for reference; decrement is atomic

      // Wallet completo: también recupera deuda
      const totalDecrement = totalAmount + debtAmount;
      const updatedWallet = await tx.user.update({
        where: { id: clientId },
        data: { balance: { decrement: totalDecrement } },
        select: { balance: true },
      });
      const balanceAfterService = Number(updatedWallet.balance);
      await tx.walletTransaction.create({
        data: {
          userId: clientId,
          type: 'PAYMENT',
          amount: totalAmount,
          balance: balanceAfterService + debtAmount, // snapshot pre-deuda
          description: `Pago con billetera — reserva ${bookingId.slice(0, 8)}`,
          bookingId,
          status: 'COMPLETED',
        },
      });
      if (debtAmount > 0) {
        await tx.walletTransaction.create({
          data: {
            userId: clientId,
            type: 'DEBT_RECOVERY',
            amount: debtAmount,
            balance: balanceAfterService,
            description: `Recuperación de deuda por tiempo extra — reserva ${bookingId.slice(0, 8)}`,
            bookingId,
            status: 'COMPLETED',
          },
        });
      }
      // Descontar donación (si aplica) y registrarla
      await _recordDonation(balanceAfterService);

      await tx.booking.update({
        where: { id: bookingId },
        data: {
          status: BookingStatus.WAITING_CAREGIVER_APPROVAL,
          paidAt: new Date(),
          walletPaymentAmount: totalAmount,
          donationAmount: effectiveDonation > 0 ? effectiveDonation : null,
          debtRecoveryAmount: debtAmount,
        },
      });
      logger.info('Pago completo con billetera', { bookingId, clientId, totalAmount, effectiveDonation, debtAmount });
      return {
        status: BookingStatus.WAITING_CAREGIVER_APPROVAL,
        paidWithWallet: true,
        walletDeducted: totalAmount + effectiveDonation + debtAmount,
        remainingAmount: 0,
      };
    }

    // ── PAGO QR CON CONTRIBUCIÓN DE BILLETERA ─────────────────────────────────
    const effectiveWalletContribution = Math.min(
      Math.max(0, walletContribution),
      totalAmount
    );

    if (effectiveWalletContribution > 0) {
      const { available } = await _getAvailableBalance();
      if (available < effectiveWalletContribution) {
        throw new BookingValidationError(
          `Saldo disponible insuficiente para la contribución de billetera. Disponible: Bs ${available.toFixed(2)}.`
        );
      }

      // Si la billetera cubre el total del servicio + donación + deuda → pago completo por billetera
      if (effectiveWalletContribution >= totalAmount && available >= totalAmount + effectiveDonation + debtAmount) {
        const totalDecrementFull = totalAmount + debtAmount;
        const updatedWalletFull = await tx.user.update({
          where: { id: clientId },
          data: { balance: { decrement: totalDecrementFull } },
          select: { balance: true },
        });
        const balanceAfterService = Number(updatedWalletFull.balance);
        await tx.walletTransaction.create({
          data: {
            userId: clientId,
            type: 'PAYMENT',
            amount: totalAmount,
            balance: balanceAfterService + debtAmount,
            description: `Pago con billetera — reserva ${bookingId.slice(0, 8)}`,
            bookingId,
            status: 'COMPLETED',
          },
        });
        if (debtAmount > 0) {
          await tx.walletTransaction.create({
            data: {
              userId: clientId,
              type: 'DEBT_RECOVERY',
              amount: debtAmount,
              balance: balanceAfterService,
              description: `Recuperación de deuda por tiempo extra — reserva ${bookingId.slice(0, 8)}`,
              bookingId,
              status: 'COMPLETED',
            },
          });
        }
        await _recordDonation(balanceAfterService);

        await tx.booking.update({
          where: { id: bookingId },
          data: {
            status: BookingStatus.WAITING_CAREGIVER_APPROVAL,
            paidAt: new Date(),
            walletPaymentAmount: totalAmount,
            donationAmount: effectiveDonation > 0 ? effectiveDonation : null,
            debtRecoveryAmount: debtAmount,
          },
        });
        return {
          status: BookingStatus.WAITING_CAREGIVER_APPROVAL,
          paidWithWallet: true,
          walletDeducted: totalAmount + effectiveDonation + debtAmount,
          remainingAmount: 0,
        };
      }

      // Parcial: descontar porción de billetera, QR para el resto + donación + deuda
      const updatedWalletPartial = await tx.user.update({
        where: { id: clientId },
        data: { balance: { decrement: effectiveWalletContribution } },
        select: { balance: true },
      });
      const newBalance = Number(updatedWalletPartial.balance);
      await tx.walletTransaction.create({
        data: {
          userId: clientId,
          type: 'PAYMENT',
          amount: effectiveWalletContribution,
          balance: newBalance,
          description: `Pago parcial con billetera — reserva ${bookingId.slice(0, 8)}`,
          bookingId,
          status: 'COMPLETED',
        },
      });
      await tx.booking.update({
        where: { id: bookingId },
        data: { walletPaymentAmount: effectiveWalletContribution },
      });

      // QR incluye el monto restante del servicio + donación completa + deuda previa
      const remainingAmount = Math.round(totalAmount - effectiveWalletContribution);
      const qrMonto = remainingAmount + effectiveDonation + debtAmount;
      const qrResult = await generateQR(bookingId, cfg.QR_VALIDITY_MINUTES_PAYMENT, qrMonto, booking.serviceType);
      await tx.booking.update({
        where: { id: bookingId },
        data: {
          qrId: qrResult.qrId,
          qrImageUrl: qrResult.qrImageUrl,
          qrExpiresAt: qrResult.qrExpiresAt,
          sipQrId: qrResult.sipQrId ?? null,
          sipTransaccionId: qrResult.sipTransaccionId ?? null,
          donationAmount: effectiveDonation > 0 ? effectiveDonation : null,
          debtRecoveryAmount: debtAmount,
          paymentApprovalRequestedAt: new Date(),
        },
      });
      logger.info('Pago parcial con billetera + QR', { bookingId, clientId, walletContribution: effectiveWalletContribution, remainingAmount, effectiveDonation, debtAmount, qrMonto });
      return {
        qrId: qrResult.qrId,
        qrImageUrl: qrResult.qrImageUrl,
        qrImageType: qrResult.qrImageType,
        qrExpiresAt: qrResult.qrExpiresAt.toISOString(),
        status: BookingStatus.PENDING_PAYMENT,
        walletDeducted: effectiveWalletContribution,
        remainingAmount: qrMonto,
        paidWithWallet: false,
      };
    }

    // ── PAGO QR COMPLETO (sin billetera) — QR incluye donación + deuda previa ─
    if (method === 'qr') {
      const qrMonto = totalAmount + effectiveDonation + debtAmount;
      const qrResult = await generateQR(bookingId, cfg.QR_VALIDITY_MINUTES_PAYMENT, qrMonto, booking.serviceType);
      await tx.booking.update({
        where: { id: bookingId },
        data: {
          qrId: qrResult.qrId,
          qrImageUrl: qrResult.qrImageUrl,
          qrExpiresAt: qrResult.qrExpiresAt,
          sipQrId: qrResult.sipQrId ?? null,
          sipTransaccionId: qrResult.sipTransaccionId ?? null,
          donationAmount: effectiveDonation > 0 ? effectiveDonation : null,
          debtRecoveryAmount: debtAmount,
          paymentApprovalRequestedAt: new Date(),
        },
      });
      logger.info('Pago QR iniciado', { bookingId, clientId, qrId: qrResult.qrId, totalAmount, effectiveDonation, debtAmount, qrMonto });
      return {
        qrId: qrResult.qrId,
        qrImageUrl: qrResult.qrImageUrl,
        qrImageType: qrResult.qrImageType,
        qrExpiresAt: qrResult.qrExpiresAt.toISOString(),
        status: BookingStatus.PENDING_PAYMENT,
      };
    }

    // ── PAGO MANUAL ────────────────────────────────────────────────────────────
    const manualPaymentId = `PAY-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    await tx.booking.update({
      where: { id: bookingId },
      data: {
        status: BookingStatus.PAYMENT_PENDING_APPROVAL,
        qrId: manualPaymentId,
        paymentApprovalRequestedAt: new Date(),
      },
    });
    await tx.adminNotification.create({
      data: {
        type: ADMIN_NOTIFICATION_PAYMENT_APPROVAL,
        caregiverId: booking.caregiverId,
        bookingId: booking.id,
      },
    });
    logger.info('Pago manual solicitado; notificación admin creada', {
      bookingId,
      clientId,
      caregiverId: booking.caregiverId,
      paymentId: manualPaymentId
    });
    logger.info('[ADMIN] Pago manual pendiente', {
      bookingId: booking.id,
      caregiverId: booking.caregiverId,
      actionUrl: `/admin/payments-pending`,
      message: 'Revisar y aprobar o rechazar en el panel admin.',
    });
    return { status: BookingStatus.PAYMENT_PENDING_APPROVAL, qrId: manualPaymentId };
  });

  // Push fuera de la transacción — nunca debe alargar los locks de fila
  // esperando una llamada de red a FCM, y sendPushToAdmins ya es fire-and-forget
  // (nunca lanza), así que no bloquea la respuesta al cliente.
  if (result.status === BookingStatus.PAYMENT_PENDING_APPROVAL) {
    sendPushToAdmins(
      '💳 Pago pendiente de aprobación',
      `Reserva ${bookingId.slice(0, 8).toUpperCase()} necesita revisión manual.`
    ).catch(() => {});
  }
  return result;
}

/**
 * Cuidador cancela la reserva de forma automática. 
 * Estado → CANCELLED. Se notifica al dueño (cliente) con el motivo y política de devolución.
 */
export async function requestCancellationByCaregiver(
  bookingId: string,
  caregiverUserId: string,
  reason: string
): Promise<BookingCreateResult> {
  const result = await prisma.$transaction(async (tx) => {
    const profile = await tx.caregiverProfile.findFirst({
      where: { userId: caregiverUserId },
      select: { id: true },
    });
    if (!profile) throw new ForbiddenError('Perfil de cuidador no encontrado');

    const booking = await tx.booking.findFirst({
      where: { id: bookingId, caregiverId: profile.id },
      include: { client: { select: { id: true } } }
    });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.status !== BookingStatus.CONFIRMED) {
      throw new BookingValidationError(
        'Solo se puede cancelar una reserva confirmada. Una vez iniciado el servicio ya no es posible cancelarlo.'
      );
    }

    const now = new Date();
    // Full refund when the caregiver cancels — client is not at fault.
    // Set refundStatus=PENDING_APPROVAL so admin can process any external (QR) portion.
    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        status: BookingStatus.CANCELLED,
        cancelledAt: now,
        cancellationReason: reason,
        refundAmount: booking.totalAmount,          // full refund
        refundStatus: RefundStatus.PENDING_APPROVAL, // admin must process QR portion
      },
    });

    // ── Auto-refund wallet portion immediately ───────────────────────────────
    const walletPaid = Number(booking.walletPaymentAmount ?? 0);
    let walletRefundNote = '';
    if (walletPaid > 0) {
      const updatedClient = await tx.user.update({
        where: { id: (booking as any).client.id },
        data: { balance: { increment: walletPaid } },
        select: { balance: true },
      });
      await tx.walletTransaction.create({
        data: {
          userId: (booking as any).client.id,
          type: 'REFUND',
          amount: walletPaid,
          balance: Number(updatedClient.balance),
          description: `Reembolso — cuidador canceló la reserva (${bookingId.slice(0, 8)})`,
          bookingId,
          status: 'COMPLETED',
        },
      });
      await tx.booking.update({
        where: { id: bookingId },
        data: { walletPaymentAmount: 0 },
      });
      walletRefundNote = ` Se reembolsaron Bs ${walletPaid.toFixed(2)} a tu billetera Garden de forma automática.`;
      logger.info('requestCancellationByCaregiver: wallet portion auto-refunded', { bookingId, walletPaid });
    }

    // 1. Notificación para el dueño (cliente)
    const qrPortion = Math.max(0, Number(booking.totalAmount) - walletPaid);
    const adminMsg = qrPortion > 0
      ? ` La empresa se contactará contigo en un plazo de 1 día hábil para gestionar la devolución de Bs ${qrPortion.toFixed(2)} según la política de reembolso.`
      : '';
    await tx.notification.create({
      data: {
        userId: (booking as any).client.id,
        title: 'Tu reserva ha sido cancelada por el cuidador',
        message: `El cuidador ha cancelado la reserva de ${booking.petName} (ID: ${bookingId.slice(0, 8)}). Motivo: ${reason}.${walletRefundNote}${adminMsg}`,
        type: 'BOOKING_CANCELLED',
      }
    });

    // 2. Notificación para el cuidador (confirmación propia)
    await tx.notification.create({
      data: {
        userId: caregiverUserId,
        title: 'Has cancelado la reserva exitosamente',
        message: `Has cancelado la reserva ${bookingId}. El cliente ha sido notificado y se gestionará el reembolso administrativo correspondiente.`,
        type: 'BOOKING_CANCELLED',
      }
    });

    // Admin notification so the refund is visible in the admin queue
    await tx.adminNotification.create({
      data: {
        type: 'CAREGIVER_CANCELLED_REFUND_NEEDED',
        caregiverId: profile.id,
        bookingId: booking.id,
      },
    });

    logger.info('Reserva cancelada automáticamente por el cuidador', {
      bookingId,
      caregiverId: profile.id,
      reason: reason.slice(0, 100),
    });
    return bookingToResponse(updated);
  });

  notificationService
    .onCaregiverCancelled(bookingId, reason)
    .catch((err) => logger.error('Notification onCaregiverCancelled failed', { bookingId, err }));
  return result;
}

// ---------------------------------------------------------------------------
// Reembolsos y modificaciones (MVP Subfase 2.2)
// ---------------------------------------------------------------------------

export interface CalculateRefundResult {
  refundAmount: number;
  refundStatus: RefundStatus;
  /** Porcentaje aplicado (100, 50, 0) para trazabilidad. */
  refundPercent: number;
}

/**
 * Calcula el reembolso según reglas MVP diferenciales.
 * Hospedaje: >48h → 100% - Bs10 admin; 24-48h → 50%; <24h → 0%.
 * Paseo: >12h → 100%; 6-12h → 50%; <6h → 0%.
 * @param booking Reserva con serviceType, fechas y totalAmount
 * @param cancellationDate Fecha/hora en que se solicita la cancelación (normalmente now)
 */
export async function calculateRefund(
  booking: Pick<
    Booking,
    'serviceType' | 'startDate' | 'endDate' | 'walkDate' | 'timeSlot' | 'totalAmount'
  >,
  cancellationDate: Date
): Promise<CalculateRefundResult> {
  const cfg = await getBookingSettings();
  const total = Number(booking.totalAmount);

  if (booking.serviceType === ServiceType.HOSPEDAJE) {
    const start = booking.startDate
      ? new Date(booking.startDate.getFullYear(), booking.startDate.getMonth(), booking.startDate.getDate(), 0, 0, 0)
      : null;
    if (!start) {
      return { refundAmount: 0, refundStatus: RefundStatus.REJECTED, refundPercent: 0 };
    }
    const hoursUntil = (start.getTime() - cancellationDate.getTime()) / (60 * 60 * 1000);
    if (hoursUntil > cfg.HOSPEDAJE_REFUND_100_HOURS) {
      const amount = Math.max(0, total - cfg.HOSPEDAJE_REFUND_ADMIN_FEE_BS);
      return {
        refundAmount: Math.round(amount * 100) / 100,
        refundStatus: RefundStatus.APPROVED,
        refundPercent: 100,
      };
    }
    if (hoursUntil > cfg.HOSPEDAJE_REFUND_50_HOURS) {
      // Admin fee también aplica en el caso del 50%
      const amount = Math.max(0, (total - cfg.HOSPEDAJE_REFUND_ADMIN_FEE_BS) * 0.5);
      return {
        refundAmount: Math.round(amount * 100) / 100,
        refundStatus: RefundStatus.APPROVED,
        refundPercent: 50,
      };
    }
    return { refundAmount: 0, refundStatus: RefundStatus.REJECTED, refundPercent: 0 };
  }

  // PASEO / GUARDERIA: referencia = mediodía del walkDate para calcular horas hasta el servicio
  const walkDate = booking.walkDate
    ? new Date(
      booking.walkDate.getFullYear(),
      booking.walkDate.getMonth(),
      booking.walkDate.getDate(),
      12,
      0,
      0
    )
    : null;
  if (!walkDate) {
    return { refundAmount: 0, refundStatus: RefundStatus.REJECTED, refundPercent: 0 };
  }
  const hoursUntil = (walkDate.getTime() - cancellationDate.getTime()) / (60 * 60 * 1000);
  if (hoursUntil > cfg.PASEO_REFUND_100_HOURS) {
    return {
      refundAmount: Math.round(total * 100) / 100,
      refundStatus: RefundStatus.APPROVED,
      refundPercent: 100,
    };
  }
  if (hoursUntil > cfg.PASEO_REFUND_50_HOURS) {
    const amount = total * 0.5;
    return {
      refundAmount: Math.round(amount * 100) / 100,
      refundStatus: RefundStatus.APPROVED,
      refundPercent: 50,
    };
  }
  return { refundAmount: 0, refundStatus: RefundStatus.REJECTED, refundPercent: 0 };
}

/**
 * Cancela una reserva y aplica política de reembolso.
 * Solo PENDING_PAYMENT o CONFIRMED; solo el cliente titular.
 * Actualiza status=CANCELLED, cancelledAt, cancellationReason, refundAmount, refundStatus.
 */
export async function cancelBooking(
  bookingId: string,
  clientId: string,
  cancellationReason?: string,
  cancellationSource?: 'CLIENT_REQUEST' | 'QR_ABANDONED' | 'PAYMENT_TIMEOUT'
): Promise<BookingCreateResult> {
  const result = await prisma.$transaction(async (tx) => {
    const booking = await tx.booking.findFirst({
      where: { id: bookingId, clientId },
    });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.status === BookingStatus.CANCELLED) {
      throw new BookingValidationError('La reserva ya está cancelada');
    }
    if (booking.status === BookingStatus.COMPLETED || booking.status === BookingStatus.IN_PROGRESS) {
      throw new BookingValidationError('No se puede cancelar una reserva ya iniciada o completada');
    }

    const now = new Date();
    let refundAmount: number;
    let refundStatus: RefundStatus;

    if (
      (booking.status === BookingStatus.PENDING_PAYMENT ||
        booking.status === BookingStatus.PAYMENT_PENDING_APPROVAL) &&
      !booking.paidAt
    ) {
      // No payment was made yet — nothing to refund
      refundAmount = 0;
      refundStatus = RefundStatus.REJECTED;
    } else {
      // Apply tiered cancellation policy (hospedaje: 100%/>48h, 50%/24-48h, 0%/<24h;
      // paseo: 100%/>12h, 50%/6-12h, 0%/<6h) — configured via admin settings.
      const refundCalc = await calculateRefund(booking, now);
      refundAmount = refundCalc.refundAmount;
      refundStatus = refundCalc.refundStatus;
    }

    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        status: BookingStatus.CANCELLED,
        cancelledAt: now,
        cancellationReason: cancellationReason ?? null,
        cancellationSource: cancellationSource ?? null,
        refundAmount: new Prisma.Decimal(refundAmount),
        refundStatus,
      },
    });

    // ── Auto-refund wallet portion if applicable ─────────────────────────────
    // For QR payments the money is external (admin processes manually).
    // For wallet payments the money is internal — refund immediately.
    const walletPaid = Number(booking.walletPaymentAmount ?? 0);
    const walletRefund = Math.min(walletPaid, refundAmount); // can't refund more than was charged
    let walletRefundNote = '';
    if (walletRefund > 0 && refundStatus === RefundStatus.APPROVED) {
      const updatedClient = await tx.user.update({
        where: { id: clientId },
        data: { balance: { increment: walletRefund } },
        select: { balance: true },
      });
      await tx.walletTransaction.create({
        data: {
          userId: clientId,
          type: 'REFUND',
          amount: walletRefund,
          balance: Number(updatedClient.balance),
          description: `Reembolso por cancelación — reserva ${bookingId.slice(0, 8)}`,
          bookingId,
          status: 'COMPLETED',
        },
      });
      walletRefundNote = ` Se reembolsaron Bs ${walletRefund.toFixed(2)} a tu billetera Garden de forma automática.`;
      logger.info('cancelBooking: wallet portion auto-refunded', { bookingId, walletRefund });
    }

    // 1 & 2. Notificaciones — solo si el cliente canceló explícitamente (no para QR abandonado o timeout)
    if (cancellationSource === 'CLIENT_REQUEST' || !cancellationSource) {
      const baseMsg = refundAmount > 0
        ? `Se te devolverá Bs ${refundAmount.toFixed(2)}.${walletRefundNote}${walletRefund < refundAmount ? ' El resto será procesado por el equipo de soporte pronto.' : ''}`
        : 'No aplica reembolso según la política de cancelación.';
      await tx.notification.create({
        data: {
          userId: clientId,
          title: 'Has cancelado tu reserva',
          message: `Tu reserva ha sido cancelada. ${baseMsg}`,
          type: 'BOOKING_CANCELLED',
        }
      });

      const caregiver = await tx.caregiverProfile.findUnique({
        where: { id: booking.caregiverId },
        select: { userId: true },
      });
      if (caregiver) {
        await tx.notification.create({
          data: {
            userId: caregiver.userId,
            title: 'Una reserva ha sido cancelada por el cliente',
            message: `El cliente ha cancelado la reserva ${bookingId}. Tu calendario se ha liberado automáticamente para estas fechas.`,
            type: 'BOOKING_CANCELLED',
          }
        });
      }
    }

    logger.info('Booking cancelled', {
      bookingId,
      clientId,
      refundAmount,
      refundStatus,
    });
    return { booking: updated, refundAmount, refundStatus };
  });

  if (cancellationSource === 'CLIENT_REQUEST' || !cancellationSource) {
    notificationService
      .onClientCancelled(bookingId)
      .catch((err) => logger.error('Notification onClientCancelled failed', { bookingId, err }));
  }

  // Invalida el QR en el banco si fue generado vía SIP y aún no fue cobrado
  if (env.SIP_ENABLED && result.booking.sipQrId) {
    sipService.disableQr(bookingId)
      .catch(err => logger.warn('[SIP] disableQr on cancel failed (non-fatal)', { bookingId, err }));
  }

  if (result.refundAmount > 0 && result.refundStatus === RefundStatus.APPROVED) {
    notificationService
      .onRefundProcessed(
        bookingId,
        `Tu reserva fue cancelada. Reembolso aprobado: Bs ${result.refundAmount.toFixed(2)}. El soporte se pondrá en contacto.`
      )
      .catch((err) => logger.error('Notification onRefundProcessed failed', { bookingId, err }));
  }

  auditLog({
    userId: clientId,
    action: 'BOOKING_CANCELLED',
    entity: 'Booking',
    entityId: bookingId,
    details: { reason: cancellationReason ?? null, refundAmount: result.refundAmount, refundStatus: result.refundStatus },
  });

  // Registro en Blockchain (asíncrono) — guarda txHash si la tx tiene éxito
  blockchainService.cancelBookingOnChain(bookingId, cancellationReason || 'Cancelado por usuario').then(async (txHash) => {
    if (txHash) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (prisma.booking as any).update({ where: { id: bookingId }, data: { blockchainCancelledTxHash: txHash } });
      logger.info('[Blockchain] cancel txHash saved', { bookingId, txHash });
    }
  }).catch(err => {
    logger.error('Blockchain cancellation failed', { bookingId, err });
  });

  return bookingToResponse(result.booking);
}

/**
 * Extiende una reserva de hospedaje (nueva endDate).
 * Solo CONFIRMED; el cliente titular; newEndDate > endDate actual.
 * Comprueba disponibilidad y solapamientos; recalcula totalDays y totalAmount.
 */
export async function extendBooking(
  bookingId: string,
  clientId: string,
  newEndDate: Date
): Promise<BookingCreateResult> {
  const cfg = await getBookingSettings();
  return prisma.$transaction(async (tx) => {
    const booking = await tx.booking.findFirst({
      where: { id: bookingId, clientId },
      select: {
        id: true,
        serviceType: true,
        status: true,
        startDate: true,
        endDate: true,
        totalDays: true,
        pricePerUnit: true,
        totalAmount: true,
        caregiverId: true,
      },
    });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.serviceType !== ServiceType.HOSPEDAJE) {
      throw new BookingValidationError('Solo se puede extender una reserva de hospedaje');
    }
    if (booking.status !== BookingStatus.CONFIRMED) {
      throw new BookingValidationError('Solo se puede extender una reserva confirmada');
    }
    const currentEnd = booking.endDate!;
    if (newEndDate <= currentEnd) {
      throw new BookingValidationError('La nueva fecha de salida debe ser posterior a la actual');
    }
    const start = booking.startDate!;
    const newEndNorm = new Date(newEndDate.getFullYear(), newEndDate.getMonth(), newEndDate.getDate(), 0, 0, 0);
    const dates: Date[] = [];
    for (let d = new Date(currentEnd); d < newEndNorm; d.setDate(d.getDate() + 1)) {
      dates.push(new Date(d));
    }
    // Para hospedaje solo se bloquean días con fila explícita isAvailable=false.
    const blockedExtRows = await tx.availability.findMany({
      where: { caregiverId: booking.caregiverId, date: { in: dates }, isAvailable: false },
    });
    if (blockedExtRows.length > 0) {
      throw new AvailabilityConflictError(
        `El cuidador no está disponible en: ${blockedExtRows.map((r) => r.date.toISOString().slice(0, 10)).join(', ')}`
      );
    }

    const overlapping = await tx.booking.count({
      where: {
        caregiverId: booking.caregiverId,
        id: { not: bookingId },
        status: { in: [BookingStatus.PENDING_PAYMENT, BookingStatus.CONFIRMED, BookingStatus.IN_PROGRESS] },
        startDate: { lte: newEndNorm },
        endDate: { gt: start },
      },
    });
    if (overlapping > 0) {
      throw new AvailabilityConflictError(
        'El cuidador tiene otra reserva que se solapa con la extensión'
      );
    }

    const totalDaysNew = Math.ceil((newEndNorm.getTime() - start.getTime()) / (24 * 60 * 60 * 1000));
    // Derive original caregiver price from the marked-up pricePerUnit
    const pricePerUnitClient = Number(booking.pricePerUnit);
    const pricePerUnitCaregiver = Math.round(pricePerUnitClient / (1 + cfg.COMMISSION_RATE));

    const subtotalCaregiver = totalDaysNew * pricePerUnitCaregiver;
    const totalAmountNew = Math.round(subtotalCaregiver * (1 + cfg.COMMISSION_RATE));
    const commissionAmount = totalAmountNew - subtotalCaregiver;

    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        endDate: newEndNorm,
        totalDays: totalDaysNew,
        totalAmount: new Prisma.Decimal(totalAmountNew),
        commissionAmount: new Prisma.Decimal(commissionAmount),
      },
    });

    logger.info('Booking extended', {
      bookingId,
      newEndDate: newEndNorm.toISOString().slice(0, 10),
      totalDaysNew,
      totalAmountNew,
    });
    return bookingToResponse(updated);
  });
}

/**
 * Cambia las fechas de una reserva de hospedaje (nuevo startDate y endDate).
 * Solo CONFIRMED; cliente titular; mínimo 1 noche entre check-in y check-out.
 * Comprueba disponibilidad y solapamientos (excluyendo esta reserva); recalcula montos.
 */
export async function changeDatesBooking(
  bookingId: string,
  clientId: string,
  newStartDate: Date,
  newEndDate: Date
): Promise<BookingCreateResult> {
  const cfg = await getBookingSettings();
  return prisma.$transaction(async (tx) => {
    const booking = await tx.booking.findFirst({
      where: { id: bookingId, clientId },
      select: {
        id: true,
        serviceType: true,
        status: true,
        startDate: true,
        endDate: true,
        pricePerUnit: true,
        caregiverId: true,
      },
    });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.serviceType !== ServiceType.HOSPEDAJE) {
      throw new BookingValidationError('Solo se pueden cambiar fechas en una reserva de hospedaje');
    }
    if (booking.status !== BookingStatus.CONFIRMED) {
      throw new BookingValidationError('Solo se pueden cambiar fechas en una reserva confirmada');
    }

    const startNorm = new Date(newStartDate.getFullYear(), newStartDate.getMonth(), newStartDate.getDate(), 0, 0, 0);
    const endNorm = new Date(newEndDate.getFullYear(), newEndDate.getMonth(), newEndDate.getDate(), 0, 0, 0);
    if (endNorm <= startNorm) {
      throw new BookingValidationError('La fecha de salida debe ser posterior a la de entrada');
    }
    const dates: Date[] = [];
    for (let d = new Date(startNorm); d < endNorm; d.setDate(d.getDate() + 1)) {
      dates.push(new Date(d));
    }
    // Para hospedaje solo se bloquean días con fila explícita isAvailable=false.
    const blockedChgRows = await tx.availability.findMany({
      where: { caregiverId: booking.caregiverId, date: { in: dates }, isAvailable: false },
    });
    if (blockedChgRows.length > 0) {
      throw new AvailabilityConflictError(
        `El cuidador no está disponible en: ${blockedChgRows.map((r) => r.date.toISOString().slice(0, 10)).join(', ')}`
      );
    }

    const overlapping = await tx.booking.count({
      where: {
        caregiverId: booking.caregiverId,
        id: { not: bookingId },
        status: { in: [BookingStatus.PENDING_PAYMENT, BookingStatus.CONFIRMED, BookingStatus.IN_PROGRESS] },
        startDate: { lte: endNorm },
        endDate: { gt: startNorm },
      },
    });
    if (overlapping > 0) {
      throw new AvailabilityConflictError(
        'El cuidador tiene otra reserva que se solapa con las nuevas fechas'
      );
    }

    const totalDaysNew = Math.ceil((endNorm.getTime() - startNorm.getTime()) / (24 * 60 * 60 * 1000));
    // Derive original caregiver price
    const pricePerUnitClient = Number(booking.pricePerUnit);
    const pricePerUnitCaregiver = Math.round(pricePerUnitClient / (1 + cfg.COMMISSION_RATE));

    const subtotalCaregiver = totalDaysNew * pricePerUnitCaregiver;
    const totalAmountNew = Math.round(subtotalCaregiver * (1 + cfg.COMMISSION_RATE));
    const commissionAmount = totalAmountNew - subtotalCaregiver;

    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        startDate: startNorm,
        endDate: endNorm,
        totalDays: totalDaysNew,
        totalAmount: new Prisma.Decimal(totalAmountNew),
        commissionAmount: new Prisma.Decimal(commissionAmount),
      },
    });

    logger.info('Booking dates changed', {
      bookingId,
      newStartDate: startNorm.toISOString().slice(0, 10),
      newEndDate: endNorm.toISOString().slice(0, 10),
      totalDaysNew,
      totalAmountNew,
    });
    return bookingToResponse(updated);
  });
}

/**
 * Crea una solicitud de pago de extensión de paseo (genera QR o solicitud manual).
 * No aplica los minutos todavía — se aplican en confirmWalkExtensionQr o cuando el admin aprueba.
 */
export async function requestWalkExtensionPayment(
  bookingId: string,
  clientId: string,
  additionalMinutes: number,
  method: 'qr' | 'manual'
): Promise<{ extensionId: string; extraAmount: number; qrId?: string; qrImageUrl?: string; qrExpiresAt?: string; status: string }> {
  const cfg = await getBookingSettings();

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, clientId },
    select: {
      id: true, serviceType: true, status: true,
      pricePerUnit: true, caregiverId: true, serviceEvents: true,
    },
  });

  if (!booking) throw new BookingNotFoundError(bookingId);
  if (booking.serviceType !== ServiceType.PASEO) throw new BookingValidationError('Solo se puede extender un paseo');
  if (booking.status !== BookingStatus.IN_PROGRESS) throw new BookingValidationError('Solo se puede extender un paseo en curso');

  const pricePerUnitClient = Number(booking.pricePerUnit);
  const pricePerUnitCaregiver = Math.round(pricePerUnitClient / (1 + cfg.COMMISSION_RATE));
  const ratePerMinCaregiver = pricePerUnitCaregiver / 60;
  const extraBase = Math.round(ratePerMinCaregiver * additionalMinutes);
  const extraTotal = Math.round(extraBase * (1 + cfg.COMMISSION_RATE));

  const extensionId = crypto.randomUUID();
  const events: any[] = Array.isArray(booking.serviceEvents) ? [...(booking.serviceEvents as any[])] : [];

  if (method === 'qr') {
    const qrResult = await generateQR(bookingId, 15, extraTotal, booking.serviceType); // 15 min de validez para extensiones
    events.push({
      type: 'EXTENSION_PENDING_PAYMENT',
      extensionId,
      additionalMinutes,
      extraAmount: extraTotal,
      method: 'qr',
      qrId: qrResult.qrId,
      qrImageUrl: qrResult.qrImageUrl,
      qrImageType: qrResult.qrImageType,
      qrExpiresAt: qrResult.qrExpiresAt.toISOString(),
      sipQrId: qrResult.sipQrId,
      sipTransaccionId: qrResult.sipTransaccionId,
      timestamp: new Date().toISOString(),
    });

    await prisma.booking.update({
      where: { id: bookingId },
      data: { serviceEvents: events },
    });

    logger.info('Walk extension QR payment initiated', { bookingId, extensionId, additionalMinutes, extraTotal });
    return {
      extensionId,
      extraAmount: extraTotal,
      qrId: qrResult.qrId,
      qrImageUrl: qrResult.qrImageUrl,
      qrExpiresAt: qrResult.qrExpiresAt.toISOString(),
      status: 'PENDING_QR',
    };
  }

  // Manual: notificar al admin
  const manualPaymentId = `EXT-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
  events.push({
    type: 'EXTENSION_PENDING_PAYMENT',
    extensionId,
    additionalMinutes,
    extraAmount: extraTotal,
    method: 'manual',
    paymentId: manualPaymentId,
    timestamp: new Date().toISOString(),
  });

  const caregiver = await prisma.caregiverProfile.findFirst({
    where: { id: booking.caregiverId },
    select: { id: true },
  });

  await prisma.$transaction([
    prisma.booking.update({ where: { id: bookingId }, data: { serviceEvents: events } }),
    ...(caregiver ? [prisma.adminNotification.create({
      data: {
        type: 'EXTENSION_PAYMENT_APPROVAL',
        caregiverId: caregiver.id,
        bookingId,
      },
    })] : []),
  ]);

  logger.info('Walk extension manual payment requested', { bookingId, extensionId, manualPaymentId, extraTotal });
  return { extensionId, extraAmount: extraTotal, status: 'PENDING_MANUAL', qrId: manualPaymentId };
}

/**
 * Confirma el pago QR de una extensión de paseo y aplica los minutos adicionales.
 */
export async function confirmWalkExtensionQr(
  bookingId: string,
  clientId: string,
  qrId: string
): Promise<BookingCreateResult> {
  const cfg = await getBookingSettings();

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, clientId }, // ← ownership check: only the booking's client can confirm
    select: {
      id: true, clientId: true, caregiverId: true, serviceType: true, status: true,
      duration: true, totalAmount: true, commissionAmount: true, pricePerUnit: true,
      petName: true, serviceEvents: true,
    },
  });

  if (!booking) throw new BookingNotFoundError(bookingId); // covers both not-found AND unauthorized
  if (booking.status !== BookingStatus.IN_PROGRESS) throw new BookingValidationError('El paseo ya no está en curso');

  const events: any[] = Array.isArray(booking.serviceEvents) ? [...(booking.serviceEvents as any[])] : [];
  const pendingIdx = events.findIndex(
    e => e.type === 'EXTENSION_PENDING_PAYMENT' && e.method === 'qr' && e.qrId === qrId
  );

  if (pendingIdx === -1) throw new BookingValidationError('QR de extensión no válido o ya procesado');

  const pending = events[pendingIdx];
  const qrExpiry = new Date(pending.qrExpiresAt);
  if (qrExpiry < new Date()) throw new BookingValidationError('El QR de extensión ha expirado. Genera uno nuevo.');

  const { additionalMinutes, extraAmount, extensionId } = pending;

  // Aplicar extensión
  const pricePerUnitClient = Number(booking.pricePerUnit);
  const pricePerUnitCaregiver = Math.round(pricePerUnitClient / (1 + cfg.COMMISSION_RATE));
  const extraCommission = extraAmount - Math.round((pricePerUnitCaregiver / 60) * additionalMinutes);

  const newDuration = (booking.duration ?? 60) + additionalMinutes;
  const newTotal = Number(booking.totalAmount) + extraAmount;
  const newCommission = Number(booking.commissionAmount) + extraCommission;

  // Reemplazar PENDING → EXTENSION_CONFIRMED
  events[pendingIdx] = {
    type: 'EXTENSION_CONFIRMED',
    extensionId,
    additionalMinutes,
    extraAmount,
    method: 'qr',
    paidAt: new Date().toISOString(),
    timestamp: new Date().toISOString(),
  };

  let caregiverUserId: string | null = null;

  const result = await prisma.$transaction(async (tx) => {
    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        duration: newDuration,
        totalAmount: new Prisma.Decimal(newTotal),
        commissionAmount: new Prisma.Decimal(newCommission),
        serviceEvents: events,
      },
    });

    const caregiver = await tx.caregiverProfile.findFirst({
      where: { id: booking.caregiverId },
      select: { userId: true },
    });
    if (caregiver) {
      caregiverUserId = caregiver.userId;
      await tx.notification.create({
        data: {
          userId: caregiver.userId,
          title: '⏱️ Extensión de paseo confirmada',
          message: `El cliente pagó ${additionalMinutes} min adicionales para el paseo de ${booking.petName ?? 'la mascota'}. Bs ${extraAmount} adicionales.`,
          type: 'SERVICE_EXTENSION',
        },
      });
    }

    logger.info('Walk extension QR confirmed', { bookingId, extensionId, additionalMinutes, newDuration, newTotal });
    return bookingToResponse(updated);
  });

  if (caregiverUserId) {
    sendPushToUser(caregiverUserId, '⏱️ Extensión confirmada', `+${additionalMinutes} min · Bs ${extraAmount} adicionales`)
      .catch(() => {});
  }

  blockchainService.recordWalkExtensionOnChain(bookingId, additionalMinutes, newTotal).catch(() => {});

  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// HOSPEDAJE EXTENSIONS
// ─────────────────────────────────────────────────────────────────────────────

export async function checkHospedajeExtensionAvailability(
  bookingId: string,
  clientId: string
): Promise<{ availableDays: number; pricePerDay: number }> {
  const [booking, cfg] = await Promise.all([
    prisma.booking.findFirst({
      where: { id: bookingId, clientId },
      select: { id: true, serviceType: true, status: true, pricePerUnit: true },
    }),
    getBookingSettings(),
  ]);

  if (!booking) return { availableDays: 0, pricePerDay: 0 };
  if (booking.serviceType !== ServiceType.HOSPEDAJE) return { availableDays: 0, pricePerDay: 0 };
  if (booking.status !== BookingStatus.IN_PROGRESS) return { availableDays: 0, pricePerDay: 0 };

  return { availableDays: cfg.HOSPEDAJE_MAX_EXTENSION_DAYS, pricePerDay: Number(booking.pricePerUnit) };
}

export async function requestHospedajeExtensionPayment(
  bookingId: string,
  clientId: string,
  additionalDays: number,
  method: 'qr' | 'manual'
): Promise<{ extensionId: string; extraAmount: number; qrId?: string; qrImageUrl?: string; qrExpiresAt?: string; status: string }> {
  const cfg = await getBookingSettings();

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, clientId },
    select: { id: true, serviceType: true, status: true, pricePerUnit: true, caregiverId: true, serviceEvents: true },
  });

  if (!booking) throw new BookingNotFoundError(bookingId);
  if (booking.serviceType !== ServiceType.HOSPEDAJE) throw new BookingValidationError('Solo se puede extender un hospedaje');
  if (booking.status !== BookingStatus.IN_PROGRESS) throw new BookingValidationError('Solo se puede extender un hospedaje en curso');

  const pricePerUnitClient = Number(booking.pricePerUnit);
  const pricePerUnitCaregiver = Math.round(pricePerUnitClient / (1 + cfg.COMMISSION_RATE));
  const extraBase = pricePerUnitCaregiver * additionalDays;
  const extraTotal = Math.round(extraBase * (1 + cfg.COMMISSION_RATE));

  const extensionId = crypto.randomUUID();
  const events: any[] = Array.isArray(booking.serviceEvents) ? [...(booking.serviceEvents as any[])] : [];

  // Prevent stacking of multiple unpaid extensions — only one at a time
  const hasPendingExtension = events.some(
    (e: any) => e.type === 'EXTENSION_PENDING_PAYMENT' && (!e.qrExpiresAt || new Date(e.qrExpiresAt) > new Date())
  );
  if (hasPendingExtension) {
    throw new BookingValidationError('Ya tienes una solicitud de extensión pendiente de pago. Confirma o espera a que expire antes de solicitar otra.');
  }

  if (method === 'qr') {
    const qrResult = await generateQR(bookingId, 15, extraTotal, booking.serviceType);
    events.push({
      type: 'EXTENSION_PENDING_PAYMENT',
      extensionId,
      additionalDays,
      extraAmount: extraTotal,
      method: 'qr',
      qrId: qrResult.qrId,
      qrImageUrl: qrResult.qrImageUrl,
      qrImageType: qrResult.qrImageType,
      qrExpiresAt: qrResult.qrExpiresAt.toISOString(),
      sipQrId: qrResult.sipQrId,
      sipTransaccionId: qrResult.sipTransaccionId,
      timestamp: new Date().toISOString(),
    });

    await prisma.booking.update({ where: { id: bookingId }, data: { serviceEvents: events } });
    logger.info('Hospedaje extension QR payment initiated', { bookingId, extensionId, additionalDays, extraTotal });
    return { extensionId, extraAmount: extraTotal, qrId: qrResult.qrId, qrImageUrl: qrResult.qrImageUrl, qrExpiresAt: qrResult.qrExpiresAt.toISOString(), status: 'PENDING_QR' };
  }

  const manualPaymentId = `EXT-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
  events.push({
    type: 'EXTENSION_PENDING_PAYMENT',
    extensionId,
    additionalDays,
    extraAmount: extraTotal,
    method: 'manual',
    paymentId: manualPaymentId,
    timestamp: new Date().toISOString(),
  });

  const caregiver = await prisma.caregiverProfile.findFirst({
    where: { id: booking.caregiverId },
    select: { id: true },
  });

  await prisma.$transaction([
    prisma.booking.update({ where: { id: bookingId }, data: { serviceEvents: events } }),
    ...(caregiver ? [prisma.adminNotification.create({
      data: { type: 'EXTENSION_PAYMENT_APPROVAL', caregiverId: caregiver.id, bookingId },
    })] : []),
  ]);

  logger.info('Hospedaje extension manual payment requested', { bookingId, extensionId, manualPaymentId, extraTotal });
  return { extensionId, extraAmount: extraTotal, status: 'PENDING_MANUAL', qrId: manualPaymentId };
}

export async function confirmHospedajeExtensionQr(
  bookingId: string,
  clientId: string,
  qrId: string
): Promise<BookingCreateResult> {
  const cfg = await getBookingSettings();

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, clientId }, // ← ownership check
    select: {
      id: true, clientId: true, caregiverId: true, serviceType: true, status: true,
      endDate: true, totalDays: true, totalAmount: true, commissionAmount: true,
      pricePerUnit: true, petName: true, serviceEvents: true,
    },
  });

  if (!booking) throw new BookingNotFoundError(bookingId); // covers not-found AND unauthorized
  if (booking.status !== BookingStatus.IN_PROGRESS) throw new BookingValidationError('El hospedaje ya no está en curso');

  const events: any[] = Array.isArray(booking.serviceEvents) ? [...(booking.serviceEvents as any[])] : [];
  const pendingIdx = events.findIndex(
    e => e.type === 'EXTENSION_PENDING_PAYMENT' && e.method === 'qr' && e.qrId === qrId
  );

  if (pendingIdx === -1) throw new BookingValidationError('QR de extensión no válido o ya procesado');

  const pending = events[pendingIdx];
  const qrExpiry = new Date(pending.qrExpiresAt);
  if (qrExpiry < new Date()) throw new BookingValidationError('El QR de extensión ha expirado. Genera uno nuevo.');

  const { additionalDays, extraAmount, extensionId } = pending;

  const pricePerUnitClient = Number(booking.pricePerUnit);
  const pricePerUnitCaregiver = Math.round(pricePerUnitClient / (1 + cfg.COMMISSION_RATE));
  const extraCommission = extraAmount - pricePerUnitCaregiver * additionalDays;

  const newEndDate = new Date(booking.endDate!);
  newEndDate.setDate(newEndDate.getDate() + additionalDays);
  const newTotalDays = (booking.totalDays ?? 1) + additionalDays;

  // Verificar que la nueva endDate no entra en conflicto con otra reserva del mismo cuidador.
  // Se hace ANTES de modificar la DB para que, si hay conflicto, el error llegue al cliente
  // y el pago (ya confirmado por el banco) sea reembolsado manualmente por el admin.
  await prisma.$transaction(async (checkTx) => {
    await assertHospedajeAvailability(
      checkTx,
      booking.caregiverId,
      booking.endDate!.toISOString(),   // desde la endDate actual (nuevo rango)
      newEndDate.toISOString(),
      1  // petCount=1 mínimo; la mascota ya está alojada, solo verificamos fechas adicionales
    );
  }).catch((err) => {
    // Si hay conflicto de disponibilidad, lanzar con mensaje claro
    if (err instanceof BookingValidationError || (err as any).code === 'AVAILABILITY_CONFLICT') {
      throw new BookingValidationError(
        `Las fechas de extensión (${additionalDays} días más) entran en conflicto con otra reserva del cuidador. ` +
        `El pago fue recibido — contacta al soporte para el reembolso.`
      );
    }
    throw err;
  });
  const newTotal = Number(booking.totalAmount) + extraAmount;
  const newCommission = Number(booking.commissionAmount) + extraCommission;

  events[pendingIdx] = {
    type: 'EXTENSION_CONFIRMED',
    extensionId,
    additionalDays,
    extraAmount,
    method: 'qr',
    paidAt: new Date().toISOString(),
    timestamp: new Date().toISOString(),
  };

  let caregiverUserId: string | null = null;

  const result = await prisma.$transaction(async (tx) => {
    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        endDate: newEndDate,
        totalDays: newTotalDays,
        totalAmount: new Prisma.Decimal(newTotal),
        commissionAmount: new Prisma.Decimal(newCommission),
        serviceEvents: events,
      },
    });

    const caregiver = await tx.caregiverProfile.findFirst({
      where: { id: booking.caregiverId },
      select: { userId: true },
    });
    if (caregiver) {
      caregiverUserId = caregiver.userId;
      await tx.notification.create({
        data: {
          userId: caregiver.userId,
          title: '🏠 Hospedaje extendido',
          message: `El cliente agregó ${additionalDays} noche${additionalDays > 1 ? 's' : ''} al hospedaje de ${booking.petName ?? 'la mascota'}. Bs ${extraAmount} adicionales.`,
          type: 'SERVICE_EXTENSION',
        },
      });
    }

    logger.info('Hospedaje extension QR confirmed', { bookingId, extensionId, additionalDays, newTotalDays, newTotal });
    return bookingToResponse(updated);
  });

  if (caregiverUserId) {
    sendPushToUser(caregiverUserId, '🏠 Hospedaje extendido', `+${additionalDays} noche${additionalDays > 1 ? 's' : ''} · Bs ${extraAmount} adicionales`).catch(() => {});
  }

  // Registro en blockchain (asíncrono — mock si no está configurado)
  blockchainService.recordHospedajeExtensionOnChain(bookingId, additionalDays, newTotal).catch((err) => {
    logger.error('Blockchain hospedaje extension failed', { bookingId, err });
  });

  return result;
}

/**
 * Extiende un paseo en curso (IN_PROGRESS) sumando 15, 30 o 60 minutos adicionales.
 * Recalcula el monto total prorrateando el precio por minuto del cuidador (precio de 60 min).
 * Notifica al cuidador por in-app + push. Registra evento en serviceEvents y en blockchain.
 */
export async function extendPaseoWalk(
  bookingId: string,
  clientId: string,
  additionalMinutes: number
): Promise<BookingCreateResult> {
  const cfg = await getBookingSettings();

  let caregiverUserId: string | null = null;

  const result = await prisma.$transaction(async (tx) => {
    const booking = await tx.booking.findFirst({
      where: { id: bookingId, clientId },
      select: {
        id: true,
        serviceType: true,
        status: true,
        duration: true,
        totalAmount: true,
        commissionAmount: true,
        pricePerUnit: true,
        caregiverId: true,
        petName: true,
        serviceEvents: true,
      },
    });

    if (!booking) throw new BookingNotFoundError(bookingId);

    if (booking.serviceType !== ServiceType.PASEO) {
      throw new BookingValidationError('Solo se puede extender un paseo');
    }
    if (booking.status !== BookingStatus.IN_PROGRESS) {
      throw new BookingValidationError('Solo se puede extender un paseo que está en curso');
    }

    // pricePerUnit es el precio de 60 min que se guardó en la reserva (con comisión incluida)
    const pricePerUnitClient = Number(booking.pricePerUnit); // precio total de 60 min con comisión
    const pricePerUnitCaregiver = Math.round(pricePerUnitClient / (1 + cfg.COMMISSION_RATE));
    const ratePerMinCaregiver = pricePerUnitCaregiver / 60;

    const extraBase = Math.round(ratePerMinCaregiver * additionalMinutes);
    const extraTotal = Math.round(extraBase * (1 + cfg.COMMISSION_RATE));
    const extraCommission = extraTotal - extraBase;

    const currentDuration = booking.duration ?? 60;
    const newDuration = currentDuration + additionalMinutes;
    const newTotal = Number(booking.totalAmount) + extraTotal;
    const newCommission = Number(booking.commissionAmount) + extraCommission;

    // Append extension event to serviceEvents array
    const events: any[] = Array.isArray(booking.serviceEvents) ? [...(booking.serviceEvents as any[])] : [];
    events.push({
      type: 'EXTENSION_CONFIRMED',
      additionalMinutes,
      extraAmount: extraTotal,
      timestamp: new Date().toISOString(),
    });

    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        duration: newDuration,
        totalAmount: new Prisma.Decimal(newTotal),
        commissionAmount: new Prisma.Decimal(newCommission),
        serviceEvents: events,
      },
    });

    // Notificación in-app al cuidador
    const caregiver = await tx.caregiverProfile.findFirst({
      where: { id: booking.caregiverId },
      select: { userId: true },
    });
    if (caregiver) {
      caregiverUserId = caregiver.userId;
      await tx.notification.create({
        data: {
          userId: caregiver.userId,
          title: '⏱️ Extensión de paseo confirmada',
          message: `El cliente ha confirmado ${additionalMinutes} minutos adicionales para el paseo de ${booking.petName ?? 'la mascota'}. Bs ${extraTotal} adicionales han sido pagados.`,
          type: 'SERVICE_EXTENSION',
        },
      });
    }

    logger.info('Paseo walk extended', {
      bookingId,
      additionalMinutes,
      newDuration,
      extraTotal,
      newTotal,
    });

    return bookingToResponse(updated);
  });

  // Push notification al cuidador (fuera de la transacción)
  if (caregiverUserId) {
    sendPushToUser(
      caregiverUserId,
      '⏱️ Extensión de paseo confirmada',
      `${additionalMinutes} minutos adicionales — Bs ${result.totalAmount}`
    ).catch((err) => logger.error('Push extension failed', { bookingId, err }));
  }

  // Registro en blockchain (asíncrono — mock si no está configurado)
  blockchainService.recordWalkExtensionOnChain(bookingId, additionalMinutes, parseFloat(result.totalAmount)).catch((err) => {
    logger.error('Blockchain walk extension failed', { bookingId, err });
  });

  return result;
}

/**
 * Obtiene las reservas del cliente autenticado, paginadas.
 * Retorna lista ordenada por createdAt DESC con metadata de paginación.
 */
export async function getMyBookings(
  clientId: string,
  page = 1,
  limit = 20
): Promise<{ bookings: BookingCreateResult[]; pagination: { page: number; limit: number; total: number; pages: number } }> {
  const skip = (page - 1) * limit;
  const hiddenSources = ['QR_ABANDONED', 'PAYMENT_TIMEOUT'];
  const baseWhere = {
    clientId,
    NOT: {
      AND: [
        { status: BookingStatus.CANCELLED },
        { cancellationSource: { in: hiddenSources } },
      ],
    },
  };

  const [bookings, total] = await Promise.all([
    prisma.booking.findMany({
      where: baseWhere,
      include: {
        caregiver: {
          include: {
            user: {
              select: {
                id: true,
                firstName: true,
                lastName: true,
                email: true,
                profilePicture: true,
              },
            },
          },
        },
        dispute: true,
        meetAndGreet: true,
        bookingPets: true,
      },
      orderBy: { createdAt: 'desc' },
      skip,
      take: limit,
    }),
    prisma.booking.count({ where: baseWhere }),
  ]);

  return {
    bookings: bookings.map(bookingToResponse),
    pagination: { page, limit, total, pages: Math.ceil(total / limit) || 1 },
  };
}

/**
 * Obtiene una reserva por ID. El cliente titular o el cuidador asignado pueden acceder.
 */
export async function getBookingById(
  bookingId: string,
  userId: string,
  role?: string
): Promise<BookingCreateResult> {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: {
      caregiver: {
        include: {
          user: {
            select: {
              id: true,
              firstName: true,
              lastName: true,
              email: true,
              profilePicture: true,
            },
          },
        },
      },
      client: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          email: true,
          phone: true,
          profilePicture: true,
          clientProfile: {
            select: {
              address: true,
              addressLat: true,
              addressLng: true,
              addressStreet: true,
              addressNumber: true,
              addressApartment: true,
              addressCondominio: true,
              addressReference: true,
              addressZone: true,
            },
          },
        },
      },
      dispute: true,
      meetAndGreet: true,
      bookingPets: true,
    },
  });

  if (!booking) {
    throw new BookingNotFoundError(bookingId);
  }

  // Verificar acceso: cliente titular, cuidador asignado o ADMIN
  const isClient = booking.clientId === userId;
  const isCaregiver = booking.caregiver.userId === userId;
  const isAdmin = role === 'ADMIN';

  if (!isClient && !isCaregiver && !isAdmin) {
    throw new ForbiddenError('No tienes acceso a esta reserva');
  }

  return bookingToResponse(booking);
}

/**
 * Lista reservas asignadas al cuidador (por userId del cuidador), paginadas.
 */
export async function getBookingsByCaregiverUserId(
  caregiverUserId: string,
  page = 1,
  limit = 20
): Promise<{ bookings: BookingCreateResult[]; pagination: { page: number; limit: number; total: number; pages: number } }> {
  const profile = await prisma.caregiverProfile.findFirst({
    where: { userId: caregiverUserId },
    select: { id: true },
  });
  if (!profile) return { bookings: [], pagination: { page, limit, total: 0, pages: 1 } };

  const skip = (page - 1) * limit;
  // El cuidador solo ve reservas que ya han pasado por el pago (o están en M&G pendiente).
  // PENDING_PAYMENT se excluye: la reserva no existe para el cuidador hasta que el cliente pague.
  const where = {
    caregiverId: profile.id,
    status: {
      notIn: [BookingStatus.PENDING_PAYMENT, BookingStatus.PAYMENT_PENDING_APPROVAL] as BookingStatus[],
    },
  };

  const [bookings, total] = await Promise.all([
    prisma.booking.findMany({
      where,
      include: {
        client: {
          select: {
            id: true,
            firstName: true,
            lastName: true,
            email: true,
            phone: true,
            profilePicture: true,
          },
        },
        dispute: true,
        meetAndGreet: true,
        bookingPets: true,
      },
      orderBy: { createdAt: 'desc' },
      skip,
      take: limit,
    }),
    prisma.booking.count({ where }),
  ]);

  return {
    bookings: bookings.map(bookingToResponse),
    pagination: { page, limit, total, pages: Math.ceil(total / limit) || 1 },
  };
}

/**
 * Cuidador acepta una reserva pagada.
 */
export async function acceptBooking(bookingId: string, caregiverUserId: string): Promise<BookingCreateResult> {
  return prisma.$transaction(async (tx) => {
    const profile = await tx.caregiverProfile.findFirst({
      where: { userId: caregiverUserId },
      select: { id: true },
    });
    if (!profile) throw new ForbiddenError('Perfil de cuidador no encontrado');

    const booking = await tx.booking.findFirst({
      where: { id: bookingId, caregiverId: profile.id },
    });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.status !== BookingStatus.WAITING_CAREGIVER_APPROVAL) {
      throw new BadRequestError('Esta reserva no está esperando aprobación del cuidador');
    }

    // Atomic transition — prevents double-accept race conditions
    const result = await tx.booking.updateMany({
      where: { id: bookingId, caregiverId: profile.id, status: BookingStatus.WAITING_CAREGIVER_APPROVAL },
      data: { status: BookingStatus.CONFIRMED },
    });
    if (result.count === 0) {
      throw new BadRequestError('Esta reserva ya fue procesada por otra acción simultánea');
    }

    const updated = await tx.booking.findFirst({
      where: { id: bookingId },
      include: {
        caregiver: { include: { user: { select: { id: true, firstName: true, lastName: true, email: true, profilePicture: true } } } },
        client: { select: { id: true, firstName: true, lastName: true, email: true, phone: true, profilePicture: true } },
      },
    });

    await tx.notification.create({
      data: {
        userId: booking.clientId,
        title: '¡Tu reserva fue aceptada! 🐾',
        message: `El cuidador aceptó tu reserva para ${booking.petName}. Ya está confirmada. Puedes ver los detalles en "Mis reservas".`,
        type: 'BOOKING_ACCEPTED',
      },
    });
    sendPushToUser(booking.clientId, '¡Tu reserva fue aceptada! 🐾', `El cuidador confirmó la reserva para ${booking.petName}.`).catch(() => {});

    notificationService.onBookingAccepted(bookingId).catch(err => {
      logger.error('Error sending onBookingAccepted notification', { bookingId, err });
    });

    return bookingToResponse(updated!);
  });
}

/**
 * Cuidador rechaza una reserva pagada.
 */
export async function rejectBooking(bookingId: string, caregiverUserId: string, reason: string): Promise<BookingCreateResult> {
  return prisma.$transaction(async (tx) => {
    const profile = await tx.caregiverProfile.findFirst({
      where: { userId: caregiverUserId },
      select: { id: true },
    });
    if (!profile) throw new ForbiddenError('Perfil de cuidador no encontrado');

    const booking = await tx.booking.findFirst({
      where: { id: bookingId, caregiverId: profile.id },
    });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.status !== BookingStatus.WAITING_CAREGIVER_APPROVAL) {
      throw new BadRequestError('Esta reserva no está esperando aprobación del cuidador');
    }

    // Atomic transition — prevents double-reject / race with client cancel
    const result = await tx.booking.updateMany({
      where: { id: bookingId, caregiverId: profile.id, status: BookingStatus.WAITING_CAREGIVER_APPROVAL },
      data: {
        status: BookingStatus.REJECTED_BY_CAREGIVER,
        cancellationReason: reason,
        refundStatus: RefundStatus.PENDING_APPROVAL,
        refundAmount: booking.totalAmount,
      },
    });
    if (result.count === 0) {
      throw new BadRequestError('Esta reserva ya fue procesada por otra acción simultánea');
    }

    const updated = await tx.booking.findFirst({ where: { id: bookingId } });

    // ── Auto-refund wallet portion if booking was paid (even partially) with wallet ─
    const walletPaid = Number(booking.walletPaymentAmount ?? 0);
    let walletRefundNote = '';
    if (walletPaid > 0) {
      const updatedClient = await tx.user.update({
        where: { id: booking.clientId },
        data: { balance: { increment: walletPaid } },
        select: { balance: true },
      });
      await tx.walletTransaction.create({
        data: {
          userId: booking.clientId,
          type: 'REFUND',
          amount: walletPaid,
          balance: Number(updatedClient.balance),
          description: `Reembolso — reserva rechazada por cuidador (${bookingId.slice(0, 8)})`,
          bookingId,
          status: 'COMPLETED',
        },
      });
      // Update booking to reflect wallet refund processed
      await tx.booking.update({
        where: { id: bookingId },
        data: { walletPaymentAmount: 0 },
      });
      walletRefundNote = ` Se reembolsaron Bs ${walletPaid.toFixed(2)} a tu billetera Garden automáticamente.`;
      logger.info('rejectBooking: wallet portion auto-refunded', { bookingId, walletPaid });
    }

    await tx.notification.create({
      data: {
        userId: booking.clientId,
        title: 'Reserva rechazada por el cuidador',
        message: `El cuidador no pudo aceptar tu reserva para ${booking.petName}. Motivo: ${reason}.${walletRefundNote}${walletPaid < Number(booking.totalAmount) ? ' El equipo de GARDEN gestionará el resto del reembolso en 1 día hábil.' : ''}`,
        type: 'BOOKING_REJECTED',
      },
    });
    sendPushToUser(booking.clientId, 'Reserva rechazada ❌', `El cuidador no pudo aceptar la reserva de ${booking.petName}.`).catch(() => {});

    await tx.adminNotification.create({
      data: {
        type: 'BOOKING_REJECTED_REFUND_NEEDED',
        caregiverId: profile.id,
        bookingId: booking.id,
      },
    });

    notificationService.onBookingRejected(bookingId, reason).catch(err => {
      logger.error('Error sending onBookingRejected notification', { bookingId, err });
    });

    return bookingToResponse(updated!);
  });
}
export async function startService(bookingId: string, caregiverUserId: string, photoUrl: string): Promise<BookingCreateResult> {
  if (!photoUrl || photoUrl.trim().length === 0) {
    throw new BadRequestError('Se requiere una foto de inicio del servicio');
  }

  return prisma.$transaction(async (tx) => {
    const profile = await tx.caregiverProfile.findFirst({ where: { userId: caregiverUserId } });
    if (!profile) throw new ForbiddenError('Perfil de cuidador no encontrado');

    const booking = await tx.booking.findFirst({ where: { id: bookingId, caregiverId: profile.id } });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.status !== BookingStatus.CONFIRMED) {
      throw new BadRequestError('El servicio solo puede iniciarse si está confirmado');
    }

    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        status: BookingStatus.IN_PROGRESS,
        serviceStartedAt: new Date(),
        serviceStartPhoto: photoUrl,
      },
    });

    // Notificación in-app al cliente
    await tx.notification.create({
      data: {
        userId: booking.clientId,
        title: '¡El servicio ha comenzado! 🐕',
        message: `El cuidador inició el servicio para ${booking.petName}. Puedes seguir el progreso en "Mis reservas".`,
        type: 'SERVICE_STARTED',
      },
    });
    sendPushToUser(booking.clientId, '¡El servicio ha comenzado! 🐕', `El cuidador está cuidando a ${booking.petName}.`).catch(() => {});
    notificationService.onServiceStarted(bookingId).catch(() => {});

    return bookingToResponse(updated);
  });
}

/** Allowed event types from caregiver during a service. */
const ALLOWED_EVENT_TYPES = ['INCIDENT', 'ACCIDENT', 'ILLNESS', 'COMPLICATION', 'NOTE', 'PHOTO', 'WALK_UPDATE', 'INCIDENT_RESOLVED'] as const;

export async function addServiceEvent(
  bookingId: string,
  caregiverUserId: string,
  type: string,
  description: string,
  photoUrl?: string,
  videoUrl?: string,
  incidentType?: string
): Promise<BookingCreateResult> {
  // Validate event type to prevent arbitrary string injection
  if (!ALLOWED_EVENT_TYPES.includes(type as any)) {
    throw new BadRequestError(`Tipo de evento inválido: ${type}. Tipos permitidos: ${ALLOWED_EVENT_TYPES.join(', ')}`);
  }
  // Validate description length
  if (!description || description.trim().length === 0) {
    throw new BadRequestError('La descripción del evento es obligatoria');
  }
  if (description.length > 1000) {
    throw new BadRequestError('La descripción no puede superar 1000 caracteres');
  }

  const profile = await prisma.caregiverProfile.findFirst({
    where: { userId: caregiverUserId },
  });
  if (!profile) throw new ForbiddenError('Perfil de cuidador no encontrado');

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, caregiverId: profile.id },
  });
  if (!booking) throw new BookingNotFoundError(bookingId);

  // Only allow events while service is in progress (completed bookings are read-only)
  if (booking.status !== BookingStatus.IN_PROGRESS) {
    throw new BadRequestError('Solo se pueden agregar eventos a servicios en curso');
  }
  if (type === 'INCIDENT_RESOLVED' && !booking.pausedAt) {
    throw new BadRequestError('No hay ninguna emergencia activa que resolver en esta reserva');
  }

  const events = (booking.serviceEvents as any[]) || [];
  events.push({
    type,
    description,
    photoUrl: photoUrl ?? null,
    videoUrl: videoUrl ?? null,
    incidentType: incidentType ?? null,
    timestamp: new Date().toISOString(),
  });

  // Datos de pausa a persistir junto al evento — única excepción donde el
  // tiempo del servicio se congela (ver calcOvertimeMinutes).
  const pauseData: { pausedAt?: Date | null; totalPausedMinutes?: number } = {};
  if ((type === 'INCIDENT' || type === 'ACCIDENT') && !booking.pausedAt) {
    pauseData.pausedAt = new Date();
  } else if (type === 'INCIDENT_RESOLVED' && booking.pausedAt) {
    const pausedMinutes = Math.round((Date.now() - booking.pausedAt.getTime()) / 60000);
    pauseData.pausedAt = null;
    pauseData.totalPausedMinutes = booking.totalPausedMinutes + pausedMinutes;
  }

  const updated = await prisma.booking.update({
    where: { id: bookingId },
    data: { serviceEvents: events, ...pauseData },
  });

  // Si es un incidente o accidente: notificar de URGENCIA al admin (quien
  // debe actuar), y al dueño con lenguaje tranquilo — no queremos generar
  // pánico en el dueño con algo que aún no sabemos qué tan grave es.
  if (type === 'INCIDENT' || type === 'ACCIDENT') {
    await prisma.notification.create({
      data: {
        userId: booking.clientId,
        title: '🐾 Novedad con tu mascota',
        message: description || 'Tu cuidador reportó una novedad durante el servicio. El equipo GARDEN ya está al tanto y acompañando la situación.',
        type: 'SERVICE_INCIDENT',
      },
    });
    sendPushToUser(
      booking.clientId,
      '🐾 Novedad con tu mascota',
      'Tu cuidador reportó algo durante el servicio y GARDEN ya está al tanto. Abre la app para ver los detalles.'
    ).catch(() => {});

    // Admin: lenguaje urgente — es quien debe intervenir si hace falta.
    await prisma.adminNotification.create({
      data: { type: 'SERVICE_INCIDENT_URGENT', caregiverId: booking.caregiverId, bookingId: booking.id },
    }).catch(() => {});
    sendPushToAdmins(
      '🚨 URGENTE: incidente en servicio activo',
      `Reserva ${bookingId.slice(0, 8).toUpperCase()} — ${incidentType ? `[${incidentType}] ` : ''}${description}`.slice(0, 180),
      { type: 'SERVICE_INCIDENT_URGENT', bookingId }
    ).catch(() => {});

    // Emitir al booking room (si el dueño está en el chat o en la pantalla del servicio)
    const io = getIO();
    if (io) {
      io.to(`booking:${bookingId}`).emit('incident_reported', {
        bookingId,
        description,
        timestamp: new Date().toISOString(),
      });
    }

    logger.info('Incident reported — admin notified urgently, client notified calmly, service timer paused', { bookingId, clientId: booking.clientId });
  }

  if (type === 'INCIDENT_RESOLVED') {
    sendPushToUser(
      booking.clientId,
      '✅ Todo en orden',
      'La novedad reportada durante el servicio ya fue resuelta. El servicio continúa con normalidad.'
    ).catch(() => {});
    logger.info('Incident resolved — service timer resumed', { bookingId, totalPausedMinutes: pauseData.totalPausedMinutes });
  }

  return bookingToResponse(updated);
}

function calcGpsDistance(points: { lat: number; lng: number }[]): number {
  let total = 0;
  for (let i = 1; i < points.length; i++) {
    const R = 6371000;
    const cur = points[i]!;
    const prev = points[i - 1]!;
    const dLat = (cur.lat - prev.lat) * Math.PI / 180;
    const dLng = (cur.lng - prev.lng) * Math.PI / 180;
    const a = Math.sin(dLat / 2) ** 2 +
      Math.cos(prev.lat * Math.PI / 180) * Math.cos(cur.lat * Math.PI / 180) *
      Math.sin(dLng / 2) ** 2;
    total += R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }
  return total;
}

/** Maximum GPS points stored per walk (prevents unbounded JSON growth). */
const GPS_MAX_POINTS = 2000;

export async function trackServiceLocation(
  bookingId: string,
  caregiverUserId: string,
  lat: number,
  lng: number,
  accuracy?: number
): Promise<void> {
  // Validate coordinate bounds before any DB operation
  if (typeof lat !== 'number' || isNaN(lat) || lat < -90 || lat > 90) {
    throw new BadRequestError('lat inválido: debe ser un número entre -90 y 90', 'INVALID_COORDS');
  }
  if (typeof lng !== 'number' || isNaN(lng) || lng < -180 || lng > 180) {
    throw new BadRequestError('lng inválido: debe ser un número entre -180 y 180', 'INVALID_COORDS');
  }

  const profile = await prisma.caregiverProfile.findFirst({ where: { userId: caregiverUserId } });
  if (!profile) throw new ForbiddenError('Perfil de cuidador no encontrado');

  const booking = await prisma.booking.findFirst({ where: { id: bookingId, caregiverId: profile.id } });
  if (!booking) throw new BookingNotFoundError(bookingId);
  if (booking.serviceType !== ServiceType.PASEO) throw new BadRequestError('GPS solo disponible para paseos (no guardería ni hospedaje)');

  // Guard: only track while the walk is actually in progress
  if (booking.status !== BookingStatus.IN_PROGRESS) {
    throw new BadRequestError('Solo se puede enviar GPS cuando el paseo está en curso');
  }

  const punto = { lat, lng, timestamp: new Date().toISOString(), accuracy: accuracy ?? 0 };
  let tracking: any[] = (booking.serviceTrackingData as any[]) || [];

  // Prevent unbounded growth: if we're at the cap, subsample older half and keep recent half
  if (tracking.length >= GPS_MAX_POINTS) {
    // Keep last 1000 points (recent history) to avoid losing the full route
    tracking = tracking.slice(-1000);
  }
  tracking.push(punto);

  await prisma.booking.update({
    where: { id: bookingId },
    data: { serviceTrackingData: tracking },
  });

  // Emit real-time GPS update via Socket.io (owner's live map receives this)
  const io = getIO();
  if (io) {
    io.to(`booking:${bookingId}`).emit('gps_update', punto);
  }
}

export async function getGpsTrack(bookingId: string, userId: string): Promise<any[]> {
  const booking = await prisma.booking.findFirst({
    where: {
      id: bookingId,
      OR: [
        { clientId: userId },
        { caregiver: { userId } },
      ],
    },
  });
  if (!booking) throw new BookingNotFoundError(bookingId);
  return (booking.serviceTrackingData as any[]) || [];
}

// ── Helper: calcular overtime al finalizar un servicio ──────────────────────
export function calcOvertimeMinutes(
  serviceType: ServiceType,
  serviceStartedAt: Date | null,
  duration: number | null,
  endDate: Date | null,
  concludedAt: Date,
  pausedMinutes: number = 0
): number {
  const GRACE_MINUTES = 15;

  if (serviceType === ServiceType.HOSPEDAJE) {
    if (!endDate) return 0;
    // endDate es @db.Date → llega como medianoche UTC (00:00 UTC = 20:00 Bolivia UTC-4).
    // "Medianoche Bolivia" del día siguiente = endDate + 24h (próxima 00:00 UTC) + 4h offset
    // = endDate + 28h. Eso sería 00:00 Bolivia del día endDate+1.
    // Usamos endDate + 24h como "inicio del día siguiente en UTC" — momento de checkout.
    const checkoutUTC = new Date(endDate.getTime() + 24 * 60 * 60 * 1000); // 00:00 UTC del día después
    const diffMs = concludedAt.getTime() - checkoutUTC.getTime();
    const diffMins = Math.max(0, Math.floor(diffMs / 60_000) - pausedMinutes);
    return Math.max(0, diffMins - GRACE_MINUTES);
  }

  // PASEO / GUARDERÍA
  if (!serviceStartedAt || !duration) return 0;
  const expectedEndMs = serviceStartedAt.getTime() + duration * 60_000;
  const diffMs = concludedAt.getTime() - expectedEndMs;
  const diffMins = Math.max(0, Math.floor(diffMs / 60_000) - pausedMinutes);
  return Math.max(0, diffMins - GRACE_MINUTES);
}

/**
 * El dueño marca (desde su lado) que el servicio ya terminó. No concluye la
 * reserva ni libera el pago — el cuidador sigue teniendo que subir sus fotos
 * en concludeService() para eso — pero congela el reloj del overtime en este
 * instante (ver uso de clientMarkedEndAt en concludeService).
 */
export async function markServiceEndedByClient(
  bookingId: string,
  clientId: string
): Promise<BookingCreateResult> {
  const markedAt = new Date();

  return prisma.$transaction(async (tx) => {
    const booking = await tx.booking.findFirst({
      where: { id: bookingId, clientId },
      include: { caregiver: { select: { userId: true } } },
    });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.status !== BookingStatus.IN_PROGRESS) {
      throw new BadRequestError('El servicio debe estar en curso para marcarlo como terminado');
    }
    if (booking.clientMarkedEndAt) {
      throw new BadRequestError('Ya marcaste este servicio como terminado');
    }

    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: { clientMarkedEndAt: markedAt },
    });

    await tx.notification.create({
      data: {
        userId: booking.caregiver.userId,
        title: 'El dueño marcó el servicio como terminado',
        message: `El dueño de ${booking.petName ?? 'la mascota'} indicó que el servicio ya terminó. Sube tus fotos finales para cerrar el servicio y recibir tu pago.`,
        type: 'SYSTEM',
      },
    });
    sendPushToUser(
      booking.caregiver.userId,
      'El dueño marcó el servicio como terminado',
      'Sube tus fotos finales para cerrar el servicio y cobrar'
    ).catch(() => {});

    return bookingToResponse(updated);
  });
}

export async function concludeService(
  bookingId: string,
  caregiverUserId: string,
  photoUrl: string,
  lat: number | null,
  lng: number | null
): Promise<BookingCreateResult> {
  const concludedAt = new Date();

  return prisma.$transaction(async (tx) => {
    const profile = await tx.caregiverProfile.findFirst({ where: { userId: caregiverUserId } });
    if (!profile) throw new ForbiddenError('Perfil de cuidador no encontrado');

    const booking = await tx.booking.findFirst({ where: { id: bookingId, caregiverId: profile.id } });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.status !== BookingStatus.IN_PROGRESS) {
      throw new BadRequestError('El servicio debe estar en curso para concluirlo');
    }

    // Validar fotos mínimas server-side (PASEO=2, otros=3)
    const events = (booking.serviceEvents as any[]) || [];
    const photoEvents = events.filter((e: any) => e.type === 'PHOTO');
    const minPhotos = booking.serviceType === ServiceType.PASEO ? 2 : 3;
    if (photoEvents.length < minPhotos) {
      throw new BookingValidationError(
        `Debes subir al menos ${minPhotos} fotos antes de finalizar el servicio. Llevas ${photoEvents.length}.`
      );
    }

    const tracking = (booking.serviceTrackingData as any[]) || [];
    if (lat && lng) tracking.push({ lat, lng, timestamp: concludedAt, type: 'END' });
    const gpsDistance = booking.serviceType === ServiceType.PASEO ? calcGpsDistance(tracking) : null;

    // ── Calcular overtime ──────────────────────────────────────────────────────
    // Si el dueño marcó "servicio terminado" (markServiceEndedByClient) antes de
    // que el cuidador suba sus fotos, el overtime se congela en ese instante —
    // el cuidador puede tardar en subir fotos sin que eso siga generando cargo.
    const overtimeClockEnd = booking.clientMarkedEndAt && booking.clientMarkedEndAt < concludedAt
      ? booking.clientMarkedEndAt
      : concludedAt;
    // Si sigue pausado por una emergencia sin resolver al momento de concluir,
    // ese tramo (desde que se pausó hasta ahora) tampoco cuenta como overtime.
    const activePauseMinutes = booking.pausedAt
      ? Math.max(0, Math.round((overtimeClockEnd.getTime() - booking.pausedAt.getTime()) / 60_000))
      : 0;
    const overtimeMins = calcOvertimeMinutes(
      booking.serviceType,
      booking.serviceStartedAt,
      booking.duration,
      booking.endDate,
      overtimeClockEnd,
      booking.totalPausedMinutes + activePauseMinutes
    );

    let overtimeFeeGross = 0;
    let overtimeFeeCaregiver = 0;
    const cfg = await getBookingSettings();

    if (overtimeMins > 0) {
      // Tarifa por minuto basada en lo que pagó el cliente (prorrateado del total)
      let ratePerMin: number;
      if (booking.serviceType === ServiceType.HOSPEDAJE) {
        const totalDays = Number(booking.totalDays ?? 1);
        ratePerMin = Number(booking.totalAmount) / (totalDays * 24 * 60);
      } else {
        // PASEO / GUARDERÍA: precio por minuto del servicio contratado
        ratePerMin = Number(booking.totalAmount) / Number(booking.duration ?? 60);
      }
      overtimeFeeGross    = Math.round(overtimeMins * ratePerMin * 100) / 100;
      overtimeFeeCaregiver = Math.round(overtimeFeeGross * (1 - cfg.COMMISSION_RATE) * 100) / 100;

      // Cobrar al cliente (puede quedar negativo — se recupera en la próxima reserva)
      const updatedClient = await tx.user.update({
        where: { id: booking.clientId },
        data: { balance: { decrement: overtimeFeeGross } },
        select: { balance: true },
      });
      await tx.walletTransaction.create({
        data: {
          userId: booking.clientId,
          type: 'OVERTIME_FEE',
          amount: overtimeFeeGross,
          balance: Number(updatedClient.balance),
          description: `Cargo por tiempo extra — ${overtimeMins} min sobre el horario acordado (${bookingId.slice(0, 8)})`,
          bookingId,
          status: 'COMPLETED',
        },
      });

      // Pagar al cuidador su parte del overtime
      const updatedCaregiver = await tx.user.update({
        where: { id: profile.userId },
        data: { balance: { increment: overtimeFeeCaregiver } },
        select: { balance: true },
      });
      await tx.walletTransaction.create({
        data: {
          userId: profile.userId,
          type: 'OVERTIME_EARNING',
          amount: overtimeFeeCaregiver,
          balance: Number(updatedCaregiver.balance),
          description: `Pago por espera extra — ${overtimeMins} min (${bookingId.slice(0, 8)})`,
          bookingId,
          status: 'COMPLETED',
        },
      });

      // Notificar al cliente del cargo
      const svcLabel = booking.serviceType === ServiceType.PASEO ? 'paseo'
                     : booking.serviceType === ServiceType.GUARDERIA ? 'guardería' : 'hospedaje';
      const balanceAfter = Number(updatedClient.balance);
      const balanceMsg = balanceAfter < 0
        ? ` Tu billetera quedó en Bs ${balanceAfter.toFixed(2)} — este saldo se sumará a tu próxima reserva.`
        : ` Se descontaron Bs ${overtimeFeeGross.toFixed(2)} de tu billetera.`;
      await tx.notification.create({
        data: {
          userId: booking.clientId,
          title: '⏰ Cargo por tiempo extra',
          message: `El ${svcLabel} de ${booking.petName ?? 'tu mascota'} se extendió ${overtimeMins} min sobre el tiempo contratado (incluidos 15 min de gracia gratuita). Cargo: Bs ${overtimeFeeGross.toFixed(2)}.${balanceMsg}`,
          type: 'SYSTEM',
        },
      });
      sendPushToUser(
        booking.clientId,
        '⏰ Cargo por tiempo extra',
        `${overtimeMins} min extra · Bs ${overtimeFeeGross.toFixed(2)} cargados a tu billetera`
      ).catch(() => {});
    }

    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        status: BookingStatus.COMPLETED,
        serviceEndedAt: concludedAt,
        serviceEndPhoto: photoUrl,
        serviceTrackingData: tracking,
        gpsDistance,
        overtimeMinutes:  overtimeMins,
        overtimeFeeAmount: overtimeFeeGross,
      },
    });

    // Notificación de servicio completado + pedido de calificación
    const ratingMsg = `El cuidador finalizó el servicio de ${booking.petName}. ¡Califica para que reciba su pago!`;
    await tx.notification.create({
      data: {
        userId: booking.clientId,
        title: 'Servicio finalizado ✅ — Califica ahora',
        message: ratingMsg,
        type: 'SERVICE_COMPLETED',
      },
    });
    sendPushToUser(booking.clientId, 'Servicio finalizado ✅', '⭐ Tu calificación libera el pago al cuidador').catch(() => {});
    notificationService.onServiceCompleted(bookingId).catch(() => {});

    auditLog({
      userId: caregiverUserId,
      action: 'BOOKING_COMPLETED',
      entity: 'Booking',
      entityId: bookingId,
      details: { serviceType: booking.serviceType, gpsDistance, overtimeMins, overtimeFeeGross },
    });

    return bookingToResponse(updated);
  });
}

export async function confirmReceiptByClient(
  bookingId: string,
  clientId: string,
  rating: number,
  comment?: string
): Promise<BookingCreateResult> {
  // Validate rating before any DB operation
  const ratingNum = Number(rating);
  if (!Number.isInteger(ratingNum) || ratingNum < 1 || ratingNum > 5) {
    throw new BadRequestError('La calificación debe ser un número entero entre 1 y 5', 'INVALID_RATING');
  }
  if (comment && comment.length > 1000) {
    throw new BadRequestError('El comentario no puede superar 1000 caracteres');
  }

  return prisma.$transaction(async (tx) => {
    const booking = await tx.booking.findFirst({
      where: { id: bookingId, clientId },
      include: { caregiver: true }
    });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.status !== BookingStatus.COMPLETED) {
      throw new BadRequestError('El servicio debe estar marcado como completado por el cuidador');
    }
    if (booking.ownerRated) {
      throw new BadRequestError('Ya calificaste este servicio');
    }
    if (booking.payoutStatus === 'ON_HOLD') {
      throw new BadRequestError('Hay una disputa activa para esta reserva. No se puede calificar nuevamente.');
    }
    if (booking.payoutStatus === 'PAID') {
      throw new BadRequestError('El pago ya fue procesado');
    }

    if (rating < 3) {
      // Atomic claim: only succeeds if ownerRated is still false at write time.
      // Prevents double-submission race conditions.
      const claimed = await tx.booking.updateMany({
        where: { id: bookingId, clientId, ownerRated: false, payoutStatus: 'PENDING' },
        data: {
          payoutStatus: 'ON_HOLD',
          ownerRated: true,
          ownerRating: rating,
          ownerComment: comment,
        },
      });
      if (claimed.count === 0) {
        throw new BadRequestError('Ya calificaste este servicio');
      }

      // Alert admin — low-rating bookings need manual review before payout is released.
      await tx.adminNotification.create({
        data: {
          type: 'LOW_RATING',
          caregiverId: booking.caregiverId,
          bookingId,
        },
      }).catch(() => {}); // don't let notification failure roll back the transaction

      const updated = await tx.booking.findUnique({ where: { id: bookingId } });
      return bookingToResponse(updated!);
    }

    // Calcular el monto a transferir (Total - Comisión)
    const amount = Number(booking.totalAmount) - Number(booking.commissionAmount);

    // Leer userId del cuidador para acceder a la billetera unificada
    const caregiverProfile = await tx.caregiverProfile.findUnique({
      where: { id: booking.caregiverId },
      select: { userId: true },
    });
    const caregiverUserId = caregiverProfile!.userId;

    // Actualizar balance unificado del cuidador (atómico)
    const updatedCaregiverUser = await tx.user.update({
      where: { id: caregiverUserId },
      data: { balance: { increment: amount } },
      select: { balance: true },
    });
    const newCaregiverBalance = Number(updatedCaregiverUser.balance);

    await tx.walletTransaction.create({
      data: {
        userId: caregiverUserId,
        type: 'EARNING',
        amount: amount,
        balance: newCaregiverBalance,
        description: `Ganancia por ${booking.serviceType === 'PASEO' ? 'paseo' : booking.serviceType === 'GUARDERIA' ? 'guardería' : 'hospedaje'} - ${booking.petName}`,
        bookingId: booking.id,
        status: 'COMPLETED',
      },
    });

    // Atomic claim for the payout path — ensures exactly one request wins the race.
    const claimed = await tx.booking.updateMany({
      where: { id: bookingId, clientId, ownerRated: false, payoutStatus: 'PENDING' },
      data: {
        payoutStatus: 'PAID',
        ownerRated: true,
        ownerRating: rating,
        ownerComment: comment,
      },
    });
    if (claimed.count === 0) {
      throw new BadRequestError('Ya calificaste este servicio');
    }
    const updated = await tx.booking.findUnique({ where: { id: bookingId } });

    sendPushToUser(caregiverUserId, '¡Pago liberado! 💸', `Recibiste el pago por el servicio de ${booking.petName}. Revisa tu billetera.`).catch(() => {});
    notificationService.onRatingReceived(bookingId, rating, comment).catch(() => {});

    // Create Review natively
    await tx.review.create({
      data: {
        bookingId: booking.id,
        clientId: clientId,
        caregiverId: booking.caregiverId,
        rating: rating,
        comment: comment,
        serviceType: booking.serviceType,
      }
    });

    // Update Caregiver Average Rating — excluir reseñas de sistema (auto-release)
    const result = await tx.review.aggregate({
      where: { caregiverId: booking.caregiverId, isSystemGenerated: false },
      _avg: { rating: true },
      _count: { id: true },
    });
    
    await tx.caregiverProfile.update({
      where: { id: booking.caregiverId },
      data: {
        rating: result._avg.rating || rating,
        reviewCount: result._count.id || 1,
      }
    });

    // Registro en Blockchain (asíncrono) - Liberar calificación
    blockchainService.finalizeBookingOnChain(bookingId, rating).then(async (txHash) => {
      if (txHash) {
        await prisma.booking.update({ where: { id: bookingId }, data: { blockchainFinalizedTxHash: txHash } });
        logger.info('[Blockchain] finalize txHash saved', { bookingId, txHash });
      }
    }).catch(err => {
      logger.error('Blockchain completion failed', { bookingId, err });
    });

    return bookingToResponse(updated!);
  });
}

/**
 * Libera el pago al cuidador automáticamente tras el vencimiento del período de reseña.
 * A diferencia de confirmReceiptByClient, NO crea una Review ni actualiza el rating del cuidador,
 * ya que el cliente nunca eligió calificar — el sistema solo libera los fondos.
 * Se llama desde el cron de auto-release en server.ts.
 */
export async function autoReleasePayment(
  bookingId: string,
  horasVencimiento: number
): Promise<void> {
  await prisma.$transaction(async (tx) => {
    const booking = await tx.booking.findFirst({
      where: {
        id: bookingId,
        status: BookingStatus.COMPLETED,
        ownerRated: false,
        payoutStatus: 'PENDING',
      },
      include: { caregiver: true },
    });
    if (!booking) return; // ya procesado o estado cambió (race-safe)

    // Atomic claim ANTES de tocar el balance — evita doble pago si este job
    // corre superpuesto con autoPayoutExpiredReviews() u otro release para
    // la misma reserva (ambos leen con guard pero antes escribían sin él).
    const claimed = await tx.booking.updateMany({
      where: { id: bookingId, status: BookingStatus.COMPLETED, ownerRated: false, payoutStatus: 'PENDING' },
      data: { payoutStatus: 'PAID', ownerRated: true },
    });
    if (claimed.count === 0) return; // otro proceso ya lo liberó

    const amount = Number(booking.totalAmount) - Number(booking.commissionAmount);

    const caregiverProfileAR = await tx.caregiverProfile.findUnique({
      where: { id: booking.caregiverId },
      select: { userId: true },
    });
    const caregiverUserIdAR = caregiverProfileAR!.userId;

    const updatedUserAR = await tx.user.update({
      where: { id: caregiverUserIdAR },
      data: { balance: { increment: amount } },
      select: { balance: true },
    });

    await tx.walletTransaction.create({
      data: {
        userId: caregiverUserIdAR,
        type: 'EARNING',
        amount,
        balance: Number(updatedUserAR.balance),
        description: `Auto-liberación tras ${horasVencimiento}h — ${booking.petName} (sin reseña del cliente)`,
        bookingId: booking.id,
        status: 'COMPLETED',
      },
    });

    // Crear reseña de sistema para mantener historial completo.
    // No se incluye en el promedio del cuidador (isSystemGenerated=true, sin puntuación numérica).
    await tx.review.create({
      data: {
        bookingId: booking.id,
        clientId:  booking.clientId,
        caregiverId: booking.caregiverId,
        rating: null as unknown as number, // null → no afecta promedio
        comment: null,
        serviceType: booking.serviceType,
        isSystemGenerated: true,
      },
    }).catch(() => {
      // Si el campo isSystemGenerated aún no existe en schema viejo, no bloquear el release.
    });

    sendPushToUser(
      caregiverUserIdAR,
      '💸 Pago liberado automáticamente',
      `El pago de Bs ${amount.toFixed(2)} por el servicio de ${booking.petName} fue liberado (el cliente no dejó reseña).`
    ).catch(() => {});
  });

  // Blockchain: solo finalizar si aún no tiene txHash (idempotencia — evita doble registro)
  const bookingForChain = await prisma.booking.findUnique({
    where: { id: bookingId },
    select: { blockchainFinalizedTxHash: true },
  });
  if (!bookingForChain?.blockchainFinalizedTxHash) {
    blockchainService.finalizeBookingOnChain(bookingId, 5).then(async (txHash) => {
      if (txHash) {
        await prisma.booking.update({ where: { id: bookingId }, data: { blockchainFinalizedTxHash: txHash } });
        logger.info('[Blockchain] auto-release finalize txHash saved', { bookingId, txHash });
      }
    }).catch(err => {
      logger.error('[AutoRelease] Blockchain finalize failed', { bookingId, err });
    });
  } else {
    logger.info('[Blockchain] auto-release skipped — already finalized', { bookingId });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REPORT BOOKING — Dueño reporta que el cuidador no se presentó
// ─────────────────────────────────────────────────────────────────────────────

/** Minutos de gracia tras la hora programada antes de poder reportar. */
const REPORT_GRACE_PASEO_MIN    = 10;
const REPORT_GRACE_DEFAULT_MIN  = 30;
const FINE_PERCENT              = 0.20; // 20 % del totalAmount como multa

/**
 * Dueño reporta incumplimiento del cuidador (no se presentó/no inició el servicio).
 *
 * Flujo:
 *  1. Valida que la reserva sea CONFIRMED, le pertenezca al cliente y haya pasado el tiempo de gracia.
 *  2. Crea ServiceReport.
 *  3. Reembolsa (totalAmount - commissionAmount) a la billetera del dueño.
 *  4. Cancela la reserva.
 *  5. Si es la primera infracción del cuidador → WARNING; si tiene más → FINE (20% del totalAmount).
 *  6. Notifica a ambas partes.
 */
export async function reportBooking(
  bookingId: string,
  clientId: string,
  reasons: string[],
  details?: string
): Promise<{ refundAmount: number; infractionType: 'WARNING' | 'FINE' }> {
  return prisma.$transaction(async (tx) => {
    // ── 1. Fetch booking ────────────────────────────────────────────────────
    const booking = await tx.booking.findFirst({
      where: { id: bookingId, clientId },
      select: {
        id: true,
        status: true,
        serviceType: true,
        walkDate: true,
        startDate: true,
        startTime: true,
        totalAmount: true,
        commissionAmount: true,
        petName: true,
        caregiverId: true,
        caregiver: { select: { id: true, userId: true, infractionCount: true } },
        serviceReport: { select: { id: true } },
      },
    });

    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.status !== BookingStatus.CONFIRMED) {
      throw new BookingValidationError(
        'Solo puedes reportar una reserva que esté confirmada y aún no haya iniciado.'
      );
    }
    if (booking.serviceReport) {
      throw new BookingValidationError('Esta reserva ya tiene un reporte registrado.');
    }

    // ── 2. Verify grace period has passed ───────────────────────────────────
    const isPaseo  = booking.serviceType === 'PASEO';
    const graceMins = isPaseo ? REPORT_GRACE_PASEO_MIN : REPORT_GRACE_DEFAULT_MIN;
    const dateStr = booking.walkDate
      ? booking.walkDate.toISOString().split('T')[0]
      : booking.startDate?.toISOString().split('T')[0];

    if (!dateStr) {
      throw new BookingValidationError('La reserva no tiene fecha programada.');
    }

    const dateParts = dateStr.split('-').map(Number);
    const year = dateParts[0]!;
    const month = dateParts[1]!;
    const day = dateParts[2]!;
    // HOSPEDAJE no almacena startTime — se usa mediodía como hora de inicio por defecto
    const defaultTime = booking.serviceType === 'HOSPEDAJE' ? '12:00' : '08:00';
    const timeStr = booking.startTime ?? defaultTime;
    const timeParts = timeStr.split(':').map(Number);
    const hour = timeParts[0] ?? (booking.serviceType === 'HOSPEDAJE' ? 12 : 8);
    const minute = timeParts[1] ?? 0;
    const scheduledAt = new Date(year, month - 1, day, hour, minute);
    const reportAvailableAt = new Date(scheduledAt.getTime() + graceMins * 60_000);

    if (new Date() < reportAvailableAt) {
      const diffMs = reportAvailableAt.getTime() - Date.now();
      const diffMins = Math.ceil(diffMs / 60_000);
      throw new BookingValidationError(
        `Aún no puedes reportar. El botón estará disponible ${diffMins} min después de la hora programada.`
      );
    }

    // ── 3. Calculate refund ─────────────────────────────────────────────────
    const totalAmount      = Number(booking.totalAmount);
    const commissionAmount = Number(booking.commissionAmount);
    const refundAmount     = totalAmount - commissionAmount; // Garden keeps its commission

    // ── 4. Refund to client wallet ──────────────────────────────────────────
    const updatedClient = await tx.user.update({
      where: { id: clientId },
      data: { balance: { increment: refundAmount } },
      select: { balance: true },
    });
    await tx.walletTransaction.create({
      data: {
        userId: clientId,
        type: 'REFUND',
        amount: refundAmount,
        balance: Number(updatedClient.balance),
        description: `Reembolso por incumplimiento del cuidador — reserva ${bookingId.slice(0, 8)}`,
        bookingId,
        status: 'COMPLETED',
      },
    });

    // ── 5. Cancel booking ────────────────────────────────────────────────────
    await tx.booking.update({
      where: { id: bookingId },
      data: {
        status: BookingStatus.CANCELLED,
        cancelledAt: new Date(),
        cancellationReason: `Reporte del dueño: ${reasons.join(', ')}`,
        refundAmount: refundAmount,
        refundStatus: 'PROCESSED' as any,
      },
    });

    // ── 6. Create service report ─────────────────────────────────────────────
    await tx.serviceReport.create({
      data: {
        bookingId,
        clientId,
        reasons,
        details,
        status: 'REFUNDED',
        refundAmount: refundAmount,
        refundedAt: new Date(),
      },
    });

    // ── 7. Determine warning vs fine ─────────────────────────────────────────
    const previousInfractions = booking.caregiver.infractionCount;
    const infractionType: 'WARNING' | 'FINE' = previousInfractions === 0 ? 'WARNING' : 'FINE';
    let fineAmount: number | undefined;

    if (infractionType === 'FINE') {
      fineAmount = Math.round(totalAmount * FINE_PERCENT);
      // Deduct fine from caregiver wallet (floor at 0)
      const caregiverUser = await tx.user.findUnique({
        where: { id: booking.caregiver.userId },
        select: { balance: true },
      });
      const caregiverBalance = Number(caregiverUser?.balance ?? 0);
      const actualFine = Math.min(fineAmount, caregiverBalance); // can't go negative
      if (actualFine > 0) {
        const updatedCaregiver = await tx.user.update({
          where: { id: booking.caregiver.userId },
          data: { balance: { decrement: actualFine } },
          select: { balance: true },
        });
        await tx.walletTransaction.create({
          data: {
            userId: booking.caregiver.userId,
            type: 'FINE',
            amount: actualFine,
            balance: Number(updatedCaregiver.balance),
            description: `Multa por incumplimiento — reserva ${bookingId.slice(0, 8)} (${FINE_PERCENT * 100}% de Bs ${totalAmount})`,
            bookingId,
            status: 'COMPLETED',
          },
        });
        fineAmount = actualFine;
      }
    }

    // ── 8. Create infraction record ──────────────────────────────────────────
    await tx.caregiverInfraction.create({
      data: {
        caregiverId: booking.caregiver.id,
        bookingId,
        type: infractionType,
        fineAmount: fineAmount ? fineAmount : null,
        bookingAmount: totalAmount,
        reasons,
      },
    });
    await tx.caregiverProfile.update({
      where: { id: booking.caregiver.id },
      data: { infractionCount: { increment: 1 } },
    });

    // ── 9. Notifications ─────────────────────────────────────────────────────
    // To client: confirm refund
    await tx.notification.create({
      data: {
        userId: clientId,
        title: '✅ Reembolso procesado',
        message:
          `Hemos recibido tu reporte y procesado un reembolso de Bs ${refundAmount} a tu billetera Garden. ` +
          `El monto ya está disponible. Lamentamos los inconvenientes.`,
        type: 'REFUND',
      },
    });

    // To caregiver: warning or fine
    const caregiverMsg = infractionType === 'WARNING'
      ? `⚠️ Has recibido una advertencia por no presentarte al servicio "${booking.petName}" ` +
        `(reserva ${bookingId.slice(0, 8)}). ` +
        `Motivos reportados: ${reasons.join(', ')}. ` +
        `Recuerda que en futuras ocasiones recibirás una multa automática del ${FINE_PERCENT * 100}% del monto de la reserva. ` +
        `Por favor, comunícate siempre con el cliente ante cualquier imprevisto.`
      : `🚫 Se ha aplicado una multa de Bs ${fineAmount ?? 0} a tu billetera por no presentarte al servicio ` +
        `"${booking.petName}" (reserva ${bookingId.slice(0, 8)}). ` +
        `Motivos: ${reasons.join(', ')}. ` +
        `Por favor, cumple siempre con tus compromisos o cancela con anticipación.`;

    await tx.notification.create({
      data: {
        userId: booking.caregiver.userId,
        title: infractionType === 'WARNING' ? '⚠️ Advertencia por incumplimiento' : '🚫 Multa por incumplimiento',
        message: caregiverMsg,
        type: 'SYSTEM',
      },
    });

    logger.info('Booking reported by client', {
      bookingId,
      clientId,
      reasons,
      refundAmount,
      infractionType,
      fineAmount,
    });

    return { refundAmount, infractionType };
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Caregiver rates the owner (client) after service completion
// ─────────────────────────────────────────────────────────────────────────────
export async function rateOwner(
  bookingId: string,
  caregiverUserId: string,
  rating: number,
  comment?: string
): Promise<BookingCreateResult> {
  const ratingNum = Number(rating);
  if (!Number.isInteger(ratingNum) || ratingNum < 1 || ratingNum > 5) {
    throw new BadRequestError('La calificación debe ser un número entero entre 1 y 5', 'INVALID_RATING');
  }
  if (comment && comment.length > 1000) {
    throw new BadRequestError('El comentario no puede superar 1000 caracteres');
  }

  const caregiverProfile = await prisma.caregiverProfile.findFirst({
    where: { user: { id: caregiverUserId } },
    select: { id: true },
  });
  if (!caregiverProfile) throw new BadRequestError('Perfil de cuidador no encontrado');

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, caregiverId: caregiverProfile.id },
  });
  if (!booking) throw new BookingNotFoundError(bookingId);
  if (booking.status !== BookingStatus.COMPLETED) {
    throw new BadRequestError('El servicio debe estar completado para calificar al dueño');
  }
  if (booking.caregiverRated) {
    throw new BadRequestError('Ya calificaste a este dueño para esta reserva');
  }

  // Atomic claim — el chequeo de arriba era leer-comparar-escribir en pasos
  // separados; dos llamadas concurrentes (doble-tap, reintento) podían pasar
  // ambas el chequeo antes de que la primera escribiera, y la segunda
  // pisaba en silencio la calificación de la primera sin ningún error.
  const claimed = await prisma.booking.updateMany({
    where: { id: bookingId, caregiverId: caregiverProfile.id, caregiverRated: false },
    data: {
      caregiverRated: true,
      caregiverRating: ratingNum,
      caregiverComment: comment ?? null,
    },
  });
  if (claimed.count === 0) {
    throw new BadRequestError('Ya calificaste a este dueño para esta reserva');
  }

  const updated = await prisma.booking.findUniqueOrThrow({ where: { id: bookingId } });
  return bookingToResponse(updated);
}

/**
 * El cliente elige una nueva hora/fecha tras detectar SLOT_CONFLICT.
 * El pago ya está hecho; se reutiliza para la nueva reserva sin cargo adicional.
 */
export async function resolveSlotConflict(
  bookingId: string,
  clientId: string,
  newData: {
    newWalkDate?: string;
    newTimeSlot?: string;
    newStartDate?: string;
    newEndDate?: string;
  }
): Promise<{ bookingId: string; status: string }> {
  return prisma.$transaction(async (tx) => {
    const booking = await tx.booking.findFirst({
      where: { id: bookingId, clientId, status: BookingStatus.SLOT_CONFLICT },
      select: {
        id: true,
        serviceType: true,
        caregiverId: true,
        petCount: true,
        clientId: true,
      },
    });
    if (!booking) throw new BookingNotFoundError(bookingId);

    let updateData: Record<string, unknown> = {
      status: BookingStatus.WAITING_CAREGIVER_APPROVAL,
    };

    if (booking.serviceType === 'PASEO') {
      if (!newData.newWalkDate || !newData.newTimeSlot) {
        throw new BookingValidationError('Debes indicar nueva fecha y bloque horario para el paseo');
      }
      await assertPaseoAvailability(
        tx,
        booking.caregiverId,
        newData.newWalkDate,
        newData.newTimeSlot as TimeSlot,
        null,
        null,
        booking.petCount
      );
      updateData.walkDate = new Date(newData.newWalkDate);
      updateData.timeSlot = newData.newTimeSlot;
    } else {
      if (!newData.newStartDate || !newData.newEndDate) {
        throw new BookingValidationError('Debes indicar nueva fecha de inicio y fin');
      }
      await assertHospedajeAvailability(
        tx,
        booking.caregiverId,
        newData.newStartDate,
        newData.newEndDate,
        booking.petCount
      );
      updateData.startDate = new Date(newData.newStartDate);
      updateData.endDate = new Date(newData.newEndDate);
    }

    await tx.booking.update({ where: { id: bookingId }, data: updateData });

    logger.info('Slot conflict resolved — new slot chosen', {
      bookingId,
      clientId,
      serviceType: booking.serviceType,
      newData,
    });

    return { bookingId, status: BookingStatus.WAITING_CAREGIVER_APPROVAL };
  });
}

/** Devuelve la primera reserva COMPLETED sin calificar del cliente (para el modal al abrir app). */
export async function getPendingRatingBooking(clientId: string) {
  const booking = await prisma.booking.findFirst({
    where: {
      clientId,
      status: BookingStatus.COMPLETED,
      ownerRated: false,
      payoutStatus: 'PENDING',
    },
    orderBy: { updatedAt: 'desc' },
    select: {
      id: true,
      serviceType: true,
      petName: true,
      updatedAt: true,
      caregiver: { select: { user: { select: { firstName: true, lastName: true } } } },
    },
  });
  return booking;
}

/**
 * Auto-desembolso: libera el pago al cuidador si el dueño no calificó en 48h tras
 * que el cuidador marcó el servicio como completado.
 *
 * Antes usaba `updatedAt` como proxy de "cuándo se completó" — pero updatedAt
 * se actualiza en CUALQUIER cambio a la fila (no solo al completar), así que
 * un update no relacionado (ej. otro proceso tocando la reserva) reiniciaba
 * silenciosamente la ventana de 48h sin que el cliente lo supiera. Ahora usa
 * serviceEndedAt, que solo se setea una vez, exactamente cuando el cuidador
 * concluye el servicio (ver línea ~3283, concludeService).
 */
export async function autoPayoutExpiredReviews() {
  const cutoff = new Date(Date.now() - 48 * 60 * 60 * 1000);
  const expired = await prisma.booking.findMany({
    where: {
      status: BookingStatus.COMPLETED,
      ownerRated: false,
      payoutStatus: 'PENDING',
      OR: [
        { serviceEndedAt: { lt: cutoff } },
        // Fallback defensivo: si por algún camino alterno una reserva llegó
        // a COMPLETED sin que se seteara serviceEndedAt, no debe quedar
        // huérfana para siempre — usa updatedAt como respaldo en ese caso.
        { serviceEndedAt: null, updatedAt: { lt: cutoff } },
      ],
    },
    include: { caregiver: { select: { userId: true } } },
  });

  for (const booking of expired) {
    try {
      const amount = Number(booking.totalAmount) - Number(booking.commissionAmount);
      await prisma.$transaction(async (tx) => {
        // Atomic claim ANTES de tocar el balance — evita doble pago si este job
        // corre superpuesto con autoReleasePayment() (cron horario, 24h por
        // defecto) para la misma reserva.
        const claimed = await tx.booking.updateMany({
          where: { id: booking.id, payoutStatus: 'PENDING' },
          data: { payoutStatus: 'PAID' },
        });
        if (claimed.count === 0) return; // otro proceso ya lo liberó

        const updatedUser = await tx.user.update({
          where: { id: booking.caregiver.userId },
          data: { balance: { increment: amount } },
          select: { balance: true },
        });
        await tx.walletTransaction.create({
          data: {
            userId: booking.caregiver.userId,
            type: 'EARNING',
            amount,
            balance: Number(updatedUser.balance),
            description: `Pago automático (sin calificación) — ${booking.petName}`,
            bookingId: booking.id,
            status: 'COMPLETED',
          },
        });
      });
      logger.info('[AutoPayout] Desembolso automático completado', { bookingId: booking.id, amount });
    } catch (err) {
      logger.error('[AutoPayout] Error en desembolso automático', { bookingId: booking.id, err });
    }
  }

  return expired.length;
}

/**
 * Confirma el pago de una extensión de servicio vía callback SIP (server-to-server).
 * No requiere clientId — la autenticación es Basic Auth en el endpoint confirmarPago.
 * Compatible con extensiones de paseo (additionalMinutes) y hospedaje (additionalDays).
 * Idempotente: si el evento ya fue confirmado, retorna sin error.
 */
export async function confirmExtensionQrBySip(bookingId: string, qrId: string): Promise<void> {
  const cfg = await getBookingSettings();

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId },
    select: {
      id: true, clientId: true, caregiverId: true, serviceType: true, status: true,
      duration: true, endDate: true, totalDays: true,
      totalAmount: true, commissionAmount: true, pricePerUnit: true,
      petName: true, serviceEvents: true,
    },
  });

  if (!booking) throw new BookingNotFoundError(bookingId);
  if (booking.status !== BookingStatus.IN_PROGRESS) {
    throw new BookingValidationError(`Reserva no está en curso para confirmar extensión (estado: ${booking.status})`);
  }

  const events: any[] = Array.isArray(booking.serviceEvents) ? [...(booking.serviceEvents as any[])] : [];
  const pendingIdx = events.findIndex(
    (e: any) => e.type === 'EXTENSION_PENDING_PAYMENT' && e.method === 'qr' && e.qrId === qrId
  );

  if (pendingIdx === -1) {
    logger.info('[SIP callback] Extensión ya procesada o qrId no encontrado — idempotente', { bookingId, qrId });
    return;
  }

  const pending = events[pendingIdx];
  if (new Date(pending.qrExpiresAt) < new Date()) {
    throw new BookingValidationError('QR de extensión expirado');
  }

  const { extraAmount, extensionId } = pending;
  const pricePerUnitClient = Number(booking.pricePerUnit);
  const pricePerUnitCaregiver = Math.round(pricePerUnitClient / (1 + cfg.COMMISSION_RATE));

  events[pendingIdx] = {
    type: 'EXTENSION_CONFIRMED',
    extensionId,
    ...(pending.additionalMinutes !== undefined ? { additionalMinutes: pending.additionalMinutes } : {}),
    ...(pending.additionalDays !== undefined ? { additionalDays: pending.additionalDays } : {}),
    extraAmount,
    method: 'qr',
    paidAt: new Date().toISOString(),
    timestamp: new Date().toISOString(),
  };

  let updateData: Parameters<typeof prisma.booking.update>[0]['data'];
  let pushTitle: string;
  let pushBody: string;
  let notifMessage: string;

  if (booking.serviceType === ServiceType.PASEO) {
    const additionalMinutes: number = pending.additionalMinutes;
    const extraCommission = extraAmount - Math.round((pricePerUnitCaregiver / 60) * additionalMinutes);
    updateData = {
      duration: (booking.duration ?? 60) + additionalMinutes,
      totalAmount: new Prisma.Decimal(Number(booking.totalAmount) + extraAmount),
      commissionAmount: new Prisma.Decimal(Number(booking.commissionAmount) + extraCommission),
      serviceEvents: events,
    };
    pushTitle = '⏱️ Extensión confirmada';
    pushBody = `+${additionalMinutes} min · Bs ${extraAmount} adicionales`;
    notifMessage = `El pago de +${additionalMinutes} min fue confirmado por el banco. Bs ${extraAmount} adicionales — ${booking.petName ?? 'mascota'}.`;
  } else {
    const additionalDays: number = pending.additionalDays;
    const extraCommission = extraAmount - pricePerUnitCaregiver * additionalDays;
    const newEndDate = new Date(booking.endDate!);
    newEndDate.setDate(newEndDate.getDate() + additionalDays);
    updateData = {
      endDate: newEndDate,
      totalDays: (booking.totalDays ?? 1) + additionalDays,
      totalAmount: new Prisma.Decimal(Number(booking.totalAmount) + extraAmount),
      commissionAmount: new Prisma.Decimal(Number(booking.commissionAmount) + extraCommission),
      serviceEvents: events,
    };
    pushTitle = '🏠 Hospedaje extendido';
    pushBody = `+${additionalDays} noche${additionalDays > 1 ? 's' : ''} · Bs ${extraAmount} adicionales`;
    notifMessage = `El pago de +${additionalDays} noche${additionalDays > 1 ? 's' : ''} fue confirmado por el banco. Bs ${extraAmount} adicionales — ${booking.petName ?? 'mascota'}.`;
  }

  let caregiverUserId: string | null = null;
  await prisma.$transaction(async (tx) => {
    await tx.booking.update({ where: { id: bookingId }, data: updateData });
    const caregiver = await tx.caregiverProfile.findFirst({
      where: { id: booking.caregiverId },
      select: { userId: true },
    });
    if (caregiver) {
      caregiverUserId = caregiver.userId;
      await tx.notification.create({
        data: {
          userId: caregiver.userId,
          title: pushTitle,
          message: notifMessage,
          type: 'SERVICE_EXTENSION',
        },
      });
    }
  });

  if (caregiverUserId) {
    sendPushToUser(caregiverUserId, pushTitle, pushBody).catch(() => {});
  }

  logger.info('[SIP callback] Extension confirmed via banco', { bookingId, extensionId, serviceType: booking.serviceType });
}

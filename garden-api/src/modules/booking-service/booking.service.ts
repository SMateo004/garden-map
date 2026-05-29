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
import { sendPushToUser } from '../../services/firebase.service.js';
import { getIO } from '../../services/socket.service.js';
import type {
  CreateBookingBody,
  InitPaymentBody,
  MgDataInput,
} from './booking.validation.js';
import type { BookingCreateResult } from './booking.types.js';
import { bookingToResponse } from './booking.types.js';
import { parseTimeBlocks } from '../../shared/availability-utils.js';

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
        qrValidityHours,
        qrValidityMinutes,
    ] = await Promise.all([
        getNumericSetting('platformCommissionPct',   10),
        getNumericSetting('hospedajeRefundAdminFeeBS', 10),
        getNumericSetting('hospedajeRefund100Horas', 48),
        getNumericSetting('hospedajeRefund50Horas',  24),
        getNumericSetting('paseoRefund100Horas',     12),
        getNumericSetting('paseoRefund50Horas',       6),
        getNumericSetting('qrValidityHours',         24),
        getNumericSetting('qrValidityMinutes',       15),
    ]);
    return {
        COMMISSION_RATE:              commissionPct / 100,
        HOSPEDAJE_REFUND_ADMIN_FEE_BS: hospedajeAdminFee,
        HOSPEDAJE_REFUND_100_HOURS:   hospedaje100h,
        HOSPEDAJE_REFUND_50_HOURS:    hospedaje50h,
        PASEO_REFUND_100_HOURS:       paseo100h,
        PASEO_REFUND_50_HOURS:        paseo50h,
        QR_VALIDITY_HOURS:            qrValidityHours,
        QR_VALIDITY_MINUTES_PAYMENT:  qrValidityMinutes,
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
      include: { pets: { select: { id: true } } },
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

    const pet = await tx.pet.findFirst({
      where: {
        id: body.petId,
        clientProfile: { userId: clientId },
      },
      select: { id: true, name: true, breed: true, age: true, size: true, specialNeeds: true },
    });

    if (!pet) {
      throw new BadRequestError(
        'Mascota no encontrada o no te pertenece. Elige una mascota de tu perfil.',
        'PET_NOT_OWNED',
        'petId'
      );
    }

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
      },
    });

    if (!caregiver) {
      throw new BadRequestError(
        'Cuidador no encontrado o no disponible para reservas',
        'CAREGIVER_NOT_FOUND',
        'caregiverId'
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
      await assertHospedajeAvailability(tx, body.caregiverId, body.startDate, body.endDate);
    } else if (body.serviceType === ServiceType.GUARDERIA) {
      await assertPaseoAvailability(
        tx,
        body.caregiverId,
        (body as any).walkDate,
        (body as any).timeSlot,
        (body as any).startTime,
        (body as any).duration
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
            (body as any).duration
          );
        }
      } else {
        await assertPaseoAvailability(
          tx,
          body.caregiverId,
          (body as any).walkDate,
          (body as any).timeSlot,
          (body as any).startTime,
          (body as any).duration
        );
      }
    }

    let pricePerUnit: number;
    let totalDays: number | null = null;
    let totalAmount: number;

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
      totalAmount = totalDays * pricePerUnit;
    } else if (body.serviceType === ServiceType.GUARDERIA) {
      const duration = (body as any).duration as number;
      const p60 = caregiver.pricePerWalk60 ?? 0;
      const priceGuarderia = (caregiver as any).pricePerGuarderia ?? p60;
      if (priceGuarderia <= 0) {
        throw new BookingValidationError('El cuidador no tiene precio de guardería configurado', 'BOOKING_VALIDATION', 'caregiverId');
      }
      // Precio por hora de guardería × horas solicitadas
      pricePerUnit = Math.round(priceGuarderia * (duration / 60));
      totalAmount = pricePerUnit;
    } else {
      const duration = (body as any).duration;
      const p60 = caregiver.pricePerWalk60 ?? 0;
      const walkDays = (body as any).walkDays as Array<{ date: string; timeSlot: string; startTime?: string }> | undefined;

      if (p60 <= 0) {
        throw new BookingValidationError('El cuidador no tiene precio de paseo configurado', 'BOOKING_VALIDATION', 'caregiverId');
      }

      // 30 min = mitad del precio de 60 min (sin campo separado en BD)
      pricePerUnit = duration === 30 ? Math.round(p60 / 2) : p60;
      // Multi-day: multiply by number of days
      const numDays = walkDays && walkDays.length > 0 ? walkDays.length : 1;
      totalAmount = pricePerUnit * numDays;
    }

    const subtotal = totalAmount;
    totalAmount = Math.round(subtotal * (1 + cfg.COMMISSION_RATE));
    const commissionAmount = totalAmount - subtotal;
    // Client sees the unit price with markup
    pricePerUnit = Math.round(pricePerUnit * (1 + cfg.COMMISSION_RATE));

    const bookingData: Prisma.BookingCreateInput = {
      client: { connect: { id: clientId } },
      caregiver: { connect: { id: body.caregiverId } },
      pet: { connect: { id: pet.id } },
      serviceType: body.serviceType as ServiceType,
      status: mgData ? BookingStatus.PENDING_MG : BookingStatus.PENDING_PAYMENT,
      totalAmount: new Prisma.Decimal(totalAmount),
      pricePerUnit: new Prisma.Decimal(pricePerUnit),
      commissionAmount: new Prisma.Decimal(commissionAmount),
      petName: pet.name,
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

    logger.info('Cliente seleccionó mascota para reserva', {
      userId: clientId,
      petId: body.petId,
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

// Bolivian public holidays (ISO strings) — kept in sync with the caregiver home screen list
const BOLIVIA_HOLIDAYS = new Set([
  '2025-01-01','2025-01-22','2025-02-24','2025-02-25','2025-04-18','2025-04-19',
  '2025-05-01','2025-06-19','2025-06-21','2025-08-06','2025-10-12','2025-11-02',
  '2025-12-25','2026-01-01','2026-01-22','2026-02-16','2026-02-17','2026-04-03',
  '2026-04-04','2026-05-01','2026-06-11','2026-06-21','2026-08-06','2026-10-12',
  '2026-11-02','2026-12-25',
]);

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

/** Hospedaje: todos los días en [start, end) deben estar disponibles (fila con isAvailable=true o defaultSchedule.hospedajeDefault). */
async function assertHospedajeAvailability(
  tx: Prisma.TransactionClient,
  caregiverId: string,
  startDate: string,
  endDate: string
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

  const profile = await tx.caregiverProfile.findUnique({
    where: { id: caregiverId },
    select: { defaultAvailabilitySchedule: true },
  });
  const defaultSchedule = (profile?.defaultAvailabilitySchedule as Record<string, unknown>) ?? {};
  const hospedajeDefault = defaultSchedule['hospedajeDefault'] !== false;

  const availabilityRows = await tx.availability.findMany({
    where: { caregiverId, date: { in: dates } },
  });
  const availableSet = new Set<string>();
  for (const d of dates) {
    const dStr = d.toISOString().slice(0, 10);
    const row = availabilityRows.find((r) => r.date.toISOString().slice(0, 10) === dStr);
    if (row) {
      // Explicit row: isAvailable wins; no day-type check needed
      if (row.isAvailable) availableSet.add(dStr);
    } else {
      // No explicit row: check hospedajeDefault AND weekdays/weekends/holidays flags
      if (hospedajeDefault && isDayTypeAllowed(d, defaultSchedule, false)) {
        availableSet.add(dStr);
      }
    }
  }
  const missing = dates.filter(
    (d) => !availableSet.has(d.toISOString().slice(0, 10))
  );
  if (missing.length > 0) {
    logger.warn('Hospedaje availability conflict', {
      caregiverId,
      startDate,
      endDate,
      missingDates: missing.map((d) => d.toISOString().slice(0, 10)),
    });
    throw new AvailabilityConflictError(
      `Fecha(s) no disponible(s) para hospedaje: ${missing.map((d) => d.toISOString().slice(0, 10)).join(', ')}. Elige otras fechas.`,
      'startDate'
    );
  }

  // Reservas que bloquean: CONFIRMED, IN_PROGRESS, PAYMENT_PENDING_APPROVAL 
  // O PENDING_PAYMENT si tiene menos de 15 minutos de antigüedad.
  const expirationDate = new Date(Date.now() - 15 * 60 * 1000);

  const overlapping = await tx.booking.count({
    where: {
      caregiverId,
      OR: [
        {
          status: { in: [BookingStatus.PAYMENT_PENDING_APPROVAL, BookingStatus.WAITING_CAREGIVER_APPROVAL, BookingStatus.CONFIRMED, BookingStatus.IN_PROGRESS] },
        },
        {
          status: BookingStatus.PENDING_PAYMENT,
          createdAt: { gte: expirationDate },
        }
      ],
      startDate: { lte: end },
      endDate: { gt: start },
    },
  });
  if (overlapping > 0) {
    throw new AvailabilityConflictError(
      'El cuidador ya tiene una reserva que se solapa con las fechas solicitadas. Elige otras fechas.',
      'startDate'
    );
  }
}

/** Paseo: la fecha debe estar disponible (fila con timeBlocks[slot]=true o defaultSchedule.paseoTimeBlocks[slot]). */
async function assertPaseoAvailability(
  tx: Prisma.TransactionClient,
  caregiverId: string,
  walkDate: string,
  timeSlot: TimeSlot,
  startTime?: string | null,
  duration?: number | null
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
    select: { defaultAvailabilitySchedule: true },
  });
  const defaultSchedule = (profile?.defaultAvailabilitySchedule as Record<string, unknown>) ?? {};
  const defaultBlocks = defaultSchedule['paseoTimeBlocks'] as Record<string, boolean> | undefined;

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
          status: { in: [BookingStatus.PAYMENT_PENDING_APPROVAL, BookingStatus.WAITING_CAREGIVER_APPROVAL, BookingStatus.CONFIRMED, BookingStatus.IN_PROGRESS] },
        },
        {
          status: BookingStatus.PENDING_PAYMENT,
          createdAt: { gte: expirationDate }
        }
      ]
    },
    select: { startTime: true, duration: true, timeSlot: true },
  });

  // Un bloque 'legacy' es aquel que no tiene hora de inicio (bloquea todo el slot)
  const legacyBookings = existingBookings.filter(b => (!b.startTime || b.startTime === '') && b.timeSlot === timeSlot);
  const timedBookings = existingBookings.filter(b => !!b.startTime && b.startTime !== '');

  const isSpecific = !!startTime && startTime !== '';
  logger.info('Check-Paseo-Avail', { walkDate, timeSlot, startTime, isSpecific, foundCount: existingBookings.length });

  // 1. Si hay una reserva legacy en este mismo bloque, bloqueamos CUALQUIER reserva nueva en el bloque
  if (legacyBookings.length > 0) {
    throw new AvailabilityConflictError(
      `El bloque ${timeSlot} ya tiene una reserva que ocupa todo el horario habilitado para este día.`,
      'timeSlot'
    );
  }

  // 2. Si la NUEVA reserva no tiene hora y hay ALGO en el bloque, bloqueamos (legacy mode)
  if (!isSpecific && existingBookings.some(b => b.timeSlot === timeSlot)) {
    throw new AvailabilityConflictError(
      `El bloque ${timeSlot} ya tiene reservas previas. Por favor, selecciona una hora específica para buscar disponibilidad.`,
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

    // Verificar solapamiento con otras reservas que tengan tiempo específico
    for (const b of timedBookings) {
      const bStart = timeToMins(b.startTime as string);
      const bDuration = b.duration || 60; // 60 min fallback por seguridad
      const bEndWithBuffer = bStart + bDuration + 30;

      if (rangesOverlap(requestedStart, requestedEndWithBuffer, bStart, bEndWithBuffer)) {
        logger.warn('Overlap detected in PASEO booking', { requestedStart, requestedEndWithBuffer, bStart, bEndWithBuffer });
        throw new AvailabilityConflictError(
          `Conflicto: El horario solicitado (${startTime}) se solapa con una reserva de ${b.startTime} a ${Math.floor((bStart + bDuration) / 60)}:${String((bStart + bDuration) % 60).padStart(2, '0')} (incluyendo descanso).`,
          'startTime'
        );
      }
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
// Pago: QR placeholder (API bancaria futura) e iniciar pago / aprobación manual
// ---------------------------------------------------------------------------

export interface GenerateQRResult {
  qrId: string;
  qrImageUrl: string;
  qrExpiresAt: Date;
}

/**
 * Genera datos de QR de pago. Placeholder para integración con API bancaria real.
 *
 * Integración futura (API bancaria):
 * - Sustituir el bloque siguiente por: llamada HTTP a proveedor (ej. banco/aggregator),
 *   enviando bookingId, totalAmount, currency; recibir qrId, qrImageUrl (o base64), expiresAt.
 * - En webhook/callback del banco: llamar a paymentService.verifyPaymentByQr(qrId) al confirmar pago.
 *
 * @param _bookingId Reserva asociada (enviar a API bancaria para referencia)
 * @param validityMinutes Minutos hasta expiración (default 24h). Página de pago usa 15.
 */
export function generateQR(
  _bookingId: string,
  validityMinutes: number = 24 * 60  // default 24h; overridden by initPayment usando el setting
): GenerateQRResult {
  const qrId = crypto.randomUUID();
  const qrExpiresAt = new Date(Date.now() + validityMinutes * 60 * 1000);
  // Placeholder: en producción reemplazar por URL/imagen devuelta por API bancaria
  const qrImageUrl = `https://api.garden.bo/qr/placeholder/${qrId}`;
  logger.info('QR generado (placeholder; integrar API bancaria)', {
    bookingId: _bookingId,
    qrId,
    validityMinutes,
  });
  return { qrId, qrImageUrl, qrExpiresAt };
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
  method: InitPaymentBody['method']
): Promise<{ qrId?: string; qrImageUrl?: string; qrExpiresAt?: string; status: string }> {
  const cfg = await getBookingSettings();
  return prisma.$transaction(async (tx) => {
    const booking = await tx.booking.findFirst({
      where: { id: bookingId, clientId },
      select: {
        id: true,
        status: true,
        caregiverId: true,
      },
    });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.status !== BookingStatus.PENDING_PAYMENT) {
      throw new BookingValidationError(
        'Solo se puede iniciar pago en reservas pendientes de pago'
      );
    }

    if (method === 'qr') {
      const { qrId, qrImageUrl, qrExpiresAt } = generateQR(
        bookingId,
        cfg.QR_VALIDITY_MINUTES_PAYMENT
      );
      await tx.booking.update({
        where: { id: bookingId },
        data: { qrId, qrImageUrl, qrExpiresAt },
      });
      logger.info('Pago QR iniciado', { bookingId, clientId, qrId });
      return {
        qrId,
        qrImageUrl,
        qrExpiresAt: qrExpiresAt.toISOString(),
        status: BookingStatus.PENDING_PAYMENT,
      };
    }

    // Pago manual: generamos un ID de pago para seguimiento
    const manualPaymentId = `PAY-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    await tx.booking.update({
      where: { id: bookingId },
      data: { 
        status: BookingStatus.PAYMENT_PENDING_APPROVAL,
        qrId: manualPaymentId // Usamos el campo qrId para guardar la referencia de pago manual
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
    // Notificación admin (MVP: console; futuro: WhatsApp/Email con link a /admin/payments-pending)
    logger.info('[ADMIN] Pago manual pendiente', {
      bookingId: booking.id,
      caregiverId: booking.caregiverId,
      actionUrl: `/admin/payments-pending`,
      message: 'Revisar y aprobar o rechazar en el panel admin.',
    });
    return { status: BookingStatus.PAYMENT_PENDING_APPROVAL, qrId: manualPaymentId };
  });
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
    // Set refundStatus=PENDING_APPROVAL so admin can process the actual transfer.
    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        status: BookingStatus.CANCELLED,
        cancelledAt: now,
        cancellationReason: reason,
        refundAmount: booking.totalAmount,          // full refund
        refundStatus: RefundStatus.PENDING_APPROVAL, // admin must process
      },
    });

    // 1. Notificación para el dueño (cliente)
    await tx.notification.create({
      data: {
        userId: (booking as any).client.id,
        title: 'Tu reserva ha sido cancelada por el cuidador',
        message: `El cuidador ha cancelado la reserva de ${booking.petName} (ID: ${bookingId.slice(0, 8)}). Motivo: ${reason}. La empresa se contactará contigo en un plazo de 1 día hábil para gestionar la devolución correspondiente según la política de reembolso.`,
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
      const amount = total * 0.5;
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
  cancellationReason?: string
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
        refundAmount: new Prisma.Decimal(refundAmount),
        refundStatus,
      },
    });

    // 1. Notificación para el cliente (dueño)
    await tx.notification.create({
      data: {
        userId: clientId,
        title: 'Has cancelado tu reserva',
        message: `Tu reserva ha sido cancelada. Se te devolverá Bs ${refundAmount.toFixed(2)} (el costo del servicio sin comisión de Garden). El equipo de soporte procesará el reembolso pronto.`,
        type: 'BOOKING_CANCELLED',
      }
    });

    // 2. Notificación para el cuidador
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

    logger.info('Booking cancelled', {
      bookingId,
      clientId,
      refundAmount,
      refundStatus,
    });
    return { booking: updated, refundAmount, refundStatus };
  });

  notificationService
    .onClientCancelled(bookingId)
    .catch((err) => logger.error('Notification onClientCancelled failed', { bookingId, err }));

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
    const availabilityRows = await tx.availability.findMany({
      where: {
        caregiverId: booking.caregiverId,
        date: { in: dates },
        isAvailable: true,
      },
    });
    const availableSet = new Set(
      availabilityRows.map((r) => r.date.toISOString().slice(0, 10))
    );
    const missing = dates.filter((d) => !availableSet.has(d.toISOString().slice(0, 10)));
    if (missing.length > 0) {
      throw new AvailabilityConflictError(
        `Fechas no disponibles para extensión: ${missing.map((d) => d.toISOString().slice(0, 10)).join(', ')}`
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
    const availabilityRows = await tx.availability.findMany({
      where: {
        caregiverId: booking.caregiverId,
        date: { in: dates },
        isAvailable: true,
      },
    });
    const availableSet = new Set(
      availabilityRows.map((r) => r.date.toISOString().slice(0, 10))
    );
    const missing = dates.filter((d) => !availableSet.has(d.toISOString().slice(0, 10)));
    if (missing.length > 0) {
      throw new AvailabilityConflictError(
        `Fechas no disponibles: ${missing.map((d) => d.toISOString().slice(0, 10)).join(', ')}`
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
    const { qrId, qrImageUrl, qrExpiresAt } = generateQR(bookingId, 15); // 15 min de validez para extensiones
    events.push({
      type: 'EXTENSION_PENDING_PAYMENT',
      extensionId,
      additionalMinutes,
      extraAmount: extraTotal,
      method: 'qr',
      qrId,
      qrImageUrl,
      qrExpiresAt: qrExpiresAt.toISOString(),
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
      qrId,
      qrImageUrl,
      qrExpiresAt: qrExpiresAt.toISOString(),
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
  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, clientId },
    select: { id: true, serviceType: true, status: true, pricePerUnit: true },
  });

  if (!booking) return { availableDays: 0, pricePerDay: 0 };
  if (booking.serviceType !== ServiceType.HOSPEDAJE) return { availableDays: 0, pricePerDay: 0 };
  if (booking.status !== BookingStatus.IN_PROGRESS) return { availableDays: 0, pricePerDay: 0 };

  return { availableDays: 30, pricePerDay: Number(booking.pricePerUnit) };
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
    const { qrId, qrImageUrl, qrExpiresAt } = generateQR(bookingId, 15);
    events.push({
      type: 'EXTENSION_PENDING_PAYMENT',
      extensionId,
      additionalDays,
      extraAmount: extraTotal,
      method: 'qr',
      qrId,
      qrImageUrl,
      qrExpiresAt: qrExpiresAt.toISOString(),
      timestamp: new Date().toISOString(),
    });

    await prisma.booking.update({ where: { id: bookingId }, data: { serviceEvents: events } });
    logger.info('Hospedaje extension QR payment initiated', { bookingId, extensionId, additionalDays, extraTotal });
    return { extensionId, extraAmount: extraTotal, qrId, qrImageUrl, qrExpiresAt: qrExpiresAt.toISOString(), status: 'PENDING_QR' };
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
  const [bookings, total] = await Promise.all([
    prisma.booking.findMany({
      where: { clientId },
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
      },
      orderBy: { createdAt: 'desc' },
      skip,
      take: limit,
    }),
    prisma.booking.count({ where: { clientId } }),
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
        },
      },
      dispute: true,
      meetAndGreet: true,
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
  const where = { caregiverId: profile.id };

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

    await tx.notification.create({
      data: {
        userId: booking.clientId,
        title: 'Reserva rechazada por el cuidador',
        message: `El cuidador no pudo aceptar tu reserva para ${booking.petName}. Motivo: ${reason}. El equipo de GARDEN gestionará tu reembolso en 1 día hábil.`,
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

    return bookingToResponse(updated);
  });
}

/** Allowed event types from caregiver during a service. */
const ALLOWED_EVENT_TYPES = ['INCIDENT', 'ACCIDENT', 'ILLNESS', 'COMPLICATION', 'NOTE', 'PHOTO', 'WALK_UPDATE'] as const;

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

  const events = (booking.serviceEvents as any[]) || [];
  events.push({
    type,
    description,
    photoUrl: photoUrl ?? null,
    videoUrl: videoUrl ?? null,
    incidentType: incidentType ?? null,
    timestamp: new Date().toISOString(),
  });

  const updated = await prisma.booking.update({
    where: { id: bookingId },
    data: { serviceEvents: events },
  });

  // Si es un incidente o accidente, notificar al dueño en tiempo real
  if (type === 'INCIDENT' || type === 'ACCIDENT') {
    await prisma.notification.create({
      data: {
        userId: booking.clientId,
        title: '⚠️ Tu cuidador reportó un incidente',
        message: description || 'Tu cuidador ha reportado un incidente durante el servicio. El equipo GARDEN está al tanto.',
        type: 'SERVICE_INCIDENT',
      },
    });

    // Push notification urgente al dueño
    await sendPushToUser(booking.clientId, '🚨 Emergencia durante el servicio', `${incidentType ? `[${incidentType}] ` : ''}${description}. Abre la app para contactar al cuidador.`);

    // Emitir al booking room (si el dueño está en el chat o en la pantalla del servicio)
    const io = getIO();
    if (io) {
      io.to(`booking:${bookingId}`).emit('incident_reported', {
        bookingId,
        description,
        timestamp: new Date().toISOString(),
      });
    }

    logger.info('Incident reported and client notified', { bookingId, clientId: booking.clientId });
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

export async function concludeService(
  bookingId: string,
  caregiverUserId: string,
  photoUrl: string,
  lat: number | null,
  lng: number | null
): Promise<BookingCreateResult> {
  return prisma.$transaction(async (tx) => {
    const profile = await tx.caregiverProfile.findFirst({ where: { userId: caregiverUserId } });
    if (!profile) throw new ForbiddenError('Perfil de cuidador no encontrado');

    const booking = await tx.booking.findFirst({ where: { id: bookingId, caregiverId: profile.id } });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.status !== BookingStatus.IN_PROGRESS) {
      throw new BadRequestError('El servicio debe estar en curso para concluirlo');
    }

    const tracking = (booking.serviceTrackingData as any[]) || [];
    if (lat && lng) tracking.push({ lat, lng, timestamp: new Date(), type: 'END' });
    const gpsDistance = booking.serviceType === ServiceType.PASEO ? calcGpsDistance(tracking) : null;

    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        status: BookingStatus.COMPLETED,
        serviceEndedAt: new Date(),
        serviceEndPhoto: photoUrl,
        serviceTrackingData: tracking,
        gpsDistance,
      },
    });

    // Notificación in-app al cliente
    await tx.notification.create({
      data: {
        userId: booking.clientId,
        title: 'Servicio finalizado ✅',
        message: `El cuidador finalizó el servicio para ${booking.petName}. Entra a "Mis reservas" para confirmar la recepción y dejar tu reseña.`,
        type: 'SERVICE_COMPLETED',
      },
    });
    sendPushToUser(booking.clientId, 'Servicio finalizado ✅', `El cuidador terminó. Deja tu reseña para liberar el pago.`).catch(() => {});

    auditLog({
      userId: caregiverUserId,
      action: 'BOOKING_COMPLETED',
      entity: 'Booking',
      entityId: bookingId,
      details: { serviceType: booking.serviceType, gpsDistance },
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

    // Leer balance ANTES del incremento (snapshot correcto para el registro de transacción)
    const profileBefore = await tx.caregiverProfile.findUnique({
      where: { id: booking.caregiverId },
      select: { balance: true, userId: true },
    });
    const balanceBefore = Number(profileBefore?.balance ?? 0);

    // Actualizar balance del cuidador (atómico)
    await tx.caregiverProfile.update({
      where: { id: booking.caregiverId },
      data: { balance: { increment: amount } },
    });

    await tx.walletTransaction.create({
      data: {
        userId: profileBefore!.userId,
        type: 'EARNING',
        amount: amount,
        balance: balanceBefore + amount, // nuevo saldo = anterior + ganancia
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

    sendPushToUser(profileBefore!.userId, '¡Pago liberado! 💸', `Recibiste el pago por el servicio de ${booking.petName}. Revisa tu billetera.`).catch(() => {});

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

    // Update Caregiver Average Rating
    const result = await tx.review.aggregate({
      where: { caregiverId: booking.caregiverId },
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

    const amount = Number(booking.totalAmount) - Number(booking.commissionAmount);

    const profileBefore = await tx.caregiverProfile.findUnique({
      where: { id: booking.caregiverId },
      select: { balance: true, userId: true },
    });
    const balanceBefore = Number(profileBefore?.balance ?? 0);

    await tx.caregiverProfile.update({
      where: { id: booking.caregiverId },
      data: { balance: { increment: amount } },
    });

    await tx.walletTransaction.create({
      data: {
        userId: profileBefore!.userId,
        type: 'EARNING',
        amount,
        balance: balanceBefore + amount,
        description: `Auto-liberación tras ${horasVencimiento}h — ${booking.petName} (sin reseña del cliente)`,
        bookingId: booking.id,
        status: 'COMPLETED',
      },
    });

    await tx.booking.update({
      where: { id: bookingId },
      data: { payoutStatus: 'PAID' },
    });

    sendPushToUser(
      profileBefore!.userId,
      '💸 Pago liberado automáticamente',
      `El pago de Bs ${amount.toFixed(2)} por el servicio de ${booking.petName} fue liberado (el cliente no dejó reseña).`
    ).catch(() => {});
  });

  // Blockchain: rating 5 = símbolo de auto-aprobación sin disputa (no infla rating del perfil)
  blockchainService.finalizeBookingOnChain(bookingId, 5).then(async (txHash) => {
    if (txHash) {
      await prisma.booking.update({ where: { id: bookingId }, data: { blockchainFinalizedTxHash: txHash } });
      logger.info('[Blockchain] auto-release finalize txHash saved', { bookingId, txHash });
    }
  }).catch(err => {
    logger.error('[AutoRelease] Blockchain finalize failed', { bookingId, err });
  });
}

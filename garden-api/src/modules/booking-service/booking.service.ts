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
import * as notificationService from '../../services/notification.service.js';
import { blockchainService } from '../../services/blockchain.service.js';
import { sendPushToUser } from '../../services/firebase.service.js';
import { getIO } from '../../services/socket.service.js';
import type {
  CreateBookingBody,
  InitPaymentBody,
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
  body: CreateBookingBody
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
    // Normalizamos a la fecha local (Bolivia -04:00 suele ser la referencia del user)
    // Usamos toLocaleDateString con el locale apropiado para obtener YYYY-MM-DD
    const todayStr = new Date(now.getTime() - (now.getTimezoneOffset() * 60000)).toISOString().split('T')[0] || '';
    const requestedDate = body.serviceType === ServiceType.HOSPEDAJE ? body.startDate : body.walkDate;

    if (requestedDate && requestedDate <= todayStr) {
      throw new BookingValidationError(
        'Las reservas deben realizarse con al menos un día de anticipación. Por favor, selecciona una fecha a partir de mañana.',
        'BOOKING_VALIDATION',
        body.serviceType === ServiceType.HOSPEDAJE ? 'startDate' : 'walkDate'
      );
    }

    const hasService =
      body.serviceType === ServiceType.HOSPEDAJE
        ? caregiver.servicesOffered.includes(ServiceType.HOSPEDAJE)
        : caregiver.servicesOffered.includes(ServiceType.PASEO);
    if (!hasService) {
      throw new BookingValidationError(
        `El cuidador no ofrece el servicio ${body.serviceType}`,
        'BOOKING_VALIDATION',
        'serviceType'
      );
    }

    if (body.serviceType === ServiceType.HOSPEDAJE) {
      await assertHospedajeAvailability(tx, body.caregiverId, body.startDate, body.endDate);
    } else {
      await assertPaseoAvailability(
        tx,
        body.caregiverId,
        body.walkDate,
        body.timeSlot,
        body.startTime,
        body.duration
      );
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
      totalDays = body.totalDays;
      totalAmount = (totalDays ?? 0) * pricePerUnit;
    } else {
      const duration = (body as any).duration;
      const p60 = caregiver.pricePerWalk60 ?? 0;

      if (p60 <= 0) {
        throw new BookingValidationError('El cuidador no tiene precio de paseo configurado', 'BOOKING_VALIDATION', 'caregiverId');
      }

      // 30 min = mitad del precio de 60 min (sin campo separado en BD)
      pricePerUnit = duration === 30 ? Math.round(p60 / 2) : p60;
      totalAmount = pricePerUnit;
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
      status: BookingStatus.PENDING_PAYMENT,
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
        : {
          walkDate: new Date((body as any).walkDate),
          timeSlot: (body as any).timeSlot,
          startTime: (body as any).startTime,
          duration: (body as any).duration,
        }),
    };

    const booking = await tx.booking.create({
      data: bookingData,
    });

    // Notificación al cuidador: nueva solicitud
    const caregiverUser = await tx.caregiverProfile.findUnique({
      where: { id: body.caregiverId },
      select: { userId: true },
    });
    if (caregiverUser) {
      await tx.notification.create({
        data: {
          userId: caregiverUser.userId,
          title: '¡Nueva solicitud de reserva!',
          message: `Tienes una nueva solicitud de ${body.serviceType === 'HOSPEDAJE' ? 'hospedaje' : 'paseo'} para ${pet.name}. Revisa tu buzón para aceptar o rechazar.`,
          type: 'NEW_BOOKING',
        },
      });
      sendPushToUser(caregiverUser.userId, '¡Nueva solicitud de reserva! 🐾', `${pet.name} necesita un cuidador. Revisa tu buzón.`).catch(() => {});
    }

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

    return bookingToResponse(booking);
  });
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
  const dates: Date[] = [];
  for (let d = new Date(start); d < end; d.setDate(d.getDate() + 1)) {
    dates.push(new Date(d));
  }

  const profile = await tx.caregiverProfile.findUnique({
    where: { id: caregiverId },
    select: { defaultAvailabilitySchedule: true },
  });
  const defaultSchedule = profile?.defaultAvailabilitySchedule as { hospedajeDefault?: boolean } | null;
  const hospedajeDefault = defaultSchedule?.hospedajeDefault !== false;

  const availabilityRows = await tx.availability.findMany({
    where: { caregiverId, date: { in: dates } },
  });
  const availableSet = new Set<string>();
  for (const d of dates) {
    const dStr = d.toISOString().slice(0, 10);
    const row = availabilityRows.find((r) => r.date.toISOString().slice(0, 10) === dStr);
    if (row) {
      if (row.isAvailable) availableSet.add(dStr);
    } else if (hospedajeDefault) {
      availableSet.add(dStr);
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

  const profile = await tx.caregiverProfile.findUnique({
    where: { id: caregiverId },
    select: { defaultAvailabilitySchedule: true },
  });
  const defaultSchedule = profile?.defaultAvailabilitySchedule as { paseoTimeBlocks?: Record<string, boolean> } | null;
  const defaultBlocks = defaultSchedule?.paseoTimeBlocks;

  const avail = await tx.availability.findUnique({
    where: {
      caregiverId_date: { caregiverId, date },
    },
  });
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

    // Verificar límites del bloque del cuidador
    const availRow = avail || (defaultBlocks ? { timeBlocks: defaultBlocks } : null);
    if (availRow) {
      const slots = parseTimeBlocks((availRow as any).timeBlocks || availRow);
      const currentBlock = slots.find(s => s.slot === timeSlot);
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
  if (booking.serviceType !== ServiceType.PASEO) return { allowedMinutes: 0, reason: 'Solo paseos pueden extenderse' };
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
    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        status: BookingStatus.CANCELLED,
        cancelledAt: now,
        cancellationReason: reason,
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

  // PASEO: referencia = mediodía del walkDate para calcular horas hasta el servicio
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
      // Refund policy: return the service price only — Garden keeps its commission
      refundAmount = Math.max(0, Number(booking.totalAmount) - Number(booking.commissionAmount));
      refundStatus = refundAmount > 0 ? RefundStatus.APPROVED : RefundStatus.REJECTED;
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

  // Registro en Blockchain (asíncrono)
  blockchainService.cancelBookingOnChain(bookingId, cancellationReason || 'Cancelado por usuario').catch(err => {
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
    const minEnd = new Date(start);
    minEnd.setDate(minEnd.getDate() + 2);
    if (newEndNorm < minEnd) {
      throw new BookingValidationError('Hospedaje: mínimo 48 horas entre check-in y check-out');
    }

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
 * Solo CONFIRMED; cliente titular; mínimo 48h entre inicio y fin.
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
    const minEnd = new Date(startNorm);
    minEnd.setDate(minEnd.getDate() + 2);
    if (endNorm < minEnd) {
      throw new BookingValidationError('Hospedaje: mínimo 48 horas entre check-in y check-out');
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
  qrId: string
): Promise<BookingCreateResult> {
  const cfg = await getBookingSettings();

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId },
    select: {
      id: true, clientId: true, caregiverId: true, serviceType: true, status: true,
      duration: true, totalAmount: true, commissionAmount: true, pricePerUnit: true,
      petName: true, serviceEvents: true,
    },
  });

  if (!booking) throw new BookingNotFoundError(bookingId);
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
  const profile = await prisma.caregiverProfile.findFirst({
    where: { userId: caregiverUserId },
    select: { id: true }
  });
  if (!profile) throw new ForbiddenError('Perfil de cuidador no encontrado');

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, caregiverId: profile.id }
  });

  if (!booking) throw new BookingNotFoundError(bookingId);
  if (booking.status !== BookingStatus.WAITING_CAREGIVER_APPROVAL) {
    throw new BadRequestError('Esta reserva no está esperando aprobación del cuidador');
  }

  const updated = await prisma.booking.update({
    where: { id: bookingId },
    data: { status: BookingStatus.CONFIRMED },
    include: {
      caregiver: { include: { user: { select: { id: true, firstName: true, lastName: true, email: true, profilePicture: true } } } },
      client: { select: { id: true, firstName: true, lastName: true, email: true, phone: true, profilePicture: true } }
    }
  });

  // Notificación in-app al cliente
  await prisma.notification.create({
    data: {
      userId: updated.clientId,
      title: '¡Tu reserva fue aceptada! 🐾',
      message: `El cuidador aceptó tu reserva para ${updated.petName}. Ya está confirmada. Puedes ver los detalles en "Mis reservas".`,
      type: 'BOOKING_ACCEPTED',
    },
  });
  sendPushToUser(updated.clientId, '¡Tu reserva fue aceptada! 🐾', `El cuidador confirmó la reserva para ${updated.petName}.`).catch(() => {});

  notificationService.onBookingAccepted(bookingId).catch(err => {
    logger.error('Error sending onBookingAccepted notification', { bookingId, err });
  });

  // Escrow ya se crea on-chain cuando el pago se confirma (payment.service.ts).
  // No duplicar la llamada aquí — el contrato rechaza bookings que ya existen.

  return bookingToResponse(updated);
}

/**
 * Cuidador rechaza una reserva pagada.
 */
export async function rejectBooking(bookingId: string, caregiverUserId: string, reason: string): Promise<BookingCreateResult> {
  const profile = await prisma.caregiverProfile.findFirst({
    where: { userId: caregiverUserId },
    select: { id: true }
  });
  if (!profile) throw new ForbiddenError('Perfil de cuidador no encontrado');

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, caregiverId: profile.id }
  });

  if (!booking) throw new BookingNotFoundError(bookingId);
  if (booking.status !== BookingStatus.WAITING_CAREGIVER_APPROVAL) {
    throw new BadRequestError('Esta reserva no está esperando aprobación del cuidador');
  }

  const updated = await prisma.booking.update({
    where: { id: bookingId },
    data: {
      status: BookingStatus.REJECTED_BY_CAREGIVER,
      cancellationReason: reason,
      refundStatus: RefundStatus.PENDING_APPROVAL,
      refundAmount: booking.totalAmount
    }
  });

  // Notificación in-app al cliente
  await prisma.notification.create({
    data: {
      userId: booking.clientId,
      title: 'Reserva rechazada por el cuidador',
      message: `El cuidador no pudo aceptar tu reserva para ${booking.petName}. Motivo: ${reason}. El equipo de GARDEN gestionará tu reembolso en 1 día hábil.`,
      type: 'BOOKING_REJECTED',
    },
  });
  sendPushToUser(booking.clientId, 'Reserva rechazada ❌', `El cuidador no pudo aceptar la reserva de ${booking.petName}.`).catch(() => {});

  notificationService.onBookingRejected(bookingId, reason).catch(err => {
    logger.error('Error sending onBookingRejected notification', { bookingId, err });
  });

  // Notificación Admin para devolución en 1 día hábil
  await prisma.adminNotification.create({
    data: {
      type: 'BOOKING_REJECTED_REFUND_NEEDED',
      caregiverId: profile.id,
      bookingId: booking.id
    }
  });

  return bookingToResponse(updated);
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

export async function addServiceEvent(
  bookingId: string,
  caregiverUserId: string,
  type: string,
  description: string,
  photoUrl?: string
): Promise<BookingCreateResult> {
  const profile = await prisma.caregiverProfile.findFirst({
    where: { userId: caregiverUserId },
  });
  if (!profile) throw new ForbiddenError('Perfil de cuidador no encontrado');

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, caregiverId: profile.id },
  });
  if (!booking) throw new BookingNotFoundError(bookingId);

  const events = (booking.serviceEvents as any[]) || [];
  events.push({
    type,
    description,
    photoUrl: photoUrl ?? null,
    timestamp: new Date().toISOString(),
  });

  const updated = await prisma.booking.update({
    where: { id: bookingId },
    data: { serviceEvents: events },
  });

  // Si es un incidente, notificar al dueño en tiempo real
  if (type === 'INCIDENT') {
    await prisma.notification.create({
      data: {
        userId: booking.clientId,
        title: '⚠️ Tu cuidador reportó un incidente',
        message: description || 'Tu cuidador ha reportado un incidente durante el servicio. El equipo GARDEN está al tanto.',
        type: 'SERVICE_INCIDENT',
      },
    });

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

export async function trackServiceLocation(
  bookingId: string,
  caregiverUserId: string,
  lat: number,
  lng: number,
  accuracy?: number
): Promise<void> {
  const profile = await prisma.caregiverProfile.findFirst({ where: { userId: caregiverUserId } });
  if (!profile) throw new ForbiddenError('Perfil de cuidador no encontrado');

  const booking = await prisma.booking.findFirst({ where: { id: bookingId, caregiverId: profile.id } });
  if (!booking) throw new BookingNotFoundError(bookingId);
  if (booking.serviceType !== ServiceType.PASEO) throw new BadRequestError('GPS solo disponible para paseos');

  const punto = { lat, lng, timestamp: new Date(), accuracy: accuracy ?? 0 };
  const tracking = (booking.serviceTrackingData as any[]) || [];
  tracking.push(punto);

  await prisma.booking.update({
    where: { id: bookingId },
    data: { serviceTrackingData: tracking },
  });

  // Emit real-time GPS update via Socket.io
  const io = getIO();
  if (io) {
    io.to(`booking:${bookingId}`).emit('gps_update', { ...punto, timestamp: punto.timestamp.toISOString() });
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
  lat: number,
  lng: number
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

    return bookingToResponse(updated);
  });
}

export async function confirmReceiptByClient(
  bookingId: string, 
  clientId: string,
  rating: number,
  comment?: string
): Promise<BookingCreateResult> {
  return prisma.$transaction(async (tx) => {
    const booking = await tx.booking.findFirst({
      where: { id: bookingId, clientId },
      include: { caregiver: true }
    });
    if (!booking) throw new BookingNotFoundError(bookingId);
    if (booking.status !== BookingStatus.COMPLETED) {
      throw new BadRequestError('El servicio debe estar marcado como completado por el cuidador');
    }
    if (booking.payoutStatus === 'PAID') {
      throw new BadRequestError('El pago ya fue procesado');
    }

    if (rating < 3) {
      // Disputa (Rating bajo) -> No liberar fondos, poner en pausa.
      const updated = await tx.booking.update({
        where: { id: bookingId },
        data: { 
          payoutStatus: 'ON_HOLD',
          ownerRated: true,
          ownerRating: rating,
          ownerComment: comment,
        }
      });
      return bookingToResponse(updated);
    }

    // Calcular el monto a transferir (Total - Comisión)
    const amount = Number(booking.totalAmount) - Number(booking.commissionAmount);

    // Actualizar balance del cuidador
    const updatedProfile = await tx.caregiverProfile.update({
      where: { id: booking.caregiverId },
      data: { balance: { increment: amount } },
      select: { balance: true, userId: true }
    });

    await tx.walletTransaction.create({
      data: {
        userId: updatedProfile.userId,
        type: 'EARNING',
        amount: amount,
        balance: Number(updatedProfile.balance),
        description: `Ganancia por ${booking.serviceType === 'PASEO' ? 'paseo' : 'hospedaje'} - ${booking.petName}`,
        bookingId: booking.id,
        status: 'COMPLETED',
      },
    });

    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        payoutStatus: 'PAID',
        ownerRated: true,
        ownerRating: rating,
        ownerComment: comment,
      }
    });

    sendPushToUser(updatedProfile.userId, '¡Pago liberado! 💸', `Recibiste el pago por el servicio de ${booking.petName}. Revisa tu billetera.`).catch(() => {});

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

    return bookingToResponse(updated);
  });
}

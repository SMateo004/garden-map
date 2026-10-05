import { CaregiverStatus, RecurringSeriesStatus, ServiceType } from '@prisma/client';
import prisma from '../../config/database.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';
import { sendPushToUser } from '../../services/firebase.service.js';
import * as bookingService from '../booking-service/booking.service.js';
import type { CreateBookingBody } from '../booking-service/booking.validation.js';
import type { CreateRecurringSeriesBody } from './recurring-booking.validation.js';

// ── Helpers de fecha (calendario, no hora exacta — mismo criterio que
// Booking.walkDate, @db.Date). El servidor corre en UTC (ver comentario en
// utils/bolivia-time.ts); Bolivia es UTC-4 todo el año, sin horario de
// verano, así que "hoy en Bolivia" = fecha del instante (ahora − 4h).
function boliviaTodayDateOnly(): string {
  const now = new Date();
  return new Date(now.getTime() - 4 * 60 * 60 * 1000).toISOString().slice(0, 10);
}
function addDaysToDateOnly(dateOnly: string, days: number): string {
  const d = new Date(dateOnly + 'T00:00:00.000Z');
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
function isoDowOfDateOnly(dateOnly: string): number {
  // getUTCDay(): 0=domingo…6=sábado → convertimos a ISO (1=lunes…7=domingo).
  const dow = new Date(dateOnly + 'T00:00:00.000Z').getUTCDay();
  return dow === 0 ? 7 : dow;
}
function nextMatchingDateFrom(daysOfWeek: number[], searchStartDateOnly: string): string {
  let candidate = searchStartDateOnly;
  for (let i = 0; i < 8; i++) {
    if (daysOfWeek.includes(isoDowOfDateOnly(candidate))) return candidate;
    candidate = addDaysToDateOnly(candidate, 1);
  }
  return candidate; // no debería llegar acá con daysOfWeek no vacío
}

const DEFAULT_GENERATE_DAYS_AHEAD = 2;

/** Primera fecha de la serie — con margen (generateDaysAhead) desde hoy para
 * que el cliente tenga tiempo de pagar antes del paseo. */
function computeInitialRunDate(daysOfWeek: number[], generateDaysAheadDays: number): string {
  return nextMatchingDateFrom(daysOfWeek, addDaysToDateOnly(boliviaTodayDateOnly(), generateDaysAheadDays));
}

/** Siguiente fecha DESPUÉS de la que se acaba de procesar — nunca busca
 * hacia atrás de "hoy", ni siquiera si la serie quedó atrasada (ej. el job
 * no corrió por varios días): eso evita generar un backlog de fechas
 * vencidas si el servidor estuvo caído. */
function computeFollowingRunDate(daysOfWeek: number[], fromDateOnly: string): string {
  const today = boliviaTodayDateOnly();
  const minStart = fromDateOnly > today ? addDaysToDateOnly(fromDateOnly, 1) : addDaysToDateOnly(today, 1);
  return nextMatchingDateFrom(daysOfWeek, minStart);
}

const DOW_LABEL = ['', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
export function formatDaysOfWeek(daysOfWeek: number[]): string {
  return daysOfWeek.map((d) => DOW_LABEL[d]).join(', ');
}

// ── CRUD de la serie ─────────────────────────────────────────────────────────

export async function createSeries(clientId: string, body: CreateRecurringSeriesBody) {
  // Validación liviana acá (existe, ofrece paseo, mascotas son del cliente).
  // La validación PROFUNDA (perfil completo, zona cubierta, disponibilidad
  // real del cuidador) la hace createBooking() en cada ocurrencia generada
  // — no se duplica esa lógica acá.
  const caregiver = await prisma.caregiverProfile.findFirst({
    where: { id: body.caregiverId, status: CaregiverStatus.APPROVED, suspended: false },
    select: {
      id: true, userId: true, servicesOffered: true, requireMeetAndGreet: true,
      maxPets: true, maxPetsPaseo: true,
      sizesAccepted: true, animalTypes: true, acceptAggressive: true, acceptPuppies: true, acceptSeniors: true,
    },
  });
  if (!caregiver) throw new NotFoundError('Cuidador no encontrado o no disponible');
  if (!caregiver.servicesOffered.includes(ServiceType.PASEO)) {
    throw new BadRequestError('Este cuidador no ofrece paseos', 'SERVICE_NOT_OFFERED');
  }
  if (caregiver.userId === clientId) {
    throw new BadRequestError('No puedes reservar tus propios servicios.', 'SELF_BOOKING_FORBIDDEN');
  }
  // Cada paseo de la serie se crea sin Meet & Greet: con un cuidador que lo
  // exige, TODAS las fechas se saltaban sin que el dueño entendiera por qué.
  if (caregiver.requireMeetAndGreet) {
    throw new BadRequestError(
      'Este cuidador pide conocerse primero (Meet & Greet). Haz una reserva normal con él y después programa los paseos recurrentes.',
      'MEET_AND_GREET_REQUIRED'
    );
  }

  const uniquePetIds = [...new Set(body.petIds)];
  const pets = await prisma.pet.findMany({
    where: { id: { in: uniquePetIds }, clientProfile: { userId: clientId } },
    select: { id: true, name: true, size: true, animalType: true, isAggressive: true, age: true },
  });
  if (pets.length !== uniquePetIds.length) {
    throw new BadRequestError('Una o más mascotas no te pertenecen', 'PET_NOT_OWNED', 'petIds');
  }
  const maxPets = caregiver.maxPetsPaseo ?? caregiver.maxPets ?? 1;
  if (uniquePetIds.length > maxPets) {
    throw new BadRequestError(
      `Este cuidador pasea como máximo ${maxPets} mascota${maxPets > 1 ? 's' : ''} a la vez.`,
      'MAX_PETS_EXCEEDED',
      'petIds'
    );
  }
  // Mismas reglas que una reserva normal, revisadas AHORA y no recién al
  // generar cada paseo (que se saltaba semana tras semana).
  bookingService.assertPetsFitCaregiver(
    uniquePetIds.map((id) => pets.find((p) => p.id === id)!),
    caregiver
  );

  const nextRunDate = computeInitialRunDate(body.daysOfWeek, DEFAULT_GENERATE_DAYS_AHEAD);

  const series = await prisma.recurringBookingSeries.create({
    data: {
      clientId,
      caregiverId: body.caregiverId,
      serviceType: ServiceType.PASEO,
      daysOfWeek: body.daysOfWeek,
      timeSlot: body.timeSlot,
      startTime: body.startTime,
      duration: body.duration,
      petIds: body.petIds,
      generateDaysAheadDays: DEFAULT_GENERATE_DAYS_AHEAD,
      nextRunDate: new Date(nextRunDate + 'T00:00:00.000Z'),
    },
  });

  logger.info('Serie de paseos recurrentes creada', {
    seriesId: series.id, clientId, daysOfWeek: body.daysOfWeek, nextRunDate,
  });
  return series;
}

export async function listMySeries(clientId: string) {
  return prisma.recurringBookingSeries.findMany({
    where: { clientId, status: { not: RecurringSeriesStatus.CANCELLED } },
    include: {
      caregiver: {
        select: { id: true, user: { select: { firstName: true, lastName: true, profilePicture: true } } },
      },
      occurrences: {
        orderBy: { createdAt: 'desc' },
        take: 3,
        select: { id: true, status: true, walkDate: true, totalAmount: true },
      },
    },
    orderBy: { createdAt: 'desc' },
  });
}

async function assertOwnedSeries(clientId: string, seriesId: string) {
  const series = await prisma.recurringBookingSeries.findFirst({ where: { id: seriesId, clientId } });
  if (!series) throw new NotFoundError('Serie de paseos recurrentes no encontrada');
  return series;
}

export async function pauseSeries(clientId: string, seriesId: string) {
  await assertOwnedSeries(clientId, seriesId);
  return prisma.recurringBookingSeries.update({
    where: { id: seriesId },
    data: { status: RecurringSeriesStatus.PAUSED },
  });
}

export async function resumeSeries(clientId: string, seriesId: string) {
  const series = await assertOwnedSeries(clientId, seriesId);
  // Recalcula desde HOY (no desde el nextRunDate viejo, que pudo quedar
  // atrás mientras estaba pausada) — evita generar un backlog al reanudar.
  const nextRunDate = computeInitialRunDate(series.daysOfWeek, series.generateDaysAheadDays);
  return prisma.recurringBookingSeries.update({
    where: { id: seriesId },
    data: { status: RecurringSeriesStatus.ACTIVE, nextRunDate: new Date(nextRunDate + 'T00:00:00.000Z') },
  });
}

export async function cancelSeries(clientId: string, seriesId: string) {
  await assertOwnedSeries(clientId, seriesId);
  return prisma.recurringBookingSeries.update({
    where: { id: seriesId },
    data: { status: RecurringSeriesStatus.CANCELLED },
  });
}

// ── Job: genera la próxima ocurrencia de cada serie activa vencida ──────────
// Llamado por recurring-booking-generation.job.ts (cron diario).
export async function generateDueOccurrences(): Promise<{ generated: number; skipped: number; failed: number }> {
  const today = boliviaTodayDateOnly();
  const due = await prisma.recurringBookingSeries.findMany({
    where: { status: RecurringSeriesStatus.ACTIVE, nextRunDate: { lte: new Date(today + 'T23:59:59.999Z') } },
  });

  let generated = 0;
  let skipped = 0;
  let failed = 0;

  for (const series of due) {
    const walkDate = series.nextRunDate.toISOString().slice(0, 10);
    try {
      // FIX (auditoría 2026-10-01, jobs — ajustado tras revisión de seguridad):
      // si el proceso se cae/reinicia justo después de que createBooking() crea
      // la reserva pero ANTES de advance() (que mueve nextRunDate a la
      // siguiente fecha) unas líneas más abajo, la próxima corrida del job
      // vuelve a ver esta misma serie como vencida para la MISMA fecha —
      // generaba una segunda reserva duplicada (y, si el saldo alcanzaba, un
      // segundo cobro automático a la billetera).
      //
      // Chequeo PRIMARIO, sin ambigüedad: ¿esta serie YA generó una reserva
      // para esta fecha? (recurringSeriesId + walkDate identifica sin dudas
      // una reserva que pertenece a esta serie).
      const existingLinked = await prisma.booking.findFirst({
        where: {
          recurringSeriesId: series.id,
          walkDate: new Date(walkDate + 'T00:00:00.000Z'),
          status: { not: 'CANCELLED' },
        },
        select: { id: true },
      });

      // Fallback ESTRECHO solo para la ventana de crash más puntual: la
      // reserva se creó pero el `update` que recién abajo la linkea a la
      // serie (recurringSeriesId) nunca llegó a correr. La primera versión de
      // este fix buscaba por cliente+cuidador+fecha sin más — una revisión de
      // seguridad señaló que eso podía confundir (y hasta "adoptar",
      // pisándole recurringSeriesId) una reserva MANUAL no relacionada del
      // mismo cliente con el mismo cuidador ese mismo día. Ahora se exige
      // además mismo horario/mascotas exactos de la serie, sin dueño de serie
      // todavía (recurringSeriesId: null — si ya tuviera uno, nunca se
      // sobreescribe), en un estado que createBooking()/initPayment() podrían
      // realmente haber dejado (se excluyen explícitamente REJECTED_BY_CAREGIVER,
      // SLOT_CONFLICT y cualquier otro estado ajeno a ese camino), y creada
      // hace poco (ventana de 2 horas — más que de sobra para un reinicio de
      // servidor, demasiado corta para confundirse con una reserva vieja).
      const existing = existingLinked ?? await prisma.booking.findFirst({
        where: {
          clientId: series.clientId,
          caregiverId: series.caregiverId,
          serviceType: ServiceType.PASEO,
          walkDate: new Date(walkDate + 'T00:00:00.000Z'),
          // Sin `?? undefined`: si la serie no tiene timeSlot/startTime
          // (null), se filtra explícitamente por IS NULL — un `undefined`
          // haría que Prisma OMITA la condición y matchee cualquier horario,
          // justo el tipo de sobre-coincidencia que esta revisión señaló.
          timeSlot: series.timeSlot,
          startTime: series.startTime,
          // Nota: Booking no tiene un campo escalar `petIds` (eso solo existe
          // en RecurringBookingSeries) — las mascotas de una reserva viven en
          // la tabla de unión BookingPet. No se agrega acá un chequeo de
          // conjunto exacto contra eso (requeriría una subconsulta
          // relacional); cliente+cuidador+fecha+horario+ventana de 2h+estado
          // ya acotan esto lo suficiente para no confundirse con una reserva
          // manual no relacionada.
          recurringSeriesId: null,
          status: { in: ['PENDING_PAYMENT', 'WAITING_CAREGIVER_APPROVAL', 'CONFIRMED'] },
          createdAt: { gte: new Date(Date.now() - 2 * 60 * 60 * 1000) },
        },
        select: { id: true },
      });
      if (existing) {
        logger.warn('recurring-booking-generation: reserva ya existía para esta fecha — se salta la creación (recuperación de corrida previa interrumpida)', {
          seriesId: series.id, walkDate, bookingId: existing.id,
        });
        if (!existingLinked) {
          // Solo entra acá vía el fallback (que ya exige recurringSeriesId:
          // null) — nunca pisa un link existente.
          await prisma.booking.update({ where: { id: existing.id }, data: { recurringSeriesId: series.id } }).catch(() => {});
        }
        await advance(series.id, series.daysOfWeek, walkDate);
        continue;
      }

      let booking;
      try {
        const bookingBody: CreateBookingBody = {
          serviceType: 'PASEO',
          caregiverId: series.caregiverId,
          petIds: series.petIds,
          walkDate,
          timeSlot: series.timeSlot ?? undefined,
          startTime: series.startTime ?? undefined,
          duration: series.duration,
        };
        booking = await bookingService.createBooking(series.clientId, bookingBody);
      } catch (e: any) {
        // No se pudo generar ESTA fecha (cuidador sin cupo, perfil
        // incompleto, zona ya no cubierta, etc.) — se salta solo esta
        // ocurrencia, la serie sigue viva para la siguiente fecha.
        skipped++;
        await notifySkipped(series.clientId, walkDate, e?.message);
        await advance(series.id, series.daysOfWeek, walkDate);
        continue;
      }

      await prisma.booking.update({ where: { id: booking.id }, data: { recurringSeriesId: series.id } });

      // Auto-pago con billetera si el saldo alcanza — si no, la reserva
      // queda PENDING_PAYMENT como cualquier reserva manual, y se notifica
      // para que el cliente complete el pago desde la app.
      let paidAutomatically = false;
      try {
        await bookingService.initPayment(booking.id, series.clientId, 'wallet');
        paidAutomatically = true;
      } catch (_) {
        // Saldo insuficiente u otro motivo — queda pendiente de pago, no es un error del job.
      }

      await notifyGenerated(series.clientId, walkDate, paidAutomatically);
      await advance(series.id, series.daysOfWeek, walkDate);
      generated++;
    } catch (e: any) {
      failed++;
      logger.error('Error generando ocurrencia de serie recurrente', { seriesId: series.id, error: e?.message });
      await prisma.recurringBookingSeries
        .update({
          where: { id: series.id },
          data: { lastRunAt: new Date(), lastRunError: String(e?.message ?? e).slice(0, 500) },
        })
        .catch(() => {});
    }
  }

  logger.info('recurring-booking-generation: corrida completa', { generated, skipped, failed, total: due.length });
  return { generated, skipped, failed };
}

async function advance(seriesId: string, daysOfWeek: number[], fromDate: string) {
  const next = computeFollowingRunDate(daysOfWeek, fromDate);
  await prisma.recurringBookingSeries.update({
    where: { id: seriesId },
    data: { nextRunDate: new Date(next + 'T00:00:00.000Z'), lastRunAt: new Date(), lastRunError: null },
  });
}

async function notifyGenerated(clientId: string, walkDate: string, paidAutomatically: boolean) {
  await sendPushToUser(
    clientId,
    paidAutomatically ? '🐾 Tu paseo recurrente ya está pagado' : '🐾 Tu paseo recurrente está listo',
    paidAutomatically
      ? `Se generó y pagó automáticamente con tu billetera el paseo del ${walkDate}.`
      : `Se generó tu paseo recurrente del ${walkDate} — complétalo pagando desde la app.`,
    { type: 'recurring_booking_generated', walkDate }
  ).catch(() => {});
}

async function notifySkipped(clientId: string, walkDate: string, reason?: string) {
  await sendPushToUser(
    clientId,
    '⚠️ No pudimos generar tu paseo recurrente',
    `El paseo del ${walkDate} no se pudo crear (${reason ?? 'el cuidador no tiene cupo'}). Tu serie sigue activa para la próxima fecha.`,
    { type: 'recurring_booking_skipped', walkDate }
  ).catch(() => {});
}

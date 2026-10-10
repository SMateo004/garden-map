/**
 * Ocupación diaria del cupo combinado Hospedaje + Guardería de un cuidador, sumando las
 * reservas de la app y los clientes de mostrador (recepción). La usan el marketplace
 * (booking.service.ts, para no vender lugares ocupados) y la recepción (para no meter más
 * mascotas de las que entran) — así ambos lados cuentan exactamente lo mismo.
 *
 * Mostrador, por día d:
 *   - visitas abiertas (mascota en el local)  → cuentan HOY
 *   - reservas de mostrador RESERVED           → cada día que cubren (la mascota viene)
 *   - reservas CHECKED_IN                      → los días que cubren DESPUÉS de hoy (hoy ya
 *                                                la cuenta su visita abierta)
 * Fechas en UTC 'YYYY-MM-DD'; endDate siempre exclusiva (como Booking.endDate).
 */
import { BookingStatus, Prisma, ServiceType } from '@prisma/client';
import { combinedHospedajeGuarderiaMax } from '../../utils/caregiver-capacity.js';

const IN_PREMISES: ServiceType[] = [ServiceType.HOSPEDAJE, ServiceType.GUARDERIA];

/** Hoy en Bolivia (UTC−4) como 'YYYY-MM-DD'. */
export function boliviaToday(now = new Date()): string {
  return new Date(now.getTime() - 4 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

export function dayKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/** Días 'YYYY-MM-DD' en [start, end). */
export function daysBetween(start: Date, end: Date): string[] {
  const out: string[] = [];
  for (let d = new Date(start); d < end; d.setUTCDate(d.getUTCDate() + 1)) out.push(dayKey(d));
  return out;
}

function add(map: Map<string, number>, day: string, n: number) {
  map.set(day, (map.get(day) ?? 0) + n);
}

/** Mascotas de mostrador por día en [start, end). */
export async function walkInPetsByDay(
  tx: Prisma.TransactionClient,
  caregiverProfileId: string,
  start: Date,
  end: Date,
  today = boliviaToday()
): Promise<Map<string, number>> {
  const byDay = new Map<string, number>();
  const inRange = (day: string) => day >= dayKey(start) && day < dayKey(end);

  const [openVisits, reservations] = await Promise.all([
    inRange(today)
      ? tx.walkInVisit.count({
          where: { caregiverProfileId, checkedOutAt: null, serviceType: { in: IN_PREMISES } },
        })
      : Promise.resolve(0),
    tx.walkInReservation.findMany({
      where: {
        caregiverProfileId,
        status: { in: ['RESERVED', 'CHECKED_IN'] },
        startDate: { lt: end },
        endDate: { gt: start },
      },
      select: { startDate: true, endDate: true, status: true },
    }),
  ]);

  if (openVisits > 0) add(byDay, today, openVisits);
  for (const r of reservations) {
    for (const day of daysBetween(r.startDate, r.endDate)) {
      if (!inRange(day)) continue;
      if (r.status === 'CHECKED_IN' && day <= today) continue;
      add(byDay, day, 1);
    }
  }
  return byDay;
}

/** Reservas de la app que ocupan el cupo: activas o con pago en curso (<15 min). */
function activeBookingFilter(): Prisma.BookingWhereInput {
  return {
    OR: [
      {
        status: {
          in: [
            BookingStatus.PAYMENT_PENDING_APPROVAL,
            BookingStatus.WAITING_CAREGIVER_APPROVAL,
            BookingStatus.CONFIRMED,
            BookingStatus.IN_PROGRESS,
            BookingStatus.PENDING_MG,
          ],
        },
      },
      { status: BookingStatus.PENDING_PAYMENT, createdAt: { gte: new Date(Date.now() - 15 * 60 * 1000) } },
    ],
  };
}

/** Ocupación combinada por día en [start, end): hospedaje + guardería de la app + mostrador. */
export async function combinedOccupancyByDay(
  tx: Prisma.TransactionClient,
  caregiverProfileId: string,
  start: Date,
  end: Date
): Promise<{ maxPets: number; byDay: Map<string, number> }> {
  const [profile, hospedaje, guarderia, walkIn] = await Promise.all([
    tx.caregiverProfile.findUnique({
      where: { id: caregiverProfileId },
      select: { maxPetsHospedaje: true, maxPetsGuarderia: true, maxPets: true },
    }),
    tx.booking.findMany({
      where: { caregiverId: caregiverProfileId, serviceType: 'HOSPEDAJE', ...activeBookingFilter(), startDate: { lt: end }, endDate: { gt: start } },
      select: { startDate: true, endDate: true, petCount: true },
    }),
    tx.booking.findMany({
      where: { caregiverId: caregiverProfileId, serviceType: 'GUARDERIA', ...activeBookingFilter(), walkDate: { gte: start, lt: end } },
      select: { walkDate: true, petCount: true },
    }),
    walkInPetsByDay(tx, caregiverProfileId, start, end),
  ]);

  const byDay = new Map<string, number>();
  const startKey = dayKey(start);
  const endKey = dayKey(end);
  for (const b of hospedaje) {
    if (!b.startDate || !b.endDate) continue;
    for (const day of daysBetween(b.startDate, b.endDate)) {
      if (day >= startKey && day < endKey) add(byDay, day, b.petCount ?? 1);
    }
  }
  for (const b of guarderia) {
    if (b.walkDate) add(byDay, dayKey(b.walkDate), b.petCount ?? 1);
  }
  for (const [day, n] of walkIn) add(byDay, day, n);

  return { maxPets: combinedHospedajeGuarderiaMax(profile ?? {}), byDay };
}

/** Primer día en [start, end) donde no entran `newPets` más, o null si hay lugar todos los días. */
export function firstFullDay(
  occupancy: { maxPets: number; byDay: Map<string, number> },
  start: Date,
  end: Date,
  newPets = 1
): { day: string; occupied: number } | null {
  for (const day of daysBetween(start, end)) {
    const occupied = occupancy.byDay.get(day) ?? 0;
    if (occupied + newPets > occupancy.maxPets) return { day, occupied };
  }
  return null;
}

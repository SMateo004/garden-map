import { CaregiverStatus, ServiceType, Zone, type TimeSlot } from '@prisma/client';
import type { Prisma } from '@prisma/client';
import prisma from '../../config/database.js';
import { getCache, CAREGIVER_LIST_CACHE_TTL, CAREGIVER_DETAIL_CACHE_TTL } from '../../shared/cache.js';
import {
  CaregiverNotFoundError,
  CaregiverProfileValidationError,
  ConflictError,
} from '../../shared/errors.js';
import type {
  CaregiverListItem,
  CaregiverDetail,
  CaregiverFilters,
  PaginatedCaregivers,
  CreateCaregiverProfileInput,
} from './caregiver.types.js';
import { type PaseoSlot, parseTimeBlocks } from '../../shared/availability-utils.js';
import { PHOTO_COUNT, MAX_BIO_CHARS } from './caregiver.validation.js';
import logger from '../../shared/logger.js';
import { blockchainService } from '../../services/blockchain.service.js';

const cache = getCache();
const MARKUP_RATE = 0.10;

/**
 * Aplica el 10% de comisión GARDEN al precio del cuidador.
 * El cliente ve el precio final, pero al cuidador se le paga su base.
 */
function applyMarkup(price: number | null | undefined): number | null {
  if (price === null || price === undefined) return null;
  const val = typeof price === 'number' ? price : Number(price);
  return Math.round(val * (1 + MARKUP_RATE));
}

/**
 * Lista cuidadores verificados con filtros y paginación.
 * Solo status=APPROVED y verified=true (aparecen tras approve del admin). Orden: rating DESC, createdAt DESC.
 */
export async function listCaregivers(filters: CaregiverFilters): Promise<PaginatedCaregivers> {
  const { service, zone, priceRange, spaceTypes, page = 1, limit = 10 } = filters;

  const cacheKey = `caregivers:list:${JSON.stringify({
    service: service ?? '',
    zone: Array.isArray(zone) ? zone.join(',') : zone ?? '',
    priceRange: priceRange ?? '',
    spaceTypes: Array.isArray(spaceTypes) ? spaceTypes.join(',') : spaceTypes ?? '',
    page,
    limit,
  })}`;
  const cached = await cache.get<PaginatedCaregivers>(cacheKey);
  if (cached) return cached;

  const zones: Zone[] | undefined = Array.isArray(zone)
    ? (zone as Zone[])
    : typeof zone === 'string'
      ? (zone.split(',').map((z) => z.trim()).filter((z): z is Zone => Object.values(Zone).includes(z as Zone)))
      : undefined;
  const zonesFilter = zones?.length ? zones : undefined;

  const where: Prisma.CaregiverProfileWhereInput = {
    suspended: false,
    status: CaregiverStatus.APPROVED,
    verified: true,
  };

  if (zonesFilter?.length) {
    where.zone = { in: zonesFilter };
  }

  if (service && service !== 'ambos') {
    const st = service === ServiceType.PASEO ? ServiceType.PASEO : ServiceType.HOSPEDAJE;
    where.servicesOffered = { has: st };
  }

  // Filtrar por tipos de espacio (multi-select): usar hasSome si hay múltiples valores
  if (spaceTypes && Array.isArray(spaceTypes) && spaceTypes.length > 0) {
    // Convertir query params (snake_case) a valores display
    const spaceTypeDisplayValues = spaceTypes.map((st) => {
      // Mapeo inverso: query param → display value
      const mapping: Record<string, string> = {
        casa_con_patio: 'Casa con patio',
        casa_sin_patio: 'Casa sin patio',
        departamento_pequeno: 'Departamento pequeño',
        departamento_amplio: 'Departamento amplio',
      };
      return mapping[st] || st; // Si no está en el mapeo, usar el valor tal cual
    }).filter(Boolean);

    if (spaceTypeDisplayValues.length > 0) {
      // Prisma hasSome: el array spaceType debe contener al menos uno de los valores seleccionados
      where.spaceType = { hasSome: spaceTypeDisplayValues };
    }
  }

  if (priceRange) {
    if (priceRange === 'economico') {
      where.pricePerDay = { gte: Math.ceil(60 / (1 + MARKUP_RATE)), lte: Math.floor(100 / (1 + MARKUP_RATE)) };
    } else if (priceRange === 'estandar') {
      where.pricePerDay = { gte: Math.ceil(100 / (1 + MARKUP_RATE)), lte: Math.floor(140 / (1 + MARKUP_RATE)) };
    } else {
      where.pricePerDay = { gte: Math.ceil(140 / (1 + MARKUP_RATE)) };
    }
  }

  const [caregivers, total] = await Promise.all([
    prisma.caregiverProfile.findMany({
      where,
      include: { user: { select: { firstName: true, lastName: true, profilePicture: true } } },
      orderBy: [{ rating: 'desc' }, { createdAt: 'desc' }],
      skip: (page - 1) * limit,
      take: limit,
    }),
    prisma.caregiverProfile.count({ where }),
  ]);

  const pages = Math.ceil(total / limit) || 1;
  const result: PaginatedCaregivers = {
    caregivers: caregivers.map((c) => ({
      id: c.id,
      firstName: c.user?.firstName ?? '',
      lastName: c.user?.lastName ?? '',
      profilePicture: c.profilePhoto ?? c.user?.profilePicture ?? null,
      photos: Array.isArray(c.photos) ? c.photos : [],
      zone: c.zone ?? '',
      services: c.servicesOffered,
      rating: c.rating,
      reviewCount: c.reviewCount,
      pricePerDay: applyMarkup(c.pricePerDay),
      pricePerWalk30: applyMarkup(c.pricePerWalk30),
      pricePerWalk60: applyMarkup(c.pricePerWalk60),
      verified: c.verified,
      spaceType: Array.isArray(c.spaceType) ? c.spaceType : (c.spaceType ? [c.spaceType] : []),
    })),
    pagination: {
      total,
      page,
      currentPage: page,
      pages,
      limit,
    },
  };

  try {
    await cache.set(cacheKey, result, CAREGIVER_LIST_CACHE_TTL);
  } catch (e) {
    logger.warn('Cache set failed for caregiver list', { cacheKey, error: (e as Error).message });
  }
  return result;
}

/**
 * Detalle público de cuidador para clientes (GET /api/caregivers/:id).
 * Solo devuelve perfiles APPROVED y verified; si no → null (404).
 * No expone CI, adminNotes, rejectionReason ni datos privados.
 */
export async function getCaregiverById(id: string): Promise<CaregiverDetail | null> {
  const cacheKey = `caregivers:detail:${id}`;
  const cached = await cache.get<CaregiverDetail>(cacheKey);
  if (cached) return cached;

  // Solo visibles para clientes: APPROVED, verified, no suspendido
  const publicWhere = {
    id,
    suspended: false,
    status: CaregiverStatus.APPROVED,
    verified: true,
  };

  // Manejar el caso donde timeBlocks no existe en la DB
  let profile;
  try {
    profile = await prisma.caregiverProfile.findUnique({
      where: publicWhere,
      include: {
        user: { select: { firstName: true, lastName: true, profilePicture: true } },
        reviews: {
          take: 10,
          orderBy: { createdAt: 'desc' },
          include: {
            client: { select: { firstName: true, lastName: true, profilePicture: true } },
          },
        },
        availability: {
          where: { date: { gte: new Date() } },
          orderBy: { date: 'asc' },
          take: 90,
          select: {
            id: true,
            caregiverId: true,
            date: true,
            isAvailable: true,
            timeBlocks: true,
          },
        },
      },
    });
  } catch (includeError: any) {
    // Si falla por columna faltante (P2022 o mensaje indica timeBlocks/column), intentamos sin timeBlocks
    const isTimeBlocksColumnMissing =
      (includeError?.code === 'P2022' && includeError?.message?.includes('timeBlocks')) ||
      (typeof includeError?.message === 'string' &&
        includeError.message.includes('timeBlocks') &&
        (includeError.message.includes('does not exist') || includeError.message.includes('column')));
    if (isTimeBlocksColumnMissing) {
      logger.warn('timeBlocks column does not exist in getCaregiverById, querying without it', { id });
      profile = await prisma.caregiverProfile.findUnique({
        where: publicWhere,
        include: {
          user: { select: { firstName: true, lastName: true, profilePicture: true } },
          reviews: {
            take: 10,
            orderBy: { createdAt: 'desc' },
            include: {
              client: { select: { firstName: true, lastName: true, profilePicture: true } },
            },
          },
          availability: {
            where: { date: { gte: new Date() } },
            orderBy: { date: 'asc' },
            take: 90,
            select: {
              id: true,
              caregiverId: true,
              date: true,
              isAvailable: true,
              // timeBlocks omitido porque no existe en la DB
            },
          },
        },
      });
      // Agregar timeBlocks como null a todas las filas de availability
      if (profile?.availability) {
        profile.availability = profile.availability.map((av: any) => ({ ...av, timeBlocks: null }));
      }
    } else {
      // Si es otro error, lo relanzamos
      throw includeError;
    }
  }

  if (!profile) return null;

  const availabilityList = Array.isArray(profile.availability) ? profile.availability : [];
  const hospedajeDates: string[] = [];
  const paseosByDate: Record<string, PaseoSlot[]> = {};
  const datesWithExplicitRow = new Set<string>();

  for (const a of availabilityList) {
    const dateStr = a.date.toISOString().slice(0, 10);
    datesWithExplicitRow.add(dateStr);
    if (a.isAvailable) {
      hospedajeDates.push(dateStr);
    }
    const slots = parseTimeBlocks((a as any).timeBlocks);
    if (slots.length) paseosByDate[dateStr] = slots;
  }

  // Aplicar horario predeterminado (o defaults absolutos) a fechas sin fila explícita
  const defaultSchedule = (profile.defaultAvailabilitySchedule as any) || { hospedajeDefault: true };
  const cur = new Date();
  cur.setHours(0, 0, 0, 0);
  const end = new Date();
  end.setDate(end.getDate() + 90);
  end.setHours(0, 0, 0, 0);

  while (cur <= end) {
    const dStr = cur.toISOString().slice(0, 10);
    if (!datesWithExplicitRow.has(dStr)) {
      if (defaultSchedule.hospedajeDefault !== false) {
        hospedajeDates.push(dStr);
      }
      const ptb = defaultSchedule.paseoTimeBlocks || defaultSchedule.weekly?.[dStr];
      let slots = parseTimeBlocks(ptb);
      // Si no hay horario configurado en absoluto, habilitar todos los bloques por defecto
      if (!profile.defaultAvailabilitySchedule && slots.length === 0) {
        slots = [
          { slot: 'MANANA', enabled: true, start: '08:00', end: '11:00' },
          { slot: 'TARDE', enabled: true, start: '13:00', end: '17:00' },
          { slot: 'NOCHE', enabled: true, start: '19:00', end: '22:00' }
        ];
      }
      if (slots.length > 0) {
        paseosByDate[dStr] = slots;
      }
    }
    cur.setDate(cur.getDate() + 1);
  }

  const detail: CaregiverDetail = {
    id: profile.id,
    firstName: profile.user.firstName,
    lastName: profile.user.lastName,
    profilePicture: profile.profilePhoto ?? profile.user.profilePicture,
    zone: profile.zone ?? '',
    services: profile.servicesOffered,
    rating: profile.rating,
    reviewCount: profile.reviewCount,
    pricePerDay: applyMarkup(profile.pricePerDay),
    pricePerWalk30: applyMarkup(profile.pricePerWalk30),
    pricePerWalk60: applyMarkup(profile.pricePerWalk60),
    verified: profile.verified,
    spaceType: Array.isArray(profile.spaceType) ? profile.spaceType : (profile.spaceType ? [profile.spaceType] : []),
    bio: profile.bio,
    photos: Array.isArray(profile.photos) ? profile.photos : [],
    availability: {
      hospedaje: hospedajeDates,
      paseos: paseosByDate,
    },
    reviews: profile.reviews.map((r) => ({
      id: r.id,
      clientName: `${r.client.firstName} ${r.client.lastName.charAt(0)}.`,
      clientPhoto: r.client.profilePicture,
      rating: r.rating,
      comment: r.comment,
      serviceType: r.serviceType,
      createdAt: r.createdAt,
    })),
    // Campos detallados (Questionnaire)
    bioDetail: profile.bioDetail,
    experienceYears: profile.experienceYears,
    experienceDescription: profile.experienceDescription,
    whyCaregiver: profile.whyCaregiver,
    whatDiffers: profile.whatDiffers,
    handleAnxious: profile.handleAnxious,
    emergencyResponse: profile.emergencyResponse,
    acceptAggressive: profile.acceptAggressive,
    acceptPuppies: profile.acceptPuppies,
    acceptSeniors: profile.acceptSeniors,
    sizesAccepted: profile.sizesAccepted,
    animalTypes: profile.animalTypes,
    acceptMedication: profile.acceptMedication,
    typicalDay: profile.typicalDay,
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
    spaceDescription: profile.spaceDescription,
  };

  // Enriquecer con reputación de blockchain
  try {
    const bcRep = await blockchainService.getCaregiverReputation(id);
    if (bcRep) {
      detail.blockchainReputation = {
        average: bcRep.average,
        count: bcRep.count,
        verified: true,
      };
    }
  } catch (bcError) {
    logger.warn('Error fetching blockchain reputation for detail', { id, bcError });
  }

  await cache.set(cacheKey, detail, CAREGIVER_DETAIL_CACHE_TTL);
  return detail;
}

/** Respuesta de GET /api/caregivers/:id/availability */
export interface CaregiverAvailabilityResponse {
  caregiverId: string;
  from: string; // ISO date
  to: string;   // ISO date
  hospedaje: string[]; // fechas YYYY-MM-DD disponibles para hospedaje
  paseos: Record<string, PaseoSlot[]>; // fecha -> [{slot, enabled, start?, end?}] disponibles
  bookedPaseos?: { date: string; startTime: string; duration: number; status: string }[];
}

/**
 * Obtiene disponibilidad del cuidador desde el modelo Availability.
 * Solo cuidador APPROVED. from/to por defecto: hoy + 90 días.
 * Retorna array vacío si no hay disponibilidad (no lanza error).
 */
export async function getCaregiverAvailability(
  caregiverId: string,
  from?: Date,
  to?: Date
): Promise<CaregiverAvailabilityResponse> {
  try {
    // Validación de caregiverId
    if (!caregiverId || typeof caregiverId !== 'string' || caregiverId.trim() === '') {
      logger.warn('Invalid caregiverId in getCaregiverAvailability', { caregiverId });
      throw new CaregiverNotFoundError(caregiverId || '');
    }

    // Normalizar fechas
    const start = from ?? new Date();
    const end = to ?? new Date(Date.now() + 90 * 24 * 60 * 60 * 1000);

    // Normalizar fechas a inicio del día (00:00:00) para comparaciones consistentes
    // IMPORTANTE: Prisma @db.Date solo almacena fecha sin hora, así que normalizamos a medianoche UTC
    const startDate = new Date(Date.UTC(start.getFullYear(), start.getMonth(), start.getDate(), 0, 0, 0, 0));
    const endDate = new Date(Date.UTC(end.getFullYear(), end.getMonth(), end.getDate(), 0, 0, 0, 0));

    // Verificar que el cuidador existe y está APPROVED
    let profile;
    try {
      profile = await prisma.caregiverProfile.findFirst({
        where: {
          id: caregiverId,
          status: CaregiverStatus.APPROVED,
          suspended: false
        },
        select: { id: true, defaultAvailabilitySchedule: true },
      });

    } catch (dbError) {
      logger.error('Database error checking caregiver profile - RETURNING EMPTY', {
        caregiverId,
        error: dbError instanceof Error ? dbError.message : String(dbError),
        stack: dbError instanceof Error ? dbError.stack : undefined,
        errorName: dbError instanceof Error ? dbError.name : undefined,
      });
      // Si hay error de DB, retornar disponibilidad vacía en lugar de fallar
      return {
        caregiverId,
        from: startDate.toISOString().slice(0, 10),
        to: endDate.toISOString().slice(0, 10),
        hospedaje: [],
        paseos: {},
      };
    }

    if (!profile) {
      logger.warn('Caregiver not found or not approved for availability - RETURNING EMPTY', {
        caregiverId,
        note: 'Returning empty availability instead of error',
      });
      // En lugar de lanzar error, retornar disponibilidad vacía
      // Esto permite que el frontend muestre el calendario sin fechas disponibles
      return {
        caregiverId,
        from: startDate.toISOString().slice(0, 10),
        to: endDate.toISOString().slice(0, 10),
        hospedaje: [],
        paseos: {},
      };
    }

    // Consultar disponibilidad - puede retornar array vacío sin problema
    // IMPORTANTE: Para campos @db.Date, Prisma espera objetos Date normalizados a medianoche UTC
    let rows;
    try {
      // Manejar el caso donde timeBlocks no existe en la DB (migración no aplicada)
      // Intentamos primero con timeBlocks, y si falla, lo intentamos sin él
      try {
        rows = await prisma.availability.findMany({
          where: {
            caregiverId,
            date: {
              gte: startDate,
              lte: endDate
            },
          },
          orderBy: { date: 'asc' },
        });
      } catch (prismaError: any) {
        // Si falla por columna faltante (P2022 o mensaje indica timeBlocks/column), intentamos sin timeBlocks
        const isTimeBlocksColumnMissing =
          (prismaError?.code === 'P2022' && prismaError?.message?.includes('timeBlocks')) ||
          (typeof prismaError?.message === 'string' &&
            prismaError.message.includes('timeBlocks') &&
            (prismaError.message.includes('does not exist') || prismaError.message.includes('column')));
        if (isTimeBlocksColumnMissing) {
          logger.warn('timeBlocks column does not exist, querying without it', { caregiverId });
          const rowsWithoutTimeBlocks = await prisma.availability.findMany({
            where: {
              caregiverId,
              date: {
                gte: startDate,
                lte: endDate
              },
            },
            select: {
              id: true,
              caregiverId: true,
              date: true,
              isAvailable: true,
            },
            orderBy: { date: 'asc' },
          });
          // Agregar timeBlocks como null a todas las filas
          rows = rowsWithoutTimeBlocks.map((row: any) => ({ ...row, timeBlocks: null })) as any[];
        } else {
          // Si es otro error, lo relanzamos para que lo maneje el catch externo
          throw prismaError;
        }
      }

    } catch (dbError) {
      // Logging agresivo del error de DB
      logger.error('Database error querying availability - CRITICAL ERROR', {
        caregiverId,
        error: dbError instanceof Error ? dbError.message : String(dbError),
        stack: dbError instanceof Error ? dbError.stack : undefined,
        errorName: dbError instanceof Error ? dbError.name : undefined,
        errorCode: (dbError as any)?.code,
        startDate: startDate.toISOString(),
        endDate: endDate.toISOString(),
        startDateType: typeof startDate,
        endDateType: typeof endDate,
      });

      // Si hay error de DB, retornar disponibilidad vacía en lugar de fallar
      // Esto evita el 500 y permite que el frontend muestre el calendario vacío
      return {
        caregiverId,
        from: startDate.toISOString().slice(0, 10),
        to: endDate.toISOString().slice(0, 10),
        hospedaje: [],
        paseos: {},
      };
    }

    // Procesar filas de disponibilidad con manejo robusto de errores
    const hospedajeDates: string[] = [];
    const paseosByDate: Record<string, PaseoSlot[]> = {};
    const datesWithExplicitRow = new Set<string>();

    for (let i = 0; i < rows.length; i++) {
      const a = rows[i];
      try {
        // Validar que el objeto de fila existe
        if (!a || typeof a !== 'object') {
          logger.warn('Invalid row object in availability', {
            index: i,
            caregiverId,
            row: a,
          });
          continue;
        }

        // Validar que date existe y es válida
        // Prisma devuelve Date objects para campos DateTime @db.Date
        if (!a.date) {
          logger.warn('Missing date in availability row', {
            availabilityId: a.id,
            caregiverId,
            index: i,
          });
          continue;
        }

        let dateObj: Date;
        try {
          if (a.date instanceof Date) {
            dateObj = a.date;
          } else if (typeof a.date === 'string') {
            dateObj = new Date(a.date);
          } else {
            logger.warn('Invalid date type in availability row', {
              availabilityId: a.id,
              caregiverId,
              dateType: typeof a.date,
              date: a.date,
              index: i,
            });
            continue;
          }
        } catch (dateParseError) {
          logger.warn('Error parsing date from availability row', {
            availabilityId: a.id,
            caregiverId,
            date: a.date,
            error: dateParseError instanceof Error ? dateParseError.message : String(dateParseError),
            index: i,
          });
          continue;
        }

        // Validar que la fecha es válida
        if (isNaN(dateObj.getTime())) {
          logger.warn('Invalid date value in availability row', {
            availabilityId: a.id,
            caregiverId,
            date: a.date,
            parsedDate: dateObj.toISOString(),
            index: i,
          });
          continue;
        }

        const dateStr = dateObj.toISOString().slice(0, 10);
        datesWithExplicitRow.add(dateStr);

        // Procesar hospedaje (isAvailable) - validar tipo boolean
        if (a.isAvailable === true) {
          hospedajeDates.push(dateStr);
        }

        // Procesar timeBlocks de forma segura para paseos
        const slots = parseTimeBlocks((a as any).timeBlocks);
        if (slots.length > 0) {
          paseosByDate[dateStr] = slots;
        }
      } catch (rowError) {
        logger.warn('Error processing availability row - SKIPPING', {
          availabilityId: a?.id,
          caregiverId,
          index: i,
          error: rowError instanceof Error ? rowError.message : String(rowError),
          stack: rowError instanceof Error ? rowError.stack : undefined,
          rowData: a ? { id: a.id, date: a.date, isAvailable: a.isAvailable } : 'null',
        });
        // Continuar con el siguiente registro en lugar de fallar todo
        continue;
      }
    }

    // Aplicar horario predeterminado (o defaults absolutos) a fechas sin fila explícita
    const defaultSchedule = (profile?.defaultAvailabilitySchedule as any) || { hospedajeDefault: true };
    const cur = new Date(startDate);
    while (cur <= endDate) {
      const dStr = cur.toISOString().slice(0, 10);
      if (!datesWithExplicitRow.has(dStr)) {
        if (defaultSchedule.hospedajeDefault !== false) {
          hospedajeDates.push(dStr);
        }
        const ptb = defaultSchedule.paseoTimeBlocks || defaultSchedule.weekly?.[dStr]; // fallback to weekly if exists
        let slots = parseTimeBlocks(ptb);
        // Si no hay horario configurado en absoluto para el perfil, habilitar todos los bloques por defecto
        if (!profile.defaultAvailabilitySchedule && slots.length === 0) {
          slots = [
            { slot: 'MANANA', enabled: true, start: '08:00', end: '11:00' },
            { slot: 'TARDE', enabled: true, start: '13:00', end: '17:00' },
            { slot: 'NOCHE', enabled: true, start: '19:00', end: '22:00' }
          ];
        }
        if (slots.length > 0) {
          paseosByDate[dStr] = slots;
        }
      }
      cur.setDate(cur.getDate() + 1);
    }

    logger.info('Availability fetched', {
      caregiverId,
      hospedajeCount: hospedajeDates.length,
      paseosCount: Object.keys(paseosByDate).length,
    });
    // 5. Fetch all active bookings (both types) to calculate real availability
    const expirationDate = new Date(Date.now() - 15 * 60 * 1000);
    const activeBookings = await prisma.booking.findMany({
      where: {
        caregiverId,
        AND: [
          {
            OR: [
              { status: { in: ['CONFIRMED', 'IN_PROGRESS', 'PAYMENT_PENDING_APPROVAL', 'COMPLETED'] } },
              { status: 'PENDING_PAYMENT', createdAt: { gte: expirationDate } }
            ]
          },
          {
            OR: [
              {
                serviceType: 'HOSPEDAJE',
                startDate: { lte: endDate },
                endDate: { gte: startDate }
              },
              {
                serviceType: 'PASEO',
                walkDate: { gte: startDate, lte: endDate }
              }
            ]
          }
        ]
      },
      select: {
        id: true,
        serviceType: true,
        startDate: true,
        endDate: true,
        walkDate: true,
        startTime: true,
        duration: true,
        status: true
      }
    });

    // 6. Filter hospedajeDates (remove dates blocked by active bookings)
    const blockedHospedajeDates = new Set<string>();
    activeBookings.forEach(b => {
      if (b.serviceType === 'HOSPEDAJE' && b.startDate && b.endDate) {
        // Normalizamos fechas para comparar strings YYYY-MM-DD
        let cur = new Date(b.startDate);
        // Aseguramos que empezamos a contar desde la fecha de inicio del bloque solicitado o la de la reserva, la mayor
        const rangeStart = startDate > b.startDate ? startDate : b.startDate;
        const rangeEnd = endDate < b.endDate ? endDate : b.endDate;

        let d = new Date(b.startDate);
        while (d < b.endDate) {
          blockedHospedajeDates.add(d.toISOString().slice(0, 10));
          d.setDate(d.getDate() + 1);
        }
      }
    });

    const finalHospedajeDates = hospedajeDates.filter(d => !blockedHospedajeDates.has(d));

    // 7. Prepare bookedPaseos for frontend validation/UI
    const bookedPaseos = activeBookings
      .filter(b => b.serviceType === 'PASEO' && b.walkDate)
      .map(b => ({
        date: b.walkDate!.toISOString().slice(0, 10),
        startTime: b.startTime || '00:00',
        duration: b.duration || 0,
        status: b.status,
      }));

    logger.info('Availability processed with active bookings', {
      caregiverId,
      originalHospedaje: hospedajeDates.length,
      finalHospedaje: finalHospedajeDates.length,
      bookedPaseos: bookedPaseos.length,
    });

    return {
      caregiverId,
      from: startDate.toISOString().slice(0, 10),
      to: endDate.toISOString().slice(0, 10),
      hospedaje: finalHospedajeDates,
      paseos: paseosByDate,
      bookedPaseos,
    };
  } catch (err) {
    logger.error('ERROR en getCaregiverAvailability - CATCH BLOCK', {
      error: err instanceof Error ? err.message : String(err),
      stack: err instanceof Error ? err.stack : undefined,
      errorName: err instanceof Error ? err.name : undefined,
      caregiverId,
      from: from?.toISOString(),
      to: to?.toISOString(),
      isOperational: err instanceof Error && 'isOperational' in err ? (err as any).isOperational : undefined,
    });

    // Calcular fechas por defecto para el retorno
    const start = from ?? new Date();
    const end = to ?? new Date(Date.now() + 90 * 24 * 60 * 60 * 1000);
    const sD = new Date(start.getFullYear(), start.getMonth(), start.getDate(), 0, 0, 0, 0);
    const eD = new Date(end.getFullYear(), end.getMonth(), end.getDate(), 23, 59, 59, 999);

    return {
      caregiverId,
      from: sD.toISOString().slice(0, 10),
      to: eD.toISOString().slice(0, 10),
      hospedaje: [],
      paseos: {},
      bookedPaseos: [],
    };
  }
}

export function validatePhotoCount(photos: string[]): void {
  if (photos.length < PHOTO_COUNT.min || photos.length > PHOTO_COUNT.max) {
    throw new CaregiverProfileValidationError(
      `Debes subir entre ${PHOTO_COUNT.min} y ${PHOTO_COUNT.max} fotos`
    );
  }
}

export function validateBio(bio: string): void {
  if (bio.length > MAX_BIO_CHARS) {
    throw new CaregiverProfileValidationError(`Bio máximo ${MAX_BIO_CHARS} caracteres`);
  }
}

/** Crea un perfil de cuidador. Falla si ya existe (ConflictError). */
export async function createCaregiverProfile(
  userId: string,
  input: CreateCaregiverProfileInput,
  photoUrls: string[]
): Promise<CaregiverListItem> {
  validateBio(input.bio);
  validatePhotoCount(photoUrls);

  const existing = await prisma.caregiverProfile.findUnique({ where: { userId } });
  if (existing) {
    throw new ConflictError('Ya tienes un perfil de cuidador');
  }

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user || user.role !== 'CAREGIVER') {
    throw new CaregiverProfileValidationError('Usuario no es cuidador');
  }

  const profile = await prisma.caregiverProfile.create({
    data: {
      userId,
      bio: input.bio,
      zone: input.zone as Zone,
      spaceType: Array.isArray(input.spaceType) ? input.spaceType : (input.spaceType ? [input.spaceType] : []),
      photos: photoUrls,
      servicesOffered: input.servicesOffered,
      pricePerDay: input.pricePerDay,
      pricePerWalk30: input.pricePerWalk30,
      pricePerWalk60: input.pricePerWalk60,
      verified: false,
    },
    include: { user: { select: { firstName: true, lastName: true, profilePicture: true } } },
  });

  return mapProfileToListItem(profile);
}

/**
 * Crea o actualiza el perfil de cuidador del usuario (upsert).
 * - Solo usuarios con role CAREGIVER.
 * - verified permanece false; solo admin puede verificar.
 * - Usa transacción Prisma para guardar perfil + fotos atómicamente.
 */
export async function upsertCaregiverProfile(
  userId: string,
  input: CreateCaregiverProfileInput,
  photoUrls: string[]
): Promise<{ profile: CaregiverListItem; created: boolean }> {
  validateBio(input.bio);
  validatePhotoCount(photoUrls);

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user || user.role !== 'CAREGIVER') {
    throw new CaregiverProfileValidationError('Usuario no es cuidador');
  }

  const profileData = {
    bio: input.bio,
    zone: input.zone as Zone,
    spaceType: Array.isArray(input.spaceType) ? input.spaceType : (input.spaceType ? [input.spaceType] : []),
    photos: photoUrls,
    servicesOffered: input.servicesOffered,
    pricePerDay: input.pricePerDay ?? null,
    pricePerWalk30: input.pricePerWalk30 ?? null,
    pricePerWalk60: input.pricePerWalk60 ?? null,
  };

  const result = await prisma.$transaction(async (tx) => {
    const existing = await tx.caregiverProfile.findUnique({ where: { userId } });

    if (existing) {
      const updated = await tx.caregiverProfile.update({
        where: { id: existing.id },
        data: profileData,
        include: { user: { select: { firstName: true, lastName: true, profilePicture: true } } },
      });
      return { profile: updated, created: false };
    }

    const created = await tx.caregiverProfile.create({
      data: {
        userId,
        ...profileData,
        verified: false,
      },
      include: { user: { select: { firstName: true, lastName: true, profilePicture: true } } },
    });
    return { profile: created, created: true };
  });

  if (!result.created) {
    await getCache().del(`caregivers:detail:${result.profile.id}`);
  }

  return {
    profile: mapProfileToListItem(result.profile),
    created: result.created,
  };
}

function mapProfileToListItem(
  profile: {
    id: string;
    zone: Zone | null;
    servicesOffered: ServiceType[];
    rating: number;
    reviewCount: number;
    pricePerDay: number | null;
    pricePerWalk30: number | null;
    pricePerWalk60: number | null;
    verified: boolean;
    spaceType: string[]; // Array de tipos de espacio
    profilePhoto?: string | null;
    photos?: string[];
    user: { firstName: string; lastName: string; profilePicture: string | null };
  }
): CaregiverListItem {
  const p = profile as { profilePhoto?: string | null; photos?: string[] };
  return {
    id: profile.id,
    firstName: profile.user.firstName,
    lastName: profile.user.lastName,
    profilePicture: p.profilePhoto ?? profile.user.profilePicture,
    photos: Array.isArray(p.photos) ? p.photos : [],
    zone: profile.zone ?? '',
    services: profile.servicesOffered,
    rating: profile.rating,
    reviewCount: profile.reviewCount,
    pricePerDay: applyMarkup(profile.pricePerDay),
    pricePerWalk30: applyMarkup(profile.pricePerWalk30),
    pricePerWalk60: applyMarkup(profile.pricePerWalk60),
    verified: profile.verified,
    spaceType: Array.isArray(profile.spaceType) ? profile.spaceType : (profile.spaceType ? [profile.spaceType] : []),
  };
}

export async function getCaregiverProfileByUserId(userId: string) {
  return prisma.caregiverProfile.findUnique({
    where: { userId },
    include: { user: true },
  });
}

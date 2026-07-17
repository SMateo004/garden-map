import { CaregiverStatus, ServiceType, Zone, Prisma, type TimeSlot } from '@prisma/client';
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
import { type PaseoSlot, parseTimeBlocks, BOLIVIA_HOLIDAYS } from '../../shared/availability-utils.js';
import { PHOTO_COUNT, MAX_BIO_CHARS } from './caregiver.validation.js';
import logger from '../../shared/logger.js';
import { blockchainService } from '../../services/blockchain.service.js';
import { getNumericSetting } from '../../utils/settings-cache.js';

const cache = getCache();

/** Lee la comisión configurada por el admin (con cache 30 s). */
async function getMarkupRate(): Promise<number> {
  const pct = await getNumericSetting('platformCommissionPct', 10);
  return pct / 100;
}

/**
 * Aplica la comisión GARDEN al precio del cuidador.
 * El cliente ve el precio final (precio cuidador × (1 + rate)).
 */
function applyMarkup(price: number | null | undefined, rate: number): number | null {
  // price === 0 means "service not offered" — return null so UIs don't render "Bs 0"
  if (price === null || price === undefined || price === 0) return null;
  const val = typeof price === 'number' ? price : Number(price);
  return Math.round(val * (1 + rate));
}

/**
 * Lista cuidadores verificados con filtros y paginación.
 * Solo status=APPROVED y verified=true (aparecen tras approve del admin). Orden: rating DESC, createdAt DESC.
 */
export async function listCaregivers(filters: CaregiverFilters): Promise<PaginatedCaregivers> {
  const {
    service, zone, cityId, zoneId, priceRange, spaceTypes,
    experienceYears, acceptAggressive, acceptPuppies, acceptSeniors, sizesAccepted,
    search, petType,
    page = 1, limit = 10, cursor,
  } = filters;

  const cacheKey = `caregivers:list:${JSON.stringify({
    service: service ?? '',
    zone: Array.isArray(zone) ? zone.join(',') : zone ?? '',
    cityId: cityId ?? '',
    zoneId: zoneId ?? '',
    priceRange: priceRange ?? '',
    spaceTypes: Array.isArray(spaceTypes) ? spaceTypes.join(',') : spaceTypes ?? '',
    experienceYears: experienceYears ?? '',
    acceptAggressive: acceptAggressive ?? '',
    acceptPuppies: acceptPuppies ?? '',
    acceptSeniors: acceptSeniors ?? '',
    sizesAccepted: Array.isArray(sizesAccepted) ? sizesAccepted.join(',') : sizesAccepted ?? '',
    search: search ?? '',
    petType: petType ?? '',
    page,
    limit,
    cursor: cursor ?? '',
  })}`;
  const cached = await cache.get<PaginatedCaregivers>(cacheKey);
  if (cached) return applyCoordJitter(cached);

  const markupRate = await getMarkupRate();

  const zones: Zone[] | undefined = Array.isArray(zone)
    ? (zone as Zone[])
    : typeof zone === 'string'
      ? (zone.split(',').map((z) => z.trim()).filter((z): z is Zone => Object.values(Zone).includes(z as Zone)))
      : undefined;
  const zonesFilter = zones?.length ? zones : undefined;

  // Zonas bloqueadas por admin — se excluyen del marketplace en tiempo real
  let blockedZones: string[] = [];
  try {
    const { getBlockedZonesList } = await import('../admin/admin.service.js');
    blockedZones = await getBlockedZonesList();
  } catch { /* Si falla, no bloquear nada */ }

  const where: Prisma.CaregiverProfileWhereInput = {
    suspended: false,
    status: CaregiverStatus.APPROVED,
    verified: true,
    // Las empresas quedan verified:true apenas confirman teléfono+email
    // (antes de terminar el paso final del wizard, perfil detallado) — a
    // diferencia del individual, donde verified:true ya implica registro
    // 100% completo. No mostrar una empresa a medias en el marketplace.
    OR: [{ isCompany: false }, { isCompany: true, caregiverProfileComplete: true }],
    // Cuidadores amateur (0 años de experiencia) con capacitación obligatoria
    // pendiente no reciben reservas hasta completarla — no aparecen en el
    // marketplace. trainingComplete se recalcula en training.service.ts y
    // por defecto es true, así que esto no afecta a nadie que no sea amateur.
    trainingComplete: true,
  } as Prisma.CaregiverProfileWhereInput;

  // El marketplace siempre filtra por ciudad — nunca mezcla cuidadores de
  // ciudades distintas, aunque el usuario no haya elegido zona todavía.
  if (cityId) {
    where.cityId = cityId;
  }

  if (zoneId) {
    // Zona real (uuid) — funciona para cualquier ciudad. Reemplaza el filtro
    // por enum legado como fuente principal de verdad.
    where.zoneId = zoneId;
  } else if (zonesFilter?.length) {
    // Fallback legado (perfiles viejos sin zoneId todavía backfillado).
    const allowedFromFilter = zonesFilter.filter((z) => !blockedZones.includes(z));
    where.zone = { in: allowedFromFilter.length ? allowedFromFilter : zonesFilter };
  } else if (blockedZones.length > 0) {
    // Sin filtro del usuario: excluir zonas bloqueadas (solo aplica al enum
    // legado de Santa Cruz; otras ciudades no tienen este feature todavía)
    where.zone = { notIn: blockedZones as Zone[] };
  }

  if (service === ServiceType.PASEO || service === ServiceType.HOSPEDAJE || service === ServiceType.GUARDERIA) {
    where.servicesOffered = { has: service as ServiceType };
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
      where.pricePerDay = { gte: Math.ceil(60 / (1 + markupRate)), lte: Math.floor(100 / (1 + markupRate)) };
    } else if (priceRange === 'estandar') {
      where.pricePerDay = { gte: Math.ceil(100 / (1 + markupRate)), lte: Math.floor(140 / (1 + markupRate)) };
    } else {
      where.pricePerDay = { gte: Math.ceil(140 / (1 + markupRate)) };
    }
  }

  if (experienceYears !== undefined) {
    (where as any).experienceYears = { gte: experienceYears };
  }

  // Exclusion logic: only hide caregivers who explicitly said NO.
  // NULL (unset) means unknown → show them (same pattern as petType filter).
  if (acceptAggressive) where.acceptAggressive = { not: false };
  if (acceptPuppies) where.acceptPuppies = { not: false };
  if (acceptSeniors) where.acceptSeniors = { not: false };

  // sizesAccepted: excluir cuidadores que tienen tamaños configurados Y ninguno coincide.
  // NULL/[] = sin restricción → deben aparecer en todos los filtros de tamaño.
  if (sizesAccepted && Array.isArray(sizesAccepted) && sizesAccepted.length > 0) {
    try {
      const sizeParams = sizesAccepted.map((s) => Prisma.sql`${s}`);
      const excluded = await prisma.$queryRaw<{ id: string }[]>(
        Prisma.sql`
          SELECT id FROM "caregiver_profiles"
          WHERE "sizesAccepted" IS NOT NULL
            AND array_length("sizesAccepted", 1) IS NOT NULL
            AND array_length("sizesAccepted", 1) > 0
            AND NOT ("sizesAccepted"::text[] && ARRAY[${Prisma.join(sizeParams)}]::text[])
        `,
      );
      logger.debug('sizesAccepted filter', { sizesAccepted, excludedCount: excluded.length });
      if (excluded.length > 0) {
        const existingNotIn = (where as any).id?.notIn ?? [];
        where.id = { notIn: [...existingNotIn, ...excluded.map((e) => e.id)] };
      }
    } catch (err) {
      logger.error('sizesAccepted subquery failed, skipping filter', {
        sizesAccepted,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // Filtrar por tipo de mascota del cliente.
  // Excluye cuidadores que tienen preferencias configuradas y el petType solicitado NO está.
  // Fuente de verdad: columna animalTypes. Fallback: serviceDetails.acceptedPetTypes.
  // array_length(ARRAY[], 1) = NULL en PG → "vacío o null" se detecta con IS NULL.
  if (petType) {
    try {
      const excluded = await prisma.$queryRaw<{ id: string }[]>`
        SELECT id FROM "caregiver_profiles"
        WHERE (
          -- Caso 1: columna animalTypes tiene datos y no incluye petType
          (
            array_length("animalTypes", 1) IS NOT NULL
            AND array_length("animalTypes", 1) > 0
            AND NOT ("animalTypes"::text[] @> ARRAY[${petType}]::text[])
          )
          OR
          -- Caso 2: columna vacía/null pero serviceDetails tiene datos y no incluye petType
          (
            array_length("animalTypes", 1) IS NULL
            AND "serviceDetails" IS NOT NULL
            AND jsonb_typeof("serviceDetails"->'acceptedPetTypes') = 'array'
            AND jsonb_array_length("serviceDetails"->'acceptedPetTypes') > 0
            AND NOT ("serviceDetails"->'acceptedPetTypes' @> ${`["${petType}"]`}::jsonb)
          )
        )
      `;
      logger.info('petType filter applied', { petType, excludedCount: excluded.length, excludedIds: excluded.map(e => e.id) });
      if (excluded.length > 0) {
        const existingNotIn = (where as any).id?.notIn ?? [];
        where.id = { notIn: [...existingNotIn, ...excluded.map((e) => e.id)] };
      }
    } catch (err) {
      logger.error('petType subquery failed, skipping filter', {
        petType,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  if (search && search.trim()) {
    const term = search.trim();
    where.user = {
      OR: [
        { firstName: { contains: term, mode: 'insensitive' } },
        { lastName: { contains: term, mode: 'insensitive' } },
      ],
    };
  }

  // Cursor-based pagination: when a cursor is provided use it for efficient
  // infinite-scroll without a full COUNT query.  Offset pagination is kept as
  // the fallback for numbered pages.
  const useCursor = Boolean(cursor);

  const include = { user: { select: { firstName: true, lastName: true, profilePicture: true } } } as const;
  const orderBy = [{ rating: 'desc' as const }, { createdAt: 'desc' as const }];

  const [caregivers, total] = await Promise.all([
    useCursor
      ? prisma.caregiverProfile.findMany({ where, include, orderBy, take: limit, cursor: { id: cursor! }, skip: 1 })
      : prisma.caregiverProfile.findMany({ where, include, orderBy, take: limit, skip: (page - 1) * limit }),
    // Skip the expensive COUNT when cursor is in use (infinite-scroll pattern)
    useCursor ? Promise.resolve(-1) : prisma.caregiverProfile.count({ where }),
  ]);

  const nextCursor = caregivers.length === limit ? (caregivers[caregivers.length - 1]?.id ?? null) : null;
  const pages = total >= 0 ? (Math.ceil(total / limit) || 1) : -1;
  const result: PaginatedCaregivers = {
    caregivers: caregivers.map((c) => ({
      id: c.id,
      firstName: c.user?.firstName ?? '',
      lastName: c.user?.lastName ?? '',
      profilePicture: c.profilePhoto ?? c.user?.profilePicture ?? null,
      photos: Array.isArray(c.photos) ? c.photos : [],
      walkerPhotos: Array.isArray((c as any).walkerPhotos) ? (c as any).walkerPhotos : [],
      caregiverPhotos: Array.isArray((c as any).caregiverPhotos) ? (c as any).caregiverPhotos : [],
      placePhotos: ((c as any).placePhotos as Record<string, string[]> | null) ?? null,
      zone: c.zone ?? '',
      services: c.servicesOffered,
      rating: c.rating,
      reviewCount: c.reviewCount,
      pricePerDay: applyMarkup(c.pricePerDay, markupRate),
      pricePerWalk30: applyMarkup(c.pricePerWalk30, markupRate),
      pricePerWalk60: applyMarkup(c.pricePerWalk60, markupRate),
      pricePerGuarderia: applyMarkup(c.pricePerGuarderia, markupRate),
      guarderiaIncludeWalk: (c as any).guarderiaIncludeWalk ?? false,
      verified: c.verified,
      spaceType: Array.isArray(c.spaceType) ? c.spaceType : (c.spaceType ? [c.spaceType] : []),
      experienceYears: c.experienceYears,
      experienceDescription: c.experienceDescription,
      whyCaregiver: c.whyCaregiver,
      whatDiffers: c.whatDiffers,
      handleAnxious: c.handleAnxious,
      emergencyResponse: c.emergencyResponse,
      acceptAggressive: c.acceptAggressive,
      acceptPuppies: c.acceptPuppies,
      acceptSeniors: c.acceptSeniors,
      sizesAccepted: c.sizesAccepted,
      isProfessional: (c as any).isProfessional ?? false,
      isCompany: (c as any).isCompany ?? false,
      companyName: (c as any).companyName ?? null,
      maxPets: c.maxPets ?? 1,
      // Store raw coords in cache; jitter is applied AFTER retrieval so each response
      // gets fresh noise and cached data doesn't leak a static jittered position.
      _addressLat: c.addressLat ?? null,
      _addressLng: c.addressLng ?? null,
    })),
    pagination: {
      total,
      page,
      currentPage: page,
      pages,
      limit,
      nextCursor,
    },
  };

  try {
    await cache.set(cacheKey, result, CAREGIVER_LIST_CACHE_TTL);
  } catch (e) {
    logger.warn('Cache set failed for caregiver list', { cacheKey, error: (e as Error).message });
  }
  return applyCoordJitter(result);
}

function applyCoordJitter(result: PaginatedCaregivers): PaginatedCaregivers {
  return {
    ...result,
    caregivers: result.caregivers.map((c: any) => {
      const { _addressLat, _addressLng, ...rest } = c;
      return {
        ...rest,
        addressLatApprox: _addressLat != null ? _addressLat + (Math.random() - 0.5) * 0.008 : null,
        addressLngApprox: _addressLng != null ? _addressLng + (Math.random() - 0.5) * 0.008 : null,
      };
    }),
  };
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

  const markupRate = await getMarkupRate();

  // Solo visibles para clientes: APPROVED + verified, no suspendido.
  // Empresas quedan verified:true antes de terminar el wizard (ver
  // comentario equivalente en el `where` del listado, más arriba en este
  // archivo) — exigirles además caregiverProfileComplete evita mostrar un
  // perfil de empresa a medias si un cliente entra directo por su URL.
  const publicWhere = {
    id,
    suspended: false,
    status: CaregiverStatus.APPROVED,
    verified: true,
    OR: [{ isCompany: false }, { isCompany: true, caregiverProfileComplete: true }],
  } as Prisma.CaregiverProfileWhereUniqueInput;

  // Manejar el caso donde timeBlocks no existe en la DB
  let profile;
  try {
    profile = await prisma.caregiverProfile.findUnique({
      where: publicWhere,
      include: {
        user: { select: { firstName: true, lastName: true, profilePicture: true } },
        reviews: {
          where: { isSystemGenerated: false },
          take: 10,
          orderBy: { createdAt: 'desc' },
          include: {
            client: { select: { firstName: true, lastName: true, profilePicture: true } },
            booking: { select: { petName: true } },
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
        extraServices: { where: { active: true }, orderBy: { createdAt: 'asc' } },
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
            where: { isSystemGenerated: false },
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
          extraServices: { where: { active: true }, orderBy: { createdAt: 'asc' } },
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
    pricePerDay: applyMarkup(profile.pricePerDay, markupRate),
    pricePerWalk30: applyMarkup(profile.pricePerWalk30, markupRate),
    pricePerWalk60: applyMarkup(profile.pricePerWalk60, markupRate),
    pricePerGuarderia: applyMarkup(profile.pricePerGuarderia, markupRate),
    guarderiaIncludeWalk: (profile as any).guarderiaIncludeWalk ?? false,
    verified: profile.verified,
    spaceType: Array.isArray(profile.spaceType) ? profile.spaceType : (profile.spaceType ? [profile.spaceType] : []),
    bio: profile.bio,
    photos: Array.isArray(profile.photos) ? profile.photos : [],
    walkerPhotos: Array.isArray((profile as any).walkerPhotos) ? (profile as any).walkerPhotos : [],
    caregiverPhotos: Array.isArray((profile as any).caregiverPhotos) ? (profile as any).caregiverPhotos : [],
    placePhotos: ((profile as any).placePhotos as Record<string, string[]> | null) ?? null,
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
      petName: (r as any).booking?.petName ?? null,
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
    requireMeetAndGreet: (profile as any).requireMeetAndGreet ?? false,
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
    isProfessional: (profile as any).isProfessional ?? false,
    isCompany: (profile as any).isCompany ?? false,
    companyName: (profile as any).companyName ?? null,
    extraServices: ((profile as any).extraServices ?? []).map((e: any) => ({
      id: e.id,
      name: e.name,
      pricePerDay: applyMarkup(e.pricePerDay, markupRate),
      appliesTo: e.appliesTo,
    })),
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
  blockedDates: string[]; // fechas YYYY-MM-DD explícitamente bloqueadas por el cuidador
  bookedPaseos?: { date: string; startTime: string; duration: number; status: string; petCount?: number }[];
  maxPets?: number;
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
        select: { id: true, defaultAvailabilitySchedule: true, maxPets: true },
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
        blockedDates: [],
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
        blockedDates: [],
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
        blockedDates: [],
      };
    }

    // Calcular defaultSchedule aquí para usarlo como fallback en filas explícitas y en el loop de fechas sin fila
    const defaultSchedule = (profile?.defaultAvailabilitySchedule as any) || { hospedajeDefault: true };
    const weekdaysEnabled = defaultSchedule.weekdays !== false;
    const weekendsEnabled = defaultSchedule.weekends !== false;
    const holidaysEnabled = defaultSchedule.holidays !== false;

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

        // Procesar timeBlocks de forma segura para paseos.
        // Si la fila tiene el formato {enabled:true, slots:{null,null,null}} el cuidador marcó
        // el día como "disponible" pero sin configurar slots → tratarlo como sin override y
        // heredar del schedule por defecto (que tiene los slots reales del cuidador).
        let rawTimeBlocks = (a as any).timeBlocks;
        if (
          rawTimeBlocks?.slots &&
          typeof rawTimeBlocks.slots === 'object' &&
          Object.values(rawTimeBlocks.slots as object).every((v) => v === null || v === undefined)
        ) {
          rawTimeBlocks = null; // Sin slots reales → ignorar, usar defaultSchedule
        }
        let slots = parseTimeBlocks(rawTimeBlocks);
        if (slots.length === 0) {
          const ptbDefault = defaultSchedule.paseoTimeBlocks;
          slots = parseTimeBlocks(ptbDefault);
          if (!ptbDefault && slots.length === 0) {
            // Sin configuración en ningún lado → todos los bloques habilitados con defaults
            slots = [
              { slot: 'MANANA', enabled: true, start: '08:00', end: '11:00' },
              { slot: 'TARDE', enabled: true, start: '13:00', end: '17:00' },
              { slot: 'NOCHE', enabled: true, start: '19:00', end: '22:00' }
            ];
          }
        }
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

    // Recopilar fechas explícitamente bloqueadas (isAvailable=false, sin slots de paseo)
    const blockedDates: string[] = [];
    for (const dateStr of datesWithExplicitRow) {
      if (!paseosByDate[dateStr]) {
        blockedDates.push(dateStr);
      }
    }

    // Aplicar horario predeterminado (o defaults absolutos) a fechas sin fila explícita
    const cur = new Date(startDate);
    while (cur <= endDate) {
      const dStr = cur.toISOString().slice(0, 10);
      if (!datesWithExplicitRow.has(dStr)) {
        const dayOfWeek = cur.getUTCDay(); // 0=domingo, 6=sábado
        const isWeekend = dayOfWeek === 0 || dayOfWeek === 6;
        const isHoliday = BOLIVIA_HOLIDAYS.has(dStr);

        // Respetar los flags de tipo de día del schedule predeterminado del cuidador
        const dayTypeEnabled =
          (isHoliday && holidaysEnabled) ||
          (!isHoliday && isWeekend && weekendsEnabled) ||
          (!isHoliday && !isWeekend && weekdaysEnabled);

        if (!dayTypeEnabled) {
          // Este tipo de día está desactivado en el schedule del cuidador — bloquearlo
          blockedDates.push(dStr);
          cur.setDate(cur.getDate() + 1);
          continue;
        }

        if (defaultSchedule.hospedajeDefault !== false) {
          hospedajeDates.push(dStr);
        }
        const ptb = defaultSchedule.paseoTimeBlocks || defaultSchedule.weekly?.[dStr]; // fallback to weekly if exists
        let slots = parseTimeBlocks(ptb);
        // Si no hay ningún bloque configurado (ptb ausente), habilitar todos los bloques por defecto
        // Nota: si ptb existe pero todos los slots están disabled, slots=[] y el día queda bloqueado
        if (!ptb && slots.length === 0) {
          slots = [
            { slot: 'MANANA', enabled: true, start: '08:00', end: '11:00' },
            { slot: 'TARDE', enabled: true, start: '13:00', end: '17:00' },
            { slot: 'NOCHE', enabled: true, start: '19:00', end: '22:00' }
          ];
        }
        if (slots.length > 0) {
          paseosByDate[dStr] = slots;
        } else if (ptb) {
          // paseoTimeBlocks configurados pero todos los slots desactivados → bloquear día
          blockedDates.push(dStr);
        }
      }
      cur.setDate(cur.getDate() + 1);
    }

    logger.info('Availability fetched', {
      caregiverId,
      hospedajeCount: hospedajeDates.length,
      paseosCount: Object.keys(paseosByDate).length,
      blockedDatesCount: blockedDates.length,
    });
    // 5. Fetch all active bookings (both types) to calculate real availability
    const expirationDate = new Date(Date.now() - 15 * 60 * 1000);
    const activeBookings = await prisma.booking.findMany({
      where: {
        caregiverId,
        AND: [
          {
            OR: [
              { status: { in: ['CONFIRMED', 'IN_PROGRESS', 'PAYMENT_PENDING_APPROVAL', 'WAITING_CAREGIVER_APPROVAL', 'PENDING_MG', 'COMPLETED'] } },
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
                serviceType: { in: ['PASEO', 'GUARDERIA'] },
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
        status: true,
        petCount: true,
      }
    });

    // 6. Filter hospedajeDates (remove dates where active booking count >= maxPets)
    // maxPets=1 → block after 1 booking (original behaviour)
    // maxPets=2 → allow up to 2 simultaneous hospedaje bookings per day, etc.
    const caregiverMaxPets = (profile as any)?.maxPets ?? 1;
    // Count occupied pet slots per date (sum petCount, not booking count)
    const hospedajeDatePetCount = new Map<string, number>();
    activeBookings.forEach(b => {
      if (b.serviceType === 'HOSPEDAJE' && b.startDate && b.endDate) {
        const bPetCount = (b as any).petCount ?? 1;
        let d = new Date(b.startDate);
        while (d < b.endDate) {
          const ds = d.toISOString().slice(0, 10);
          hospedajeDatePetCount.set(ds, (hospedajeDatePetCount.get(ds) ?? 0) + bPetCount);
          d.setDate(d.getDate() + 1);
        }
      }
    });

    // A date is available if at least 1 pet slot is free (remaining = maxPets - occupied > 0)
    const finalHospedajeDates = hospedajeDates.filter(
      d => (hospedajeDatePetCount.get(d) ?? 0) < caregiverMaxPets
    );

    // 7. Prepare bookedPaseos for frontend validation/UI
    const bookedPaseos = activeBookings
      .filter(b => (b.serviceType === 'PASEO' || b.serviceType === 'GUARDERIA') && b.walkDate)
      .map(b => ({
        date: b.walkDate!.toISOString().slice(0, 10),
        startTime: b.startTime || '00:00',
        duration: b.duration || 0,
        status: b.status,
        petCount: (b as any).petCount ?? 1,
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
      blockedDates,
      bookedPaseos,
      maxPets: caregiverMaxPets,
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
      blockedDates: [],
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
      pricePerGuarderia: input.pricePerGuarderia,
      guarderiaIncludeWalk: false,
      verified: false,
    },
    include: { user: { select: { firstName: true, lastName: true, profilePicture: true } } },
  });

  const markupRate = await getMarkupRate();
  return mapProfileToListItem(profile, markupRate);
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
    pricePerGuarderia: input.pricePerGuarderia ?? null,
    guarderiaIncludeWalk: false,
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
    profile: mapProfileToListItem(result.profile, await getMarkupRate()),
    created: result.created,
  };
}

function mapProfileToListItem(profile: any, markupRate: number): CaregiverListItem {
  const p = profile;
  return {
    id: profile.id,
    firstName: profile.user.firstName,
    lastName: profile.user.lastName,
    profilePicture: p.profilePhoto ?? profile.user.profilePicture,
    photos: Array.isArray(p.photos) ? p.photos : [],
    walkerPhotos: Array.isArray((p as any).walkerPhotos) ? (p as any).walkerPhotos : [],
    caregiverPhotos: Array.isArray((p as any).caregiverPhotos) ? (p as any).caregiverPhotos : [],
    placePhotos: ((p as any).placePhotos as Record<string, string[]> | null) ?? null,
    zone: profile.zone ?? '',
    services: profile.servicesOffered,
    rating: profile.rating,
    reviewCount: profile.reviewCount,
    pricePerDay: applyMarkup(profile.pricePerDay, markupRate),
    pricePerWalk30: applyMarkup(profile.pricePerWalk30, markupRate),
    pricePerWalk60: applyMarkup(profile.pricePerWalk60, markupRate),
    pricePerGuarderia: applyMarkup(profile.pricePerGuarderia, markupRate),
    guarderiaIncludeWalk: (profile as any).guarderiaIncludeWalk ?? false,
    verified: profile.verified,
    spaceType: Array.isArray(profile.spaceType) ? profile.spaceType : (profile.spaceType ? [profile.spaceType] : []),
    experienceYears: profile.experienceYears,
    experienceDescription: profile.experienceDescription,
    whyCaregiver: profile.whyCaregiver,
    whatDiffers: profile.whatDiffers,
    handleAnxious: profile.handleAnxious,
    emergencyResponse: profile.emergencyResponse,
    acceptAggressive: profile.acceptAggressive,
    acceptPuppies: profile.acceptPuppies,
    acceptSeniors: profile.acceptSeniors,
    requireMeetAndGreet: (profile as any).requireMeetAndGreet ?? false,
    sizesAccepted: profile.sizesAccepted,
  };
}

export async function getCaregiverProfileByUserId(userId: string) {
  return prisma.caregiverProfile.findUnique({
    where: { userId },
    include: { user: true },
  });
}

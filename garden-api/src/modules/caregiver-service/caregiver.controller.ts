import { Request, Response } from 'express';
import { ZodError } from 'zod';
import * as caregiverService from './caregiver.service.js';
import {
  listCaregiversQuerySchema,
  createCaregiverProfileSchema,
  ZONE_QUERY_TO_ENUM,
  caregiverPhotosFilesSchema,
} from './caregiver.validation.js';
import { processAndUploadToCloudinary } from './upload.middleware.js';
import { CaregiverNotFoundError, CaregiverProfileValidationError, NotFoundError } from '../../shared/errors.js';
import { asyncHandler } from '../../shared/async-handler.js';
import logger from '../../shared/logger.js';

/**
 * GET /api/caregivers
 * Solo cuidadores con status=APPROVED (y verified=true). Client-friendly: paginación + filtros.
 * Filtros: service (hospedaje|paseo|ambos), zone, priceRange (economico|estandar|premium), spaceType.
 * Query: page (default 1), limit (default 10, max 50). Orden: rating DESC, createdAt DESC.
 */
export const list = asyncHandler(async (req: Request, res: Response) => {
  try {
    const query = listCaregiversQuerySchema.parse(req.query);
    const serviceFilter =
      query.service === 'paseo' || query.service === 'hospedaje'
        ? (query.service === 'paseo' ? 'PASEO' : 'HOSPEDAJE')
        : undefined;
    const zoneFilter = query.zone ? [ZONE_QUERY_TO_ENUM[query.zone]].filter(Boolean) : undefined;

    const result = await caregiverService.listCaregivers({
      service: serviceFilter ?? (query.service as 'ambos' | undefined),
      zone: zoneFilter?.length ? (zoneFilter as string[]) : undefined,
      priceRange: query.priceRange,
      spaceTypes: query.spaceTypes,
      experienceYears: query.experienceYears,
      acceptAggressive: query.acceptAggressive,
      acceptPuppies: query.acceptPuppies,
      acceptSeniors: query.acceptSeniors,
      sizesAccepted: query.sizesAccepted,
      search: query.search,
      page: query.page,
      limit: query.limit,
    });
    res.json({ success: true, data: result });
  } catch (err) {
    logger.error('GET /api/caregivers failed', { error: err instanceof Error ? err.message : String(err) });
    throw err;
  }
});

/** GET /api/caregivers/:id/availability — fechas disponibles (modelo Availability). Query: from?, to? (ISO date). */
export const getAvailability = asyncHandler(async (req: Request, res: Response) => {
  const caregiverId = req.params.id;
  
  try {
    // Validación de caregiverId
    if (!caregiverId || typeof caregiverId !== 'string' || caregiverId.trim() === '') {
      logger.warn('Missing or invalid caregiverId in availability request', { 
        caregiverId,
        type: typeof caregiverId,
        isEmpty: caregiverId?.trim() === '',
      });
      throw new CaregiverNotFoundError(caregiverId || '');
    }

    // Validar formato UUID básico (opcional pero útil)
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(caregiverId)) {
      logger.warn('Invalid UUID format for caregiverId', { caregiverId });
      // No lanzamos error aquí, dejamos que Prisma lo maneje
    }

    // Parsear fechas con manejo robusto
    let from: Date | undefined;
    let to: Date | undefined;

    if (req.query.from) {
      try {
        const fromStr = String(req.query.from);
        const fromDate = new Date(fromStr);
        if (isNaN(fromDate.getTime())) {
          logger.warn('Invalid from date in availability request', { from: fromStr });
          throw new CaregiverProfileValidationError('Fecha "from" inválida. Debe ser una fecha ISO válida.');
        }
        from = fromDate;
      } catch (dateError) {
        logger.error('Error parsing from date', { 
          from: req.query.from, 
          error: dateError instanceof Error ? dateError.message : String(dateError),
          stack: dateError instanceof Error ? dateError.stack : undefined,
        });
        throw new CaregiverProfileValidationError('Fecha "from" inválida. Debe ser una fecha ISO válida.');
      }
    }

    if (req.query.to) {
      try {
        const toStr = String(req.query.to);
        const toDate = new Date(toStr);
        if (isNaN(toDate.getTime())) {
          logger.warn('Invalid to date in availability request', { to: toStr });
          throw new CaregiverProfileValidationError('Fecha "to" inválida. Debe ser una fecha ISO válida.');
        }
        to = toDate;
      } catch (dateError) {
        logger.error('Error parsing to date', { 
          to: req.query.to, 
          error: dateError instanceof Error ? dateError.message : String(dateError),
          stack: dateError instanceof Error ? dateError.stack : undefined,
        });
        throw new CaregiverProfileValidationError('Fecha "to" inválida. Debe ser una fecha ISO válida.');
      }
    }

    // Llamar al servicio
    let data;
    try {
      logger.debug('About to call getCaregiverAvailability service', {
        caregiverId,
        from: from?.toISOString(),
        to: to?.toISOString(),
      });
      
      data = await caregiverService.getCaregiverAvailability(caregiverId, from, to);
      
      logger.info('Service call successful - DATA RECEIVED', {
        caregiverId,
        hasData: !!data,
        dataType: typeof data,
        isArray: Array.isArray(data),
        dataKeys: data ? Object.keys(data) : [],
        hospedajeCount: data?.hospedaje?.length ?? 0,
        paseosCount: data ? Object.keys(data.paseos).length : 0,
      });
    } catch (serviceError) {
      logger.error('Service call failed - THROWING ERROR', {
        caregiverId,
        error: serviceError instanceof Error ? serviceError.message : String(serviceError),
        stack: serviceError instanceof Error ? serviceError.stack : undefined,
        errorName: serviceError instanceof Error ? serviceError.name : undefined,
        from: from?.toISOString(),
        to: to?.toISOString(),
      });
      throw serviceError;
    }

    // Validar que data existe antes de responder
    if (!data) {
      logger.warn('Service returned null/undefined data - CREATING EMPTY STRUCTURE', { caregiverId });
      // Retornar estructura vacía en lugar de error
      data = {
        caregiverId,
        from: from ? from.toISOString().slice(0, 10) : new Date().toISOString().slice(0, 10),
        to: to ? to.toISOString().slice(0, 10) : new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10),
        hospedaje: [],
        paseos: {},
      };
    }

    // Validar estructura de respuesta antes de enviar
    try {
      if (!data.caregiverId || !data.from || !data.to || !Array.isArray(data.hospedaje) || typeof data.paseos !== 'object') {
        logger.error('Invalid data structure returned from service', {
          caregiverId,
          data: JSON.stringify(data),
        });
        throw new Error('Estructura de datos inválida retornada del servicio');
      }

      res.json({ success: true, data });
    } catch (validationError) {
      logger.error('Error validating response data structure', {
        caregiverId,
        error: validationError instanceof Error ? validationError.message : String(validationError),
        data: JSON.stringify(data),
      });
      throw validationError;
    }
  } catch (err) {
    // Logging agresivo del error ANTES de re-lanzar
    logger.error('ERROR en GET /api/caregivers/:id/availability - CATCH BLOCK', {
      error: err instanceof Error ? err.message : String(err),
      stack: err instanceof Error ? err.stack : undefined,
      name: err instanceof Error ? err.name : undefined,
      caregiverId: req.params.id,
      query: req.query,
      path: req.path,
      method: req.method,
      url: req.url,
      isAppError: err instanceof Error && 'isOperational' in err,
      errorCode: err instanceof Error && 'code' in err ? (err as any).code : undefined,
      statusCode: err instanceof Error && 'statusCode' in err ? (err as any).statusCode : undefined,
    });
    
    // Re-lanzar el error para que asyncHandler/errorHandler lo maneje
    // El errorHandler global convertirá esto en una respuesta JSON apropiada
    throw err;
  }
});

/** GET /api/caregivers/:id — detalle público (solo APPROVED, sin auth). 404 si no existe o no está disponible. */
export const getById = asyncHandler(async (req: Request, res: Response) => {
  const id = req.params.id!;
  const caregiver = await caregiverService.getCaregiverById(id);
  if (!caregiver) throw new NotFoundError('Cuidador no disponible');
  res.json({ success: true, data: caregiver });
});

/**
 * Parsea el body de multipart/form-data para crear/actualizar perfil.
 * Acepta: body.data (JSON string) o campos sueltos: bio, zone, spaceType, servicesOffered, precios.
 */
function parseCaregiverBody(body: Record<string, unknown>): unknown {
  if (body.data !== undefined && body.data !== '') {
    const raw = body.data;
    return typeof raw === 'string' ? JSON.parse(raw) : raw;
  }
  const servicesOffered = body.servicesOffered;
  const servicesArray = Array.isArray(servicesOffered)
    ? servicesOffered
    : typeof servicesOffered === 'string' && servicesOffered
      ? servicesOffered.split(',').map((s: string) => s.trim()).filter(Boolean)
      : [];
  return {
    bio: body.bio,
    zone: body.zone,
    spaceType: body.spaceType !== undefined && (Array.isArray(body.spaceType) ? body.spaceType.length > 0 : body.spaceType !== '') ? body.spaceType : undefined,
    servicesOffered: servicesArray,
    pricePerDay: body.pricePerDay !== undefined && body.pricePerDay !== '' ? body.pricePerDay : undefined,
    pricePerWalk30: body.pricePerWalk30 !== undefined && body.pricePerWalk30 !== '' ? body.pricePerWalk30 : undefined,
    pricePerWalk60: body.pricePerWalk60 !== undefined && body.pricePerWalk60 !== '' ? body.pricePerWalk60 : undefined,
  };
}

/**
 * Sube las fotos del cuidador a Cloudinary (folder: garden/caregivers/{userId})
 * y devuelve las URLs. Multer ya validó tipo JPG/PNG y tamaño <5MB.
 * Sin archivos temp en disco (memoria); no hace falta limpieza posterior.
 */
async function uploadPhotos(
  userId: string,
  files: Express.Multer.File[]
): Promise<string[]> {
  const buffers = files.map((f) => f.buffer);
  return processAndUploadToCloudinary(buffers, userId);
}

/**
 * POST /api/caregivers
 * Crea o actualiza el perfil del cuidador (role CAREGIVER).
 * multipart/form-data: bio, zone, spaceType, servicesOffered, photos (4–6, JPG/PNG, <5MB c/u).
 * Flujo: validar fotos → subir a Cloudinary → en transacción Prisma guardar perfil con URLs.
 */
export const create = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const files = (req.files as Express.Multer.File[] | undefined) ?? [];

  try {
    caregiverPhotosFilesSchema.parse(files);
  } catch (e) {
    if (e instanceof ZodError && e.issues[0]?.message) {
      throw new CaregiverProfileValidationError(e.issues[0].message as string);
    }
    throw e;
  }
  const photoUrls = await uploadPhotos(userId, files);

  const rawBody = parseCaregiverBody(req.body as Record<string, unknown>);
  const input = createCaregiverProfileSchema.parse(rawBody);

  const { profile, created } = await caregiverService.upsertCaregiverProfile(userId, input, photoUrls);

  if (created) {
    res.status(201).json({ success: true, data: profile });
  } else {
    res.status(200).json({ success: true, data: profile });
  }
});

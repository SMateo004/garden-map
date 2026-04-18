import { z } from 'zod';
import { ServiceType, Zone } from '@prisma/client';

const MAX_BIO_LENGTH = 500;
const MAX_SPACE_TYPE_LENGTH = 300;
const MIN_PHOTOS = 2;
const MAX_PHOTOS = 6;

export const createCaregiverProfileSchema = z.object({
  bio: z.string().min(1, 'Bio requerida').max(MAX_BIO_LENGTH, `Máximo ${MAX_BIO_LENGTH} caracteres`),
  zone: z.nativeEnum(Zone),
  spaceType: z.array(z.enum(['Casa con patio', 'Casa sin patio', 'Departamento pequeño', 'Departamento amplio'])).min(1, 'Elige al menos un tipo de espacio').optional(),
  servicesOffered: z
    .array(z.nativeEnum(ServiceType))
    .min(1, 'Al menos un servicio')
    .refine((arr) => new Set(arr).size === arr.length, 'Servicios duplicados'),
  pricePerDay: z.coerce.number().int().min(0).optional(),
  pricePerWalk30: z.coerce.number().int().min(0).optional(),
  pricePerWalk60: z.coerce.number().int().min(0).optional(),
});

/** Query params para GET /api/caregivers (MVP + spec técnica) */
export const listCaregiversQuerySchema = z.object({
  service: z.string().optional().transform((v) => v?.toLowerCase()).pipe(z.enum(['hospedaje', 'paseo', 'ambos']).optional()),
  zone: z.enum(['equipetrol', 'urbari', 'norte', 'las_palmas', 'centro', 'remanzo', 'sur', 'urubo_norte', 'urubo_sur', 'otros']).optional(),
  priceRange: z.enum(['economico', 'estandar', 'premium']).optional(),
  // spaceTypes: comma-separated string que se convierte a array (ej: "casa_con_patio,departamento_pequeno")
  spaceTypes: z.string().optional().transform((val) => {
    if (!val) return undefined;
    return val.split(',').map((s) => s.trim()).filter(Boolean);
  }),
  experienceYears: z.coerce.number().optional(),
  acceptAggressive: z.preprocess((val) => val === 'true', z.boolean()).optional(),
  acceptPuppies: z.preprocess((val) => val === 'true', z.boolean()).optional(),
  acceptSeniors: z.preprocess((val) => val === 'true', z.boolean()).optional(),
  // sizesAccepted: comma-separated string (ej: "PEQUEÑO,MEDIANO")
  sizesAccepted: z.string().optional().transform((val) => {
    if (!val) return undefined;
    return val.split(',').map((s) => s.trim()).filter(Boolean);
  }),
  search: z.string().max(80).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(10),
  /** Cursor para infinite-scroll: ID del último cuidador de la página anterior. */
  cursor: z.string().optional(),
});

/** Mapeo query zone (lowercase) → Prisma Zone enum */
export const ZONE_QUERY_TO_ENUM: Record<string, Zone> = {
  equipetrol: Zone.EQUIPETROL,
  urbari: Zone.URBARI,
  norte: Zone.NORTE,
  las_palmas: Zone.LAS_PALMAS,
  centro: Zone.CENTRO,
  remanzo: Zone.REMANZO,
  sur: Zone.SUR,
  urubo_norte: Zone.URUBO_NORTE,
  urubo_sur: Zone.URUBO_SUR,
  otros: Zone.OTROS,
};

export const ZONE_VALUES = Object.values(Zone) as string[];

export const MAX_BIO_CHARS = MAX_BIO_LENGTH;
export const PHOTO_COUNT = { min: MIN_PHOTOS, max: MAX_PHOTOS };
/** Solo JPG/PNG para fotos de perfil (requisito MVP) */
export const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/png'] as const;
export const MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024; // 5MB por archivo

/** Validación Zod del array de archivos: min 4, max 6 (tipos y tamaño los valida Multer) */
export const caregiverPhotosFilesSchema = z
  .array(z.unknown())
  .min(PHOTO_COUNT.min, `Mínimo ${PHOTO_COUNT.min} fotos reales requeridas`)
  .max(PHOTO_COUNT.max, `Máximo ${PHOTO_COUNT.max} fotos`);

export type CreateCaregiverProfileBody = z.infer<typeof createCaregiverProfileSchema>;
export type ListCaregiversQuery = z.infer<typeof listCaregiversQuerySchema>;

/** Mirrors backend caregiver types — flexible for doc changes */

export type ServiceType = 'HOSPEDAJE' | 'PASEO';
export type TimeSlot = 'MANANA' | 'TARDE' | 'NOCHE';

export interface CaregiverListItem {
  id: string;
  firstName: string;
  lastName: string;
  profilePicture: string | null;
  /** URLs de fotos del perfil (Cloudinary). Primera se usa como avatar en card si no hay profilePicture. */
  photos?: string[];
  zone?: string | null;
  services: ServiceType[];
  rating: number;
  reviewCount: number;
  pricePerDay: number | null;
  pricePerWalk30: number | null;
  pricePerWalk60: number | null;
  verified: boolean;
  spaceType: string[]; // Array de tipos de espacio seleccionados
}

export interface ReviewPublic {
  id: string;
  clientName: string;
  clientPhoto: string | null;
  rating: number;
  comment: string | null;
  serviceType: ServiceType;
  createdAt: string;
}

export interface PaseoSlot {
  slot: 'MANANA' | 'TARDE' | 'NOCHE';
  enabled: boolean;
  start?: string;
  end?: string;
}

export interface CaregiverAvailabilityResponse {
  caregiverId: string;
  from: string;
  to: string;
  hospedaje: string[];
  paseos: Record<string, PaseoSlot[]>;
  bookedPaseos?: { date: string; startTime: string; duration: number; status: string }[];
}

export interface CaregiverDetail extends CaregiverListItem {
  bio: string | null;
  bioDetail?: string | null;
  photos: string[];
  availability: {
    hospedaje: string[];
    paseos: Record<string, PaseoSlot[]>;
  };
  reviews: ReviewPublic[];

  // Campos adicionales del perfil detallado
  experienceYears?: string | null;
  experienceDescription?: string | null;
  whyCaregiver?: string | null;
  whatDiffers?: string | null;
  handleAnxious?: string | null;
  emergencyResponse?: string | null;
  acceptAggressive?: boolean;
  acceptPuppies?: boolean;
  acceptSeniors?: boolean;
  sizesAccepted?: string[];
  animalTypes?: string[];
  acceptMedication?: string[];
  homeType?: string | null;
  ownHome?: boolean | null;
  hasYard?: boolean | null;
  yardFenced?: boolean | null;
  hasChildren?: boolean | null;
  hasOtherPets?: boolean | null;
  petsSleep?: string | null;
  clientPetsSleep?: string | null;
  hoursAlone?: number | null;
  workFromHome?: boolean | null;
  maxPets?: number | null;
  oftenOut?: boolean | null;
  typicalDay?: string | null;
  spaceDescription?: string | null;
  blockchainReputation?: {
    average: number;
    count: number;
    verified: boolean;
  } | null;
}

export interface PaginatedCaregivers {
  caregivers: CaregiverListItem[];
  pagination: {
    total: number;
    page: number;
    currentPage: number;
    pages: number;
    limit: number;
  };
}

/** Params para GET /api/caregivers (alineados con backend) */
export type ListCaregiversParams = {
  service?: 'hospedaje' | 'paseo' | 'ambos';
  zone?: ZoneQuery;
  priceRange?: 'economico' | 'estandar' | 'premium';
  spaceTypes?: string[]; // Array de tipos de espacio para filtrado (query param: comma-separated)
  page?: number;
  limit?: number;
};

/** Zone en query: lowercase como en API */
export const ZONES_QUERY = ['equipetrol', 'urbari', 'norte', 'las_palmas', 'centro_san_martin', 'otros'] as const;
export type ZoneQuery = (typeof ZONES_QUERY)[number];

export interface CreateCaregiverProfileBody {
  bio: string;
  zone: string;
  spaceType?: string;
  servicesOffered: ServiceType[];
  pricePerDay?: number;
  pricePerWalk30?: number;
  pricePerWalk60?: number;
}

/** Zone enum values — must match backend Prisma enum Zone */
export const ZONES = ['EQUIPETROL', 'URBARI', 'NORTE', 'LAS_PALMAS', 'CENTRO_SAN_MARTIN', 'OTROS'] as const;
export type Zone = (typeof ZONES)[number];

export const ZONE_LABELS: Record<Zone, string> = {
  EQUIPETROL: 'Equipetrol',
  URBARI: 'Urbarí',
  NORTE: 'Norte',
  LAS_PALMAS: 'Las Palmas',
  CENTRO_SAN_MARTIN: 'Centro/Av. San Martín',
  OTROS: 'Otros',
};

/** Opciones de tipo de espacio (multi-select) */
export const SPACE_TYPE_OPTIONS = [
  'Casa con patio',
  'Casa sin patio',
  'Departamento pequeño',
  'Departamento amplio',
] as const;

export type SpaceTypeOption = (typeof SPACE_TYPE_OPTIONS)[number];

/** Mapeo de valores display a query params (snake_case) */
export const SPACE_TYPE_QUERY_MAP: Record<SpaceTypeOption, string> = {
  'Casa con patio': 'casa_con_patio',
  'Casa sin patio': 'casa_sin_patio',
  'Departamento pequeño': 'departamento_pequeno',
  'Departamento amplio': 'departamento_amplio',
};

/** Mapeo inverso: query param → display value */
export const SPACE_TYPE_QUERY_TO_DISPLAY: Record<string, SpaceTypeOption> = {
  casa_con_patio: 'Casa con patio',
  casa_sin_patio: 'Casa sin patio',
  departamento_pequeno: 'Departamento pequeño',
  departamento_amplio: 'Departamento amplio',
};
export const PRICE_RANGES = ['economico', 'estandar', 'premium'] as const;
export const SERVICE_OPTIONS = ['hospedaje', 'paseo', 'ambos'] as const;

/** Etiquetas para filtros (query values) */
export const ZONE_QUERY_LABELS: Record<ZoneQuery, string> = {
  equipetrol: 'Equipetrol',
  urbari: 'Urbarí',
  norte: 'Norte',
  las_palmas: 'Las Palmas',
  centro_san_martin: 'Centro/Av. San Martín',
  otros: 'Otros',
};
export const SERVICE_LABELS: Record<(typeof SERVICE_OPTIONS)[number], string> = {
  hospedaje: 'Hospedaje',
  paseo: 'Paseo',
  ambos: 'Ambos',
};
export const PRICE_RANGE_LABELS: Record<(typeof PRICE_RANGES)[number], string> = {
  economico: 'Económico',
  estandar: 'Estándar',
  premium: 'Premium',
};

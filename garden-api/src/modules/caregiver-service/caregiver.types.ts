import type { ServiceType, TimeSlot } from '@prisma/client';

export interface CaregiverListItem {
  id: string;
  firstName: string;
  lastName: string;
  profilePicture: string | null;
  /** URLs de fotos del perfil (Cloudinary). Incluir en listado para mostrar galería. */
  photos: string[];
  zone: string;
  services: ServiceType[];
  rating: number;
  reviewCount: number;
  pricePerDay: number | null;
  pricePerWalk30: number | null;
  pricePerWalk60: number | null;
  verified: boolean;
  spaceType: string[]; // Array de tipos de espacio seleccionados
  experienceYears: any;
  experienceDescription: string | null;
  whyCaregiver: string | null;
  whatDiffers: string | null;
  handleAnxious: string | null;
  emergencyResponse: string | null;
  acceptAggressive: boolean | null;
  acceptPuppies: boolean | null;
  acceptSeniors: boolean | null;
  sizesAccepted: any[] | null;
}

export interface CaregiverDetail extends CaregiverListItem {
  bio: string | null;
  bioDetail?: string | null;
  photos: string[];
  availability: {
    hospedaje: string[];
    paseos: Record<string, import('../../shared/availability-utils.js').PaseoSlot[]>;
  };
  reviews: ReviewPublic[];
  // Campos cuestionario
  animalTypes?: string[] | null;
  acceptMedication?: string[] | null;
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

export interface ReviewPublic {
  id: string;
  clientName: string;
  clientPhoto: string | null;
  rating: number;
  comment: string | null;
  serviceType: ServiceType;
  createdAt: Date;
}

export interface CaregiverFilters {
  service?: ServiceType | 'ambos';
  zone?: string | string[];
  priceRange?: 'economico' | 'estandar' | 'premium';
  spaceTypes?: string[]; // Array de tipos de espacio para filtrado multi-select
  page?: number;
  limit?: number;
  /** Cursor para infinite-scroll: ID del último cuidador de la página anterior. */
  cursor?: string;
  experienceYears?: any;
  acceptAggressive?: boolean;
  acceptPuppies?: boolean;
  acceptSeniors?: boolean;
  sizesAccepted?: any[];
  search?: string;
}

export interface PaginatedCaregivers {
  caregivers: CaregiverListItem[];
  pagination: {
    total: number;
    page: number;
    currentPage: number;
    pages: number;
    limit: number;
    /** ID del último elemento: pasar como ?cursor= para obtener la siguiente página. */
    nextCursor: string | null;
  };
}

export interface CreateCaregiverProfileInput {
  bio: string;
  zone: string;
  spaceType?: string[]; // Array de tipos de espacio
  servicesOffered: ServiceType[];
  pricePerDay?: number;
  pricePerWalk30?: number;
  pricePerWalk60?: number;
}

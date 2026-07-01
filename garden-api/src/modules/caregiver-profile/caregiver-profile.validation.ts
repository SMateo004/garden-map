/**
 * Validación para flujo de registro cuidador con guardado progresivo.
 * - PATCH: schemas parciales (cualquier subconjunto de campos).
 * - Submit: validación de campos obligatorios vía superRefine / check.
 */

import { z } from 'zod';
import {
  ServiceType,
  Zone,
  AnimalType,
  MedicationType,
  PetSize,
  HomeType,
  PetsSleep,
  ClientPetsSleep,
} from '@prisma/client';
import {
  serviceAvailabilitySchema,
  ratesSchema,
  currentPetsDetailsSchema,
} from '../auth/auth.validation.js';

const MIN_TEXT_DRAFT = 5;
const MIN_BIO = 50;

// --- PATCH: actualización parcial (todos los campos opcionales) ---

export const patchCaregiverProfileSchema = z.record(z.any()).optional();

export interface PatchCaregiverProfileBody {
  bio?: string;
  bioDetail?: string;
  zone?: any;
  spaceType?: string[];
  spaceDescription?: string;
  address?: string;
  servicesOffered?: any[];
  serviceAvailability?: any;
  pricePerDay?: number;
  pricePerWalk30?: number;
  pricePerWalk60?: number;
  pricePerGuarderia?: number;
  rates?: any;
  termsAccepted?: boolean;
  privacyAccepted?: boolean;
  verificationAccepted?: boolean;
  photos?: string[];
  profilePhoto?: string | null;
  experienceYears?: any;
  ownPets?: boolean;
  currentPetsDetails?: any;
  caredOthers?: boolean;
  animalTypes?: any[];
  experienceDescription?: string;
  whyCaregiver?: string;
  whatDiffers?: string;
  handleAnxious?: string;
  emergencyResponse?: string;
  acceptAggressive?: boolean;
  acceptMedication?: any[];
  acceptPuppies?: boolean;
  acceptSeniors?: boolean;
  sizesAccepted?: any[];
  noAcceptBreeds?: boolean;
  breedsWhy?: string;
  homeType?: any;
  ownHome?: boolean;
  hasYard?: boolean;
  yardFenced?: boolean;
  hasChildren?: boolean;
  hasOtherPets?: boolean;
  petsSleep?: any;
  clientPetsSleep?: any;
  hoursAlone?: number;
  workFromHome?: boolean;
  maxPets?: number;
  oftenOut?: boolean;
  typicalDay?: string;
  ciAnversoUrl?: string;
  ciReversoUrl?: string;
  ciNumber?: string;
  onboardingStatus?: any;
  serviceDetails?: any;
}

// --- Submit: lista de campos obligatorios para enviar solicitud (MVP wizard) ---

const REQUIRED_FIELDS_FOR_SUBMIT = [
  'bio',
  'zone',
  'servicesOffered',
  'photos',           // caregiverPhotos mín 2
  'placePhotoSala',   // solo HOSPEDAJE/GUARDERÍA
  'placePhotoDescanso',
  'placePhotoAlimentacion',
  'profilePhoto',
  'termsAccepted',
  'privacyAccepted',
  'verificationAccepted',
  'identityVerified',
  'emailVerified',
  'experienceYears',
  'experienceDescription',
  'whyCaregiver',
  'whatDiffers',
  'handleAnxious',
  'emergencyResponse',
  'sizesAccepted',
] as const;

export type RequiredSubmitField = (typeof REQUIRED_FIELDS_FOR_SUBMIT)[number];

/** Devuelve los nombres de campos obligatorios que faltan o están vacíos en el perfil. */
export function getMissingRequiredFieldsForSubmit(profile: any): RequiredSubmitField[] {
  const missing: RequiredSubmitField[] = [];
  const bioText = (profile.bio ?? '').trim();
  const bioDetailText = (profile.bioDetail ?? '').trim();
  if (bioText.length < 10 && bioDetailText.length < 10) missing.push('bio');
  if (!profile.zone) missing.push('zone');

  const services = Array.isArray(profile.servicesOffered) ? profile.servicesOffered : [];
  if (services.length < 1) missing.push('servicesOffered');

  // Fotos del cuidador en acción — obligatorio para TODOS los servicios (mín 2)
  const caregiverPhotos = Array.isArray(profile.caregiverPhotos) ? profile.caregiverPhotos : [];
  if (caregiverPhotos.length < 2) missing.push('photos');

  // Fotos del hogar por sección — solo HOSPEDAJE o GUARDERÍA
  const needsPlacePhotos = services.includes(ServiceType.HOSPEDAJE) || services.includes(ServiceType.GUARDERIA);
  if (needsPlacePhotos) {
    const placePhotos = (profile.placePhotos ?? {}) as Record<string, string[]>;
    if (!placePhotos['sala'] || placePhotos['sala'].length < 1) missing.push('placePhotoSala');
    if (!placePhotos['descanso'] || placePhotos['descanso'].length < 1) missing.push('placePhotoDescanso');
    if (!placePhotos['alimentacion'] || placePhotos['alimentacion'].length < 1) missing.push('placePhotoAlimentacion');
  }

  if (!profile.profilePhoto) missing.push('profilePhoto');

  // Verificación de identidad (IA) y email son obligatorios para aprobar
  if (profile.identityVerificationStatus !== 'VERIFIED') missing.push('identityVerified');
  if (profile.emailVerified !== true && profile.user?.emailVerified !== true) missing.push('emailVerified');

  // Paso 6 (Perfil profesional)
  if (profile.experienceYears === null || profile.experienceYears === undefined) missing.push('experienceYears');
  if (!Array.isArray(profile.sizesAccepted) || profile.sizesAccepted.length === 0) missing.push('sizesAccepted');

  // Campos de experiencia: solo requeridos si NO es amateur (experienceYears > 0)
  const isAmateur = profile.isAmateur === true || profile.experienceYears === 0;
  if (!isAmateur) {
    if (!profile.experienceDescription || profile.experienceDescription.trim().length < 5) missing.push('experienceDescription');
    if (!profile.whyCaregiver || profile.whyCaregiver.trim().length < 3) missing.push('whyCaregiver');
    if (!profile.whatDiffers || profile.whatDiffers.trim().length < 3) missing.push('whatDiffers');
    if (!profile.handleAnxious || profile.handleAnxious.trim().length < 3) missing.push('handleAnxious');
    if (!profile.emergencyResponse || profile.emergencyResponse.trim().length < 3) missing.push('emergencyResponse');
  }

  return missing;
}

// --- PATCH /api/caregiver/availability ---
const timeSlotConfigSchema = z.object({
  enabled: z.boolean(),
  start: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  end: z.string().regex(/^\d{2}:\d{2}$/).optional(),
}).nullable();

const timeBlocksSchema = z.object({
  morning: timeSlotConfigSchema.optional(),
  afternoon: timeSlotConfigSchema.optional(),
  night: timeSlotConfigSchema.optional(),
});

const defaultScheduleSchema = z.object({
  hospedajeDefault: z.boolean().optional(),
  weekdays:  z.boolean().optional(),
  weekends:  z.boolean().optional(),
  holidays:  z.boolean().optional(),
  paseoTimeBlocks: timeBlocksSchema.optional(),
  weekly: z.record(z.string(), z.object({
    enabled: z.boolean(),
    slots: timeBlocksSchema,
  })).optional(),
});

const dayOverrideSchema = z.object({
  isAvailable: z.boolean().optional(),
  timeBlocks: timeBlocksSchema.optional(),
  reason: z.string().max(2000).optional(),
});

export const patchAvailabilityBodySchema = z.object({
  defaultSchedule: defaultScheduleSchema.optional(),
  overrides: z.record(z.string().regex(/^\d{4}-\d{2}-\d{2}$/), dayOverrideSchema).optional(),
});

export type PatchAvailabilityBody = z.infer<typeof patchAvailabilityBodySchema>;

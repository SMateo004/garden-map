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
  idDocument?: string;
  selfie?: string;
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
  'photos',
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
  'acceptAggressive',
  'acceptPuppies',
  'acceptSeniors',
  'sizesAccepted',
] as const;

export type RequiredSubmitField = (typeof REQUIRED_FIELDS_FOR_SUBMIT)[number];

/** Devuelve los nombres de campos obligatorios que faltan o están vacíos en el perfil. */
export function getMissingRequiredFieldsForSubmit(profile: any): RequiredSubmitField[] {
  const missing: RequiredSubmitField[] = [];
  if (!profile.bio || profile.bio.trim().length < 50) missing.push('bio');
  if (!profile.zone) missing.push('zone');

  const services = Array.isArray(profile.servicesOffered) ? profile.servicesOffered : [];
  if (services.length < 1) missing.push('servicesOffered');

  const onlyPaseo = services.length === 1 && services.includes(ServiceType.PASEO);
  const minPhotosRequired = onlyPaseo ? 2 : 4;
  const photos = Array.isArray(profile.photos) ? profile.photos : [];
  if (photos.length < minPhotosRequired) missing.push('photos');

  if (!profile.profilePhoto) missing.push('profilePhoto');

  // Verificación de identidad y email son pasos del wizard pero no bloquean
  // la aprobación automática — se marcan al completar los pasos correspondientes.

  // New questions
  if (!profile.experienceYears) missing.push('experienceYears');
  if (!profile.experienceDescription || profile.experienceDescription.length < 20) missing.push('experienceDescription');
  if (!profile.whyCaregiver || profile.whyCaregiver.length < 5) missing.push('whyCaregiver');
  if (!profile.whatDiffers || profile.whatDiffers.length < 5) missing.push('whatDiffers');
  if (!profile.handleAnxious) missing.push('handleAnxious');
  if (!profile.emergencyResponse) missing.push('emergencyResponse');
  if (profile.acceptAggressive === null || profile.acceptAggressive === undefined) missing.push('acceptAggressive');
  if (profile.acceptPuppies === null || profile.acceptPuppies === undefined) missing.push('acceptPuppies');
  if (profile.acceptSeniors === null || profile.acceptSeniors === undefined) missing.push('acceptSeniors');
  if (!Array.isArray(profile.sizesAccepted) || profile.sizesAccepted.length === 0) missing.push('sizesAccepted');

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

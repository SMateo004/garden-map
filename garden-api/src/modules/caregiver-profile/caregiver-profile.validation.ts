/**
 * Validación para flujo de registro cuidador con guardado progresivo.
 * - PATCH: schemas parciales (cualquier subconjunto de campos).
 * - Submit: validación de campos obligatorios vía superRefine / check.
 */

import { z } from 'zod';
import {
  ServiceType,
  Zone,
  ExperienceYears,
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

export const patchCaregiverProfileSchema = z
  .object({
    bio: z.string().min(1).max(500).optional(),
    bioDetail: z.string().max(300).optional(),
    zone: z.nativeEnum(Zone).optional(),
    spaceType: z.array(z.string()).optional(),
    spaceDescription: z.string().max(500).optional(),
    address: z.string().max(500).optional(),

    servicesOffered: z.array(z.nativeEnum(ServiceType)).min(1).optional(),
    serviceAvailability: serviceAvailabilitySchema,
    pricePerDay: z.number().int().min(0).optional(),
    pricePerWalk30: z.number().int().min(0).optional(),
    pricePerWalk60: z.number().int().min(0).optional(),
    rates: ratesSchema,

    termsAccepted: z.boolean().optional(),
    privacyAccepted: z.boolean().optional(),
    verificationAccepted: z.boolean().optional(),

    photos: z.array(z.string().url()).optional(),
    profilePhoto: z.string().url().optional().nullable(),

    experienceYears: z.nativeEnum(ExperienceYears).optional(),
    ownPets: z.boolean().optional(),
    currentPetsDetails: currentPetsDetailsSchema,
    caredOthers: z.boolean().optional(),
    animalTypes: z.array(z.nativeEnum(AnimalType)).optional(),
    experienceDescription: z.string().min(MIN_TEXT_DRAFT).optional(),
    whyCaregiver: z.string().min(MIN_TEXT_DRAFT).optional(),
    whatDiffers: z.string().min(MIN_TEXT_DRAFT).optional(),
    handleAnxious: z.string().min(MIN_TEXT_DRAFT).optional(),
    emergencyResponse: z.string().min(MIN_TEXT_DRAFT).optional(),
    acceptAggressive: z.boolean().optional(),
    acceptMedication: z.array(z.nativeEnum(MedicationType)).optional(),
    acceptPuppies: z.boolean().optional(),
    acceptSeniors: z.boolean().optional(),
    sizesAccepted: z.array(z.nativeEnum(PetSize)).optional(),
    noAcceptBreeds: z.boolean().optional(),
    breedsWhy: z.string().max(500).optional(),
    homeType: z.nativeEnum(HomeType).optional(),
    ownHome: z.boolean().optional(),
    hasYard: z.boolean().optional(),
    yardFenced: z.boolean().optional(),
    hasChildren: z.boolean().optional(),
    hasOtherPets: z.boolean().optional(),
    petsSleep: z.nativeEnum(PetsSleep).optional().nullable(),
    clientPetsSleep: z.nativeEnum(ClientPetsSleep).optional().nullable(),
    hoursAlone: z.number().int().min(0).optional(),
    workFromHome: z.boolean().optional(),
    maxPets: z.number().int().min(1).optional(),
    oftenOut: z.boolean().optional(),
    typicalDay: z.string().min(MIN_TEXT_DRAFT).optional(),
    idDocument: z.string().url().optional(),
    selfie: z.string().url().optional(),
    ciAnversoUrl: z.string().url().optional(),
    ciReversoUrl: z.string().url().optional(),
    ciNumber: z.string().max(50).optional(),
    onboardingStatus: z
      .object({
        step: z.number().int().min(1).max(10),
        completed: z.array(z.boolean()),
      })
      .optional(),
  });

export type PatchCaregiverProfileBody = z.infer<typeof patchCaregiverProfileSchema>;

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

  if (profile.identityVerificationStatus !== 'VERIFIED') missing.push('identityVerified');
  if (profile.emailVerified !== true && profile.user?.emailVerified !== true) missing.push('emailVerified');

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

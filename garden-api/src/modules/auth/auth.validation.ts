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

/** Teléfono Bolivia: exactamente 8 dígitos, debe empezar con 6 o 7 (sin +591) */
const PHONE_CAREGIVER_REGEX = /^[67][0-9]{7}$/;

export const phoneCaregiverSchema = z
  .string()
  .min(1, 'Teléfono requerido')
  .transform((s) => s.replace(/\D/g, '').replace(/^591/, ''))
  .refine((s) => PHONE_CAREGIVER_REGEX.test(s), 'Teléfono: 8 dígitos, debe empezar con 6 o 7');

/** @deprecated Use phoneCaregiverSchema */
export const phoneSchema = phoneCaregiverSchema;

/** Para registro cliente: 8 dígitos, empieza con 6 o 7 (sin +591). Almacenamos solo los 8 dígitos. */
const phoneClientSchema = z
  .string()
  .min(1, 'Teléfono requerido')
  .transform((s) => s.replace(/\D/g, '').replace(/^591/, ''))
  .refine((s) => /^[67][0-9]{7}$/.test(s), 'Teléfono: 8 dígitos, debe empezar con 6 o 7');

const MIN_TEXT_DRAFT = 5;

/** Disponibilidad por servicio (weekdays, weekends, holidays, times[], lastMinute) */
export const serviceAvailabilityItemSchema = z.object({
  weekdays: z.boolean(),
  weekends: z.boolean(),
  holidays: z.boolean(),
  times: z.array(z.enum(['MORNING', 'AFTERNOON', 'NIGHT'])).min(1),
  lastMinute: z.boolean(),
});

/** Mapa servicio -> disponibilidad (HOSPEDAJE, PASEO) */
export const serviceAvailabilitySchema = z
  .object({
    HOSPEDAJE: serviceAvailabilityItemSchema.optional(),
    PASEO: serviceAvailabilityItemSchema.optional(),
  })
  .optional();

/** Tarifas: night, paseo, additional, holiday */
export const ratesSchema = z.object({
  night: z.number().min(0).optional(),
  paseo: z.number().min(0).optional(),
  additional: z.number().min(0).optional(),
  holiday: z.number().min(0).optional(),
}).optional();

/** Un ítem de mascota actual (type, age, size, temperament) */
export const currentPetsDetailsItemSchema = z.object({
  type: z.string(),
  age: z.union([z.number(), z.string()]).optional(),
  size: z.string().optional(),
  temperament: z.string().optional(),
});

export const currentPetsDetailsSchema = z.array(currentPetsDetailsItemSchema).optional();

// --- Login ---
export const loginSchema = z.object({
  email: z.string().email('Email inválido'),
  password: z.string().min(1, 'Contraseña requerida'),
});

/** Valida fecha de nacimiento y que la edad sea >= 18 */
const dateOfBirthSchema = z
  .string()
  .or(z.date())
  .transform((v) => (typeof v === 'string' ? new Date(v) : v))
  .refine((d) => !isNaN(d.getTime()), 'Fecha de nacimiento inválida')
  .refine((d) => {
    const today = new Date();
    let age = today.getFullYear() - d.getFullYear();
    const m = today.getMonth() - d.getMonth();
    if (m < 0 || (m === 0 && today.getDate() < d.getDate())) age--;
    return age >= 18;
  }, 'Debes tener al menos 18 años');

// --- Register caregiver (full submit) ---
export const registerCaregiverUserSchema = z.object({
  email: z.string().email('Email inválido'),
  password: z.string().min(8, 'Mínimo 8 caracteres'),
  firstName: z.string().min(1, 'Nombre requerido').max(100),
  lastName: z.string().min(1, 'Apellido requerido').max(100),
  phone: phoneCaregiverSchema,
  dateOfBirth: dateOfBirthSchema,
  country: z.string().min(1, 'País requerido').max(100),
  city: z.string().min(1, 'Ciudad requerida').max(100),
  isOver18: z.literal(true, { errorMap: () => ({ message: 'Debes ser mayor de 18 años' }) }),
});

export const registerCaregiverProfileSchema = z.object({
  bio: z
    .string()
    .min(50, 'La descripción debe tener al menos 50 caracteres')
    .max(500, 'La descripción no puede superar 500 caracteres')
    .optional(),
  // zone, servicesOffered, and photos are optional at registration time —
  // they are saved later via PATCH /caregiver/profile (step-by-step wizard).
  zone: z.nativeEnum(Zone, {
    invalid_type_error: 'Zona no válida; elige una de la lista',
  }).optional(),
  spaceType: z
    .array(z.enum(['Casa con patio', 'Casa sin patio', 'Departamento pequeño', 'Departamento amplio']))
    .min(1, 'Selecciona al menos un tipo de espacio')
    .optional(),
  address: z.string().max(500).optional(),

  servicesOffered: z
    .array(z.nativeEnum(ServiceType))
    .min(1, 'Elige al menos un servicio (Hospedaje o Paseo)')
    .optional(),
  serviceAvailability: serviceAvailabilitySchema,
  pricePerDay: z.number().int().min(0).optional(),
  pricePerWalk30: z.number().int().min(0).optional(),
  pricePerWalk60: z.number().int().min(0).optional(),
  rates: ratesSchema,

  experienceYears: z.number().optional(),
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
  petsSleep: z.nativeEnum(PetsSleep).optional(),
  clientPetsSleep: z.nativeEnum(ClientPetsSleep).optional(),
  hoursAlone: z.number().int().min(0).optional(),
  workFromHome: z.boolean().optional(),
  maxPets: z.number().int().min(1).optional(),
  oftenOut: z.boolean().optional(),
  typicalDay: z.string().min(MIN_TEXT_DRAFT).optional(),
  photos: z
    .array(z.string().url('Cada foto debe ser una URL válida'))
    .max(6, 'Máximo 6 fotos')
    .optional(),
  idDocument: z.string().url().optional(),
  selfie: z.string().url().optional(),
  ciAnversoUrl: z.string().url().optional(),
  ciReversoUrl: z.string().url().optional(),
  ciNumber: z.string().max(50).optional(),
  profilePhoto: z.string().url().optional(),
});

export const registerCaregiverSchema = z
  .object({
    user: registerCaregiverUserSchema,
    profile: registerCaregiverProfileSchema,
    /** Código de invitación beta. Solo requerido cuando betaInviteRequired=true en AppSettings. */
    inviteCode: z.string().max(64).optional(),
  })
  .superRefine((data, ctx) => {
    // Only cross-validate photos vs services when both are provided
    const services = data.profile.servicesOffered;
    const photos = data.profile.photos;
    if (!services || !photos || photos.length === 0) return;
    const paseoOnly = services.length === 1 && services.includes('PASEO');
    if (paseoOnly) {
      if (photos.length < 2) ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Paseo: sube al menos 2 fotos personales (máx. 4)', path: ['profile', 'photos'] });
      else if (photos.length > 4) ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Paseo: máximo 4 fotos personales', path: ['profile', 'photos'] });
    } else {
      if (photos.length < 4) ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Hospedaje: sube al menos 4 fotos del espacio (máx. 6)', path: ['profile', 'photos'] });
      else if (photos.length > 6) ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Hospedaje: máximo 6 fotos del espacio', path: ['profile', 'photos'] });
    }
  });

// --- PATCH caregiver profile (partial) ---
const spaceTypeEnum = z.string(); // Liberalized

export const patchCaregiverProfileSchema = z.object({
  bio: z.string().min(1).max(500).optional(),
  zone: z.nativeEnum(Zone).optional(),
  spaceType: z.array(spaceTypeEnum).optional(),
  address: z.string().max(500).optional(),

  servicesOffered: z.array(z.nativeEnum(ServiceType)).min(1).optional(),
  serviceAvailability: serviceAvailabilitySchema,
  pricePerDay: z.number().int().min(0).optional(),
  pricePerWalk30: z.number().int().min(0).optional(),
  pricePerWalk60: z.number().int().min(0).optional(),
  rates: ratesSchema,

  experienceYears: z.number().optional(),
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
  photos: z.array(z.string().url()).optional(),
  idDocument: z.string().url().optional(),
  selfie: z.string().url().optional(),
});

// --- Register client (simplificado) ---
export const registerClientSchema = z.object({
  firstName: z.string().min(1, 'Nombre requerido').max(100).transform((v) => v.trim()),
  lastName: z.string().min(1, 'Apellido requerido').max(100).transform((v) => v.trim()),
  email: z.string().email('Email inválido'),
  password: z.string().min(8, 'Mínimo 8 caracteres'),
  phone: phoneClientSchema,
  address: z.string().max(500, 'Máximo 500 caracteres').optional().transform((v) => (v && v.trim() ? v.trim() : undefined)),
  dateOfBirth: z
    .string()
    .or(z.date())
    .transform((v) => (typeof v === 'string' ? new Date(v) : v))
    .refine((d) => !isNaN(d.getTime()), 'Fecha de nacimiento inválida')
    .optional(),
  bio: z.string().max(500, 'Máximo 500 caracteres').optional().transform((v) => (v && v.trim() ? v.trim() : undefined)),
  /** Código de invitación beta. Solo requerido cuando betaInviteRequired=true en AppSettings. */
  inviteCode: z.string().max(64).optional(),
});

export type LoginBody = z.infer<typeof loginSchema>;
export type RegisterCaregiverBody = z.infer<typeof registerCaregiverSchema>;
export type RegisterClientBody = z.infer<typeof registerClientSchema>;
export type PatchCaregiverProfileBody = z.infer<typeof patchCaregiverProfileSchema>;

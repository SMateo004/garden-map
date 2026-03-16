import { z } from 'zod';

/** 8 dígitos, debe empezar con 6 o 7 (sin +591) */
const PHONE_CAREGIVER = /^[67][0-9]{7}$/;

const phoneTransform = z
  .string()
  .transform((s) => s.replace(/\D/g, '').replace(/^591/, ''))
  .refine((s) => PHONE_CAREGIVER.test(s), 'Teléfono: 8 dígitos, debe empezar con 6 o 7');

const dateOfBirthSchema = z
  .string()
  .min(1, 'Fecha de nacimiento requerida')
  .refine((s) => !isNaN(new Date(s).getTime()), 'Fecha inválida')
  .refine((s) => {
    const d = new Date(s);
    const today = new Date();
    let age = today.getFullYear() - d.getFullYear();
    const m = today.getMonth() - d.getMonth();
    if (m < 0 || (m === 0 && today.getDate() < d.getDate())) age--;
    return age >= 18;
  }, 'Debes tener al menos 18 años');

export const step1Schema = z.object({
  firstName: z.string().min(1, 'Nombre requerido').max(100),
  lastName: z.string().min(1, 'Apellido requerido').max(100),
  phone: phoneTransform,
  dateOfBirth: dateOfBirthSchema,
});

export const step2Schema = z.object({
  email: z.string().email('Email inválido'),
  password: z.string().min(8, 'Mínimo 8 caracteres'),
  confirmPassword: z.string(),
}).refine((d) => d.password === d.confirmPassword, { message: 'Las contraseñas no coinciden', path: ['confirmPassword'] });

export const step3Schema = z.object({
  zone: z.enum(['EQUIPETROL', 'URBARI', 'NORTE', 'LAS_PALMAS', 'CENTRO_SAN_MARTIN', 'OTROS'], { required_error: 'Elige una zona' }),
});

export const step4Schema = z.object({
  servicesOffered: z.array(z.enum(['HOSPEDAJE', 'PASEO'])).min(1, 'Elige al menos un servicio'),
});

export const step5Schema = z.object({
  bioSummary: z.string().min(50, 'Mínimo 50 caracteres').max(500, 'Máximo 500 caracteres'),
  bioDetail: z.string().max(300).optional(),
});

export const step6Schema = z.object({
  spaceType: z.array(z.enum(['Casa con patio', 'Casa sin patio', 'Departamento pequeño', 'Departamento amplio'])).min(1, 'Elige al menos un tipo de espacio').optional(),
  spaceDescription: z.string().max(200).optional(),
});

export const step7Schema = z.object({
  pricePerDay: z.number().int().min(0).optional(),
  pricePerWalk30: z.number().int().min(0).optional(),
  pricePerWalk60: z.number().int().min(0).optional(),
});

/** Requirement: paseoOnly? 2-4 : 4-6 */
export function step8Schema(servicesOffered: ('HOSPEDAJE' | 'PASEO')[]): z.ZodType<{ photoUrls: string[] }> {
  const onlyPaseo = servicesOffered.length === 1 && servicesOffered.includes('PASEO');
  const min = onlyPaseo ? 2 : 4;
  const max = onlyPaseo ? 4 : 6;
  return z.object({
    photoUrls: z.array(z.string().url())
      .min(min, `Debes subir al menos ${min} fotos`)
      .max(max, `Máximo ${max} fotos`),
  });
}

export const step9Schema = z.object({
  termsAccepted: z.literal(true, { errorMap: () => ({ message: 'Debes aceptar los términos' }) }),
  privacyAccepted: z.literal(true, { errorMap: () => ({ message: 'Debes aceptar la política de privacidad' }) }),
  verificationAccepted: z.literal(true, { errorMap: () => ({ message: 'Debes aceptar la verificación' }) }),
});

export type Step1Values = z.infer<typeof step1Schema>;
export type Step2Values = z.infer<typeof step2Schema>;
export type Step3Values = z.infer<typeof step3Schema>;
export type Step4Values = z.infer<typeof step4Schema>;
export type Step5Values = z.infer<typeof step5Schema>;
export type Step6Values = z.infer<typeof step6Schema>;
export type Step7Values = z.infer<typeof step7Schema>;
export type Step8Values = z.infer<ReturnType<typeof step8Schema>>;
export type Step9Values = z.infer<typeof step9Schema>;

export const stepSchemas = [
  step1Schema,
  step2Schema,
  step3Schema,
  step4Schema,
  step5Schema,
  step6Schema,
  step7Schema,
  step9Schema,
] as const;

/** Returns schema for step (1-9). Step 8 is dynamic based on servicesOffered. */
export function getStepSchema(step: number, data: { servicesOffered?: ('HOSPEDAJE' | 'PASEO')[] }) {
  if (step === 8) return step8Schema(data.servicesOffered ?? []);
  return stepSchemas[step === 9 ? 7 : step - 1];
}

export interface WizardDraft {
  currentStep: number;
  lastSavedAt: string;
  data: Partial<WizardData>;
}

export interface WizardData {
  firstName: string;
  lastName: string;
  phone: string;
  dateOfBirth: string;
  email: string;
  password: string;
  confirmPassword: string;
  zone: string;
  servicesOffered: ('HOSPEDAJE' | 'PASEO')[];
  bioSummary: string;
  bioDetail: string;
  spaceType: string[];
  spaceDescription: string;
  pricePerDay: number;
  pricePerWalk30: number;
  pricePerWalk60: number;
  photoUrls: string[];
  termsAccepted: boolean;
  privacyAccepted: boolean;
  verificationAccepted: boolean;
}

export const defaultWizardData: WizardData = {
  firstName: '',
  lastName: '',
  phone: '',
  dateOfBirth: '',
  email: '',
  password: '',
  confirmPassword: '',
  zone: '',
  servicesOffered: [],
  bioSummary: '',
  bioDetail: '',
  spaceType: [],
  spaceDescription: '',
  pricePerDay: 0,
  pricePerWalk30: 0,
  pricePerWalk60: 0,
  photoUrls: [],
  termsAccepted: false,
  privacyAccepted: false,
  verificationAccepted: false,
};

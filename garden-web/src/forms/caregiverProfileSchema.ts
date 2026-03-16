import * as yup from 'yup';
import { ZONES, SPACE_TYPES } from '@/types/caregiver';

const MAX_BIO = 500;

export const caregiverProfileSchema = yup.object({
  bio: yup
    .string()
    .required('La descripción es obligatoria')
    .max(MAX_BIO, `Máximo ${MAX_BIO} caracteres`),
  zone: yup
    .string()
    .required('Elige una zona')
    .oneOf([...ZONES]),
  spaceType: yup
    .string()
    .optional()
    .oneOf([...SPACE_TYPES]),
  servicesOffered: yup
    .array()
    .of(yup.string().oneOf(['HOSPEDAJE', 'PASEO']))
    .min(1, 'Elige al menos un servicio')
    .required(),
  pricePerDay: yup.number().integer().min(0).optional().nullable(),
  pricePerWalk30: yup.number().integer().min(0).optional().nullable(),
  pricePerWalk60: yup.number().integer().min(0).optional().nullable(),
});

export type CaregiverProfileFormValues = yup.InferType<typeof caregiverProfileSchema>;

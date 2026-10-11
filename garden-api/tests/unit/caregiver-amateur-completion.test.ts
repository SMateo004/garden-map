/**
 * Cuidador principiante (0 años de experiencia): las preguntas de experiencia
 * no se le muestran en el registro (paso 7), así que no pueden dejar su perfil
 * como incompleto. Antes "0" contaba como experiencia sin cargar y se exigían
 * siempre "¿Por qué eres cuidador?" y "¿Qué te diferencia?".
 */
import { checkAndAutoSubmitProfile } from '../../src/modules/caregiver-profile/caregiver-profile-completion.helper';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: { caregiverProfile: { findUnique: jest.fn(), update: jest.fn().mockResolvedValue({}) } },
}));

const db = prisma as unknown as { caregiverProfile: { findUnique: jest.Mock; update: jest.Mock } };

const base = {
  id: 'cp1',
  user: { firstName: 'Ana', lastName: 'Pérez', emailVerified: true, phone: '71234567' },
  emailVerified: true,
  profilePhoto: 'https://x/foto.jpg',
  identityVerificationStatus: 'VERIFIED',
  bio: 'Amo a los animales y tengo tiempo libre para pasearlos con mucho cuidado.',
  bioDetail: 'Paseos tranquilos',
  servicesOffered: ['PASEO'],
  caregiverPhotos: ['a', 'b'],
  zone: 'EQUIPETROL',
  animalTypes: ['DOGS'],
  sizesAccepted: ['SMALL'],
  acceptAggressive: false,
  acceptPuppies: true,
  acceptSeniors: true,
  pricePerWalk60: 30,
  shirtSize: 'M',
  onboardingStatus: {},
};

function written() {
  return db.caregiverProfile.update.mock.calls[0][0].data as {
    caregiverProfileComplete: boolean;
    onboardingStatus: { percentage: number };
  };
}

beforeEach(() => jest.clearAllMocks());

it('0 años sin responder las preguntas de experiencia: perfil completo y 100 %', async () => {
  db.caregiverProfile.findUnique.mockResolvedValue({
    ...base,
    experienceYears: 0,
    experienceDescription: null,
    whyCaregiver: null,
    whatDiffers: null,
    handleAnxious: null,
    emergencyResponse: null,
  });
  await checkAndAutoSubmitProfile('u1');
  expect(written().caregiverProfileComplete).toBe(true);
  expect(written().onboardingStatus.percentage).toBe(100);
});

it('con experiencia, esas preguntas siguen siendo obligatorias', async () => {
  db.caregiverProfile.findUnique.mockResolvedValue({
    ...base,
    experienceYears: 2,
    experienceDescription: null,
    whyCaregiver: null,
    whatDiffers: null,
    handleAnxious: null,
    emergencyResponse: null,
  });
  await checkAndAutoSubmitProfile('u1');
  expect(written().caregiverProfileComplete).toBe(false);
  expect(written().onboardingStatus.percentage).toBeLessThan(100);
});

it('con experiencia y todo respondido: completo', async () => {
  db.caregiverProfile.findUnique.mockResolvedValue({
    ...base,
    experienceYears: 2,
    experienceDescription: 'Cuidé perros de vecinos durante dos años.',
    whyCaregiver: 'Me encantan',
    whatDiffers: 'Paciencia',
    handleAnxious: 'Calma y juegos',
    emergencyResponse: 'Veterinario',
  });
  await checkAndAutoSubmitProfile('u1');
  expect(written().caregiverProfileComplete).toBe(true);
  expect(written().onboardingStatus.percentage).toBe(100);
});

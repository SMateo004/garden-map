import { createSeries } from '../../src/modules/recurring-booking/recurring-booking.service';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    caregiverProfile: { findFirst: jest.fn() },
    pet: { findMany: jest.fn() },
    recurringBookingSeries: { create: jest.fn().mockResolvedValue({ id: 'serie-1' }) },
  },
}));
jest.mock('../../src/services/firebase.service', () => ({ sendPushToUser: jest.fn() }));

const CAREGIVER_ID = '11111111-1111-4111-8111-111111111111';
const PET_ID = '22222222-2222-4222-8222-222222222222';
const body = { caregiverId: CAREGIVER_ID, petIds: [PET_ID], daysOfWeek: [1, 3], timeSlot: 'MANANA' as const, duration: 60 };

const caregiver = (over: Record<string, unknown> = {}) => ({
  id: CAREGIVER_ID, userId: 'cuidador', servicesOffered: ['PASEO'], requireMeetAndGreet: false,
  maxPets: 2, maxPetsPaseo: 2, sizesAccepted: ['SMALL', 'MEDIUM'], animalTypes: ['DOGS'],
  acceptAggressive: true, acceptPuppies: true, acceptSeniors: true, ...over,
});
const pet = (over: Record<string, unknown> = {}) => ({
  id: PET_ID, name: 'Luna', size: 'SMALL', animalType: 'DOGS', isAggressive: false, age: 3, ...over,
});

describe('crear serie de paseos recurrentes', () => {
  beforeEach(() => jest.clearAllMocks());

  it('crea la serie cuando el cuidador acepta a la mascota', async () => {
    (prisma.caregiverProfile.findFirst as jest.Mock).mockResolvedValue(caregiver());
    (prisma.pet.findMany as jest.Mock).mockResolvedValue([pet()]);
    await expect(createSeries('dueño', body)).resolves.toEqual({ id: 'serie-1' });
  });

  it('rechaza de entrada una mascota que el cuidador no acepta (antes fallaba cada semana)', async () => {
    (prisma.caregiverProfile.findFirst as jest.Mock).mockResolvedValue(caregiver());
    (prisma.pet.findMany as jest.Mock).mockResolvedValue([pet({ size: 'GIANT' })]);
    await expect(createSeries('dueño', body)).rejects.toMatchObject({ code: 'PET_SIZE_NOT_ACCEPTED' });
    expect(prisma.recurringBookingSeries.create).not.toHaveBeenCalled();
  });

  it('pide completar la mascota si no tiene especie o tamaño', async () => {
    (prisma.caregiverProfile.findFirst as jest.Mock).mockResolvedValue(caregiver());
    (prisma.pet.findMany as jest.Mock).mockResolvedValue([pet({ animalType: null })]);
    await expect(createSeries('dueño', body)).rejects.toMatchObject({ code: 'PET_INCOMPLETE' });
  });

  it('no deja crear series con un cuidador que exige Meet & Greet', async () => {
    (prisma.caregiverProfile.findFirst as jest.Mock).mockResolvedValue(caregiver({ requireMeetAndGreet: true }));
    (prisma.pet.findMany as jest.Mock).mockResolvedValue([pet()]);
    await expect(createSeries('dueño', body)).rejects.toMatchObject({ code: 'MEET_AND_GREET_REQUIRED' });
  });
});

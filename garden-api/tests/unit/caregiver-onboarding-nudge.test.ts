/**
 * Recordatorio de registro de cuidador sin terminar: días 1, 3 y 7, máximo 3, con el paso que
 * falta, y nunca dos veces el mismo aviso.
 */
import prisma from '../../src/config/database';
import { enviarRecordatoriosRegistroCuidador } from '../../src/jobs/caregiver-onboarding-nudge.job';

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    caregiverProfile: { findMany: jest.fn(), updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
    notification: { create: jest.fn() },
  },
}));
jest.mock('../../src/services/firebase.service', () => ({ sendPushToUser: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../src/jobs/job-lease', () => ({ scheduleExclusive: jest.fn() }));

const db = prisma as any;
const DAY = 24 * 60 * 60 * 1000;
const now = new Date('2026-10-22T14:00:00Z');
const cg = (daysAgo: number, count: number, idv = 'PENDING') => ({
  id: `cp${daysAgo}-${count}`, userId: 'u1', createdAt: new Date(now.getTime() - daysAgo * DAY),
  onboardingNudgeCount: count, identityVerificationStatus: idv,
});
beforeEach(() => jest.clearAllMocks());

it('manda el primer aviso al día 1 y espera al día 3 para el segundo', async () => {
  db.caregiverProfile.findMany.mockResolvedValue([cg(1.2, 0), cg(2, 1), cg(3.1, 1)]);
  await expect(enviarRecordatoriosRegistroCuidador(now)).resolves.toBe(2);
});

it('dice qué falta: identidad o perfil', async () => {
  db.caregiverProfile.findMany.mockResolvedValue([cg(1.5, 0, 'VERIFIED')]);
  await enviarRecordatoriosRegistroCuidador(now);
  expect(db.notification.create.mock.calls[0][0].data.message).toMatch(/Completa tu perfil/);
});

it('si otra corrida ya lo mandó, no lo repite', async () => {
  db.caregiverProfile.findMany.mockResolvedValue([cg(1.5, 0)]);
  db.caregiverProfile.updateMany.mockResolvedValueOnce({ count: 0 });
  await expect(enviarRecordatoriosRegistroCuidador(now)).resolves.toBe(0);
  expect(db.notification.create).not.toHaveBeenCalled();
});

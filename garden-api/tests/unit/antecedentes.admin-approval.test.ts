/**
 * Sello "Antecedentes verificados": siempre lo otorga un admin.
 * - La IA nunca deja el documento en LIMPIO, aunque lo vea limpio.
 * - No se puede resubir un documento mientras otro está en revisión
 *   (antes servía para sacar un caso marcado de la cola del admin).
 * - La aprobación del admin solo funciona sobre un documento en revisión.
 */

import { assertCanSubmitAntecedentes, submitAntecedentesDocument } from '../../src/modules/caregiver-profile/caregiver-profile.service';
import { dismissAntecedentesFlag } from '../../src/modules/admin/admin.service';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    caregiverProfile: { findUnique: jest.fn(), updateMany: jest.fn() },
    adminNotification: { create: jest.fn().mockResolvedValue({}) },
    adminAction: { create: jest.fn().mockResolvedValue({}) },
    notification: { create: jest.fn().mockResolvedValue({}) },
  },
}));

jest.mock('../../src/agents/documento-antecedentes.agent', () => ({
  verificarAntecedentes: jest.fn(),
}));

jest.mock('../../src/shared/cache', () => ({
  getCache: jest.fn(),
  delByPrefix: jest.fn().mockResolvedValue(undefined),
}));

const mockPrisma = prisma as any;
const agent = jest.requireMock('../../src/agents/documento-antecedentes.agent') as { verificarAntecedentes: jest.Mock };
const buf = Buffer.from('x');

beforeEach(() => {
  jest.clearAllMocks();
  mockPrisma.caregiverProfile.findUnique.mockResolvedValue({ id: 'p1', userId: 'u1', antecedentesStatus: 'PENDING' });
  mockPrisma.caregiverProfile.updateMany.mockResolvedValue({ count: 1 });
});

describe('subida de antecedentes', () => {
  it('documento limpio según la IA: queda en revisión, no en LIMPIO', async () => {
    agent.verificarAntecedentes.mockResolvedValue({ documentoLicito: true, antecedentesDetectados: false });
    const r = await submitAntecedentesDocument('u1', 'url', buf, 'application/pdf');
    expect(r.antecedentesStatus).toBe('EN_REVISION');
    const writes = mockPrisma.caregiverProfile.updateMany.mock.calls.map((c: any[]) => c[0].data.antecedentesStatus);
    expect(writes).not.toContain('LIMPIO');
    expect(mockPrisma.adminNotification.create).toHaveBeenCalledWith({ data: { type: 'ANTECEDENTES_REVIEW', caregiverId: 'p1' } });
  });

  it('documento dudoso: queda en revisión con alerta prioritaria', async () => {
    agent.verificarAntecedentes.mockResolvedValue({ documentoLicito: false, antecedentesDetectados: false });
    await submitAntecedentesDocument('u1', 'url', buf, 'application/pdf');
    expect(mockPrisma.adminNotification.create).toHaveBeenCalledWith({ data: { type: 'ANTECEDENTES_FLAGGED', caregiverId: 'p1' } });
  });

  it('resubida con un documento ya en revisión: se rechaza sin llamar a la IA', async () => {
    mockPrisma.caregiverProfile.updateMany.mockResolvedValue({ count: 0 });
    await expect(submitAntecedentesDocument('u1', 'url', buf, 'application/pdf')).rejects.toThrow();
    expect(agent.verificarAntecedentes).not.toHaveBeenCalled();
  });

  it('chequeo previo: bloquea EN_REVISION y LIMPIO, permite PENDING y RECHAZADO', async () => {
    for (const status of ['EN_REVISION', 'LIMPIO', 'FLAGGED']) {
      mockPrisma.caregiverProfile.findUnique.mockResolvedValue({ antecedentesStatus: status });
      await expect(assertCanSubmitAntecedentes('u1')).rejects.toThrow();
    }
    for (const status of ['PENDING', 'RECHAZADO']) {
      mockPrisma.caregiverProfile.findUnique.mockResolvedValue({ antecedentesStatus: status });
      await expect(assertCanSubmitAntecedentes('u1')).resolves.toBeUndefined();
    }
  });
});

describe('aprobación del admin', () => {
  it('otorga LIMPIO solo sobre un documento en revisión y avisa al cuidador', async () => {
    await dismissAntecedentesFlag('p1', 'admin-1');
    expect(mockPrisma.caregiverProfile.updateMany).toHaveBeenCalledWith(expect.objectContaining({
      where: { id: 'p1', antecedentesStatus: 'EN_REVISION' },
      data: expect.objectContaining({ antecedentesStatus: 'LIMPIO', antecedentesReviewedById: 'admin-1' }),
    }));
    expect(mockPrisma.notification.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ userId: 'u1', type: 'ANTECEDENTES_APPROVED' }),
    }));
  });

  it('doble clic o documento ya no en revisión: falla sin notificar', async () => {
    mockPrisma.caregiverProfile.updateMany.mockResolvedValue({ count: 0 });
    await expect(dismissAntecedentesFlag('p1', 'admin-1')).rejects.toThrow();
    expect(mockPrisma.notification.create).not.toHaveBeenCalled();
  });
});

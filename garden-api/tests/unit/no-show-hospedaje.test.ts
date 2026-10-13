/**
 * El hospedaje no tiene hora de entrada: antes el no-show tomaba la medianoche
 * y lo cancelaba sin reembolso a las 00:30 del día de entrada, antes de que el
 * cuidador pudiera recibir a la mascota. Ahora cuenta desde las 23:59.
 */
import { computeStartTime } from '../../src/jobs/no-show-expiry.job';

jest.mock('../../src/config/database', () => ({ __esModule: true, default: {} }));
jest.mock('../../src/services/firebase.service', () => ({ sendPushToUser: jest.fn() }));

const day = (d: string) => new Date(`${d}T00:00:00.000Z`);

describe('computeStartTime', () => {
  it('hospedaje sin hora: fin del día de entrada en Bolivia (23:59 = 03:59 UTC del día siguiente)', () => {
    const t = computeStartTime({ serviceType: 'HOSPEDAJE', startDate: day('2026-10-20'), walkDate: null, startTime: null });
    expect(t!.toISOString()).toBe('2026-10-21T03:59:00.000Z');
  });

  it('paseo: su fecha y hora reales (sin cambios)', () => {
    const t = computeStartTime({ serviceType: 'PASEO', startDate: null, walkDate: day('2026-10-20'), startTime: '13:00' });
    expect(t!.toISOString()).toBe('2026-10-20T17:00:00.000Z');
  });
});

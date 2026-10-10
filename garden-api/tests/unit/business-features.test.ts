import {
  resolveFeatures,
  assertFeature,
  setFeatures,
  getFeaturesAdminView,
} from '../../src/modules/business-features/business-features.service';
import { requireBusinessFeature } from '../../src/middleware/require-business-feature.middleware';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    caregiverProfile: { findUnique: jest.fn(), update: jest.fn().mockResolvedValue({}) },
  },
}));

const findUnique = prisma.caregiverProfile.findUnique as jest.Mock;
const update = prisma.caregiverProfile.update as jest.Mock;

const company = (businessFeatures: unknown) => ({ id: 'p1', isCompany: true, isProfessional: false, businessFeatures });

beforeEach(() => jest.clearAllMocks());

describe('resolveFeatures', () => {
  it('sin nada guardado todo está apagado (los negocios no lo tienen hasta que el admin lo habilite)', () => {
    const f = resolveFeatures(company(null));
    expect(Object.values(f).every((v) => v === false)).toBe(true);
  });

  it('solo cuenta true literal', () => {
    expect(resolveFeatures(company({ RECEPTION: 'true' })).RECEPTION).toBe(false);
    expect(resolveFeatures(company({ RECEPTION: true })).RECEPTION).toBe(true);
  });

  it('no aplica a cuidadores individuales ni profesionales aunque esté guardado', () => {
    for (const p of [
      { isCompany: false, isProfessional: false, businessFeatures: { RECEPTION: true, STAFF_TEAM: true } },
      { isCompany: false, isProfessional: true, businessFeatures: { RECEPTION: true, STAFF_TEAM: true } },
    ]) {
      const f = resolveFeatures(p);
      expect(f.RECEPTION).toBe(false);
      expect(f.STAFF_TEAM).toBe(false);
    }
  });

  it('los permisos del equipo dependen del equipo', () => {
    const off = resolveFeatures(company({ STAFF_BOOKING_DECISIONS: true, STAFF_CLIENT_CHAT: true }));
    expect(off.STAFF_BOOKING_DECISIONS).toBe(false);
    expect(off.STAFF_CLIENT_CHAT).toBe(false);
    const on = resolveFeatures(company({ STAFF_TEAM: true, STAFF_BOOKING_DECISIONS: true }));
    expect(on.STAFF_BOOKING_DECISIONS).toBe(true);
    expect(on.STAFF_CLIENT_CHAT).toBe(false);
  });
});

describe('assertFeature / requireBusinessFeature', () => {
  it('apagada → 403 FEATURE_DISABLED', async () => {
    findUnique.mockResolvedValue(company({}));
    await expect(assertFeature('p1', 'RECEPTION')).rejects.toMatchObject({ statusCode: 403, code: 'FEATURE_DISABLED' });
  });

  it('el middleware del dueño busca su perfil y deja pasar si está habilitada', async () => {
    findUnique.mockResolvedValueOnce({ id: 'p1' }).mockResolvedValueOnce(company({ RECEPTION: true }));
    const next = jest.fn();
    await requireBusinessFeature('RECEPTION')({ user: { userId: 'u1' } } as any, {} as any, next);
    expect(next).toHaveBeenCalledWith();
  });

  it('el middleware del empleado usa la empresa y exige TODAS las funciones', async () => {
    findUnique.mockResolvedValue(company({ STAFF_TEAM: true }));
    const next = jest.fn();
    await requireBusinessFeature('STAFF_TEAM', 'RECEPTION')(
      { user: { userId: 'staff' }, staffContext: { caregiverProfileId: 'p1' } } as any,
      {} as any,
      next
    );
    expect(next.mock.calls[0][0]).toMatchObject({ code: 'FEATURE_DISABLED' });
    expect(findUnique.mock.calls[0][0].where).toEqual({ id: 'p1' });
  });
});

describe('setFeatures (solo admin)', () => {
  it('enciende y apaga sin dejar claves en false', async () => {
    findUnique.mockResolvedValue(company({ STAFF_TEAM: true }));
    const { before, after } = await setFeatures('p1', { RECEPTION: true, STAFF_TEAM: false });
    expect(before).toEqual({ STAFF_TEAM: true });
    expect(after).toEqual({ RECEPTION: true });
    expect(update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { businessFeatures: { RECEPTION: true } } });
  });

  it('rechaza funciones que no aplican al tipo de cuenta', async () => {
    findUnique.mockResolvedValue({ isCompany: false, isProfessional: false, businessFeatures: null });
    await expect(setFeatures('p1', { RECEPTION: true })).rejects.toMatchObject({ code: 'FEATURE_NOT_APPLICABLE' });
    expect(update).not.toHaveBeenCalled();
  });

  it('la vista del admin de un individual no lista funciones de empresa', async () => {
    findUnique.mockResolvedValue({ id: 'p1', isCompany: false, isProfessional: false, businessFeatures: null });
    expect((await getFeaturesAdminView('p1')).features).toEqual([]);
  });
});

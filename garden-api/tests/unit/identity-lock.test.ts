/**
 * Nombre, apellido y fecha de nacimiento: una vez cargados solo los cambia un admin.
 */
const mockUserFind = jest.fn();
const mockProfileFind = jest.fn();
jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    user: { findUnique: (...a: unknown[]) => mockUserFind(...a) },
    caregiverProfile: { findUnique: (...a: unknown[]) => mockProfileFind(...a) },
  },
}));

import { assertIdentityEditable, getIdentityLock } from '../../src/modules/auth/identity-lock.service';

const user = (over: Record<string, unknown> = {}) => ({
  firstName: 'Ana',
  lastName: 'Pérez',
  dateOfBirth: new Date('1995-03-04T00:00:00.000Z'),
  ...over,
});

describe('bloqueo de identidad', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockProfileFind.mockResolvedValue(null); // dueño: sin perfil de cuidador
  });

  it('cambiar el nombre ya cargado → IDENTITY_LOCKED', async () => {
    mockUserFind.mockResolvedValue(user());
    await expect(assertIdentityEditable('u1', { firstName: 'Beatriz' })).rejects.toMatchObject({ code: 'IDENTITY_LOCKED', statusCode: 403 });
  });

  it('cambiar el apellido o la fecha de nacimiento también', async () => {
    mockUserFind.mockResolvedValue(user());
    await expect(assertIdentityEditable('u1', { lastName: 'Gómez' })).rejects.toMatchObject({ code: 'IDENTITY_LOCKED' });
    await expect(assertIdentityEditable('u1', { dateOfBirth: '1990-01-01' })).rejects.toMatchObject({ code: 'IDENTITY_LOCKED' });
  });

  it('reenviar los mismos valores (la app manda todo en cada guardado) pasa, aunque cambien mayúsculas o espacios', async () => {
    mockUserFind.mockResolvedValue(user());
    await expect(
      assertIdentityEditable('u1', { firstName: ' ana ', lastName: 'PÉREZ', dateOfBirth: '1995-03-04T00:00:00.000Z' })
    ).resolves.toBeUndefined();
  });

  it('sin cambios de identidad en el pedido no consulta nada', async () => {
    await expect(assertIdentityEditable('u1', {})).resolves.toBeUndefined();
    expect(mockUserFind).not.toHaveBeenCalled();
  });

  it('completar lo que falta sí se puede: apellido "-" de Google y fecha vacía', async () => {
    mockUserFind.mockResolvedValue(user({ lastName: '-', dateOfBirth: null }));
    await expect(assertIdentityEditable('u1', { lastName: 'Pérez', dateOfBirth: '1995-03-04' })).resolves.toBeUndefined();
  });

  it('cuidador con el registro sin terminar y sin identidad verificada aún puede corregir su nombre', async () => {
    mockUserFind.mockResolvedValue(user());
    mockProfileFind.mockResolvedValue({ profileStatus: 'INCOMPLETE', identityVerificationStatus: 'PENDING' });
    await expect(assertIdentityEditable('u1', { firstName: 'Beatriz' })).resolves.toBeUndefined();
  });

  it('cuidador con identidad verificada queda bloqueado aunque su perfil siga incompleto', async () => {
    mockUserFind.mockResolvedValue(user());
    mockProfileFind.mockResolvedValue({ profileStatus: 'INCOMPLETE', identityVerificationStatus: 'VERIFIED' });
    await expect(assertIdentityEditable('u1', { firstName: 'Beatriz' })).rejects.toMatchObject({ code: 'IDENTITY_LOCKED' });
  });

  it('cuidador con el perfil ya enviado queda bloqueado', async () => {
    mockUserFind.mockResolvedValue(user());
    mockProfileFind.mockResolvedValue({ profileStatus: 'UNDER_REVIEW', identityVerificationStatus: 'PENDING' });
    await expect(assertIdentityEditable('u1', { lastName: 'Gómez' })).rejects.toMatchObject({ code: 'IDENTITY_LOCKED' });
  });

  it('getIdentityLock informa qué campos están bloqueados', async () => {
    mockUserFind.mockResolvedValue(user({ lastName: '-', dateOfBirth: null }));
    expect(await getIdentityLock('u1')).toEqual({ firstName: true, lastName: false, dateOfBirth: false });
    mockUserFind.mockResolvedValue(user());
    expect(await getIdentityLock('u1')).toEqual({ firstName: true, lastName: true, dateOfBirth: true });
  });
});

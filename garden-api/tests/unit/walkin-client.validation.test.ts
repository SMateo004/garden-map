import { createWalkInClientBodySchema, patchWalkInClientBodySchema } from '../../src/modules/caregiver-crm/caregiver-crm.validation';

describe('cliente presencial (walk-in)', () => {
  it('editar con correo vacío lo borra en vez de responder "Email inválido"', () => {
    const r = patchWalkInClientBodySchema.safeParse({ name: 'Ana', phone: '', email: '', notes: '  ' });
    expect(r.success).toBe(true);
    expect(r.success && r.data).toEqual({ name: 'Ana', phone: null, email: null, notes: null });
  });

  it('un correo escrito tiene que tener formato real', () => {
    const r = createWalkInClientBodySchema.safeParse({ name: 'Ana', email: 'ana@' });
    expect(r.success).toBe(false);
    expect(!r.success && r.error.errors[0]?.message).toBe('Revisa el correo del cliente');
  });

  it('el nombre no puede ser solo espacios', () => {
    expect(createWalkInClientBodySchema.safeParse({ name: '   ' }).success).toBe(false);
    expect(createWalkInClientBodySchema.safeParse({ name: ' Ana ' }).success).toBe(true);
  });
});

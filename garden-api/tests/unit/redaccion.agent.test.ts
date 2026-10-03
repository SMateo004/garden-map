/**
 * Agente de redacción: la mejora a pedido nunca inventa ni rebasa límites, y la corrección
 * automática previa a publicar falla abierta (devuelve el original ante cualquier duda).
 */
const mockCallClaude = jest.fn();
jest.mock('../../src/services/claude.service', () => ({
  callClaude: (...a: unknown[]) => mockCallClaude(...a),
}));

import {
  mejorarRedaccion,
  corregirTexto,
  corregirCamposPerfil,
  similitudPalabras,
  recortarA,
  RedaccionRechazadaError,
} from '../../src/agents/redaccion.agent';

describe('mejorarRedaccion', () => {
  beforeEach(() => mockCallClaude.mockReset());

  it('rechaza un campo que no admite IA', async () => {
    await expect(mejorarRedaccion({ campo: 'phone', texto: 'x'.repeat(30) })).rejects.toBeInstanceOf(RedaccionRechazadaError);
    expect(mockCallClaude).not.toHaveBeenCalled();
  });

  it('sin texto y sin notas pide al cuidador que cuente algo (no llama a Claude)', async () => {
    await expect(mejorarRedaccion({ campo: 'bio' })).rejects.toThrow(/pocas palabras/);
    expect(mockCallClaude).not.toHaveBeenCalled();
  });

  it('con texto suficiente mejora (modo mejorado) y manda el texto como datos', async () => {
    mockCallClaude.mockResolvedValue({ texto: 'Soy paseador con experiencia y amo a los perros.' });
    const out = await mejorarRedaccion({ campo: 'bio', texto: 'soy paseador con esperiencia y amo a los perros' });
    expect(out).toEqual({ texto: 'Soy paseador con experiencia y amo a los perros.', modo: 'mejorado' });
    expect(mockCallClaude.mock.calls[0][1]).toContain('esperiencia');
  });

  it('sin texto pero con notas redacta (modo generado)', async () => {
    mockCallClaude.mockResolvedValue({ texto: 'Cuido perros en mi casa con patio.' });
    const out = await mejorarRedaccion({ campo: 'bio', notas: 'cuido perros en casa con patio' });
    expect(out.modo).toBe('generado');
  });

  it('recorta al límite de la columna (bio = 500)', async () => {
    mockCallClaude.mockResolvedValue({ texto: 'Frase corta. '.repeat(100) });
    const out = await mejorarRedaccion({ campo: 'bio', texto: 'a'.repeat(50) });
    expect(out.texto.length).toBeLessThanOrEqual(500);
    expect(out.texto.endsWith('.')).toBe(true);
  });

  it('si la IA devuelve vacío con razón, se la muestra al usuario', async () => {
    mockCallClaude.mockResolvedValue({ texto: '', razon: 'El texto no habla de mascotas.' });
    await expect(mejorarRedaccion({ campo: 'bio', texto: 'receta de cocina de la abuela' })).rejects.toThrow(/no habla de mascotas/);
  });

  it('un fallo técnico de Claude se propaga (el endpoint responde 503)', async () => {
    mockCallClaude.mockRejectedValue(new Error('network'));
    await expect(mejorarRedaccion({ campo: 'bio', texto: 'a'.repeat(30) })).rejects.toThrow('network');
  });
});

describe('corregirTexto (automática, falla abierta)', () => {
  beforeEach(() => mockCallClaude.mockReset());

  it('acepta una corrección ortográfica', async () => {
    mockCallClaude.mockResolvedValue({ texto: 'Tengo cinco años de experiencia con perros grandes.' });
    expect(await corregirTexto('experienceDescription', 'tengo cinco años de esperiencia con perros grandes')).toBe(
      'Tengo cinco años de experiencia con perros grandes.',
    );
  });

  it('descarta una "corrección" que reescribe o inventa contenido', async () => {
    mockCallClaude.mockResolvedValue({ texto: 'Soy veterinario certificado con diez años en clínicas internacionales.' });
    const original = 'Me gusta pasear perros por las tardes';
    expect(await corregirTexto('bio', original)).toBe(original);
  });

  it('descarta una corrección que excede el límite de la columna', async () => {
    const original = 'Cuido perros con mucho cariño. '.repeat(10);
    mockCallClaude.mockResolvedValue({ texto: original + 'palabra '.repeat(200) });
    expect(await corregirTexto('bio', original)).toBe(original);
  });

  it('ante error técnico devuelve el original sin lanzar', async () => {
    mockCallClaude.mockRejectedValue(new Error('timeout'));
    expect(await corregirTexto('bio', 'Texto original del cuidador')).toBe('Texto original del cuidador');
  });

  it('no llama a Claude con textos vacíos o demasiado cortos', async () => {
    expect(await corregirTexto('bio', '  ')).toBe('  ');
    expect(mockCallClaude).not.toHaveBeenCalled();
  });
});

describe('corregirCamposPerfil', () => {
  beforeEach(() => mockCallClaude.mockReset());

  it('solo toca campos de texto del perfil y devuelve únicamente los que cambiaron', async () => {
    mockCallClaude.mockImplementation(async (_s: string, msg: string) =>
      msg.includes('biografia') || msg.includes('esperiencia')
        ? { texto: 'Tengo experiencia con perros.' }
        : { texto: 'Cuido perros con cariño.' });

    const cambios = await corregirCamposPerfil({
      bio: 'Cuido perros con cariño.', // ya estaba bien → no cambia
      experienceDescription: 'Tengo esperiencia con perros.', // se corrige
      pricePerDay: 120, // no es texto → se ignora
      phone: '71234567', // no está en la lista → se ignora
      whyCaregiver: null, // null → se ignora
    });
    expect(cambios).toEqual({ experienceDescription: 'Tengo experiencia con perros.' });
  });
});

describe('utilidades', () => {
  it('similitudPalabras ignora tildes y mayúsculas', () => {
    expect(similitudPalabras('Paseo perros GRANDES', 'paséo perros grandes')).toBe(1);
    expect(similitudPalabras('uno dos tres cuatro', 'cinco seis siete ocho')).toBe(0);
  });

  it('recortarA no corta palabras a la mitad', () => {
    const out = recortarA('palabra '.repeat(20), 30);
    expect(out.length).toBeLessThanOrEqual(30);
    expect(out.endsWith('palabra')).toBe(true);
  });
});

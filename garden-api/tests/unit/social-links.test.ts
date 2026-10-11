/**
 * Redes del cuidador: se guarda solo el @usuario y el link lo arma el
 * servidor. Se aceptan los links que mandaban las versiones anteriores de la
 * app y se rechaza cualquier otra cosa (antes se guardaba cualquier JSON).
 */
import { extractHandle, normalizeSocialInput, socialForResponse, socialUrl } from '../../src/shared/social-links';

describe('extractHandle: lo que escribe el cuidador → usuario', () => {
  it('acepta "@usuario" y "usuario"', () => {
    expect(extractHandle('instagram', '@maria.paseos')).toBe('maria.paseos');
    expect(extractHandle('instagram', '  maria_paseos  ')).toBe('maria_paseos');
    expect(extractHandle('tiktok', '@@maria.bo')).toBe('maria.bo');
  });

  it('acepta el link completo de esa red (lo que mandaba la app vieja)', () => {
    expect(extractHandle('instagram', 'https://instagram.com/maria.paseos/')).toBe('maria.paseos');
    expect(extractHandle('instagram', 'www.instagram.com/maria?igsh=abc')).toBe('maria');
    expect(extractHandle('facebook', 'https://m.facebook.com/patitas.scz')).toBe('patitas.scz');
    expect(extractHandle('facebook', 'https://www.facebook.com/profile.php?id=100012345678')).toBe('100012345678');
    expect(extractHandle('tiktok', 'https://www.tiktok.com/@maria.bo?lang=es')).toBe('maria.bo');
  });

  it('rechaza links de otra red u otro sitio y caracteres inválidos', () => {
    expect(extractHandle('instagram', 'https://evil.example/instagram.com/x')).toBeUndefined();
    expect(extractHandle('instagram', 'https://facebook.com/maria')).toBeUndefined();
    expect(extractHandle('instagram', 'javascript:alert(1)')).toBeUndefined();
    expect(extractHandle('instagram', 'maria paseos')).toBeUndefined();
    expect(extractHandle('instagram', 'a'.repeat(31))).toBeUndefined();
    expect(extractHandle('facebook', 'ma_ria')).toBeUndefined();
    expect(extractHandle('tiktok', 'x')).toBeUndefined();
  });

  it('vacío = sin esa red', () => {
    expect(extractHandle('instagram', '')).toBeNull();
    expect(extractHandle('instagram', '   ')).toBeNull();
    expect(extractHandle('instagram', undefined)).toBeNull();
  });
});

describe('normalizeSocialInput: al guardar', () => {
  it('guarda solo usuarios, de las redes conocidas', () => {
    expect(normalizeSocialInput({
      instagram: '@maria.paseos',
      facebook: 'https://facebook.com/patitas.scz',
      tiktok: '',
      twitter: '@ignorado',
    })).toEqual({ instagram: 'maria.paseos', facebook: 'patitas.scz' });
  });

  it('todo vacío o null = sin redes', () => {
    expect(normalizeSocialInput({ instagram: '', facebook: ' ' })).toBeNull();
    expect(normalizeSocialInput(null)).toBeNull();
  });

  it('un usuario inválido da un error claro para mostrar en la app', () => {
    expect(() => normalizeSocialInput({ tiktok: 'no vale' })).toThrow('El usuario de TikTok no es válido: escribe solo tu @usuario.');
    expect(() => normalizeSocialInput('https://instagram.com/x')).toThrow('Redes sociales inválidas.');
  });
});

describe('socialForResponse: al mostrar', () => {
  it('devuelve los usuarios y los links armados por el servidor', () => {
    expect(socialForResponse({ instagram: 'maria', facebook: '100012345678', tiktok: 'maria.bo' })).toEqual({
      socialHandles: { instagram: 'maria', facebook: '100012345678', tiktok: 'maria.bo' },
      socialLinks: {
        instagram: 'https://www.instagram.com/maria',
        facebook: 'https://www.facebook.com/profile.php?id=100012345678',
        tiktok: 'https://www.tiktok.com/@maria.bo',
      },
    });
  });

  it('lee bien los datos viejos guardados como link y descarta lo inválido', () => {
    expect(socialForResponse({ instagram: 'https://instagram.com/maria', facebook: 'javascript:alert(1)' })).toEqual({
      socialHandles: { instagram: 'maria' },
      socialLinks: { instagram: 'https://www.instagram.com/maria' },
    });
    expect(socialForResponse(null)).toEqual({ socialHandles: null, socialLinks: null });
  });

  it('socialUrl: un link por red', () => {
    expect(socialUrl('facebook', 'patitas.scz')).toBe('https://www.facebook.com/patitas.scz');
  });
});

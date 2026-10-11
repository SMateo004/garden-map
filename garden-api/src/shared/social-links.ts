/**
 * Redes sociales del cuidador: se guarda SOLO el usuario (sin @ ni link) y el
 * link completo lo arma el servidor al responder. Así el cuidador escribe
 * "@maria.paseos" en vez de pegar un link, nadie puede guardar un link
 * cualquiera que después se abre desde el perfil público, y sumar una red es
 * agregarla acá.
 *
 * Se acepta igual lo que mandaban las versiones anteriores de la app (el link
 * completo, ej. https://instagram.com/maria): se extrae el usuario. Los datos
 * viejos guardados como link también se leen bien (socialForResponse).
 */
import { BadRequestError } from './errors.js';

export const SOCIAL_NETWORKS = ['instagram', 'facebook', 'tiktok'] as const;
export type SocialNetwork = (typeof SOCIAL_NETWORKS)[number];
export type SocialHandles = Partial<Record<SocialNetwork, string>>;

const LABELS: Record<SocialNetwork, string> = { instagram: 'Instagram', facebook: 'Facebook', tiktok: 'TikTok' };

/** Caracteres válidos de un usuario en cada red (reglas públicas de cada una). */
const HANDLE_RULES: Record<SocialNetwork, RegExp> = {
  instagram: /^[A-Za-z0-9._]{1,30}$/,
  facebook: /^[A-Za-z0-9.]{3,50}$/,
  tiktok: /^[A-Za-z0-9._]{2,24}$/,
};

const HOSTS: Record<SocialNetwork, RegExp> = {
  instagram: /(^|\.)instagram\.com$/i,
  facebook: /(^|\.)(facebook\.com|fb\.com)$/i,
  tiktok: /(^|\.)tiktok\.com$/i,
};

/** Link público que se abre desde el perfil del cuidador. */
export function socialUrl(network: SocialNetwork, handle: string): string {
  switch (network) {
    case 'instagram':
      return `https://www.instagram.com/${handle}`;
    case 'facebook':
      // Un perfil sin usuario propio solo tiene id numérico.
      return /^\d+$/.test(handle)
        ? `https://www.facebook.com/profile.php?id=${handle}`
        : `https://www.facebook.com/${handle}`;
    case 'tiktok':
      return `https://www.tiktok.com/@${handle}`;
  }
}

/**
 * Usuario a partir de lo que escribió la persona: "@maria", "maria" o un link
 * de esa red. null si quedó vacío; undefined si no es un usuario válido.
 */
export function extractHandle(network: SocialNetwork, raw: unknown): string | null | undefined {
  if (raw == null) return null;
  if (typeof raw !== 'string') return undefined;
  let value = raw.trim();
  if (!value) return null;

  const looksLikeLink = /^https?:\/\//i.test(value) || /^(www\.)?[a-z0-9.-]+\.(com)\b/i.test(value);
  if (looksLikeLink) {
    let url: URL;
    try {
      url = new URL(/^https?:\/\//i.test(value) ? value : `https://${value}`);
    } catch {
      return undefined;
    }
    if (!HOSTS[network].test(url.hostname)) return undefined;
    if (network === 'facebook' && url.pathname.replace(/\/+$/, '') === '/profile.php') {
      value = url.searchParams.get('id') ?? '';
    } else {
      value = decodeURIComponent(url.pathname.split('/').filter(Boolean)[0] ?? '');
    }
  }

  value = value.replace(/^@+/, '');
  return HANDLE_RULES[network].test(value) || (network === 'facebook' && /^\d{5,20}$/.test(value))
    ? value
    : undefined;
}

/**
 * Para guardar: valida y deja solo usuarios. null = sin redes. Lanza un error
 * claro (para mostrar tal cual en la app) si alguno no es un usuario válido.
 */
export function normalizeSocialInput(input: unknown): SocialHandles | null {
  if (input == null) return null;
  if (typeof input !== 'object' || Array.isArray(input)) {
    throw new BadRequestError('Redes sociales inválidas.', 'INVALID_SOCIAL_LINKS', 'socialLinks');
  }
  const out: SocialHandles = {};
  for (const network of SOCIAL_NETWORKS) {
    const handle = extractHandle(network, (input as Record<string, unknown>)[network]);
    if (handle === undefined) {
      throw new BadRequestError(
        `El usuario de ${LABELS[network]} no es válido: escribe solo tu @usuario.`,
        'INVALID_SOCIAL_HANDLE',
        `socialLinks.${network}`,
      );
    }
    if (handle) out[network] = handle;
  }
  return Object.keys(out).length > 0 ? out : null;
}

/**
 * Para responder: los usuarios (para mostrar "@maria" y precargar el
 * formulario) y los links armados (lo que abren las versiones instaladas de
 * la app). Tolera datos viejos guardados como link y descarta lo inválido.
 */
export function socialForResponse(stored: unknown): {
  socialHandles: SocialHandles | null;
  socialLinks: Partial<Record<SocialNetwork, string>> | null;
} {
  const handles: SocialHandles = {};
  if (stored && typeof stored === 'object' && !Array.isArray(stored)) {
    for (const network of SOCIAL_NETWORKS) {
      const handle = extractHandle(network, (stored as Record<string, unknown>)[network]);
      if (handle) handles[network] = handle;
    }
  }
  if (Object.keys(handles).length === 0) return { socialHandles: null, socialLinks: null };
  const links: Partial<Record<SocialNetwork, string>> = {};
  for (const [network, handle] of Object.entries(handles) as [SocialNetwork, string][]) {
    links[network] = socialUrl(network, handle);
  }
  return { socialHandles: handles, socialLinks: links };
}

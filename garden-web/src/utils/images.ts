/**
 * Placeholder estable (sin 404). Usar en todos los <img>: src={getImageUrl(url)} loading="lazy" alt="..."
 */
export const PLACEHOLDER_IMAGE_URL =
  'https://placehold.co/400x300/EEEEEE/999999/png?text=Sin+foto&font=montserrat';

/** Base URL for uploads (API serves static files at /uploads) */
export const UPLOADS_BASE_URL =
  (import.meta.env.VITE_API_URL || 'http://localhost:3000').replace(/\/$/, '') + '/uploads';

/**
 * Devuelve la URL a mostrar: la URL real si es válida (http/https), o el placeholder estable.
 * Acepta blob: y data: para previews locales (ej. foto recién elegida antes de subir).
 * Si la URL es relativa (/uploads/...), la convierte en absoluta usando UPLOADS_BASE_URL.
 */
export function getImageUrl(url?: string | null): string {
  if (url != null && typeof url === 'string') {
    const t = url.trim();
    if (t.length > 0) {
      if (t.startsWith('http://') || t.startsWith('https://')) return t;
      if (t.startsWith('blob:') || t.startsWith('data:')) return t;
      if (t.startsWith('/uploads/')) return UPLOADS_BASE_URL.replace(/\/uploads\/?$/, '') + t;
    }
  }
  return PLACEHOLDER_IMAGE_URL;
}

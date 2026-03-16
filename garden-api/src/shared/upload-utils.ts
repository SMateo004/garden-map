/**
 * Asegura que solo se persistan URLs absolutas (https://...) en la base de datos.
 * Nunca guardar rutas relativas (/uploads/...) ni solo public_id de Cloudinary.
 */
export function ensureAbsoluteUrl(url: string | null | undefined): string | null {
  if (url == null || typeof url !== 'string') return null;
  const trimmed = url.trim();
  if (trimmed.startsWith('https://') || trimmed.startsWith('http://')) return trimmed;
  return null;
}

/** Filtra un array de URLs y devuelve solo las absolutas (para photos[]). */
export function ensureAbsoluteUrls(urls: string[] | null | undefined): string[] {
  if (!Array.isArray(urls)) return [];
  return urls.map(ensureAbsoluteUrl).filter((u): u is string => u != null);
}

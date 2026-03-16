import DOMPurify from 'dompurify';

/** Sanitiza HTML para mostrar en bio. Permite etiquetas básicas seguras; evita XSS. */
export function sanitizeBio(html: string): string {
  if (!html) return '';
  return DOMPurify.sanitize(html, {
    ALLOWED_TAGS: ['b', 'i', 'em', 'strong', 'br', 'p'],
    ALLOWED_ATTR: [],
  });
}

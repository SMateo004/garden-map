/**
 * Cuentas de prueba para la revisión de las tiendas (Apple / Google) y las pruebas en vivo:
 * reviewer.admin, reviewer.cliente y reviewer.cuidador, SIEMPRE con el dominio propio de Garden.
 * No se puede falsear: registrar un correo @gardenbo.com exige verificarlo por código en ese buzón.
 *
 * Usos: exentas de la renovación periódica de términos (caregiver-terms.service.ts) y fuera del
 * registro público en blockchain (chain-registry.service.ts) — una prueba no debe quedar escrita
 * para siempre en la red principal ni gastar gas. La analítica las excluye con el mismo patrón SQL.
 */
export const TEST_EMAIL_PREFIX = 'reviewer.';
export const TEST_EMAIL_DOMAIN = '@gardenbo.com';

export function isTestAccountEmail(email: string | null | undefined): boolean {
  const e = (email ?? '').trim().toLowerCase();
  return e.startsWith(TEST_EMAIL_PREFIX) && e.endsWith(TEST_EMAIL_DOMAIN) && e.length > TEST_EMAIL_PREFIX.length + TEST_EMAIL_DOMAIN.length;
}

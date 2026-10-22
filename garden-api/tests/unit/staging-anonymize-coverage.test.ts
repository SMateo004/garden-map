/**
 * Toda columna del schema con pinta de dato personal tiene que estar en el anonimizador de staging
 * (scripts/staging/anonymize.sql) o en la lista de abajo, con el motivo. Así una columna nueva con
 * teléfonos, documentos o tokens no llega a staging sin que nadie lo decida.
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = join(__dirname, '..', '..');
const schema = readFileSync(join(root, 'prisma', 'schema.prisma'), 'utf8');
const sql = readFileSync(join(root, 'scripts', 'staging', 'anonymize.sql'), 'utf8');

const PII = /(email|phone|password|pin|token|secret|bankaccount|ci(Number|Anverso|Reverso|Front|Back)|nit(Number|Document|RazonSocial)?$|selfie|faceCropped|liveness|antecedentesUrl|microchip|vaccinePhotos|^documents$|address(Street|Number|Apartment|Condominio|Reference|Detail)?$|^ip(Address)?$|emergencyContacts|socialLinks|fcm|otp)/i;

/** tabla.columna que matchean el patrón pero se quedan a propósito. */
const KEEP: Record<string, string> = {
  'users.emailVerified': 'booleano',
  'users.phoneOtpExpiresAt': 'fecha, el código ya se borra',
  'users.phoneChangeAuthorizedUntil': 'fecha',
  'caregiver_profiles.emailVerified': 'booleano',
  'caregiver_profiles.phoneVerified': 'booleano',
  'caregiver_profiles.nitStatus': 'estado, no el documento',
  'caregiver_profiles.address': 'texto de zona que se muestra en el perfil público',
  'client_profiles.phoneVerified': 'booleano',
  'client_profiles.address': 'zona general; calle, número y referencia sí se borran',
  'booking_transport_legs.addressLat': 'redondeado',
  'vet_clinics.address': 'veterinarias: datos públicos',
  'vet_clinics.phone': 'veterinarias: datos públicos',
  'refresh_tokens.tokenHash': 'la tabla entera se borra',
  'password_resets.tokenHash': 'la tabla entera se borra',
  'blockchain_records.txHash': 'público en la blockchain',
  'blockchain_records.contractAddress': 'público en la blockchain',
  'identity_verification_sessions.livenessStatus': 'estado, no la imagen',
};

/** Texto de los UPDATE de esa tabla: la columna tiene que estar en uno de ellos, no en otra tabla. */
const updatesOf = (table: string) =>
  sql.split(`UPDATE "${table}" SET`).slice(1).map((chunk) => chunk.split(';')[0]).join(' ');

it('el anonimizador cubre todas las columnas con datos personales', () => {
  const missing: string[] = [];
  for (const m of schema.matchAll(/^model (\w+) \{([\s\S]*?)^\}/gm)) {
    const body = m[2]!;
    const table = body.match(/@@map\("(\w+)"\)/)?.[1] ?? m[1]!;
    const wholeTableDeleted = new RegExp(`DELETE FROM "${table}"`).test(sql);
    for (const [, col, type] of body.matchAll(/^\s+(\w+)\s+(\S+)/gm)) {
      if (!/^(String|Json)/.test(type!) || !PII.test(col!)) continue;
      const key = `${table}.${col}`;
      if (KEEP[key] || wholeTableDeleted || updatesOf(table).includes(`"${col}"`)) continue;
      missing.push(key);
    }
  }
  expect(missing).toEqual([]);
});

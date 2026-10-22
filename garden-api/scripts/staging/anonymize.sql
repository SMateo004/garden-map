-- Anonimiza una copia de producción para usarla como entorno de pruebas (staging).
--
-- Lo corre .github/workflows/db-backup.yml DESPUÉS de restaurar el respaldo en la base de
-- staging, nunca contra producción (el workflow compara los hosts y se niega si coinciden).
-- Objetivo: que desde staging no se pueda escribir, llamar ni notificar a una persona real,
-- y que no queden documentos ni datos de pago. Las cuentas reviewer.* (incluidas
-- reviewer.qa.*) quedan intactas para poder entrar con sus contraseñas de siempre.
--
-- Al agregar una columna con datos personales al schema, agrégala acá.

BEGIN;

-- Marca para que nadie confunda esta base con producción (y para que el workflow lo verifique).
INSERT INTO "app_settings" ("key", "value", "updatedAt")
VALUES ('environment', '"staging"', now())
ON CONFLICT ("key") DO UPDATE SET "value" = '"staging"', "updatedAt" = now();

-- Usuarios: correo y teléfono imposibles de entregar, sin tokens de push ni datos bancarios,
-- y sin contraseña utilizable (solo se entra con las cuentas reviewer.*).
UPDATE "users" SET
  "email"        = 'u-' || "id" || '@staging.gardenbo.test',
  "phone"        = '+000' || substr(md5("id"), 1, 12),
  "passwordHash" = '!staging-sin-acceso',
  "lastName"     = left("lastName", 1) || '.',
  "fcmToken"     = NULL,
  "bankAccount"  = NULL,
  "phoneOtp"     = NULL,
  "pendingPhone" = NULL
WHERE "email" NOT LIKE 'reviewer.%@gardenbo.com';

-- Sesiones y códigos: nada de lo emitido en producción vale en staging.
DELETE FROM "refresh_tokens";
DELETE FROM "password_resets";
DELETE FROM "password_reset_codes";
DELETE FROM "email_verifications";

-- Perfiles: documentos, carnet, NIT, cuentas bancarias, contactos de emergencia y la dirección
-- exacta. La ubicación se redondea (~1 km) para que el mapa y las distancias sigan sirviendo.
UPDATE "caregiver_profiles" SET
  "ciAnversoUrl" = NULL, "ciReversoUrl" = NULL, "ciNumber" = NULL,
  "nitNumber" = NULL, "nitDocumentUrl" = NULL,
  "bankAccount" = NULL, "emergencyContacts" = NULL,
  "addressStreet" = NULL, "addressNumber" = NULL, "addressApartment" = NULL,
  "addressReference" = NULL, "addressDetail" = NULL,
  "addressLat" = round("addressLat"::numeric, 2)::float8,
  "addressLng" = round("addressLng"::numeric, 2)::float8
WHERE "userId" NOT IN (SELECT "id" FROM "users" WHERE "email" LIKE 'reviewer.%@gardenbo.com');

UPDATE "client_profiles" SET
  "phone" = NULL, "nit" = NULL, "nitRazonSocial" = NULL,
  "addressStreet" = NULL, "addressNumber" = NULL, "addressApartment" = NULL,
  "addressReference" = NULL,
  "addressLat" = round("addressLat"::numeric, 2)::float8,
  "addressLng" = round("addressLng"::numeric, 2)::float8
WHERE "userId" NOT IN (SELECT "id" FROM "users" WHERE "email" LIKE 'reviewer.%@gardenbo.com');

UPDATE "bookings" SET "nit" = '0', "nitRazonSocial" = NULL;
UPDATE "booking_transport_legs" SET "address" = NULL, "addressReference" = NULL,
  "addressLat" = round("addressLat"::numeric, 2)::float8,
  "addressLng" = round("addressLng"::numeric, 2)::float8;

UPDATE "walk_in_clients" SET "phone" = NULL, "email" = NULL;

-- Verificación de identidad: selfies, fotos del carnet e IPs.
UPDATE "identity_verification_sessions" SET "selfieUrl" = NULL, "ciFrontUrl" = NULL, "ciBackUrl" = NULL, "ipAddress" = NULL;
UPDATE "verification_audits" SET "ipAddress" = NULL;

COMMIT;

# Entorno de pruebas (staging) y respaldos de la base

Estado: **funcionando desde el 2026-10-23** (primera corrida en verde: 73 tablas restauradas en
staging con las mismas filas que producción). La base de staging está en Render, región Virginia.

## Cómo funciona

Todos los días a las 04:00 (hora de Bolivia), el workflow **Respaldo de la base y entorno de pruebas**:

1. Cuenta las filas de cada tabla de producción y hace un `pg_dump` completo.
2. Cifra el respaldo (AES-256, con `BACKUP_PASSPHRASE`) y lo sube a un bucket **privado** de S3.
   Guarda 30 días. El repo es público: el respaldo nunca se sube como artefacto de GitHub.
3. Si existe `STAGING_DATABASE_URL`, baja ese mismo respaldo, lo restaura en la base de staging
   y compara las filas con producción. **Así el respaldo se prueba restaurándolo de verdad todos
   los días.** Si algo no cuadra, el workflow falla y GitHub te avisa por correo.
4. Anonimiza staging (`scripts/staging/anonymize.sql`). Correos y teléfonos quedan imposibles de
   entregar, sin tokens de push, carnets, NIT, cuentas bancarias, selfies ni direcciones exactas.
   Las cuentas `reviewer.*` quedan intactas para entrar con su contraseña de siempre.

El workflow se niega a restaurar si la URL de staging apunta al mismo servidor que producción.

## Pasos para dejarlo andando

### 1. Base de staging (Render)
- New → PostgreSQL. Nombre `garden-staging-db`, región **Oregon** (la misma que producción),
  PostgreSQL **16**. El plan más chico de pago alcanza (la base pesa ~20 MB). El plan gratis vence
  a los 30 días.
- Copia la **External Database URL** para el secret `STAGING_DATABASE_URL`.

### 2. API de staging (Render)
- Crea la rama: `git push origin origin/main:refs/heads/staging`.
- New → Web Service, mismo repo, **Branch: `staging`**, Root Directory `garden-api`, mismos
  Build y Start Command que producción.
- Variables de entorno: copia las de producción **con estos cambios**:
  - `DATABASE_URL` = Internal URL de `garden-staging-db`.
  - `JWT_SECRET` y `JWT_REFRESH_SECRET`: valores **nuevos**, distintos de producción.
  - `API_PUBLIC_URL` = la URL `.onrender.com` del servicio de staging.
  - `BLOCKCHAIN_ENABLED=false` y `SIP_ENABLED=false`.
  - **No copiar**: `BIRD_API_KEY`, `VONAGE_*`, `WHATSAPP_*`, `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
    (SNS y Rekognition), `FIREBASE_PROJECT_ID`/`FIREBASE_CLIENT_EMAIL`/`FIREBASE_PRIVATE_KEY`, ni `BLOCKCHAIN_PRIVATE_KEY`. Sin ellas,
    staging no puede mandar SMS, push ni escribir en la blockchain.
  - `RESEND_API_KEY` es obligatoria para arrancar: usa una key aparte de Resend o un valor de
    relleno. Los correos de staging terminan en `@staging.gardenbo.test` y no se entregan.
- Flujo de trabajo: lo que quieras probar se sube primero a `staging`
  (`git push origin HEAD:staging`), se prueba ahí, y recién después va a `main` (producción).

### 3. Bucket de respaldos (AWS)
- S3 → Create bucket, por ejemplo `garden-db-backups`, región `us-east-1`, con **Block all public
  access** activado.
- IAM → un usuario nuevo solo para respaldos, con permisos sobre ese bucket nada más:
  `s3:PutObject`, `s3:GetObject`, `s3:ListBucket`, `s3:DeleteObject`. No reutilices las keys de
  Rekognition.

### 4. Secrets de GitHub
Settings → Secrets and variables → Actions → New repository secret:

| Secret | Valor |
|---|---|
| `PROD_DATABASE_URL` | External URL de la base de producción |
| `BACKUP_PASSPHRASE` | Una clave larga nueva. **Guárdala también en el gestor de contraseñas**: sin ella los respaldos no se pueden abrir |
| `BACKUP_AWS_ACCESS_KEY_ID` / `BACKUP_AWS_SECRET_ACCESS_KEY` | Las del usuario IAM del paso 3 |
| `BACKUP_S3_BUCKET` | `garden-db-backups` |
| `STAGING_DATABASE_URL` | External URL de `garden-staging-db` |

### 5. Primera corrida
Actions → **Respaldo de la base y entorno de pruebas** → Run workflow. Tienen que quedar en
verde los dos jobs: "Respaldar producción" y "Restaurar en staging y verificar".

## Restaurar en una emergencia

```bash
aws s3 ls s3://garden-db-backups/db-backups/
aws s3 cp s3://garden-db-backups/db-backups/garden-AAAA-MM-DDTHHMM.dump.gpg .
gpg --decrypt --output garden.dump garden-AAAA-MM-DDTHHMM.dump.gpg
pg_restore --dbname="<URL de la base NUEVA>" --no-owner --no-privileges garden.dump
```

Restaura en una base **nueva** y apunta `DATABASE_URL` a ella. No restaures encima de la base
dañada sin antes guardar una copia.

## Respaldos propios de Render

La base de producción (`garden-db`, plan Basic-256mb) tiene **Point-in-Time Recovery de 3 días**
(verificado el 2026-10-23 en Render → garden-db → Recovery): se puede volver a cualquier momento
de los últimos 3 días con **Restore database**, que crea una base nueva. Con un workspace Pro sube
a 7 días. Para algo que se rompió hace más de 3 días, o si se pierde el acceso a Render, está el
respaldo diario de este workflow (30 días en S3).

## Llave de firma de Android

- `garden-app/android/garden-upload-key.jks` y `garden-app/android/key.properties` viven solo en
  la máquina de desarrollo. Verificada el 2026-10-22: alias `upload`, SHA1
  `33:18:AC:FC:03:A4:A3:D7:73:E5:38:92:7B:C9:CE:52:27:21:2D:3A`, la misma registrada en Play.
- **Respaldo:** adjunta los dos archivos a la entrada del gestor de contraseñas donde ya están sus
  contraseñas. `key.properties` contiene las contraseñas en texto plano: no lo mandes por chat ni
  lo subas a ningún lado sin cifrar.
- Play App Signing está activo (Google guarda la llave con la que se firma la app publicada). Si
  esta llave de carga se pierde, se puede pedir otra desde Play Console → Firma de apps (ya se
  hizo en agosto de 2026; tarda 48 h). Molesto, pero no se pierde la app.

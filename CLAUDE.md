# GARDEN — contexto para Claude Code

Marketplace de cuidado de mascotas en Santa Cruz de la Sierra, Bolivia. Conecta dueños con
paseadores/cuidadores verificados: paseo, guardería y hospedaje, con pago por QR bancario,
billetera interna, seguimiento GPS en vivo durante los paseos, chat, calificaciones y
resolución de disputas asistida por IA.

Monorepo con dos proyectos reales — no hay más carpetas activas que estas dos:

- **`garden-api/`** — Express + Prisma + PostgreSQL (TypeScript).
- **`garden-app/`** — Flutter (iOS, Android, Web). Bundle/package: `com.garden.bolivia`.

Si ves referencias a una carpeta `garden-web` (React/Vite) en algún doc viejo, ignoralas — esa
carpeta ya no existe, fue reemplazada por `garden-app` (Flutter).

## ⚠️ No hay entorno de staging — leé esto antes de tocar nada

`garden-api/.env` (gitignorado, nunca en el repo) tiene `DATABASE_URL` apuntando **directo a la
base de datos de producción en Render**. No existe una base de datos local ni de staging. Esto
significa:

- Correr `npm run dev` en `garden-api` conecta a datos **reales**.
- Para probar cosas usá las cuentas dedicadas de prueba (mismo password para las tres):
  `reviewer.admin@gardenbo.com` / `reviewer.cliente@gardenbo.com` / `reviewer.cuidador@gardenbo.com`
  — password `ReviewGarden2026!`.
- Si creás cuentas o datos de prueba nuevos (no las `reviewer.*`), **limpialos vos mismo al
  terminar** — usuarios, bookings y wallet transactions sueltos quedan en producción para
  siempre si no los borrás. Ya pasó una vez en este proyecto (una auditoría dejó 6 cuentas
  basura y contaminó el saldo de las cuentas reviewer con bugs que se estaban probando).
- Antes de un cambio grande, considerá si de verdad hace falta probar contra producción o si
  alcanza con revisar el código.

### Alternativa: Postgres local vía Docker (para probar lógica de datos sin tocar prod)

`garden-api/docker-compose.yml` levanta un Postgres 16 local (puerto 5433) con datos sintéticos
propios — nunca un volcado de producción. Pensado para lo que solo necesita una base de datos
correcta, no las integraciones externas reales (Resend, AWS, SIP, etc. — esas siguen siendo las
reales sin importar qué DATABASE_URL uses, así que una prueba final contra producción con las
cuentas `reviewer.*` sigue haciendo falta para lo que dependa de ellas).

```bash
docker compose up -d          # levanta el contenedor (Docker Desktop debe estar corriendo)
cp .env.local.example .env.local
npm run db:push:local         # sincroniza el schema en la base local (vacía)
npm run db:seed:local         # crea admin/cuidadores de prueba (prisma/seed.ts)
npm run dev:local             # arranca la API apuntando a la base local, no a producción
```

**Estado conocido (2026-08-26):** el setup está armado y `docker compose up` + la conexión TCP
cruda al contenedor funcionan bien (verificado con `psql` y un socket Node directo), pero
`prisma db push`/`db seed` fallan con `P1000: Authentication failed` contra este Postgres local
específicamente en esta máquina (Windows + Docker Desktop) — probé usuario/contraseña correctos,
`127.0.0.1` en vez de `localhost`, `sslmode=disable`, auth `md5` explícito, y forzar el engine
binario nativo (`PRISMA_SCHEMA_ENGINE_TYPE=binary`) en vez del WASM por defecto de Prisma 5.22;
ninguno lo resolvió, y el contenedor nunca registra el intento de conexión — apunta a un problema
del lado del engine de Prisma en este entorno, no de la config. Si te encontrás con esto: probá
otra versión de Prisma, o simplemente cambiá `DATABASE_URL` en `.env` a mano de forma temporal
para el `db push`/seed puntual (mismo mecanismo que ya usa todo lo demás en este proyecto).

## Cómo se despliega (verificado con el historial real de GitHub Actions, no asumido)

- **Push a `garden-api/**` en `main`** → `.github/workflows/deploy-api.yml` dispara un deploy
  hook de Render → redeploy automático de la API en `https://api.gardenbo.com` (dominio propio
  sobre Render, sirve por Cloudflare). Sin acción manual — Render reinicia solo.
- **Push a `garden-app/**` en `main`** → `.github/workflows/deploy-flutter-web.yml` compila
  Flutter Web y despliega a Vercel. `gardenbo.com` apunta a ese deploy de Vercel (landing
  estático + redirect a `/app.html` para las rutas de Flutter).
- **PRs** generan preview URLs de Vercel con comentario automático en el PR.
- Confirmar el estado real de cualquiera de los dos con `gh run list --workflow=deploy-api.yml`
  o `--workflow=deploy-flutter-web.yml` — no confíes en documentación vieja sobre esto, verificá
  con `gh`.
- Variables de entorno en Render/Vercel se cambian desde sus dashboards — al guardar, Render
  reinicia el servicio solo (no hace falta redeploy manual ni tocar código).

## Builds nativas (iOS / Android) — separadas del pipeline anterior

Los pipelines de arriba solo cubren el build **web** de Flutter. Los builds de iOS/Android para
las tiendas se generan a mano:

```bash
cd garden-app
flutter build appbundle --release   # Android, para Play Store
flutter build ipa --release          # iOS, para App Store (requiere macOS + Xcode)
```

- **Firma de Android**: `garden-app/android/garden-upload-key.jks` +
  `garden-app/android/key.properties` — ambos gitignorados, viven solo en la máquina donde se
  generaron. Las contraseñas están en un gestor de contraseñas (pedíselas a Sai si las
  necesitás). **Si se pierden, no se puede volver a actualizar la app en Play Store con el mismo
  listing.**
- **Firma de iOS**: requiere cuenta de Apple Developer Program activa (certificados y
  provisioning profiles se gestionan desde Xcode/Developer Portal, no desde este repo).
- Checklist completo de lo que falta para subir a las tiendas: pedile a Claude que lo regenere,
  o buscá el artifact ya generado en la conversación donde se creó.

## Variables de entorno — `garden-api/.env`

Nunca versionado, nunca se pega en chat/PR en texto plano. Se transfiere entre máquinas por un
canal privado (gestor de contraseñas, AirDrop, etc.). Validado con Zod al arrancar
(`src/config/env.ts`) — si falta algo obligatorio, el server no arranca y te dice exactamente
qué falta.

Puntos que ya causaron incidentes reales, tenerlos presentes:
- `GOOGLE_MAPS_KEY` es obligatoria — sin ella el server no arranca.
- `API_PUBLIC_URL` **debe** ser la URL pública real (`https://api.gardenbo.com`) apenas
  `SIP_ENABLED=true` — si queda en `localhost` (su default), el server arranca igual pero el
  banco nunca puede confirmar pagos porque le mandamos un callback inalcanzable. Ya está validado
  al arrancar para que esto falle rápido en vez de en silencio.
- `SENTRY_DSN` — activo en producción, revisá Sentry ante cualquier bug reportado antes de
  asumir que hay que reproducirlo a mano.

## Pagos y dinero — reglas que no se negocian

- **`User.balance` es la ÚNICA fuente de verdad de saldo.** `CaregiverProfile.balance` y
  `ClientProfile.balance` están deprecados — si ves código que los lee o escribe, es un bug (ya
  encontramos y arreglamos uno así: una disputa resuelta "pagaba" a estos campos deprecados y el
  ganador nunca podía retirar el dinero de verdad).
- Cualquier operación que lea-luego-escriba un balance debe pasar por
  `SELECT ... FOR UPDATE` dentro de una `$transaction` — sin esto, dos requests concurrentes
  duplican/triplican créditos. Patrón ya establecido en varios lados de `booking.service.ts` y
  `admin.service.ts`; copiá ese patrón, no inventes uno nuevo.
- SIP (pago QR bancario boliviano) — código completo en `src/services/sip.service.ts`, gateado
  por `SIP_ENABLED`. Mientras estén vacías las credenciales del banco, el sistema cae a un QR
  placeholder local (solo en dev) o bloquea el pago con alerta a admins (en producción). No es un
  bug, es el diseño esperado hasta que lleguen las credenciales del banco.

## Verificación de teléfono

Cadena de 3 canales en `src/services/otp-delivery.service.ts`, cada uno se salta solo si el
anterior falla o no está configurado:

1. **WhatsApp Business Cloud API** (`WHATSAPP_PHONE_NUMBER_ID`/`WHATSAPP_ACCESS_TOKEN`) — sin
   configurar todavía (pendiente verificación de negocio de Meta, estancada pidiendo más info —
   ver Business Manager > Autorizaciones y verificaciones). Si en el futuro se resuelve vía un
   BSP como Infobip en vez de ir directo por Meta, revisar esto primero.
2. **Infobip SMS** (`INFOBIP_API_KEY`/`INFOBIP_BASE_URL`/`SMS_SENDER_ID`) — cuenta en trámite de
   alta (agosto 2026), pendiente de que ventas la habilite (el signup self-serve mandó a un
   flujo de contacto comercial en vez de dar API key directo).
3. **AWS SNS Publish** (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_REGION`, ya
   configurados para Rekognition, + `SMS_SENDER_ID`) — API clásica de SNS, **distinta** de AWS
   End User Messaging SMS/Pinpoint (la que se abandonó, ver abajo). No requiere número dedicado
   ni Business Verification: sin origen especificado, AWS elige uno del pool compartido. Es la
   red de contención que sí funciona hoy sin ningún trámite pendiente, mientras Infobip/WhatsApp
   se activan.

Se descartó AWS End User Messaging SMS (Pinpoint, con número Toll-Free) porque quedó rechazado
dos veces ("Business Verification Failed", cuenta personal sin entidad legal en EEUU) y no había
forma de reintentarlo — **no confundir con AWS SNS Publish (punto 3), que es una API distinta y
sí está en uso**. También se descartó Twilio: su propia documentación admite que en Bolivia
sobrescribe el Sender ID de forma inconsistente fuera de la red Viva, lo que puede hacer que
mensajes figuren como "delivered" sin llegar nunca — coincide con problemas reales ya vividos con
Twilio en este proyecto. Importante para Bolivia sin importar el proveedor: **Tigo exige registro
de Sender ID** (si no se hace, filtra en silencio); Entel reemplaza el Sender ID por un shortcode
fijo igual (no es un bug); Viva no tiene restricciones.

Mientras ninguno de los tres canales esté activo, el código guarda el OTP en la base y notifica a
los admins para dar soporte manual — esto ya funciona, no es un error.

## Convenciones de git

- Nunca `git add -A` — stagear archivos por nombre explícito. El repo suele acumular archivos
  sueltos de pruebas (fotos falsas, scripts `_tmp_*`, capturas) que no deben commitearse.
  `git status --porcelain` antes de cada commit para revisar qué se está por subir.
  - Se acumulan también archivos `.md` sueltos en la raíz de sesiones anteriores (`FIX-*.md`,
  `SETUP_REQUIRED.md`, etc.) — varios están obsoletos. Si un doc contradice lo que ves en el
  código real o en `gh run list`, confiá en el código/GitHub, no en el doc.
- Nunca force-push, nunca `--no-verify`, nunca amend salvo pedido explícito.
- Mensajes de commit en español, formato `tipo: descripción corta` (fix/feat/chore), con cuerpo
  explicando el *por qué* cuando el cambio no es obvio — mirá `git log` para el tono exacto.
- Solo commitear cuando el usuario lo pide explícitamente.

## Metodología de testing establecida

- Preferí probar en vivo contra la API real con `curl` y las cuentas `reviewer.*` en vez de
  asumir que el código funciona por lectura sola — este proyecto maneja dinero real.
- Después de cualquier cambio en `garden-api`: `npx tsc --noEmit` (hay 2-3 errores preexistentes
  no relacionados, conocidos — no los persigas, solo confirmá que no agregaste nuevos).
- Después de cualquier cambio en `garden-app`: `flutter analyze` (debería dar 0 errores).
- Limpiá cualquier dato de prueba que hayas creado en producción antes de terminar la sesión.

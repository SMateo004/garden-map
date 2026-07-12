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

WhatsApp Business Cloud API (`WHATSAPP_PHONE_NUMBER_ID`/`WHATSAPP_ACCESS_TOKEN`) — sin
configurar todavía (pendiente verificación de negocio de Meta). Fallback: AWS End User Messaging
SMS con número Toll-Free — registro ante operadoras enviado, revisá el estado real con:

```bash
node -e "require('dotenv').config(); const {PinpointSMSVoiceV2Client,DescribeRegistrationsCommand}=require('@aws-sdk/client-pinpoint-sms-voice-v2'); new PinpointSMSVoiceV2Client({region:process.env.AWS_REGION,credentials:{accessKeyId:process.env.AWS_ACCESS_KEY_ID,secretAccessKey:process.env.AWS_SECRET_ACCESS_KEY}}).send(new DescribeRegistrationsCommand({RegistrationIds:['registration-b4dadc4573ea4654817489ca61965fac']})).then(r=>console.log(r.Registrations[0]))"
```

Mientras ninguno de los dos esté activo, el código guarda el OTP en la base y notifica a los
admins para dar soporte manual — esto ya funciona, no es un error.

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

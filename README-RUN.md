# Cómo hacer correr GARDEN sin errores

**Guía detallada (checklist, comandos exactos, flujo en navegador, debug):** [docs/RUN-LOCAL.md](docs/RUN-LOCAL.md)

**Flujo completo de aprobación de cuidador (admin revisa → aprueba/rechaza → dashboard):** [docs/FLUJO-APROBACION-CUIDADOR.md](docs/FLUJO-APROBACION-CUIDADOR.md)

**Flujo completo Dueño (sin login → reservar → registrarse → completar perfil mascota → reservar):** [docs/FLUJO-DUENO-PRUEBA.md](docs/FLUJO-DUENO-PRUEBA.md)

**Flujo completo de reserva y notificaciones (confirmación, pago, cancelación, reembolsos):** [docs/FLUJO-RESERVA-Y-NOTIFICACIONES.md](docs/FLUJO-RESERVA-Y-NOTIFICACIONES.md)

**Disponibilidad del cuidador (horario predeterminado, overrides por fecha, motivo):** [docs/DISPONIBILIDAD-CUIDADOR.md](docs/DISPONIBILIDAD-CUIDADOR.md)

## 1. Base de datos (PostgreSQL)

Desde la raíz del proyecto:

```bash
docker compose up -d
```

Esto levanta PostgreSQL en `localhost:5432` con usuario `user`, contraseña `password` y base `garden_db` (igual que en `.env.example`).

Si no usas Docker, asegúrate de tener PostgreSQL en el puerto 5432 y que tu `garden-api/.env` tenga la `DATABASE_URL` correcta.

## 2. Variables de entorno de la API

En `garden-api` debe existir un `.env`. Si no existe:

```bash
cd garden-api
cp .env.example .env
```

Revisa que `DATABASE_URL` coincida con tu Postgres (por defecto `postgresql://user:password@localhost:5432/garden_db`).

## 3. Migraciones

El schema Prisma usa **IDs y claves foráneas en `String` con `@default(uuid())`** (p. ej. `User.id`, `Pet.id`, `Booking.petId`) para evitar conflictos de tipo en PostgreSQL.

```bash
cd garden-api
npx prisma generate
npx prisma migrate dev
```

- **Imágenes en todo el MVP:** La migración `20260218000000_add_all_image_columns` añade las columnas de imagen que puedan faltar en la DB (`profilePhoto` en caregiver_profiles, `petPhoto` en client_profiles, CI, etc.). Sin ella, GET /api/caregivers puede devolver 500 (P2022). Tras aplicarla, reinicia el API.
- **Si la API sale al arrancar** con el mensaje "Database schema out of sync. Table or column missing": la DB no tiene la tabla `caregiver_profiles` o la columna `profilePhoto`. Desde `garden-api` ejecuta `npm run db:push` (o `npx prisma db push`) y vuelve a iniciar la API.
- **Para evitar el error de schema:** desde `garden-api` puedes usar `npm run dev:safe` o `npm run start:safe`; hacen `db:push` y luego arrancan la API.
- La migración `20260217100000_restore_client_profile_pet_photo` restaura `petPhoto` en `client_profiles` si se había eliminado.

**Pruebas exhaustivas de imágenes:** Ver [docs/PRUEBAS-IMAGENES.md](docs/PRUEBAS-IMAGENES.md) (5 casos: mascota, cuidador, CI, placeholder, refresh).

**Reset sin seed:** [garden-api/prisma/README-RESET-SEED.md](garden-api/prisma/README-RESET-SEED.md). **Reset total (borrar migraciones y recrear DB desde schema):** si la tabla `caregiver_profiles` no existe o la DB está inconsistente, usa [garden-api/prisma/README-RESET-DB-LIMPIO.md](garden-api/prisma/README-RESET-DB-LIMPIO.md): `rm -rf prisma/migrations`, `npx prisma db push --force-reset --accept-data-loss`, luego seed y `npm run dev`.

Si alguna migración falló antes (p. ej. `bookings_petId_fkey` uuid vs text), puedes resetear y reaplicar todo (borra la DB y vuelve a aplicar migraciones; seed solo si lo ejecutas a mano):

```bash
cd garden-api
npx prisma migrate reset --force --skip-seed
tsx prisma/seed.ts
```

**Seed (admin + 2 cuidadores de prueba):** Ejecutar a mano tras el reset (el seed automático está deshabilitado):

```bash
cd garden-api
tsx prisma/seed.ts
```

Contraseña de prueba para todos: `GardenSeed2024!`
- Admin: `admin@garden.bo`
- Cuidador DRAFT: `cuidador.draft@garden.bo`
- Cuidador PENDING: `cuidador.pending@garden.bo`

**Endpoints flujo cuidador:**
- `POST /api/auth/caregiver/register` — Registro cuidador (full submit); status PENDING_REVIEW.
- `POST /api/auth/login` — Login (opcional `?role=caregiver`).
- `GET /api/caregiver/my-profile` — Perfil del cuidador (Bearer, CAREGIVER).
- `PATCH /api/caregiver/profile` — Autosave parcial (Bearer, CAREGIVER); 403 si status APPROVED.
- `POST /api/caregiver/submit` — Enviar solicitud (status → PENDING_REVIEW).

**Admin:**
- `GET /api/admin/caregivers/pending?page=1&limit=20` — Lista PENDING_REVIEW/NEEDS_REVISION (Bearer, ADMIN).
- `PATCH /api/admin/caregivers/:id/review` — Body: `{ action: "approve"|"reject"|"request_revision", reason?: string }`.

## 4. Arrancar API y frontend

**Terminal 1 – API:**

```bash
cd garden-api
npm run dev
```

Debe mostrar "Database connected" y "GARDEN API listening on port 3000". En desarrollo el backend **siempre** usa el puerto 3000 (independiente de `PORT` en `.env`).

**Comprobar que la API responde:** abre en el navegador **http://localhost:3000/health**. Debe devolver `{"success":true,"data":{"status":"ok","port":"3000",...}}`.

**Terminal 2 – Frontend (tienes que estar en la carpeta garden-web):**

```bash
cd garden-web
npm run dev
```

Si estás en la raíz del repo (`garden-mvp`), el path es `garden-web`. Si estabas en `garden-api`, sal primero: `cd ..` y luego `cd garden-web`. Debes ver en consola algo como `[GARDEN] Frontend (garden-web)` y luego `VITE ready` / `Local: http://localhost:5173/`.

El frontend apunta a la API con `VITE_API_URL=http://localhost:3000` (archivo `garden-web/.env`). Si esa variable no está definida, se usa por defecto `http://localhost:3000` en el cliente axios.

Abre en el navegador: **http://localhost:5173/**

**Login admin:** **http://localhost:5173/admin/auth** (mismo usuario/contraseña del seed: `admin@garden.bo` / `GardenSeed2024!`).

## Scripts desde la raíz (garden-mvp)

Con `package.json` en la raíz:

```bash
# Migrar + seed (requiere Postgres y DATABASE_URL en garden-api/.env)
npm run setup:db

# Verificación del flujo (API debe estar corriendo en :3000)
BASE_URL=http://localhost:3000 node scripts/verification-flow.js

# Tests
npm run test:api    # Jest en garden-api
npm run test:web    # Vitest en garden-web
```

## Flujo "Soy cuidador"

1. En la web (localhost:5173), clic en **"Soy cuidador →"** → navega a `/caregiver/auth`.
2. Pestaña **Registrarme** → **Comenzar registro** → wizard de 10 pasos (guardado en localStorage; condicional: paso hogar solo si Hospedaje).
3. Al enviar: registro completo (User + CaregiverProfile) con status PENDING_REVIEW, o si ya eres cuidador: POST `/api/caregiver/submit`.
4. Admin: login con `admin@garden.bo` / `GardenSeed2024!`; GET pending, PATCH review (approve/reject/request_revision).
5. Listado público (`/api/caregivers` y página Cuidadores): solo perfiles **verified/APPROVED**; min 4 fotos.

## Resumen de enlaces

| Servicio   | URL                    |
|-----------|-------------------------|
| Frontend  | http://localhost:5173/ |
| API       | http://localhost:3000/  |
| Health API| http://localhost:3000/health |

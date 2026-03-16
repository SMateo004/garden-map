# Flujo "Soy cuidador" — Integración completa MVP

## Resumen

Integración backend + frontend para el flujo: **botón "Soy cuidador" → auth → wizard (autosave) → submit → admin review**, alineada con el MVP (fotos reales, status DRAFT → PENDING_REVIEW → APPROVED, no visible hasta aprobado).

## Archivos generados/actualizados

### Backend (garden-api)

- **prisma/schema.prisma** — Ya incluye: `CaregiverStatus`, `AdminNotification`, campos 15 pasos (bio, bioDetail, zone, spaceType, spaceDescription, termsAccepted, etc.), índices `status`, `userId`.
- **prisma/seed.ts** — 1 admin (`admin@garden.bo`), 2 cuidadores (DRAFT + PENDING_REVIEW). Contraseña: `GardenSeed2024!`.
- **modules/caregiver-profile/** — PATCH profile (parcial, 403 si APPROVED), POST submit (validación obligatorios, PENDING_REVIEW, AdminNotification), GET my-profile.
- **modules/admin/** — GET caregivers/pending (paginación), PATCH caregivers/:id/review (approve/reject/request_revision), validación Zod, tipos en admin.types.ts.
- **tests/unit/admin.service.test.ts** — Actualizado para `listPendingCaregivers(page, limit)` y filtro por status.

### Frontend (garden-web)

- **api/caregiverProfile.ts** — `getMyProfile()`, `patchProfile(payload)`, `submitProfile()` (con token Bearer).
- **Navbar** — Botón "Soy cuidador →" ya navega a `/caregiver/auth`; si es cuidador, a `/caregiver/dashboard`.
- **CaregiverAuthPage** — Tabs login / Registrarme; "Comenzar registro" → `/caregiver/register`.
- **RegisterWizard** — 10 pasos, progress bar, condicional hogar solo si Hospedaje, guardado en localStorage; submit vía `registerCaregiver` (full) o en el futuro `submitProfile()` si ya está logueado.
- **Listing** — Backend ya filtra por `verified: true` (solo APPROVED visibles).

### Raíz (garden-mvp)

- **package.json** — Scripts: `setup:db`, `setup:db:dev`, `start:api`, `start:web`, `start:full`, `test:flow`, `test:api`, `test:web`, `verification`.
- **scripts/verification-flow.js** — Login cuidador → my-profile → login admin → GET pending → PATCH approve → GET /api/caregivers. Ejecutar con API en marcha: `BASE_URL=http://localhost:3000 node scripts/verification-flow.js`.
- **README-RUN.md** — Instrucciones de DB, seed, endpoints, flujo "Soy cuidador", scripts.

## Cómo ejecutar todo

1. **PostgreSQL**
   ```bash
   docker compose up -d
   ```

2. **Variables**
   - `garden-api/.env` con `DATABASE_URL`, `JWT_SECRET`, `CLOUDINARY_*` (ver `garden-api/.env.example`).

3. **Migraciones y seed**
   - Primera vez (crea carpeta migrations):
     ```bash
     cd garden-api && npx prisma migrate dev --name init && npx prisma db seed
     ```
   - O desde raíz (si ya existen migraciones):
     ```bash
     npm run setup:db
     ```

4. **Servidores**
   - Terminal 1: `cd garden-api && npm run dev` → API en :3000.
   - Terminal 2: `cd garden-web && npm run dev` → Frontend en :5173.

5. **Verificación**
   ```bash
   BASE_URL=http://localhost:3000 node scripts/verification-flow.js
   ```

6. **Tests**
   - Backend: `cd garden-api && npm run test:unit` (60 tests).
   - Frontend: `cd garden-web && npm run test:run` (54 tests).

## Consistencias MVP verificadas

- **No visible hasta APPROVED** — `listCaregivers` usa `verified: true` (sincronizado con status APPROVED).
- **Mínimo 4 fotos** — Validación en registro (Zod + backend) y en submit (getMissingRequiredFieldsForSubmit).
- **Status flow** — DRAFT (borrador) → PENDING_REVIEW (submit) → APPROVED (admin) / REJECTED / NEEDS_REVISION.
- **Admin** — Solo role ADMIN; GET pending paginado; PATCH review con action + reason opcional; console.log para notificación (sustituible por email/WhatsApp).

## Posibles mejoras (V2)

- Filtros en listing por zona/servicio ya existen en backend; exponer en UI.
- Autosave del wizard vía PATCH cada paso (o throttle 30s) cuando el usuario ya es CAREGIVER (token); cargar datos con GET my-profile al volver.
- Precios dinámicos: campos ya en schema (`pricePerDay`, `pricePerWalk30`, `pricePerWalk60`); UI de búsqueda por rango ya soportada en API.

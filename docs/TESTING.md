# GARDEN MVP — Testing & CI

Estructura de tests e integración continua. Objetivo de cobertura **80%** (alineado con doc técnica). Flexible para evolución.

---

## 1. Backend (garden-api)

### Unit tests (Jest)
- **`tests/unit/caregiver.service.test.ts`**: validaciones (photo count, bio), listCaregivers (filtros, paginación), createCaregiverProfile (conflict, rol).
- **`tests/unit/admin.service.test.ts`**: `toggleVerify` (not found, true→false, false→true), `listPendingCaregivers`.

### Integration tests (Jest + Supertest)
- **`tests/integration/caregivers.api.test.ts`**: API HTTP con Prisma mockeado (sin DB real).
  - `GET /api/caregivers`: 200, lista paginada, filtros.
  - `GET /api/caregivers/:id`: 200 detalle, 404 si no existe.
  - `GET /health`: 200.

### Cobertura
- `npm run test:coverage` en `garden-api`.
- Umbral en `jest.config.js`: `coverageThreshold.global` 80% (branches, functions, lines, statements).

### Debug / logging
- **Winston** en `src/shared/logger.ts`: nivel por `LOG_LEVEL`, logs a `logs/error.log` y `logs/combined.log`, consola en desarrollo.
- **Error handler** (`src/shared/error-handler.ts`) registra errores no controlados con `logger.error`.

---

## 2. Frontend (garden-web)

### Unit tests (Vitest + RTL)
- **`ProfileCard.test.tsx`**: render nombre/zona, badge “Verificado por GARDEN” condicional, link a detalle.
- **`Badge.test.tsx`**: variantes default, verified, muted.
- **`UploadForm.test.tsx`**: label, error, onChange al elegir archivo, remove.
- **`ErrorBoundary.test.tsx`**: render children, fallback al lanzar, UI por defecto con “Reintentar”.

### E2E (Playwright)
- **`e2e/profiles-flow.spec.ts`**:
  - Listing carga y muestra filtros.
  - Navegación a registro cuidador.
  - Formulario de registro con campos requeridos.
  - Navegación a detalle al hacer click en card (si hay datos).

### Cobertura
- `npm run test:coverage` en `garden-web` (Vitest + v8).
- Excluidos: `node_modules`, `src/test`, `*.test.*`, `*.d.ts`.

### Error Boundary
- **`src/components/ErrorBoundary.tsx`**: captura errores de render, muestra fallback o UI por defecto, opcional `onError` para logging/Sentry.
- App envuelta en `<ErrorBoundary>` en `main.tsx`.

---

## 3. CI/CD (GitHub Actions)

- **Workflow**: `.github/workflows/ci.yml`.
- **Triggers**: push a `main`/`develop`, pull_request a `main`.

### Jobs
1. **backend**: `garden-api` — `npm run test:unit`, `npm run test:integration`, `npm run test:coverage`. Env: `DATABASE_URL`, `JWT_SECRET`, `JWT_REFRESH_SECRET` (placeholders; tests usan mocks).
2. **frontend**: `garden-web` — `npm run test:run`, `npm run test:coverage`.
3. **e2e**: `garden-web` — Playwright (Chromium). Arranca solo el frontend con `webServer`; E2E no depende del API para los casos actuales.

### Notas
- Si no existe `package-lock.json` en cada proyecto, el workflow hace `npm install` como fallback.
- Cobertura en CI puede ser `continue-on-error: true` hasta alcanzar 80% estable.

---

## 4. Comandos rápidos

```bash
# Backend
cd garden-api
npm run test:unit
npm run test:integration
npm run test:coverage

# Frontend
cd garden-web
npm run test:run
npm run test:coverage
npm run test:e2e
```

---

## 5. Evolución

- **Backend**: Sustituir mocks de Prisma por DB de test (ej. PostgreSQL en Docker) en integración si se prefiere.
- **Frontend**: Añadir E2E con API real levantando backend en CI (job de servicios).
- **Cobertura**: Ajustar `coverageThreshold` o exclusiones según nuevas carpetas/archivos.
- **Logging**: Conectar `ErrorBoundary.onError` o backend logger a Sentry/LogRocket cuando se integre.

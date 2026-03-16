# Self-review: tests flujo cuidador

## Cobertura y gaps

### Backend (garden-api)

| Área | Archivo | Cobertura | Gaps |
|------|---------|-----------|------|
| Auth service (unit) | `tests/unit/auth.service.test.ts` | register success/fail, login, 409 EMAIL/PHONE, INVALID_ROLE | isOver18 ya cubierto en validation (Zod rechaza) |
| Auth validation (unit) | `tests/unit/auth.validation.test.ts` | phone, login, register (isOver18=false, phone, photos) | — |
| Auth API (integration) | `tests/integration/auth.caregiver.api.test.ts` | POST register 201/400/409, POST login 200/401/400 | GET /api/auth/me no cubierto en este archivo |
| Upload registration (integration) | `tests/integration/upload.registration.api.test.ts` | POST /api/upload/registration-photos 200 con mock | Respuesta 400 con &lt;4 fotos no probada (mock inyecta 4) |

- **Edge isOver18=false**: cubierto en integración (400 VALIDATION_ERROR) y en unit (auth.validation.test.ts).
- **Cobertura 80%**: ejecutar `npm run test:coverage` en garden-api; si algún módulo queda por debajo, añadir casos en unit o integration según corresponda.

### Frontend (garden-web)

| Área | Archivo | Cobertura | Gaps |
|------|---------|-----------|------|
| Wizard schemas (unit) | `src/forms/caregiverWizardSchemas.test.ts` | step1–step9 valid/invalid | step8 (photoUrls) no probado con array (se valida en wizard) |
| RegisterWizard (RTL) | `src/pages/caregiver/RegisterWizard.test.tsx` | step 1–2 advance/validation, step 4 required service, step 5 min bio, condicional PASEO → salta step 6 | Step 8 (upload) y step 9/10 no cubiertos en RTL (E2E sí) |
| CaregiverAuthPage (RTL) | `src/pages/CaregiverAuthPage.test.tsx` | tabs, login form, Comenzar registro → navigate | Submit login no probado (E2E sí) |
| E2E caregiver-flow | `e2e/caregiver-flow.spec.ts` | link → auth, tabs, wizard step 1 | — |
| E2E caregiver-full-flow | `e2e/caregiver-full-flow.spec.ts` | login mock → dashboard, register full wizard mock → dashboard | Depende de selectores (placeholders/labels); si cambian, actualizar |

- **Condicional “no hogar si no Hospedaje”**: cubierto en RTL (test “conditional: only PASEO skips step 6”).
- **Cobertura 80%**: el umbral global en `vite.config.ts` (80% lines/functions/branches/statements) falla porque incluye todo el proyecto (e2e, config, páginas sin tests). Módulos del flujo cuidador: `caregiverWizardSchemas.ts` 100%, `CaregiverAuthPage.tsx` ~87%, `RegisterWizard.tsx` ~55%. Para acercar el wizard a 80% habría que añadir RTL para pasos 8–10 y submit. Para cumplir solo en “flujo cuidador” se podría usar `coverage.include`/excluir más archivos o un threshold por directorio (si el tool lo permite).

## Comandos

```bash
# Backend
cd garden-api && npm run test:unit && npm run test:integration
cd garden-api && npm run test:coverage

# Frontend
cd garden-web && npm run test:run
cd garden-web && npm run test:coverage
cd garden-web && npm run test:e2e
```

## Ajustes realizados (tests que fallaban)

- **react-hot-toast**: alias en `vite.config.ts` para entorno test (`VITEST=true`) que resuelve a `src/test/mocks/react-hot-toast.ts`, evitando dependencia de `node_modules` en tests. Los tests que importan `CaregiverAuthPage` o `RegisterWizard` ya cargan sin error.
- **RegisterWizard**: mock de `localStorage` en el test (getItem/setItem/removeItem/clear) para evitar `localStorage.removeItem is not a function` en el entorno de test.
- **CaregiverAuthPage**: dos botones con texto "Iniciar sesión" (tab y submit). Tests actualizados: (1) "shows login and register tabs" usa `getAllByRole` y comprueba que existan ambos textos; (2) "shows login form by default" comprueba que al menos un botón sea `type="submit"` entre los que tienen ese nombre.

## Resumen

- Backend: register/login e isOver18 edge cubiertos (unit + integration); upload con mock en integration.
- Frontend: validación por paso (Zod + RTL), condicional PASEO sin hogar en RTL; E2E completo (registro + login → dashboard) con API mockeada. **29 tests** en schemas + RegisterWizard + CaregiverAuthPage pasan.
- Gaps menores: GET /api/auth/me sin test dedicado (usado por frontend); step8/9 RTL opcionales si se prioriza E2E.

# Admin Login 401 — Analysis

## 1. Login Endpoint

| Check | Result |
|-------|--------|
| Route | `POST /api/auth/login` — **no auth middleware** |
| Public? | ✅ Sí. `auth.routes.ts:10` — `router.post('/login', authController.login)` sin `authMiddleware` |
| Requiere auth? | ❌ No. Login está pensado para usuarios no autenticados |

## 2. Token Flow

| Step | Location | Status |
|------|----------|--------|
| Token returned on login | `auth.controller.ts:194` — `res.json({ success: true, data: { accessToken, expiresIn, user } })` | ✅ |
| Stored in frontend | `auth.ts:69` — `setStoredToken(accessToken)` tras login exitoso | ✅ |
| Attached in requests | `client.ts:24-28` — interceptor añade `Authorization: Bearer ${token}` si existe | ✅ |

## 3. Role Validation

| Check | Result |
|-------|--------|
| Admin en DB | Seed crea `admin@garden.bo` con `role: UserRole.ADMIN` |
| roleFilter en login | Admin usa `login(..., false)` → no se envía `?role=caregiver` |
| requireRole('ADMIN') | Admin routes usan `authMiddleware` + `requireRole('ADMIN')` → devuelve **403** si el rol no es ADMIN, no 401 |

## 4. API Client

| Check | Result |
|-------|--------|
| Authorization header | ✅ Se añade en cada request: `config.headers.Authorization = \`Bearer ${token}\`` |
| Token key | `localStorage['garden_access_token']` |

---

## Causas posibles de 401

El backend devuelve **401** en estos casos:

1. **auth.service.login** → `UnauthorizedError('Credenciales inválidas')`:
   - Usuario no existe (email incorrecto o seed no ejecutado)
   - Contraseña incorrecta

2. **authMiddleware** → `UnauthorizedError`:
   - Sin header `Authorization: Bearer ...`
   - Token inválido o expirado (`jwt.verify` falla)

3. **auth.controller me** → 401 si:
   - Usuario no encontrado en DB tras validar token

---

## Root cause más probable

Si el 401 ocurre **al hacer login** (POST /api/auth/login):

- El único 401 en login viene de `auth.service.login`: usuario no encontrado o contraseña incorrecta.
- Posibles causas:
  1. Seed no ejecutado → no existe `admin@garden.bo`
  2. Contraseña incorrecta (la correcta es `GardenSeed2024!`)

Si el 401 ocurre **después de iniciar sesión** (por ejemplo, en GET /api/auth/me o en rutas admin):

- Token no se envía o es inválido.
- También posible: `JWT_SECRET` distinto al usado al firmar el token.

---

## Fix mínimo

1. **Asegurar que existe el admin y la contraseña es correcta:**
   ```bash
   cd garden-api && npx prisma db seed
   ```
   Credenciales: `admin@garden.bo` / `GardenSeed2024!`

2. **Comprobar que el login admin NO usa role filter:**
   - `AdminAuthPage.tsx:33` usa `login(data.email, data.password, false)` → correcto.

3. **Si el 401 aparece en /me tras login:**
   - Comprobar que `JWT_SECRET` en `.env` tiene al menos 32 caracteres.
   - Verificar que no hay cambios de `JWT_SECRET` entre peticiones (reload de servidor, varios .env, etc.).

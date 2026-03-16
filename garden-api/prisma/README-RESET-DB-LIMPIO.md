# Reset completo de DB y migraciones (versión agresiva mínima)

Cuando la tabla `caregiver_profiles` (u otras) no existe, las migraciones están corruptas o la DB queda inconsistente, usa este flujo para **empezar de cero** sin historial de migraciones.

## Requisitos

- PostgreSQL en marcha (`docker compose up -d` o local).
- `garden-api/.env` con `DATABASE_URL` correcta.

---

## Pasos exactos

### 1. Borrar historial de migraciones

```bash
cd garden-api
rm -rf prisma/migrations
```

No hace falta borrar `node_modules/@prisma/client`; `prisma generate` lo regenera.

### 2. Resetear la DB y crear todas las tablas desde el schema

```bash
cd garden-api
npx prisma db push --force-reset --accept-data-loss
```

- **Qué hace:** Borra el schema público de la DB, recrea **todas** las tablas a partir de `schema.prisma` (users, caregiver_profiles, client_profiles, pets, bookings, etc.).
- **Preguntas:** No pide confirmación; `--accept-data-loss` acepta la pérdida de datos.
- **Resultado:** DB vacía y en sync con el schema. Prisma también ejecuta `generate` y deja el cliente actualizado.

### 3. Configurar el seed en package.json

En `garden-api/package.json` debe existir (antes de `"engines"`):

```json
  "prisma": {
    "seed": "tsx prisma/seed.ts"
  },
```

Si no está, añádelo. Así `npx prisma db seed` usará el script correcto.

### 4. Ejecutar el seed

```bash
cd garden-api
npx prisma db seed
```

O directamente:

```bash
npx tsx prisma/seed.ts
```

- **Qué hace:** Crea admin (`admin@garden.bo`), cuidador DRAFT y cuidador PENDING_REVIEW. Contraseña: `GardenSeed2024!`
- Si falla con "tabla users no existe", la DB no se creó bien: repite el paso 2 y asegúrate de que no haya errores.

### 5. Reiniciar el backend

```bash
cd garden-api
npm run dev
```

Debe mostrar algo como:

- `Database connected`
- `GARDEN API listening on port 3000`

Si ves errores Prisma (P2021, P2022), la DB no está en sync: repite desde el paso 2.

### 6. Comprobar que todo responde bien

- **GET /api/caregivers** (debe devolver 200, array de cuidadores o vacío):
  ```bash
  curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3000/api/caregivers?page=1&limit=10"
  ```
  Esperado: `200`

- **GET /api/auth/me** sin token (debe devolver 401):
  ```bash
  curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3000/api/auth/me"
  ```
  Esperado: `401`

- **Frontend:** Abre `http://localhost:5173` y comprueba que no haya 500 en la consola al cargar el listado de cuidadores.

---

## Comprobar que las tablas existen

**Opción A – Prisma Studio**

```bash
cd garden-api
npx prisma studio
```

Abre el navegador en la URL que indique (p. ej. http://localhost:5555). Revisa que existan tablas como `users`, `caregiver_profiles`, `client_profiles`, `pets`, etc.

**Opción B – Consulta SQL**

```bash
psql "$DATABASE_URL" -c "\dt public.*"
```

O desde `psql` conectado a la DB:

```sql
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;
```

Debe aparecer `caregiver_profiles`, `users`, etc.

---

## Si el seed falla (ej. "tabla users no existe")

1. Comprueba que el paso 2 terminó sin errores y que `prisma db push --force-reset` mostró "Your database is now in sync with your Prisma schema".
2. Comprueba que usas la misma DB que el backend: mismo `DATABASE_URL` en `garden-api/.env`.
3. Si sigue fallando, comenta temporalmente en `prisma/seed.ts` las líneas que usan `prisma.user.upsert()` y `prisma.caregiverProfile.upsert()`, deja solo `console.log('Seed omitido');` y ejecuta `npx tsx prisma/seed.ts`. Si así funciona, el problema es el orden o las tablas; descomenta por bloques y vuelve a ejecutar hasta localizar la línea que falla.

---

## Resumen en una sola secuencia

```bash
cd garden-api
rm -rf prisma/migrations
npx prisma db push --force-reset --accept-data-loss
# Verificar que package.json tiene "prisma": { "seed": "tsx prisma/seed.ts" }
npx tsx prisma/seed.ts
npm run dev
# En otra terminal:
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3000/api/caregivers?page=1&limit=10"
# Debe imprimir: 200
```

---

## Después del reset

- **No hay carpeta `prisma/migrations`:** el estado de la DB lo marca solo `db push`. Para cambios futuros de schema puedes:
  - Seguir usando `npx prisma db push` (sin historial de migraciones), o
  - Crear de nuevo un historial con `npx prisma migrate dev --name init` (genera la primera migración a partir del schema actual y la aplica).
- Las columnas de imágenes (`profilePhoto`, `photos`, `petPhoto`, `ciAnversoUrl`, `ciReversoUrl`) están en el schema y quedan creadas con `db push`; el backend puede guardar y devolver fotos una vez configurado Cloudinary o placeholders.

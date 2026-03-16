# Ejecutar GARDEN MVP localmente — Guía completa

## 1. Checklist de verificación

Comprueba cada ítem antes de arrancar.

### Base de datos

- [ ] **¿PostgreSQL disponible?**
  - **Opción A (recomendada):** Docker. Debe existir `docker-compose.yml` en la raíz del repo.
  - **Opción B:** PostgreSQL instalado localmente (puerto 5432, usuario/contraseña/base que coincidan con `DATABASE_URL`).

### Variables de entorno (garden-api)

- [ ] **¿Existe `garden-api/.env`?**  
  Si no existe, créalo a partir del ejemplo:
  - **Mac/Linux:** `cp garden-api/.env.example garden-api/.env`
  - **Windows (CMD):** `copy garden-api\.env.example garden-api\.env`
  - **Windows (PowerShell):** `Copy-Item garden-api\.env.example garden-api\.env`

- [ ] **Variables mínimas en `garden-api/.env`:**
  - `DATABASE_URL` — Conexión a PostgreSQL (ej: `postgresql://user:password@localhost:5432/garden_db`).
  - `JWT_SECRET` — Al menos 32 caracteres (en `.env.example` ya hay uno de ejemplo).
  - `PORT` — Opcional; por defecto 3000.
  - `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` — Opcionales para desarrollo; subida de fotos puede fallar si no están, pero el resto de la app corre.

### Migraciones Prisma

- [ ] **¿Se han aplicado las migraciones?**
  - **Primera vez (no hay carpeta `prisma/migrations`):** crea y aplica la migración:
    ```bash
    cd garden-api
    npx prisma migrate dev --name init
    ```
  - **Ya tienes migraciones:** solo aplica:
    ```bash
    cd garden-api
    npx prisma migrate deploy
    ```
  - Desde la raíz, `npm run setup:db` hace `migrate deploy` + seed; si es la primera vez y no hay migraciones, ejecuta antes a mano `migrate dev --name init` dentro de `garden-api`.

### Seed

- [ ] **¿Seed ejecutado?** (admin + 2 cuidadores de prueba)
  ```bash
  cd garden-api
  npx prisma db seed
  ```

### Dependencias

- [ ] **garden-api:** `cd garden-api && npm install`
- [ ] **garden-web:** `cd garden-web && npm install`

---

## 2. Comandos exactos (en orden)

Ejecuta en orden. Asume que estás en la **raíz del monorepo** (`garden-mvp`).

### Paso 1: Levantar la base de datos

**Con Docker (recomendado):**

```bash
docker compose up -d
```

Comprueba que el contenedor está en marcha: `docker compose ps` (debe verse el servicio `db`).

**Sin Docker (PostgreSQL local):**  
Asegúrate de que PostgreSQL esté corriendo en el puerto 5432 y que la base `garden_db` exista (o que tu `DATABASE_URL` apunte a una base creada).

---

### Paso 2: Variables de entorno y migraciones + seed

**Mac/Linux:**

```bash
# Crear .env si no existe
cp garden-api/.env.example garden-api/.env
# Editar garden-api/.env si necesitas cambiar DATABASE_URL o JWT_SECRET

cd garden-api
npm install
npx prisma generate
npx prisma migrate dev --name init
npx prisma db seed
cd ..
```

**Windows (PowerShell):**

```powershell
Copy-Item garden-api\.env.example garden-api\.env
cd garden-api
npm install
npx prisma generate
npx prisma migrate dev --name init
npx prisma db seed
cd ..
```

- Si `prisma migrate dev` dice que no hay migraciones pendientes pero la carpeta `prisma/migrations` está vacía, el comando anterior crea la primera migración.
- Si ya tienes migraciones aplicadas, en lugar de `migrate dev` puedes usar `npx prisma migrate deploy` y luego `npx prisma db seed`.

---

### Paso 3: Levantar el backend

**Terminal 1:**

```bash
cd garden-api
npm run dev
```

Salida esperada:

- `Database connected`
- `GARDEN API listening on port 3000`

Si falla por conexión a la base, revisa que Docker/PostgreSQL esté arriba y que `DATABASE_URL` en `.env` sea correcta.

---

### Paso 4: Levantar el frontend

**Terminal 2** (nueva ventana):

```bash
cd garden-web
npm install
npm run dev
```

Salida esperada:

- `Vite dev server running at http://localhost:5173` (o el puerto que indique).

---

### Paso 5 (opcional): Verificación automática del flujo

Con la **API corriendo** en el puerto 3000:

**Mac/Linux:**

```bash
BASE_URL=http://localhost:3000 node scripts/verification-flow.js
```

**Windows (PowerShell):**

```powershell
$env:BASE_URL="http://localhost:3000"; node scripts/verification-flow.js
```

Salida esperada: mensajes tipo `OK: Login cuidador`, `OK: GET my-profile`, `OK: Login admin`, etc., y al final `Tests passed: X/Y` y “Flujo verificado sin errores” si todo va bien.

---

## 3. Probar el flujo en el navegador

### URLs

| Dónde              | URL                          |
|--------------------|------------------------------|
| Frontend (Vite)    | http://localhost:5173         |
| API (Express)      | http://localhost:3000        |
| Health API         | http://localhost:3000/health |

### Paso a paso en la UI

1. **Abrir la app**  
   Ir a **http://localhost:5173**. Deberías ver la página principal (listado de cuidadores o mensaje vacío).

2. **Botón “Soy cuidador”**  
   - Clic en **“Soy cuidador →”** (o “Soy cuidador” en móvil).  
   - Debe llevarte a **/caregiver/auth** (página de login/registro de cuidadores).  
   - El enlace **“Cuidadores”** sigue llevando al listado (inicio).

3. **Registrarse como nuevo cuidador**  
   - En /caregiver/auth, pestaña **“Registrarme”**.  
   - Clic en **“Comenzar registro”** → irás al wizard (**/caregiver/register**).  
   - Completar varios pasos (nombre, teléfono, email, contraseña, zona, servicios, bio, etc.).  
   - El progreso se guarda en **localStorage** (autosave al cambiar de paso).  
   - En el paso de fotos subir al menos 4 (si no tienes Cloudinary configurado, el registro puede fallar en ese paso; el resto del flujo se puede probar con seed).  
   - Al final, aceptar términos y hacer clic en **“Enviar solicitud”**.  
   - Deberías ver un mensaje de éxito y redirección al dashboard del cuidador.

4. **Iniciar sesión como admin**  
   - Cerrar sesión si estabas logueado.  
   - Ir de nuevo a **http://localhost:5173/caregiver/auth**.  
   - Pestaña **“Iniciar sesión”**.  
   - Email: **admin@garden.bo**  
   - Contraseña: **GardenSeed2024!**  
   - Iniciar sesión.

5. **Panel admin**  
   - Con sesión de admin, en la barra debe aparecer **“Panel admin”**.  
   - Clic en **“Panel admin”** → **/admin/caregivers/pending**.  
   - Deberías ver la lista de solicitudes en estado PENDING_REVIEW (y NEEDS_REVISION si las hay).  
   - Para cada una puedes: **Aprobar**, **Rechazar**, **Pedir revisión**.

6. **Aprobar una solicitud**  
   - Clic en **“Aprobar”** en una fila.  
   - El estado pasa a APPROVED y la fila puede desaparecer de la lista (porque ya no está “pending”).

7. **Comprobar listado público**  
   - Ir al inicio (**“Cuidadores”** o **http://localhost:5173/**).  
   - El cuidador que aprobaste debería aparecer en el listado (solo se muestran perfiles verificados/aprobados).

---

## 4. Comandos de debug rápidos

### Logs del backend

- Los verás en la **Terminal 1** donde corre `npm run dev` en `garden-api`.  
- Errores de conexión a DB o de JWT suelen aparecer ahí.

### Estado de la base de datos

**Prisma Studio (recomendado):**

```bash
cd garden-api
npx prisma studio
```

Se abre en el navegador (p. ej. http://localhost:5555). Ahí puedes ver tablas `users`, `caregiver_profiles`, etc.

**Consulta rápida por consola (perfiles pendientes):**

```bash
cd garden-api
npx prisma db execute --stdin <<< "SELECT id, status, \"userId\" FROM caregiver_profiles WHERE status IN ('PENDING_REVIEW','NEEDS_REVISION');"
```

**Windows (PowerShell)** — usar Prisma Studio o un cliente SQL con la misma consulta.

### Comprobar que un perfil está PENDING_REVIEW

- En **Prisma Studio**: tabla `caregiver_profiles`, columna `status` = `PENDING_REVIEW`.  
- O en el **Panel admin** de la app: si el perfil aparece en “Solicitudes de cuidadores”, está en PENDING_REVIEW o NEEDS_REVISION.

### Puerto en uso

- **Backend (3000):**  
  - Mac/Linux: `lsof -i :3000`  
  - Windows: `netstat -ano | findstr :3000`  
- **Frontend (5173):**  
  - Mac/Linux: `lsof -i :5173`  
  - Windows: `netstat -ano | findstr :5173`

Si cambias el puerto del backend, en `garden-web` el proxy de Vite apunta a `http://localhost:3000`; si tu API corre en otro puerto, ajusta `vite.config.ts` (proxy `/api`).

### .env no existe o API no arranca

- Asegúrate de tener `garden-api/.env` (copiado de `.env.example`).  
- `JWT_SECRET` debe tener al menos 32 caracteres.  
- `DATABASE_URL` debe ser válida y la base accesible (Docker o PostgreSQL local).

---

## 5. Resumen final

### URLs a abrir

- **App:** http://localhost:5173  
- **API health:** http://localhost:3000/health  
- **Panel admin (logueado como admin):** http://localhost:5173/admin/caregivers/pending  

### Credenciales de prueba (seed)

| Rol       | Email                     | Contraseña      |
|----------|----------------------------|-----------------|
| Admin    | admin@garden.bo            | GardenSeed2024! |
| Cuidador (draft)   | cuidador.draft@garden.bo   | GardenSeed2024! |
| Cuidador (pending) | cuidador.pending@garden.bo | GardenSeed2024! |

### Qué deberías ver en pantalla

1. **Inicio:** Listado de cuidadores (vacío o con los aprobados). Navbar: “Cuidadores”, “Soy cuidador →”.
2. **Clic “Soy cuidador”:** Página de login/registro cuidador (/caregiver/auth).
3. **Registro completo:** Wizard 10 pasos, luego mensaje de éxito y dashboard cuidador.
4. **Login admin:** Tras iniciar sesión con admin@garden.bo, en navbar: “Panel admin”.
5. **Panel admin:** Lista de solicitudes con botones Aprobar / Rechazar / Pedir revisión.
6. **Tras aprobar:** Esa solicitud deja de aparecer en pending; el cuidador aparece en el listado público.

### Cómo confirmar que los datos están en la base

- **Prisma Studio:** `cd garden-api && npx prisma studio` → revisar `users` (admin y cuidadores) y `caregiver_profiles` (status: DRAFT, PENDING_REVIEW, APPROVED).  
- **Panel admin:** Si ves solicitudes, esos perfiles existen y tienen status PENDING_REVIEW o NEEDS_REVISION.  
- **Listado público:** Solo se muestran perfiles con `verified: true` / status APPROVED; si un cuidador aparece ahí, está guardado y aprobado en la DB.

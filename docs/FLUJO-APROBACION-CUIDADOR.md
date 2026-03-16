# Flujo completo de aprobación de cuidador

Este documento describe el flujo integrado: cuidador envía solicitud → admin revisa → aprueba o rechaza → cuidador ve resultado en su dashboard.

---

## Credenciales de prueba

Tras ejecutar `npx prisma db seed` en `garden-api`:

| Rol | Email | Contraseña |
|-----|--------|------------|
| **Admin** | `admin@garden.bo` | `GardenSeed2024!` |
| **Cuidador (pendiente de revisión)** | `cuidador.pending@garden.bo` | `GardenSeed2024!` |
| **Cuidador (borrador)** | `cuidador.draft@garden.bo` | `GardenSeed2024!` |

- **Login admin:** http://localhost:5173/admin/auth  
- **Login cuidador:** http://localhost:5173/caregiver/auth  

---

## Flujo deseado (resumen)

1. **Cuidador** completa el wizard → Enviar → `status = PENDING_REVIEW`
2. **Admin** va a `/admin/caregivers/pending` → clic en **Revisar** → abre página detallada con todos los datos y fotos
3. **Admin aprueba** → `status = APPROVED` → cuidador aparece en listado público y en su dashboard solo ve mensaje de felicitación (sin “pendiente”)
4. **Admin rechaza** → `status = REJECTED` → cuidador ve mensaje de rechazo + botón **Intentar nuevamente** que abre wizard pre-llenado

---

## Instrucciones paso a paso para probar

### Requisitos previos

- Base de datos levantada (`docker compose up -d` desde la raíz).
- API corriendo: `cd garden-api && npm run dev`
- Frontend corriendo: `cd garden-web && npm run dev`
- Seed ejecutado: `cd garden-api && npx prisma db seed`

---

### Prueba 1: Admin revisa y aprueba (cuidador ya en PENDING_REVIEW)

1. **Admin**
   - Ir a http://localhost:5173/admin/auth  
   - Iniciar sesión: `admin@garden.bo` / `GardenSeed2024!`  
   - Serás redirigido a **Solicitudes de cuidadores** (`/admin/caregivers/pending`).

2. **Listado pendientes**
   - Deberías ver al menos a **Carlos López** (`cuidador.pending@garden.bo`) con estado `PENDING_REVIEW`.  
   - Clic en el botón verde **Revisar**.

3. **Página de revisión**
   - Se abre `/admin/caregivers/:id/review` con todos los datos: personales, servicios, experiencia, hogar, tarifas, fotos, documentos.  
   - Revisar la información.  
   - Clic en el botón verde **Aprobar**.

4. **Resultado**
   - Toast: “Solicitud aprobada”.  
   - Redirección a `/admin/caregivers/pending`.  
   - Ese cuidador ya no aparece en la lista (solo se listan PENDING_REVIEW y NEEDS_REVISION).  
   - En el **listado público** http://localhost:5173 el cuidador debe aparecer.

5. **Vista cuidador (dashboard)**
   - Cerrar sesión de admin (o usar otra ventana/incógnito).  
   - Ir a http://localhost:5173/caregiver/auth e iniciar sesión con `cuidador.pending@garden.bo` / `GardenSeed2024!`.  
   - Ir al dashboard (`/caregiver/dashboard`).  
   - Debe mostrarse **solo**: “¡Felicidades! Tu perfil ha sido verificado y ya está visible en GARDEN.”  
   - **No** debe aparecer mensaje de “pendiente de verificación”.

---

### Prueba 2: Admin rechaza → cuidador intenta de nuevo

1. **Tener un cuidador en PENDING_REVIEW**  
   - Si ya aprobaste al de prueba, puedes crear uno nuevo completando el wizard con otro email o volver a ejecutar el seed (el cuidador `cuidador.pending@garden.bo` vuelve a `PENDING_REVIEW`).

2. **Admin**
   - Login en http://localhost:5173/admin/auth  
   - Ir a **Solicitudes de cuidadores** → **Revisar** sobre un solicitante.  
   - Clic en **Rechazar**.  
   - En el cuadro de diálogo escribir un motivo (ej.: “Faltan fotos del espacio”).  
   - Confirmar.

3. **Resultado admin**
   - Toast “Rechazada” y vuelta al listado.  
   - Ese cuidador deja de aparecer en pendientes (status = REJECTED).

4. **Vista cuidador (dashboard)**
   - Iniciar sesión como ese cuidador en http://localhost:5173/caregiver/auth  
   - En `/caregiver/dashboard` debe verse:  
     **“Tu solicitud fue rechazada. Motivo: [el motivo que escribiste]”**  
     y el botón **“Intentar nuevamente”**.

5. **Intentar nuevamente**
   - Clic en **Intentar nuevamente**.  
   - Debe abrirse el wizard de registro (`/caregiver/register`) **pre-llenado** con los datos anteriores (nombre, zona, servicios, bio, fotos, etc.).  
   - El cuidador puede editar y al final **Subir y seguir** / enviar.  
   - Se llama a PATCH perfil + submit → `status` vuelve a `PENDING_REVIEW`.  
   - Toast de éxito y redirección al dashboard (mensaje de “en revisión”).

---

### Prueba 3: Admin pide revisión (NEEDS_REVISION)

1. En la página de revisión detallada, clic en **Solicitar revisión** (amarillo).  
2. Opcional: escribir un motivo en el modal y confirmar.  
3. El cuidador deja de aparecer en “pendientes” con PENDING_REVIEW (pasa a NEEDS_REVISION).  
4. El cuidador en su dashboard ve el mensaje de “Se solicitó revisión…” y el botón **“Editar y reenviar”**, que también lleva al wizard pre-llenado.

---

## Logging en backend (cambios de estado)

En la terminal del backend (`garden-api`) deberías ver logs como:

- **Cuidador envía solicitud:**  
  `CaregiverProfile: solicitud enviada → PENDING_REVIEW` (profileId, userId).
- **Admin aprueba:**  
  `Admin: cuidador aprobado` (profileId, adminId, caregiverEmail).
- **Admin rechaza:**  
  `Admin: solicitud rechazada` (profileId, adminId, caregiverEmail, reasonLength).
- **Admin pide revisión:**  
  `Admin: pedido de revisión` (profileId, adminId, caregiverEmail, hasReason).

---

## Rutas clave

| Ruta | Quién | Descripción |
|------|--------|-------------|
| `/caregiver/auth` | Público | Login cuidador |
| `/caregiver/register` | Cuidador / nuevo | Wizard de registro (pre-llenado si REJECTED/NEEDS_REVISION/DRAFT) |
| `/caregiver/dashboard` | Cuidador | Dashboard según status (felicitación / rechazo / pendiente / revisión) |
| `/admin/auth` | Público | Login admin |
| `/admin/caregivers/pending` | Admin | Lista PENDING_REVIEW y NEEDS_REVISION |
| `/admin/caregivers/:id/review` | Admin | Revisión detallada + Aprobar / Rechazar / Solicitar revisión |
| `/` (listado) | Público | Solo cuidadores con status APPROVED |

---

## Archivos relevantes del flujo

- **Backend:** `garden-api/src/modules/admin/` (service, controller, routes), `garden-api/src/modules/caregiver-profile/caregiver-profile.service.ts` (submit + logging), `garden-api/prisma/seed.ts`.
- **Frontend:** `garden-web/src/pages/caregiver/CaregiverDashboard.tsx`, `garden-web/src/pages/caregiver/RegisterWizard.tsx`, `garden-web/src/pages/admin/AdminPendingPage.tsx`, `garden-web/src/pages/admin/AdminCaregiverReviewPage.tsx`, `garden-web/src/App.tsx` (rutas).

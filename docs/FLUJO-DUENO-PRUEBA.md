# Flujo completo Dueño (CLIENT) — Prueba paso a paso

Este documento describe el flujo integrado: **sin login → intentar reservar → registrarse como Dueño → completar perfil de mascota → reservar**, y cómo verificarlo.

## Archivos modificados (integración del flujo)

### Backend
- **`garden-api/src/modules/auth/auth.controller.ts`**  
  - `GET /api/auth/me`: para usuarios con `role === 'CLIENT'` se incluye `clientProfile: { isComplete: boolean }` para redirigir a completar perfil de mascota cuando corresponda.

### Frontend
- **`garden-web/src/api/auth.ts`**  
  - Tipo `AuthUser` con `clientProfile?: { isComplete: boolean } | null`.
- **`garden-web/src/contexts/AuthContext.tsx`**  
  - `login()` llama a `loadUser()` tras login para tener usuario (y `clientProfile`) desde `/api/auth/me`.  
  - `refreshUser()` expuesto para actualizar usuario tras completar perfil.  
  - `loadUser()` devuelve el usuario cargado.
- **`garden-web/src/App.tsx`**  
  - `ClientOnlyRoute`: solo CLIENT logueado; resto redirige a `/`.  
  - `ClientPetProfileRedirect`: si CLIENT y `!clientProfile?.isComplete`, redirige a `/profile/complete-pet` con `state.returnTo`.  
  - Rutas `/profile/complete-pet` y `/profile/complete` protegidas con `ClientOnlyRoute` y misma página.
- **`garden-web/src/components/Navbar.tsx`**  
  - Botón **"Cerrar sesión"** visible en escritorio y móvil para cualquier usuario logueado (CLIENT, CAREGIVER, ADMIN).
- **`garden-web/src/components/LoginRequiredModal.tsx`**  
  - Tras registro exitoso: `refreshUser()` y luego `navigate('/profile/complete-pet', { state: { returnTo } })` para que AuthContext tenga el usuario y el flujo lleve de vuelta a reserva/detalle.
- **`garden-web/src/pages/CompletePetProfilePage.tsx`**  
  - Tras guardar con `isComplete`: `refreshUser()` y `navigate(returnTo)` (página anterior o `/`).
- **`garden-web/src/pages/CaregiverDetailPage.tsx`**  
  - "Reservar" sin login abre modal con `returnTo={/reservar/${id}}`; perfil incompleto redirige a `/profile/complete-pet` con `returnTo` al detalle o reserva.
- **`garden-web/src/pages/BookingPage.tsx`**  
  - Si CLIENT con perfil incompleto, redirige a `/profile/complete-pet` con `returnTo: /reservar/:id`.
- **`garden-web/src/pages/ClientProfileCompletePage.tsx`**  
  - Sin cambios de flujo; sigue siendo página de bienvenida/completar perfil cliente si se usa.
- Referencias a `/profile/complete` actualizadas a `/profile/complete-pet` donde aplica (modal registro, BookingPage, CaregiverDetailPage).

---

## Pasos exactos para probar el flujo desde cero

**Requisitos:** API corriendo (`cd garden-api && npm run dev`), frontend corriendo (`cd garden-web && npm run dev`), base de datos con migraciones y opcionalmente seed. Abrir **http://localhost:5173/**.

### Paso 1 — Sin login, intentar reservar un cuidador

1. **Abrir** http://localhost:5173/
2. **Ver** el listado de cuidadores (público, sin login).
3. **Clic** en un cuidador para ir al detalle (`/caregivers/:id`).
4. **Clic** en el botón **"Reservar ahora"**.

**Qué debería ver el usuario:**  
- Se abre un **modal** con título "Iniciar sesión" o "Registrarme como Dueño de mascota".  
- Opciones: **Iniciar sesión** (email/contraseña) y enlace **"Registrarme como Dueño"** (o pestaña/switch para registrarse).  
- El listado de cuidadores sigue siendo visible y público en todo momento.

---

### Paso 2 — Registrarse como Dueño

1. En el modal, **cambiar** a **"Registrarme como Dueño de mascota"**.
2. **Completar** el formulario: nombre completo, email, contraseña (mín. 8 caracteres, mayúscula, minúscula, número), confirmar contraseña, teléfono (+591 y 8–9 dígitos), dirección.
3. **Enviar** el formulario (Registrarme / Crear cuenta).

**Qué debería ver el usuario:**  
- Toast: "Registro exitoso. Bienvenido a GARDEN."  
- El modal se cierra.  
- **Redirección automática** a la página **"Completa el perfil de tu mascota"** (`/profile/complete-pet`) con el mensaje tipo: "Completa el perfil de tu mascota para poder reservar servicios".  
- En la **navbar** debe aparecer **"Cerrar sesión"** (usuario ya logueado como CLIENT).

---

### Paso 3 — Completar datos de la mascota

1. En `/profile/complete-pet`, **rellenar**:  
   - Nombre de la mascota (obligatorio)  
   - Raza (opcional)  
   - Edad en años (opcional)  
   - Tamaño (obligatorio): Pequeño / Mediano / Grande / Gigante  
   - **Foto de la mascota (obligatoria)**: arrastrar o seleccionar imagen (JPG/PNG, máx. 5 MB)  
   - Necesidades especiales y notas (opcionales)
2. **Guardar** ("Guardar y continuar").

**Qué debería ver el usuario:**  
- Toast: "Perfil completado exitosamente. Ya puedes reservar servicios."  
- **Redirección** a la página desde la que venía:  
  - Si llegó desde "Reservar" en el detalle de un cuidador → vuelve al **detalle de ese cuidador** o a **`/reservar/:id`** (página de reserva).  
  - Si llegó desde el registro sin `returnTo` → va a **`/`** (listado).

---

### Paso 4 — Reservar

1. Tras la redirección, estar en **detalle del cuidador** o en **`/reservar/:id`**.
2. **Clic** de nuevo en **"Reservar ahora"** (en detalle) o completar el formulario de reserva en `/reservar/:id` (tipo de servicio, fechas, datos de la mascota, etc.).
3. **Enviar** la reserva.

**Qué debería ver el usuario:**  
- No debe aparecer el modal de login ni redirección a complete-pet (perfil ya completo).  
- Flujo de reserva normal: confirmación, éxito, redirección a página de éxito o "Mis Reservas" según la implementación.

---

### Paso 5 — Botón "Cerrar sesión" y listado público

1. **Comprobar** que en la **navbar** (escritorio y móvil) hay **"Cerrar sesión"** mientras el usuario esté logueado (CLIENT o CAREGIVER).
2. **Clic** en **"Cerrar sesión"**: debe limpiar sesión y redirigir a `/`.
3. **Comprobar** que el **listado de cuidadores** (`/`) se ve **sin estar logueado** y también **logueado como CLIENT**.

**Qué debería ver el usuario:**  
- "Cerrar sesión" visible para cualquier rol logueado.  
- Tras cerrar sesión: en home y listado público.  
- Listado de cuidadores siempre accesible (público).

---

## Resumen del flujo esperado

| Paso | Acción                         | Resultado                                                                 |
|------|--------------------------------|---------------------------------------------------------------------------|
| 1    | Sin login → clic "Reservar"   | Modal login/registro; opción "Registrarme como Dueño"                    |
| 2    | Registrar como Dueño          | User + ClientProfile vacío; redirección a `/profile/complete-pet`         |
| 3    | Completar mascota y guardar   | `isComplete = true`; redirección a detalle/reserva o `/`                  |
| 4    | Reservar                      | Puede reservar sin volver a pedir perfil                                 |
| 5    | Navbar                        | "Cerrar sesión" visible; listado público con y sin login                 |

---

## Verificación: foto de mascota se guarda y se muestra

Para confirmar que la foto se sube a Cloudinary, se guarda en `ClientProfile.petPhoto` y se muestra en la app:

1. **Reiniciar backend y frontend** (por si hubo cambios).
2. **Login como dueño** (o registrar uno nuevo) y entrar en **`/profile/complete-pet`**.
3. **Subir una foto**: arrastrar o seleccionar una imagen (JPG/PNG, máx. 5 MB).
   - Debe aparecer **"Subiendo foto..."** y luego **toast "Foto subida correctamente"**.
   - La previsualización debe mostrar la imagen (primero blob local, tras subir la URL de Cloudinary).
4. **Completar** nombre, tamaño y el resto de campos y **Guardar**.
   - Toast **"Perfil completado exitosamente..."** y redirección a home o a la página de reserva.
5. **Comprobar en Network (DevTools)**:
   - **POST /api/upload/pet-photo**: respuesta `{ success: true, data: { url: "https://..." } }` con URL de Cloudinary.
   - **PATCH /api/client/profile**: respuesta debe incluir `data.petPhoto` con la misma URL y `data.isComplete: true`.
6. **Volver a `/profile/complete-pet`** (por ejemplo desde "Mis Reservas" o navegando): la foto guardada debe mostrarse al cargar el perfil (el GET my-profile devuelve `petPhoto` y el formulario la usa como preview).
7. **Intentar reservar**: no debe redirigir de nuevo a complete-pet (perfil ya completo).

**Backend (logs):** En consola del API deberías ver líneas como:
- `Subiendo foto de mascota` (userId, file).
- `Foto subida a Cloudinary` (userId, url).
- `PATCH /api/client/profile: body incluye petPhoto` (userId, petPhotoLength).
- `ClientProfile: actualizando petPhoto` y `Perfil actualizado con foto` (userId, profileId, isComplete, petPhoto).

**Causa habitual por la que la foto “no se guardaba”:** El formulario validaba `petPhoto` como URL obligatoria antes de enviar. Al elegir un archivo, el campo seguía vacío hasta después del upload, la validación fallaba y no se llegaba a subir ni a hacer el PATCH. Ahora `petPhoto` es opcional en el formulario y la foto se sube al hacer clic en Guardar; si hay archivo seleccionado se sube primero y luego se envía la URL en el PATCH.

---

## Errores frecuentes a evitar

- **Registro sin `refreshUser()`:** el usuario queda en localStorage pero AuthContext no tiene `user` → en complete-pet podría verse como "no logueado". Solución: llamar `refreshUser()` tras registro antes de `navigate('/profile/complete-pet')`.
- **returnTo perdido:** al redirigir a complete-pet desde reserva/detalle, pasar siempre `state.returnTo` para volver a la página correcta tras guardar.
- **CAREGIVER afectado:** la redirección a complete-pet y `ClientOnlyRoute` aplican solo a `role === 'CLIENT'`; CAREGIVER no debe ser redirigido a complete-pet ni ver rutas rotas.

Si algo no coincide con lo anterior, revisar que la API devuelva `clientProfile.isComplete` en `GET /api/auth/me` para CLIENT y que el frontend use `returnTo` en todas las navegaciones a `/profile/complete-pet` cuando el usuario viene del flujo de reserva.

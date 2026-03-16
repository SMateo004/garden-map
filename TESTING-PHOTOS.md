# Pruebas de fotos en GARDEN

Verificación de que **todas las fotos se guardan y se muestran** en todo el programa: perfil mascota, listado/detalle de cuidadores, revisión admin (CI) y confirmación de reserva.

## Fix aplicado (imágenes en todo el programa)

- **Placeholder:** Se usa `https://placehold.co/400x300/EEEEEE/999999/png?text=Sin+foto&font=montserrat` (estable; evita 404 de via.placeholder.com). Definido en `garden-web/src/constants/photos.ts`; `getImageUrl()` en `utils/images.ts` lo usa cuando no hay URL válida.
- **Backend uploads:** En todos los endpoints de upload se guarda `secure_url` (URL completa Cloudinary), se loguea "Imagen subida y guardada" con `{ url, field, userId }` y se retorna la URL en la respuesta. Pet-photo además actualiza `ClientProfile.petPhoto` para refetch inmediato.
- **Backend GET:** Los endpoints que devuelven perfiles/listas incluyen siempre `petPhoto`, `photos`, `profilePhoto`, `ciAnversoUrl`, `ciReversoUrl` (y `pets[].photoUrl` en my-profile).
- **Profile photo cuidador:** POST `/api/upload/profile-photo` (multipart `profilePhoto`, auth CAREGIVER) sube a Cloudinary y persiste en `caregiver_profiles.profilePhoto`. El listado y detalle usan `profilePhoto` o `photos[0]` con `getImageUrl()`.
- **Frontend:** Todas las `<img>` usan `src={getImageUrl(url)}`, `loading="lazy"` y `alt`; tras guardar (p. ej. en Completar perfil mascota) se hace `invalidateQueries` + `refetch` del perfil/mascotas.

---

## Prueba rápida: subir foto de mascota → ver si aparece inmediatamente

1. Iniciar sesión como **dueño** (cliente).
2. Ir a **Completar perfil mascota** (`/profile/complete-pet`).
3. Rellenar nombre y tamaño de la mascota, **subir una foto** (arrastrar o seleccionar JPG/PNG).
4. Comprobar que la **preview** se muestra al instante en la misma pantalla (refetch/invalidate ya disparados tras el upload).
5. Pulsar **Guardar y continuar**.
6. Ir a **Mi perfil** (`/profile`): la foto de la mascota debe verse en la tarjeta (o placeholder "Sin foto" si falló el guardado).
7. Si no se ve: revisar que el backend devuelva `pets[].photoUrl` y `petPhoto` en GET `/api/client/my-profile` y que en el front se use `getImageUrl(pet.photoUrl)` para evitar `src` vacío y 404.

---

## Requisitos previos

- **Backend** (`garden-api`) en marcha: `cd garden-api && PORT=3000 npm run dev`
- **Frontend** (`garden-web`) en marcha: `cd garden-web && npm run dev`
- Base de datos en sync con el schema: `cd garden-api && npx prisma db push` (o `migrate deploy` si usas migraciones)
- Cloudinary configurado (`.env` en `garden-api` con `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`) o en desarrollo con placeholders

---

## 1. Dueño: perfil de mascota y foto

**Objetivo:** La foto de la mascota se sube, se guarda y se ve en seguida (refetch tras upload) y en todo el flujo del dueño.

### Pasos

1. **Registro como dueño**
   - Ir a la app (ej. `http://localhost:5173`).
   - Registrarse como **Cliente** (dueño) con email y contraseña.
   - Iniciar sesión.

2. **Completar perfil de mascota**
   - Ir a **Mi perfil** (o el enlace que lleve a completar perfil).
   - Si aparece el aviso “Completa el perfil de tu mascota”, pulsar **Completar ahora** (o ir a `/profile/complete-pet`).
   - Rellenar: nombre, raza (opcional), edad (opcional), **tamaño** (obligatorio).
   - **Subir foto:** arrastrar una imagen (JPG/PNG, máx. 5 MB) o elegir archivo.
   - Comprobar que **justo después de subir** se ve la foto en la misma pantalla (preview).
   - Pulsar **Guardar y continuar**.

3. **Comprobar que la foto aparece en todo el flujo dueño**
   - **Mi perfil** (`/profile`): en la sección “Mis mascotas” debe verse la **foto de la mascota** (o placeholder “Sin foto” si no hay URL).
   - **Editar mascota** (`/profile/edit-pet/:id`): debe mostrarse la **misma foto** (o placeholder) junto al campo “URL de la foto”.
   - Si se sube una **nueva foto** en “Completar perfil mascota” y se guarda, al volver a Mi perfil o Editar mascota debe verse la **nueva** foto sin recargar a mano (refetch automático).

**Criterio de éxito:** La foto se ve en la pantalla de completar perfil al instante tras subirla, y en Mi perfil y Editar mascota con la misma URL. Placeholder solo cuando no hay foto.

---

## 2. Cuidador: fotos del espacio y foto de perfil

**Objetivo:** Las fotos del cuidador (espacio y, si aplica, foto personal) se guardan en el registro y se ven en listado y detalle.

### Pasos

1. **Registro como cuidador**
   - Cerrar sesión o usar otra sesión/ventana.
   - Registrarse como **Cuidador** (wizard de registro).
   - Completar pasos: datos personales, zona, servicios, bio, etc.

2. **Subir fotos del espacio (paso “Fotos de tu espacio”)**
   - Subir **entre 4 y 6** imágenes (JPG/PNG, máx. 5 MB cada una).
   - Pulsar **Subir y seguir**.
   - Comprobar que el wizard avanza y que en el resumen o pasos siguientes se indica que las fotos están subidas (ej. “X fotos subidas”).

3. **Subir CI (anverso y reverso)**
   - En el paso de verificación de identidad, subir **CI anverso** y **CI reverso**.
   - Pulsar **Subir y seguir**.
   - Comprobar que se muestran las **dos imágenes** (o placeholder si falla la URL) en la misma pantalla.
   - Completar el resto del wizard y enviar la solicitud.

4. **Admin aprueba al cuidador**
   - Iniciar sesión como **Admin**.
   - Ir a listado de cuidadores pendientes y abrir la solicitud del cuidador recién registrado.
   - Comprobar:
     - **Fotos del espacio:** grid con todas las fotos (o placeholder por imagen si falta URL).
     - **Foto de perfil / selfie:** se muestran con imagen o placeholder.
     - **CI anverso y reverso:** ambas imágenes visibles (o placeholder).

5. **Listado y detalle público de cuidadores**
   - Cerrar sesión o usar ventana incógnito.
   - Ir al **listado de cuidadores** (página principal o `/caregivers`).
   - Comprobar que cada tarjeta de cuidador muestra una **foto** (foto principal o primera del array `photos`; si no hay, placeholder “Sin foto”).
   - Entrar al **detalle** de un cuidador (`/caregivers/:id`).
   - Comprobar que el **carrusel** muestra todas las **fotos del espacio** (o un slide con placeholder si no hay fotos).

**Criterio de éxito:** Fotos del espacio y CI visibles en el wizard y en la revisión admin. Tras aprobación, listado y detalle muestran las fotos (o placeholder) sin excepciones.

---

## 3. Admin: revisión de CI (anverso y reverso)

**Objetivo:** En la revisión de una solicitud de cuidador se ven siempre las imágenes de CI.

### Pasos

1. Iniciar sesión como **Admin**.
2. Ir a **Cuidadores** → **Pendientes** (o la ruta de listado de solicitudes).
3. Abrir una solicitud (ej. **Revisar** o “Ver detalle”).
4. En la sección **“Verificación de identidad (CI)”** comprobar:
   - **CI Anverso:** se muestra la imagen (o placeholder “Sin foto” si no hay URL).
   - **CI Reverso:** igual.
   - Ambas con `loading="lazy"` y enlaces “Abrir en nueva pestaña” si aplica.

**Criterio de éxito:** Siempre se muestra una imagen (foto subida o placeholder); nunca un bloque vacío o roto.

---

## 4. Reserva: foto de la mascota en confirmación

**Objetivo:** En la pantalla de confirmación de reserva se ve la foto de la mascota seleccionada (o placeholder).

### Pasos

1. Iniciar sesión como **dueño** con al menos una mascota **con foto** guardada.
2. Ir al **listado de cuidadores**, elegir uno y pulsar **Reservar**.
3. En el flujo de reserva:
   - Elegir **servicio** (hospedaje o paseo), **fechas** y, si aplica, **mascota**.
   - En el selector de mascota, comprobar que cada opción muestra la **foto** de la mascota (o placeholder).
4. Llegar a la pantalla **“Confirmar reserva”** (`/booking/:id/confirm`).
5. Comprobar en el resumen:
   - **Cuidador:** se muestra **foto del cuidador** (profilePicture o primera de `photos`; si no hay, placeholder).
   - **Mascota:** se muestra la **foto de la mascota** seleccionada (o placeholder “Sin foto”).

**Criterio de éxito:** En confirmación de reserva siempre se ve una imagen para cuidador y para mascota (foto real o placeholder).

---

## Placeholder y refetch

- **Placeholder estable:** En todo el front se usa `PHOTO_PLACEHOLDER` = `https://placehold.co/400x300/EEEEEE/999999/png?text=Sin+foto&font=montserrat` cuando no hay URL de foto (evita 404).
- **Dónde se usa:** Perfil mascota (lista, edición, completar), listado/detalle cuidadores, revisión admin (fotos espacio, perfil, selfie, CI), selector de mascota, confirmación de reserva, etc.
- **Refetch tras upload:**
  - **Foto mascota (Completar perfil):** Tras subir la imagen el backend guarda la URL en `ClientProfile.petPhoto` y la devuelve; el front hace `invalidateQueries` de `CLIENT_MY_PROFILE_QUERY_KEY` y `CLIENT_PETS_QUERY_KEY` y llama a `refetchProfile()` y `refetchPets()`. Al guardar el formulario se persiste también en `Pet.photoUrl`.

Si en algún flujo no se cumple lo anterior (foto no se guarda, no se muestra o no se refresca), revisar que el backend devuelva en los endpoints correspondientes los campos `photoUrl` (mascota), `photos`, `profilePhoto`, `ciAnversoUrl`, `ciReversoUrl` según lo definido en el schema y en las respuestas de API.

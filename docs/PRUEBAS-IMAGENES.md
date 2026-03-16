# Pruebas exhaustivas: imágenes en todo el MVP

Objetivo: que **todas** las fotos (mascota, cuidador, CI, etc.) se guarden como URLs absolutas de Cloudinary y se **muestren** en todos los lugares del frontend, sin 404 ni 500.

## Antes de probar

1. **Aplicar migración de columnas de imagen** (prioridad #1):
   ```bash
   cd garden-api
   npx prisma migrate deploy
   ```
   Si usas `migrate dev` en desarrollo:
   ```bash
   npx prisma migrate dev --name add_all_image_columns
   ```
   La migración `20260218000000_add_all_image_columns` asegura que existan en la DB: `caregiver_profiles.profilePhoto`, `client_profiles.petPhoto`, `caregiver_profiles.ciAnversoUrl`, `ciReversoUrl`, `ciNumber`.

2. Reiniciar el API tras la migración.

3. Frontend y API en marcha (por ejemplo `npm run dev` en cada uno).

---

## Caso 1: Foto de mascota → perfil dueño

1. Iniciar sesión como **dueño** (cliente).
2. Ir a **Completar perfil de mascota** (o Mi perfil → Completar ahora).
3. Rellenar nombre y tamaño, **subir una foto** (JPG/PNG).
4. Pulsar **Guardar y continuar**.
5. **Comprobar:** Te redirige a Mi perfil y la **foto de la mascota se ve** en la tarjeta de la mascota (o al menos el placeholder "Sin foto" si no hay URL, nunca 404).
6. **Refrescar la página** (F5) y comprobar que la foto **sigue visible**.

---

## Caso 2: Fotos de cuidador → listado y detalle

1. Registrarse o iniciar sesión como **cuidador**.
2. En el wizard de registro (o edición de perfil), **subir 4–6 fotos** del espacio.
3. Guardar y enviar perfil (si es registro). Si ya estás aprobado, solo editar y guardar.
4. Como **admin**, aprobar al cuidador si está pendiente.
5. Abrir el **listado público** de cuidadores (/) como anónimo o como cliente.
6. **Comprobar:** En las **tarjetas** de cuidadores se muestra la foto de perfil (o placeholder).
7. Entrar al **detalle** de un cuidador (clic en la tarjeta).
8. **Comprobar:** El **carousel de fotos** muestra las imágenes (o placeholder), sin 404.

---

## Caso 3: CI → revisión admin

1. Como **cuidador**, en el wizard subir **CI anverso y reverso**.
2. Enviar solicitud para revisión.
3. Como **admin**, ir a **Cuidadores pendientes** y abrir la **revisión** de ese cuidador.
4. **Comprobar:** Se muestran las **imágenes del CI** (anverso y reverso) o placeholder "Sin foto", sin 404 ni 500.

---

## Caso 4: Sin imagen → placeholder estable

1. En cualquier pantalla que muestre fotos (perfil dueño sin foto de mascota, tarjeta de cuidador sin foto, etc.), **comprobar** que se muestra el placeholder **"Sin foto"** (placehold.co 400x300 gris).
2. **No** debe haber 404 en la consola del navegador ni imágenes rotas.
3. La URL del placeholder debe ser:  
   `https://placehold.co/400x300/EEEEEE/999999/png?text=Sin+foto&font=montserrat`

---

## Caso 5: Refrescar página → fotos siguen visibles

1. Tras haber subido foto de mascota (Caso 1) o fotos de cuidador (Caso 2), **refrescar la página** (F5).
2. **Comprobar:** Las fotos **siguen visibles** (no dependen solo de estado en memoria).
3. Los GET del backend devuelven `petPhoto`, `pets[].photoUrl`, `profilePhoto`, `photos[]`, `ciAnversoUrl`, `ciReversoUrl` según corresponda, y el frontend pinta con `getImageUrl(url)`.

---

## Resumen de comprobaciones

| Dónde | Qué comprobar |
|-------|----------------|
| Mi perfil (dueño) | Fotos de mascotas visibles o placeholder. |
| Listado cuidadores | Foto en cada tarjeta (profilePhoto o primera de photos). |
| Detalle cuidador | Carousel con fotos (profilePhoto + photos). |
| Revisión admin | Fotos del espacio, foto de perfil, selfie, CI anverso/reverso. |
| Confirmación reserva | Foto cuidador y foto mascota si aplica. |
| Sin imagen | Placeholder "Sin foto" estable, sin 404. |
| Tras refrescar | Mismas fotos visibles (datos desde backend). |

Si **algún** caso falla (500 en API, 404 en imágenes, fotos no aparecen), revisar: 1) que la migración esté aplicada, 2) que el backend guarde siempre la URL completa (`secure_url`) en la DB, 3) que todos los GET incluyan los campos de imagen y 4) que el frontend use `src={getImageUrl(url)}` en todas las `<img>`.

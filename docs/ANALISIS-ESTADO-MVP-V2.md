# Análisis del estado del prototipo MVP GARDEN (V2 mínima)

**Fecha:** Febrero 2025  
**Contexto:** Basado en la conversación completa con el usuario, errores reportados y fixes aplicados.

---

## 0. Estado crítico actual (verificado en codebase y logs)

| Problema | Evidencia | Acción |
|----------|-----------|--------|
| **Columna `profilePhoto` inexistente en DB** | debug.log y combined.log: `The column caregiver_profiles.profilePhoto does not exist in the current database` | Ejecutar `npx prisma db push --force-reset --accept-data-loss` y `npx tsx prisma/seed.ts` en garden-api |
| **dist/ con agent log** | garden-api/dist/server.js, caregiver.controller.js, caregiver.service.js contienen `fetch('http://127.0.0.1:7242/...')` | `cd garden-api && npm run build` (el src/*.ts está limpio; dist es compilación antigua) |
| **vite.config.js con agent log** | garden-web/vite.config.js líneas 15–27 tienen agent log | El fuente es vite.config.ts (limpio). Eliminar vite.config.js si es redundante, o limpiar el agent log |
| **Sin carpeta migrations** | `prisma/migrations` no existe (0 archivos) | Usar `db push` para aplicar schema; no `migrate dev` |

El schema Prisma tiene `profilePhoto` en CaregiverProfile (línea 179); si la DB no se ha sincronizado con `db push`, GET /api/caregivers devolverá 500.

---

## 1. Estado general del prototipo

### 1.1 Frontend (garden-web)

| Aspecto | Estado | Detalle |
|---------|--------|---------|
| Carga | ✅ OK | Vite en puerto 5173, proxy `/api` → localhost:3000 |
| Conexión con backend | ✅ OK | Axios con baseURL, proxy en dev |
| Listado cuidadores | ✅ OK | ListingPage → ProfileCard, datos de GET /api/caregivers |
| Perfiles (dueño) | ✅ OK | ClientProfilePage, PetCard, useClientMyProfile con refetchOnMount: 'always' |
| Perfiles (cuidador detalle) | ✅ OK | CaregiverDetailPage → ProfileDetail (carousel fotos) |
| Reservas | ✅ OK | BookingConfirmationPage, PaymentPage, MyBookingsPage |
| Imágenes | ⚠️ Parcial | getImageUrl en utils/images.ts; placeholder placehold.co; blob/data para previews. Si Cloudinary no está configurado, se guardan URLs placeholder en dev. |
| Admin review | ✅ OK | AdminCaregiverReviewPage con PhotoGrid, profilePhoto, CI, etc. |

**Stack:** React 18, Vite, React Query, React Router, Tailwind, react-slick, react-dropzone, zod, react-hook-form.

### 1.2 Backend (garden-api)

| Aspecto | Estado | Detalle |
|---------|--------|---------|
| Arranque | ✅ OK | `tsx watch src/server.ts`, puerto 3000 |
| Conexión DB | ✅ OK | Prisma + PostgreSQL (DATABASE_URL) |
| GET /api/auth/me | ✅ OK | 401 sin token; 200 con Bearer |
| GET /api/caregivers | ✅ OK | Lista cuidadores APPROVED; devuelve profilePhoto, photos[]; cache en memoria |
| GET /api/client/my-profile | ✅ OK | petPhoto, pets[].photoUrl, user |
| GET /api/caregivers/:id | ✅ OK | Detalle con profilePhoto, photos, availability |
| Uploads | ⚠️ Condicional | pet-photo, registration-photos, CI: usan secure_url de Cloudinary; en dev sin Cloudinary retornan placeholders y pet-photo guarda en DB. logger.info('Foto subida y guardada') aplicado. |
| Bookings | ✅ OK | Creación, confirmación, pago, cancelación |

**Stack:** Node.js, Express, Prisma, bcrypt, jsonwebtoken, Cloudinary, multer, sharp, winston, zod.

### 1.3 Base de datos (garden_db)

| Aspecto | Estado | Detalle |
|---------|--------|---------|
| Tablas | ✅ OK | Tras `db push --force-reset`: users, caregiver_profiles, client_profiles, pets, bookings, availability, reviews, admin_actions, admin_notifications |
| Migraciones | ❌ Eliminadas | Se eliminó `prisma/migrations`; el schema se aplica con `npx prisma db push` (sin historial de migraciones) |
| Columnas de imágenes | ✅ OK | En schema: profilePhoto, photos (String[]), petPhoto, photoUrl (Pet), ciAnversoUrl, ciReversoUrl, qrImageUrl (Booking) |
| Seed | ✅ Configurado | package.json tiene `"prisma": { "seed": "tsx prisma/seed.ts" }`; crea admin + 2 cuidadores |

### 1.4 Cloudinary

| Aspecto | Estado | Detalle |
|---------|--------|---------|
| Configuración | ⚠️ Opcional | CLOUDINARY_CLOUD_NAME, API_KEY, API_SECRET; si no existen → dev usa placeholders |
| Carpetas | ✅ Definidas | garden/pets, garden/caregivers, garden/ci en config/cloudinary.ts |
| URLs guardadas | ✅ | uploadSinglePetPhoto, processAndUploadToCloudinary, uploadCiImage usan secure_url; ensureAbsoluteUrl en auth/caregiver-profile/client-pets |
| Dev sin Cloudinary | ✅ | pet-photo guarda placeholder en ClientProfile; registration-photos y CI retornan URLs placeholder sin subir |

---

## 2. Qué está de más (redundante o innecesario para MVP V2)

### 2.1 Código extra

| Tipo | Ubicación | Acción |
|------|-----------|--------|
| **dist/ desactualizado** | garden-api/dist/*.js | Contiene agent log (fetch a 127.0.0.1:7242) de compilaciones antiguas. El código fuente (src/*.ts) está limpio. Ejecutar `cd garden-api && npm run build` para regenerar dist. |
| **vite.config.js** | garden-web/vite.config.js | Transpilado legacy con agent log (líneas 15–27). El fuente es vite.config.ts (limpio). Vite usa .ts por defecto. Eliminar vite.config.js o limpiar el agent log. |
| **Logging excesivo** | Varios | logger.info en uploads y GET my-profile son útiles; no crítico eliminarlos para MVP. |
| **LazyLoadImage** | ProfileCard, ProfileDetail | Sustituido por `<img>` nativo con loading="lazy"; react-lazy-load-image-component sigue en package.json pero puede no usarse en estos componentes. Revisar si se usa en otros. |

### 2.2 Migraciones

- **prisma/migrations:** Eliminado. No hay historial. Para cambios futuros de schema:
  - Opción A: seguir con `npx prisma db push` (sin migraciones).
  - Opción B: crear baseline con `npx prisma migrate dev --name init` (genera primera migración a partir del schema actual).

### 2.3 Documentación redundante

- **README-RUN.md:** Menciona migraciones `20260217100000`, `20260218000000` que ya no existen. Debería actualizarse para reflejar el flujo actual: `db push` para reset total.
- **README-RUN.md:** Dice "seed automático está deshabilitado" pero package.json tiene prisma.seed configurado; contradicción.
- **MIGRATION-*.md** en prisma/: documentación de migraciones antiguas; útil como referencia histórica, no afecta ejecución.

### 2.4 Dependencias

- **yup** en garden-web: instalado pero el proyecto usa zod para validación; posible redundancia.
- **react-lazy-load-image-component:** si ya no se usa en ProfileCard/ProfileDetail, se puede eliminar.
- **Zod 3.23.8:** estable; actualización a latest no crítica para MVP.

---

## 3. Qué está fallando o podría fallar

### 3.1 Errores que fueron corregidos (contexto)

| Error | Causa | Fix aplicado |
|-------|-------|--------------|
| 500 en GET /api/caregivers (P2022, columna profilePhoto) | Columna no existía en DB | Migración add_all_image_columns; luego se eliminaron migraciones y se usó db push. |
| 500 en GET /api/caregivers (tabla caregiver_profiles no existe) | DB inconsistente, migraciones corruptas | `rm -rf prisma/migrations` + `npx prisma db push --force-reset` + seed. |
| 404 en placeholders (via.placeholder.com) | URL bloqueada o caída | getImageUrl usa placehold.co estable; acepta blob/data para previews. |
| Fotos no se muestran | Upload no guardaba en dev; columnas faltantes; frontend src=undefined | Upsert de petPhoto en upload dev; getImageUrl; refetchOnMount en useClientMyProfile. |
| Seed falla (tabla users no existe) | Seed corría antes de migraciones aplicadas | Seed desacoplado de reset; se ejecuta manualmente tras db push. |

### 3.2 Posibles fallos futuros

| Riesgo | Probabilidad | Mitigación |
|--------|--------------|------------|
| **Cronología de migraciones** | N/A | No hay migraciones; db push es la fuente de verdad. |
| **Validación Zod en bookings** | Media | Si duration viene como string desde form, coerce a number en schema. Revisar schemas de booking. |
| **Uploads Cloudinary no guardados** | Baja | En dev sin Cloudinary, pet-photo hace upsert con placeholder; createClientPet/patchClientPet reciben photoUrl y lo persisten. |
| **Refetch tras upload** | Baja | invalidateQueries + refetch en CompletePetProfilePage; refetchOnMount en useClientMyProfile. |
| **CORS en producción** | Media | Revisar app.use(cors()) y origen permitido al desplegar. |
| **Deprecation url.parse** | Baja | Warning en Node; no rompe; migrar a URL() cuando se actualice. |
| **Prisma 5.22.0** | Baja | Versión estable; actualizar a 6.x/7.x puede introducir breaking changes; no prioritario para MVP. |

### 3.3 Problemas con fotos (resumen)

- **Upload:** Cloudinary → secure_url guardada; dev sin Cloudinary → placeholder guardado en ClientProfile (pet-photo).
- **GET:** my-profile, caregivers, caregivers/:id, admin detail incluyen petPhoto, profilePhoto, photos[], ciAnversoUrl, ciReversoUrl.
- **Frontend:** getImageUrl(url) en todos los componentes; placeholder placehold.co; blob/data para previews.
- **Posible fallo:** Si placehold.co devuelve 404 en algún entorno, el usuario quedaría con imagen rota. Alternativa: data URL SVG inline (ya se usó en versión anterior).

---

## 4. Recomendaciones para estabilizar y optimizar

### 4.1 Pasos exactos para limpiar DB y migraciones (flujo actual)

```bash
cd garden-api
rm -rf prisma/migrations
npx prisma db push --force-reset --accept-data-loss
npx tsx prisma/seed.ts
npm run dev
```

Verificar:

```bash
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3000/api/caregivers?page=1&limit=10"
# Esperado: 200
```

Documentación: `garden-api/prisma/README-RESET-DB-LIMPIO.md`.

### 4.2 Actualizaciones (opcionales, no críticas para MVP)

- **Prisma:** `npm install prisma@latest @prisma/client@latest -D` (y en dependencies). Revisar changelog por breaking changes.
- **Zod:** `npm install zod@latest` en garden-api y garden-web.
- Prioridad baja; el MVP funciona con las versiones actuales.

### 4.3 Fixes para fotos (ya aplicados; verificar)

- **getImageUrl:** utils/images.ts con placeholder estable y soporte blob/data.
- **Refetch tras upload:** invalidateQueries + refetch en CompletePetProfilePage.
- **Coerce duration:** Si el formulario de reserva envía duration como string, añadir `.coerce` en el schema Zod de booking.
- **Cloudinary en producción:** Configurar CLOUDINARY_* en .env de producción para que las fotos reales se suban y guarden.

### 4.4 Tests básicos recomendados

| Caso | Pasos | Verificación |
|------|-------|--------------|
| Registro dueño | Registrar cliente → completar perfil mascota con foto → guardar | Foto visible en Mi perfil |
| Registro cuidador | Registrar cuidador con 4–6 fotos + CI | Fotos visibles en admin review |
| Listado cuidadores | Abrir / como anónimo | Tarjetas con foto o placeholder, sin 500 |
| Reserva | Cliente → reservar → confirmar → pagar | Reserva confirmada, QR si aplica |
| Admin review | Admin → cuidadores pendientes → revisar | Fotos, CI, aprobar/rechazar |

### 4.5 Prioridades para MVP V2

1. **Flujo principal:** registro dueño → perfil mascota → listado cuidadores → reserva → admin review.
2. **Eliminar extras:** Código debug en dist (rebuild), docs desactualizados (README-RUN), dependencias no usadas (yup, react-lazy-load si procede).
3. **Fotos:** Mantener getImageUrl, placeholder estable, refetch tras upload; en producción, Cloudinary configurado.
4. **Estabilidad DB:** Usar `db push` para cambios de schema hasta decidir reintroducir migraciones con baseline.

### 4.6 Inconsistencias en documentación (acciones sugeridas)

- **README-RUN.md línea 46–49:** Quitar referencias a migraciones 20260217/20260218 (ya no existen). Indicar que el flujo de reset total es `db push --force-reset` según README-RESET-DB-LIMPIO.md.
- **README-RUN.md líneas 53, 62–68:** Corregir: el seed está configurado en package.json; `npx prisma db seed` funciona; `tsx prisma/seed.ts` es alternativa manual. El reset con migraciones ya no aplica (no hay migraciones); el reset total usa db push.

---

## 5. Stack técnico (resumen)

| Capa | Tecnologías |
|------|-------------|
| Frontend | React 18, Vite, React Router, React Query, Tailwind, react-slick, react-dropzone, react-hook-form, zod, axios |
| Backend | Node.js, Express, Prisma, PostgreSQL, bcrypt, JWT, Cloudinary, multer, sharp, winston |
| DB | PostgreSQL (Docker o local), Prisma ORM |
| Upload/Storage | Cloudinary (garden/pets, garden/caregivers, garden/ci); placeholders en dev sin config |
| Validación | Zod (backend y frontend) |
| Dev | tsx, dotenv |

---

## 6. Comandos de referencia rápida

```bash
# Reset total DB (sin migraciones)
cd garden-api && rm -rf prisma/migrations
npx prisma db push --force-reset --accept-data-loss
npx tsx prisma/seed.ts

# Arranque
cd garden-api && npm run dev
cd garden-web && npm run dev

# Verificar API
curl -s "http://localhost:3000/api/caregivers?page=1&limit=10" | head -200

# Verificar tablas
cd garden-api && npx prisma studio
```

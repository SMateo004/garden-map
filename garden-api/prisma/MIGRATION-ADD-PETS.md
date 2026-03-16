# Migración: múltiples mascotas por dueño (Pet + ClientProfile)

## Schema actualizado

- **ClientProfile**: solo datos del dueño (`address`, `phone`). Relación `pets Pet[]`. Se mantiene `isComplete` (true cuando tiene al menos un Pet con name, size y photoUrl).
- **Pet**: nuevo modelo; datos de cada mascota (`name`, `breed`, `age`, `size`, `photoUrl`, `specialNeeds`, `notes`). Relación muchos-a-uno con `ClientProfile`.
- **PetSize**: se reutiliza el enum existente (SMALL, MEDIUM, LARGE, GIANT).

## Comando recomendado

```bash
cd garden-api
npx prisma migrate dev --name add_multiple_pets
```

Luego regenerar el cliente:

```bash
npx prisma generate
```

## Si ya hay datos en ClientProfile (columnas de mascota)

La migración generada por Prisma **creará la tabla `pets`** y **eliminará** las columnas antiguas de `client_profiles` (`pet_name`, `pet_breed`, `pet_age`, `pet_size`, `pet_photo`, `special_needs`, `notes`). Cualquier dato que esté solo en esas columnas se pierde en ese paso.

### Opción A – Desarrollo (sin conservar datos)

- Ejecutar la migración tal cual.
- Si necesitas datos de prueba, volver a registrar dueños y mascotas desde la app o ajustar el seed para crear `Pet` en lugar de usar campos en `ClientProfile`.

### Opción B – Conservar datos existentes (pasos manuales)

1. **Crear solo la tabla `pets` (sin borrar columnas aún)**  
   Editar temporalmente el schema: en `ClientProfile` volver a añadir los campos antiguos de mascota (petName, petBreed, etc.) y comentar o no usar la relación `pets` en la migración, **o** crear la tabla `pets` a mano con SQL y luego marcar la migración como aplicada.

2. **Copiar datos de `client_profiles` a `pets`** (ejecutar en la base de datos):

```sql
INSERT INTO "pets" (id, "clientProfileId", name, breed, age, size, "photoUrl", "specialNeeds", notes, "createdAt", "updatedAt")
SELECT
  gen_random_uuid(),
  cp.id,
  COALESCE(cp."petName", 'Mascota'),
  cp."petBreed",
  cp."petAge",
  cp."petSize",
  cp."petPhoto",
  cp."specialNeeds",
  cp."notes",
  cp."createdAt",
  cp."updatedAt"
FROM "client_profiles" cp
WHERE cp."petName" IS NOT NULL AND cp."petName" <> '';
```

(Columnas en comillas porque Prisma usa camelCase en la base.)

3. **Eliminar columnas antiguas** con una nueva migración o con un `ALTER TABLE` manual y luego marcar la migración como aplicada.

### Opción C – Empezar desde cero (desarrollo)

```bash
npx prisma migrate reset
```

Esto aplica todas las migraciones desde cero y ejecuta el seed. Los dueños creados por el seed no tienen mascotas en el modelo antiguo; tras la migración tendrás que registrar mascotas desde la app o ampliar el seed para crear registros en `Pet`.

## Coherencia con el proyecto

- **Cloudinary**: `Pet.photoUrl` almacena la URL devuelta por el upload (igual que antes en `petPhoto`).
- **Booking**: sigue guardando en la reserva una copia de los datos de la mascota (`petName`, `petBreed`, etc.); no es necesario añadir `petId` al MVP. Opcionalmente más adelante se puede referenciar `Pet.id` en la reserva.
- **isComplete**: en el backend debe actualizarse cuando el cliente tenga al menos un `Pet` con `name`, `size` y `photoUrl` no nulos (misma lógica que antes con un solo conjunto de campos).

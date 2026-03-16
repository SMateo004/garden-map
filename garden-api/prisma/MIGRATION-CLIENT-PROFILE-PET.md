# Migración: ClientProfile con información de mascota

## Resumen

Esta migración extiende el modelo `ClientProfile` para incluir información completa de la mascota del cliente (dueño). El perfil ahora incluye campos para datos de la mascota y un flag `isComplete` que bloquea la creación de reservas hasta que el perfil esté completo.

## Cambios en el Schema

### Modelo ClientProfile actualizado

```prisma
model ClientProfile {
  id            String   @id @default(uuid())
  userId        String   @unique
  user          User     @relation(fields: [userId], references: [id], onDelete: Cascade)
  
  address       String?  @db.VarChar(500)
  phone         String?  @db.VarChar(20)
  
  // Perfil de mascota (obligatorio para poder reservar)
  petName       String?  @db.VarChar(200)
  petBreed      String?  @db.VarChar(100)
  petAge        Int?
  petSize       PetSize?
  petPhoto      String?  @db.Text
  specialNeeds  String?  @db.Text
  notes         String?  @db.Text
  
  isComplete    Boolean  @default(false)   // true cuando tiene foto y datos básicos de mascota
  
  createdAt     DateTime @default(now())
  updatedAt     DateTime @updatedAt

  @@index([userId])
  @@index([isComplete]) // Para filtrar clientes que pueden reservar
  @@index([petSize]) // Para búsquedas por tamaño de mascota
  @@map("client_profiles")
}
```

### Campos agregados

- `phone`: Teléfono alternativo del cliente (puede diferir del User.phone)
- `petName`: Nombre de la mascota principal
- `petBreed`: Raza de la mascota
- `petAge`: Edad en años
- `petSize`: Tamaño (enum PetSize: SMALL, MEDIUM, LARGE, GIANT)
- `petPhoto`: URL de foto en Cloudinary
- `specialNeeds`: Necesidades especiales (medicación, dieta, etc.)
- `notes`: Notas adicionales
- `isComplete`: Flag que bloquea reservas si es `false`

### Índices agregados

1. `@@index([isComplete])`: Para filtrar clientes que pueden reservar (isComplete = true)
2. `@@index([petSize])`: Para búsquedas/filtros por tamaño de mascota

## Comando de migración

```bash
cd garden-api
npx prisma migrate dev --name add_pet_info_to_client_profile
npx prisma generate
```

## Validación de isComplete

El flag `isComplete` debe ser `true` para permitir reservas. La validación se realiza en:

- **Backend**: `booking.service.ts` → `createBooking()` debe verificar `clientProfile.isComplete === true` antes de crear la reserva
- **Frontend**: Mostrar mensaje claro si el perfil no está completo al intentar reservar

### Criterios para isComplete = true

El perfil se considera completo cuando tiene:
- `petName` (requerido)
- `petSize` (requerido)
- `petPhoto` (requerido)

Estos campos son los mínimos necesarios para poder hacer una reserva.

## Actualización del endpoint de registro

El endpoint `POST /api/auth/client/register` ahora crea automáticamente un `ClientProfile` vacío con:
- `address`: Dirección proporcionada en el registro
- `phone`: Teléfono del registro (también guardado en User)
- `isComplete`: `false` (bloquea reservas hasta completar perfil)

## Próximos pasos

1. **Validación en booking.service.ts**: Agregar verificación de `isComplete` antes de crear reservas
2. **Frontend**: Crear página/formulario para completar perfil de mascota
3. **API endpoint**: Crear `PATCH /api/client/profile` para actualizar perfil y calcular `isComplete` automáticamente

## Notas técnicas

- El enum `PetSize` ya existe en el schema (SMALL, MEDIUM, LARGE, GIANT)
- `petPhoto` usa `@db.Text` para URLs largas de Cloudinary
- `specialNeeds` y `notes` usan `@db.Text` para textos largos
- Los índices mejoran el rendimiento de consultas por `isComplete` y `petSize`

# Instrucciones de Prueba End-to-End - Subfase 2.2

## Requisitos Previos

1. **Base de datos**: PostgreSQL corriendo (Docker o local)
2. **Backend**: API corriendo en `http://localhost:3000`
3. **Frontend**: Aplicación React corriendo en `http://localhost:5173` (o puerto configurado)
4. **Usuarios de prueba**: Creados con `npm run seed` en el backend

## Usuarios de Prueba Disponibles

- **Cliente**: Crea un usuario desde el frontend o usa:
  - Email: `cliente@test.com`
  - Password: `GardenSeed2024!`
  - Role: `CLIENT`

- **Cuidador APPROVED**: 
  - Email: `cuidador.approved@garden.bo` (crear manualmente o aprobar uno pendiente)
  - Password: `GardenSeed2024!`
  - Status: `APPROVED`

- **Admin**:
  - Email: `admin@garden.bo`
  - Password: `GardenSeed2024!`
  - Role: `ADMIN`

---

## Flujo Completo de Prueba

### 1. Listado de Cuidadores con Filtros (Solo APPROVED)

**Objetivo**: Verificar que el listado muestre solo cuidadores aprobados y que los filtros funcionen correctamente.

**Pasos**:

1. Abre `http://localhost:5173` en el navegador
2. En la página principal (`/`), deberías ver el listado de cuidadores
3. **Verificar filtros**:
   - Filtro de servicio: Selecciona "Hospedaje" o "Paseo"
   - Filtro de zona: Selecciona una zona (ej: "NORTE", "SUR")
   - Filtro de precio: Selecciona "Económico", "Estándar" o "Premium"
   - Filtro de espacio: Selecciona tipo de espacio si aplica
4. Verifica que solo aparezcan cuidadores con status `APPROVED`
5. Verifica que los chips de filtros activos se muestren y puedas eliminarlos

**Resultado esperado**:
- Solo cuidadores `APPROVED` aparecen en el listado
- Los filtros se aplican correctamente
- Los chips muestran filtros activos y se pueden eliminar

---

### 2. Ver Detalle de Cuidador y Calendario de Disponibilidad

**Objetivo**: Verificar que el detalle del cuidador muestre correctamente el calendario de disponibilidad.

**Pasos**:

1. Haz clic en cualquier cuidador del listado
2. En la página de detalle (`/caregivers/:id`), deberías ver:
   - Información completa del cuidador
   - **Calendario de Hospedaje**: Muestra días disponibles (verde) y bloqueados (gris)
   - **Calendario de Paseos**: Muestra bloques de tiempo disponibles (mañana/tarde)
3. Verifica que los días pasados estén deshabilitados
4. Verifica que los días disponibles se muestren correctamente

**Resultado esperado**:
- El calendario muestra correctamente la disponibilidad
- Los días pasados están deshabilitados
- El botón "Reservar" está visible y funcional

---

### 3. Crear Reserva y Generar QR

**Objetivo**: Crear una reserva exitosamente y verificar que se genere el QR.

**Pasos**:

1. En la página de detalle del cuidador, haz clic en "Reservar"
2. Si no estás autenticado, serás redirigido al login
3. Inicia sesión como cliente (`cliente@test.com`)
4. En la página de reserva (`/reservar/:id`):
   - Selecciona el tipo de servicio (Hospedaje o Paseo)
   - **Para Hospedaje**:
     - Selecciona fecha de entrada (mínimo 48h desde hoy)
     - Selecciona fecha de salida (mínimo 48h después de entrada)
   - **Para Paseo**:
     - Selecciona fecha del paseo
     - Selecciona horario (Mañana/Tarde)
     - Selecciona duración (30 o 60 minutos)
   - Completa información de la mascota:
     - Nombre (obligatorio)
     - Raza (opcional)
     - Edad (opcional)
     - Necesidades especiales (opcional)
5. Revisa el resumen de precio
6. Revisa la tabla de reglas de cancelación
7. Haz clic en "Confirmar Reserva"

**Resultado esperado**:
- La reserva se crea exitosamente
- Se muestra la página de éxito (`/bookings/:id/success`)
- Se muestra el QR placeholder
- El estado de la reserva es `PENDING_PAYMENT`

---

### 4. Simular Pago (Mock) y Confirmar Reserva

**Objetivo**: Verificar que el pago QR se pueda verificar y la reserva se confirme.

**Pasos**:

1. En la página de éxito de la reserva (`/bookings/:id/success`):
   - Verifica que se muestre el QR placeholder
   - Verifica que se muestre la fecha de expiración del QR
2. Haz clic en el botón "Verificar Pago QR"
3. El sistema debería verificar el pago (mock) y actualizar el estado

**Resultado esperado**:
- El botón "Verificar Pago QR" está visible
- Al hacer clic, se muestra un toast de éxito
- La reserva cambia a estado `CONFIRMED`
- Se redirige a la página de detalle de la reserva

**Nota**: En producción, este paso sería reemplazado por la integración real con el banco.

---

### 5. Ver Mis Reservas

**Objetivo**: Verificar que el cliente pueda ver todas sus reservas.

**Pasos**:

1. En el navbar, haz clic en "Mis Reservas" (visible solo para clientes autenticados)
2. En la página `/bookings`, deberías ver:
   - Lista de todas tus reservas
   - Estado de cada reserva (badge de color)
   - Información básica (servicio, mascota, fechas, monto)
3. Haz clic en cualquier reserva para ver el detalle

**Resultado esperado**:
- Se muestran todas las reservas del cliente
- Las reservas están ordenadas por fecha de creación (más recientes primero)
- Cada reserva muestra información relevante

---

### 6. Cancelar Reserva (Según Reglas del MVP)

**Objetivo**: Verificar que la cancelación aplique correctamente las reglas de reembolso.

**Pasos**:

1. En la página de detalle de una reserva (`/bookings/:id`):
   - Verifica que el botón "Cancelar Reserva" esté visible (solo para `PENDING_PAYMENT` o `CONFIRMED`)
2. Haz clic en "Cancelar Reserva"
3. En el modal:
   - Opcionalmente ingresa un motivo de cancelación
   - Haz clic en "Confirmar Cancelación"
4. Verifica el resultado según las reglas:
   - **Hospedaje**:
     - Cancelación >48h antes: 100% reembolso (menos Bs 10 admin)
     - Cancelación 24-48h antes: 50% reembolso
     - Cancelación <24h antes: 0% reembolso
   - **Paseo**:
     - Cancelación >12h antes: 100% reembolso
     - Cancelación 6-12h antes: 50% reembolso
     - Cancelación <6h antes: 0% reembolso

**Resultado esperado**:
- La reserva cambia a estado `CANCELLED`
- Se muestra el monto de reembolso calculado correctamente
- El estado del reembolso se muestra (`APPROVED` o `REJECTED`)

**Pruebas específicas**:

- **Prueba 1**: Cancela una reserva de hospedaje con fecha >48h en el futuro → Debe mostrar 100% reembolso (menos Bs 10)
- **Prueba 2**: Cancela una reserva de hospedaje con fecha entre 24-48h → Debe mostrar 50% reembolso
- **Prueba 3**: Cancela una reserva de paseo con fecha >12h en el futuro → Debe mostrar 100% reembolso
- **Prueba 4**: Cancela una reserva de paseo con fecha <6h → Debe mostrar 0% reembolso

---

### 7. Extender Reserva (Solo Hospedaje CONFIRMED)

**Objetivo**: Verificar que se pueda extender una reserva de hospedaje confirmada.

**Pasos**:

1. Asegúrate de tener una reserva de hospedaje con estado `CONFIRMED`
2. En la página de detalle de la reserva (`/bookings/:id`):
   - Verifica que el botón "Extender Hospedaje" esté visible
3. Haz clic en "Extender Hospedaje"
4. En el modal:
   - Selecciona una nueva fecha de salida (posterior a la fecha actual de salida)
5. Haz clic en "Confirmar Extensión"

**Resultado esperado**:
- La reserva se actualiza con la nueva fecha de salida
- El monto total se recalcula automáticamente
- Se muestra un toast de éxito
- La disponibilidad del cuidador se verifica para los nuevos días

---

### 8. Cambiar Fechas de Reserva (Solo Hospedaje CONFIRMED)

**Objetivo**: Verificar que se puedan cambiar las fechas de una reserva de hospedaje confirmada.

**Pasos**:

1. Asegúrate de tener una reserva de hospedaje con estado `CONFIRMED`
2. En la página de detalle de la reserva (`/bookings/:id`):
   - Verifica que el botón "Cambiar Fechas" esté visible
3. Haz clic en "Cambiar Fechas"
4. En el modal:
   - Selecciona una nueva fecha de entrada (mínimo 48h desde hoy)
   - Selecciona una nueva fecha de salida (mínimo 48h después de entrada)
5. Haz clic en "Confirmar Cambio"

**Resultado esperado**:
- La reserva se actualiza con las nuevas fechas
- El monto total se recalcula automáticamente
- Se verifica la disponibilidad del cuidador para las nuevas fechas
- Se muestra un toast de éxito

---

## Pruebas Adicionales

### Pruebas de Validación

1. **Crear reserva sin autenticación**: Debe redirigir al login
2. **Crear reserva con fechas no disponibles**: Debe mostrar error 409
3. **Crear reserva de hospedaje con menos de 48h**: Debe mostrar error de validación
4. **Cancelar reserva ya cancelada**: Debe mostrar error
5. **Extender reserva de paseo**: Debe mostrar error (solo hospedaje)
6. **Cambiar fechas de reserva no confirmada**: Debe mostrar error

### Pruebas de UI/UX

1. **Responsive**: Verifica que todo funcione en móvil
2. **Loading states**: Verifica que se muestren spinners durante cargas
3. **Error handling**: Verifica que los errores se muestren con toasts
4. **Navegación**: Verifica que los enlaces funcionen correctamente

---

## Comandos Útiles

### Backend

```bash
# Iniciar servidor de desarrollo
cd garden-api
npm run dev

# Ejecutar tests
npm test

# Ejecutar tests específicos
npm test -- booking.service.test.ts
npm test -- bookings.api.test.ts

# Seed de base de datos
npm run seed
```

### Frontend

```bash
# Iniciar servidor de desarrollo
cd garden-web
npm run dev

# Build de producción
npm run build
```

### Base de Datos

```bash
# Generar Prisma Client
cd garden-api
npx prisma generate

# Crear migración
npx prisma migrate dev --name nombre_migracion

# Ver datos en Prisma Studio
npx prisma studio
```

---

## Checklist de Verificación

- [ ] Listado muestra solo cuidadores APPROVED
- [ ] Filtros funcionan correctamente
- [ ] Calendario de disponibilidad se muestra correctamente
- [ ] Creación de reserva funciona (hospedaje y paseo)
- [ ] QR se genera correctamente
- [ ] Verificación de pago QR funciona (mock)
- [ ] Cancelación aplica reglas de reembolso correctamente
- [ ] Extensión de reserva funciona
- [ ] Cambio de fechas funciona
- [ ] Página "Mis Reservas" muestra todas las reservas
- [ ] Navegación entre páginas funciona
- [ ] Estados de carga y errores se muestran correctamente
- [ ] Responsive funciona en móvil

---

## Notas Importantes

1. **Mock de Pago QR**: El sistema actual usa un mock para verificar pagos QR. En producción, esto se reemplazará con la integración real del banco.

2. **Reglas de Reembolso**: Las reglas están hardcodeadas según el MVP:
   - Hospedaje: 48h/24h
   - Paseos: 12h/6h
   - Admin fee: Bs 10 (solo para hospedaje 100% reembolso)

3. **Disponibilidad**: El sistema verifica disponibilidad tanto en `Availability` como en reservas existentes que se solapen.

4. **Validaciones**: Todas las validaciones están implementadas tanto en frontend (Zod) como en backend (Zod + Prisma).

---

## Troubleshooting

### Error: "No se puede crear reserva - Cuidador no encontrado"
- Verifica que el cuidador tenga status `APPROVED`
- Verifica que el cuidador ofrezca el servicio solicitado

### Error: "Fechas no disponibles"
- Verifica que las fechas estén en `Availability` con `isAvailable: true`
- Verifica que no haya reservas que se solapen

### Error: "QR expirado"
- Los QR tienen validez de 24 horas
- Crea una nueva reserva para generar un nuevo QR

### Error: "No se puede cancelar reserva ya iniciada"
- Solo se pueden cancelar reservas con estado `PENDING_PAYMENT` o `CONFIRMED`
- Reservas `IN_PROGRESS` o `COMPLETED` no se pueden cancelar

---

## Contacto y Soporte

Si encuentras problemas durante las pruebas, verifica:
1. Los logs del backend (`garden-api/.cursor/debug.log`)
2. La consola del navegador (F12)
3. Los logs de Prisma (`npx prisma studio` para ver datos)

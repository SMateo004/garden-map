# Disponibilidad del cuidador (MVP v2 – Paso 1)

El cuidador aprobado gestiona su disponibilidad desde **Mi disponibilidad** en su dashboard. Esa disponibilidad se usa en el flujo de reserva del cliente (solo se muestran fechas/horarios disponibles).

## Cómo probar

1. **Login como cuidador** (usuario con rol CAREGIVER y perfil aprobado).
2. **Ir a disponibilidad:** desde el panel del cuidador, clic en **Disponibilidad** (o navegar a `/caregiver/availability`).
3. **Definir horario predeterminado:**
   - Marca/desmarca "Disponible para hospedaje por defecto".
   - Marca los bloques para paseos: Mañana, Tarde, Noche.
4. **Seleccionar fechas en el calendario:** haz clic en uno o varios días (el mismo clic añade/quita la fecha de la selección).
5. **Panel lateral:**
   - **Aplicar predeterminado a fechas seleccionadas:** aplica el horario predeterminado a todas las fechas seleccionadas.
   - Para la(s) fecha(s) seleccionada(s): marca "Disponible este día", bloques Mañana/Tarde/Noche y, opcional, **Motivo** (ej. "Vacaciones", "Viaje").
6. **Guardar:** clic en **Guardar disponibilidad** → debe aparecer toast de éxito.
7. **Comprobar:** recarga la página o vuelve a entrar en Disponibilidad y verifica que el horario predeterminado y los overrides por fecha se mantienen.

## API (solo CAREGIVER)

- **GET** `/api/caregiver/availability?from=YYYY-MM-DD&to=YYYY-MM-DD`  
  También acepta `start` y `end` como alias.  
  Devuelve `defaultSchedule` y `dates` (por cada fecha: `isAvailable`, `timeBlocks`, `reason`).

- **PATCH** `/api/caregiver/availability`  
  Body: `{ defaultSchedule?: { hospedajeDefault, paseoTimeBlocks }, overrides?: { [date]: { isAvailable?, timeBlocks?, reason? } } }`  
  Actualiza el horario predeterminado en el perfil y crea/actualiza filas en `Availability` para cada clave de `overrides`.

## Integración con reservas

- **GET** `/api/caregivers/:id/availability?from=...&to=...` (público o cliente) usa las filas de `Availability` para devolver fechas disponibles para hospedaje y bloques para paseos.
- En la página de reserva del cliente, el calendario y los horarios de paseo solo muestran opciones disponibles según esta disponibilidad.

## Migración

Si aplicas la migración nueva (`add_caregiver_availability_with_timeblocks`):

```bash
cd garden-api
npx prisma migrate dev --name add_caregiver_availability_with_timeblocks
```

Si ya tienes filas en `availability`, la nueva columna `overrideReason` queda NULL; no se pierden datos. El índice `availability_caregiverId_idx` mejora las consultas por cuidador.

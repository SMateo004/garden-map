# Migración Subfase 2.2 — Booking y Availability (MVP)

## Resumen de cambios en el schema

- **RefundStatus** (nuevo enum): `PENDING_APPROVAL`, `APPROVED`, `REJECTED`, `PROCESSED` (reembolsos; reglas MVP 48h hospedaje / 12h paseos).
- **Booking**: montos en `Decimal(10,2)` (totalAmount, pricePerUnit, commissionAmount, refundAmount); campos QR (qrId, qrImageUrl, qrExpiresAt); cancelación y reembolso (refundStatus, refundAmount). Comentarios MVP en schema.
- **Availability**: una fila por (caregiverId, date); `timeBlocks` JSON (`{ "manana": true, "tarde": false }`) para paseos; `@@unique([caregiverId, date])`. Eliminados `serviceType` y `timeSlots` del modelo.

## Comando de migración recomendado

Desde la raíz del backend:

```bash
cd garden-api
npx prisma generate
npx prisma migrate dev --name subfase_2_2_booking_availability
```

- **`prisma generate`**: regenera el cliente con los nuevos tipos (Decimal, RefundStatus, etc.).
- **`prisma migrate dev`**: crea la migración SQL y la aplica; pide nombre si no se pasa `--name`.

Si ya tienes datos en `availability` con `serviceType`/`timeSlots`, la migración puede incluir pasos de migración de datos (mapear filas antiguas al nuevo formato) o requerir un script de datos; en desarrollo con seed desde cero suele bastar con la migración automática.

## Índices considerados (rendimiento)

- **Booking**: `(caregiverId, status)`, `(clientId, status)`, `(status, startDate)`, `(paidAt)` — listados por cuidador/cliente, calendario y pagos.
- **Availability**: `(caregiverId, date)`, `(date, isAvailable)` — calendario y búsqueda de huecos.

## Reglas MVP referenciadas en comentarios

- Hospedaje: ventana mínima **48h** para cancelación/reembolso.
- Paseos: ventana **12h** antes; bloques **MANANA** / **TARDE**; duración **30** o **60** minutos.

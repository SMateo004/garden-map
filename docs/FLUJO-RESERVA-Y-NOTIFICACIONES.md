# Flujo completo de reserva y notificaciones (GARDEN MVP)

Este documento describe el flujo de reserva de punta a punta y cómo probarlo, incluyendo las notificaciones (placeholders Email/WhatsApp) y su trazabilidad.

---

## 1. Resumen del flujo

1. **Cliente** selecciona cuidador → elige fechas/horario y mascota → **confirma datos** (página de confirmación) → **paga** (QR o pago manual).
2. **Pago confirmado** → reserva pasa a `CONFIRMED` → **notificación a cliente y cuidador** (email + WhatsApp placeholder).
3. **Cancelación por cliente** → reserva `CANCELLED` + reembolso según política → **notificación al cliente** con mensaje "El soporte se pondrá en contacto" si hay reembolso.
4. **Cancelación solicitada por cuidador** → reserva `CANCELLATION_REQUESTED` → **notificación a admin** para revisión.
5. **Admin aprueba cancelación** → reserva `CANCELLED` + reembolso → **notificación a cliente y cuidador**; si hay reembolso, **notificación de reembolso** al cliente ("El soporte se pondrá en contacto").
6. **Admin rechaza cancelación** → reserva vuelve a `CONFIRMED` → **notificación al cuidador**.

---

## 2. Servicio de notificaciones

- **Ubicación:** `garden-api/src/services/notification.service.ts`
- **Placeholders:** `sendEmailPlaceholder(to, subject, body, meta)` y `sendWhatsAppPlaceholder(toPhone, body, meta)`.
- **Eventos implementados:**
  - `onBookingConfirmed(bookingId)` — pago confirmado → cliente + cuidador
  - `onCancellationRequested(bookingId, 'client'|'caregiver', reason?)` — solicitud de cancelación → admin
  - `onCancellationApproved(bookingId, refundAmount, refundStatus)` — admin aprobó → cliente + cuidador
  - `onCancellationRejected(bookingId)` — admin rechazó → cuidador
  - `onClientCancelled(bookingId)` — cliente canceló → cuidador
  - `onRefundProcessed(bookingId, message)` — reembolso / "El soporte se pondrá en contacto" → cliente

**Trazabilidad:** Cada envío se registra con `logger.info('[NOTIFICATION] ...')` y `console.log` con `event` y `bookingId`. En consola del servidor verás líneas como:

- `[EMAIL_PLACEHOLDER] to=... subject=... event=BOOKING_CONFIRMED_CLIENT bookingId=...`
- `[WHATSAPP_PLACEHOLDER] to=... event=... bookingId=...`

**Integración futura:**

- **Email:** Sustituir el cuerpo de `sendEmailPlaceholder` por llamada a SendGrid, Resend o SES.
- **WhatsApp:** Sustituir `sendWhatsAppPlaceholder` por Twilio: `twilioClient.messages.create({ from: WHATSAPP_FROM, to: 'whatsapp:' + toPhone, body })`.

---

## 3. Puntos de integración en el código

| Momento | Dónde | Qué se llama |
|--------|--------|---------------|
| Pago confirmado (QR) | `payment.service.ts` → `verifyPaymentByQr` | `onBookingConfirmed(bookingId)` |
| Pago confirmado (manual admin) | `payment.service.ts` → `verifyPaymentManual` | `onBookingConfirmed(bookingId)` |
| Pago confirmado (Stripe) | `payment.service.ts` → `handleCheckoutCompleted` | `onBookingConfirmed(bookingId)` |
| Cliente cancela | `booking.service.ts` → `cancelBooking` | `onClientCancelled(bookingId)` (cuidador) + `onRefundProcessed(bookingId, message)` si hay reembolso |
| Cuidador solicita cancelación | `booking.service.ts` → `requestCancellationByCaregiver` | `onCancellationRequested(bookingId, 'caregiver', reason)` |
| Admin aprueba cancelación | `booking.service.ts` → `approveCancellationRequest` | `onCancellationApproved` + `onRefundProcessed` si hay reembolso |
| Admin rechaza cancelación | `booking.service.ts` → `rejectCancellationRequest` | `onCancellationRejected(bookingId)` |

Las notificaciones se disparan con `.catch(...)` para no bloquear la respuesta; los fallos se registran en `logger.error`.

---

## 4. Cómo probar el flujo completo

### Requisitos previos

- Base de datos con migraciones aplicadas y seed (admin + al menos 1 cuidador APPROVED + 1 cliente con perfil y mascota).
- API: `cd garden-api && npm run dev`
- Web: `cd garden-web && npm run dev`
- Tener a mano: usuario **cliente** (email/contraseña), usuario **cuidador**, usuario **admin**.

---

### 4.1. Flujo feliz: reserva y pago confirmado

1. **Login como cliente** en la web.
2. Ir a **Cuidadores** y abrir un cuidador que ofrezca Hospedaje o Paseo.
3. Clic en **Reservar** → elegir tipo de servicio, fechas (o fecha + bloque para paseo), mascota → **Enviar** (se crea la reserva `PENDING_PAYMENT`).
4. Redirige a **Confirmar reserva** (`/booking/:id/confirm`). Revisar datos y clic en **Confirmar y pagar**.
5. Entras en **Pago** (`/booking/:id/payment`). Se genera el QR (placeholder). Opciones:
   - **Probar verificación por QR:** llamar desde Postman/curl:
     ```bash
     # Obtener qrId de la reserva (GET /api/bookings/:id con token cliente) o de la respuesta al generar QR
     curl -X POST http://localhost:3000/api/payments/verify \
       -H "Content-Type: application/json" -H "Authorization: Bearer <TOKEN_CLIENTE>" \
       -d '{"qrId":"<QR_ID_DE_LA_RESERVA>"}'
     ```
   - **Probar pago manual:** en la misma página, clic en **La API bancaria no responde / Pago manual**. Luego como **admin**: Panel admin → **Pagos pendientes** → Aprobar pago para esa reserva.
6. Tras confirmar el pago, la reserva pasa a `CONFIRMED`.
7. **Verificar notificaciones:** en la consola del servidor (garden-api) deben aparecer:
   - `[NOTIFICATION] Email placeholder` y `[EMAIL_PLACEHOLDER]` para cliente y cuidador (eventos `BOOKING_CONFIRMED_CLIENT`, `BOOKING_CONFIRMED_CAREGIVER`).
   - `[WHATSAPP_PLACEHOLDER]` para ambos.

---

### 4.2. Cancelación por cliente (con reembolso)

1. Con una reserva **CONFIRMED** (o recién confirmada), como **cliente** ir a **Próximas reservas** (`/profile/reservations`) o **Mis reservas** (`/bookings`).
2. Abrir la reserva y usar **Cancelar** (o desde la lista, según la UI). Indicar motivo si se pide.
3. La reserva pasa a `CANCELLED`; si aplica reembolso (según política 48h hospedaje / 12h paseo), se calcula `refundAmount` y `refundStatus`.
4. **Verificar notificaciones:** si hay reembolso aprobado, en consola:
   - `[NOTIFICATION] Email placeholder` y `[WHATSAPP_PLACEHOLDER]` con evento `REFUND_PROCESSED_CLIENT` y mensaje que incluye "El soporte se pondrá en contacto".

---

### 4.3. Cancelación solicitada por cuidador → admin aprueba/rechaza

1. Tener una reserva **CONFIRMED** asignada a un cuidador.
2. **Login como cuidador** → **Mis reservas** (`/caregiver/reservations`).
3. En la reserva, clic en **Solicitar cancelación** y escribir motivo → Enviar.
4. La reserva pasa a `CANCELLATION_REQUESTED`.
5. **Verificar notificaciones:** en consola, `[NOTIFICATION] Cancellation requested → admin` y/o `[ADMIN_NOTIFY]` (según implementación).
6. **Login como admin** → **Reservas** (`/admin/reservations`) → filtrar por **Cancelación solicitada**.
7. En la fila de esa reserva:
   - **Aprobar cancelación:** clic en **Aprobar cancelación**. La reserva pasa a `CANCELLED` y se aplica reembolso. En consola: `onCancellationApproved` (cliente + cuidador) y si hay reembolso `onRefundProcessed` (cliente, mensaje "El soporte se pondrá en contacto").
   - **Rechazar:** clic en **Rechazar**. La reserva vuelve a `CONFIRMED`. En consola: `onCancellationRejected` (cuidador).

---

### 4.4. Resumen de logs a buscar

En la salida del servidor (garden-api) deberías ver, según el caso:

| Acción | Logs esperados |
|--------|-----------------|
| Pago confirmado (QR o manual o Stripe) | `Booking confirmed...` + `[NOTIFICATION] Email placeholder` (BOOKING_CONFIRMED_CLIENT, BOOKING_CONFIRMED_CAREGIVER) + `[WHATSAPP_PLACEHOLDER]` |
| Cliente cancela | `Booking cancelled` + `[NOTIFICATION]` CLIENT_CANCELLED_CAREGIVER + REFUND_PROCESSED_CLIENT si hay reembolso |
| Cuidador solicita cancelación | `Cancelación solicitada por cuidador` + `[NOTIFICATION] Cancellation requested` |
| Admin aprueba cancelación | `Admin aprobó cancelación` + `[NOTIFICATION]` CANCELLATION_APPROVED_CLIENT/CAREGIVER + REFUND_PROCESSED_CLIENT si aplica |
| Admin rechaza cancelación | `Admin rechazó solicitud` + `[NOTIFICATION]` CANCELLATION_REJECTED_CAREGIVER |

---

## 5. Robustez y buenas prácticas

- **No bloqueo:** Las notificaciones se ejecutan con `.catch(...)` para que un fallo en email/WhatsApp no devuelva error al usuario.
- **Trazabilidad:** Cada evento incluye `event`, `bookingId` y en logs `logger.info`/`logger.error`.
- **Placeholders:** Un solo punto de sustitución por API real: `sendEmailPlaceholder` y `sendWhatsAppPlaceholder` en `notification.service.ts`.
- **Datos de contacto:** Se obtienen de la reserva con `client` y `caregiver.user` (email, phone) para enviar a la persona correcta.

Para dudas sobre el flujo de aprobación de cuidadores o del dueño (registro, perfil mascota), ver los otros docs referenciados en `README-RUN.md`.

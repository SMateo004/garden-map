# Pagos con Stripe — GARDEN

Este documento describe el flujo de pagos con **Stripe** (sustituye el anterior flujo con QR / Tigo Money / BNB).

---

## 1. Flujo de pago

1. **Cliente** tiene una reserva en estado `PENDING_PAYMENT` (creada por el flujo de bookings).
2. **Frontend** llama a `POST /api/payments/create-checkout-session` con `{ bookingId }` (y opcionalmente `successUrl`, `cancelUrl`).
3. **Backend** crea una [Stripe Checkout Session](https://docs.stripe.com/checkout) en modo `payment`, con el monto de la reserva en **BOB** (Bolivianos). Devuelve `{ sessionId, url }`.
4. **Frontend** redirige al usuario a `url` (página de pago de Stripe).
5. El usuario paga con tarjeta en Stripe; Stripe redirige a `successUrl` (ej. `/bookings/:id/success`).
6. **Stripe** envía un webhook `checkout.session.completed` a `POST /api/payments/webhook`.
7. **Backend** verifica la firma del webhook, actualiza la reserva a `CONFIRMED` y guarda `paidAt`. Opcional: enviar notificación (WhatsApp/email) al cuidador.

No hay “comprobar pago” manual: la confirmación es automática vía webhook.

---

## 2. Variables de entorno

| Variable | Obligatorio | Descripción |
|----------|-------------|-------------|
| `STRIPE_SECRET_KEY` | Sí (para pagos) | Clave secreta de Stripe (`sk_test_...` en test, `sk_live_...` en producción). |
| `STRIPE_PUBLISHABLE_KEY` | Sí (en frontend) | Clave pública (`pk_test_...` / `pk_live_...`) para el cliente. |
| `STRIPE_WEBHOOK_SECRET` | Sí (para webhook) | Secreto del webhook (`whsec_...`) para verificar eventos. |

Si `STRIPE_SECRET_KEY` no está definida o no empieza por `sk_`, el backend no crea sesiones de pago y devuelve error al llamar a create-checkout-session.

---

## 3. Endpoints

### `POST /api/payments/create-checkout-session`

- **Auth:** Bearer JWT (cliente dueño de la reserva).
- **Body:** `{ "bookingId": "uuid", "successUrl?: "https://...", "cancelUrl?: "https://..." }`
- **Respuesta 200:** `{ "success": true, "data": { "sessionId": "...", "url": "https://checkout.stripe.com/..." } }`
- **Uso en frontend:** redirigir al usuario a `data.url`.

### `POST /api/payments/webhook`

- **Auth:** Ninguna. Stripe firma el cuerpo con `STRIPE_WEBHOOK_SECRET`.
- **Body:** Raw (Stripe envía JSON). El servidor debe usar el cuerpo sin parsear para verificar la firma; por eso esta ruta usa `express.raw()` y no `express.json()`.
- **Eventos manejados:** `checkout.session.completed` → se marca la reserva como pagada y `CONFIRMED`.

---

## 4. Modelo de datos (Prisma)

En `Booking` se usan:

- `stripeCheckoutSessionId`: ID de la sesión de Checkout (único).
- `stripePaymentIntentId`: ID del PaymentIntent (opcional, para referencia).
- `paidAt`: fecha/hora en que se confirmó el pago (vía webhook).
- `status`: pasa a `CONFIRMED` cuando se recibe el webhook.

Los campos antiguos de QR (`qrId`, `qrImageUrl`, `qrExpiresAt`) fueron reemplazados por el flujo Stripe.

---

## 5. Frontend (resumen)

- Obtener `STRIPE_PUBLISHABLE_KEY` por env (ej. `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` o `VITE_STRIPE_PUBLISHABLE_KEY`).
- Tras crear la reserva (o desde la página de la reserva pendiente):
  - Llamar a `POST /api/payments/create-checkout-session` con `bookingId`.
  - Redirigir a `data.url` (por ejemplo `window.location.href = data.url`).
- Página de éxito: URL configurada como `successUrl` (ej. `/bookings/[id]/success`). Mostrar mensaje de “Pago realizado” y/o redirigir al detalle de la reserva.
- Página de cancelación: `cancelUrl` (ej. `/bookings/[id]`) para que el usuario pueda reintentar o cambiar de opción.

No es necesario integrar Stripe.js en el frontend para este flujo: basta con la redirección a Checkout.

---

## 6. Despliegue y webhook

1. **URL del webhook:** debe ser HTTPS en producción, por ejemplo:  
   `https://api.garden.bo/api/payments/webhook`
2. **Configurar en Stripe Dashboard:** Developers → Webhooks → Add endpoint → URL anterior. Evento: `checkout.session.completed`.
3. **Secreto:** Stripe muestra `whsec_...`; configurarlo como `STRIPE_WEBHOOK_SECRET` en el backend.
4. **Pruebas:** En desarrollo se puede usar [Stripe CLI](https://stripe.com/docs/stripe-cli) para reenviar eventos al local:  
   `stripe listen --forward-to localhost:3000/api/payments/webhook`  
   y usar el `whsec_...` que devuelve el CLI como `STRIPE_WEBHOOK_SECRET` en `.env` local.

---

## 7. Moneda y montos

- Los importes en la base de datos están en **Bolivianos (Bs)**.
- Stripe recibe el monto en **centavos** para BOB (1 Bs = 100 centavos). El backend convierte: `amountCentavos = totalAmount * 100`.
- Stripe soporta la moneda [BOB](https://docs.stripe.com/currencies#obsolete-currencies) (Bolivian Boliviano).

---

## 8. Migración desde QR / banco

- Se eliminaron `qrId`, `qrImageUrl`, `qrExpiresAt` del schema de `Booking`.
- Se añadieron `stripeCheckoutSessionId` y `stripePaymentIntentId`.
- Ejecutar migración de Prisma tras el cambio de schema:  
  `npx prisma migrate dev --name replace_qr_with_stripe`

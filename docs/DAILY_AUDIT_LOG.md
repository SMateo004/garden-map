# Registro de auditoría diaria automatizada

Este archivo lo mantiene una rutina automática (Claude) que corre una vez al día sobre este
repo. Cada entrada documenta qué área se auditó, qué se encontró, qué se arregló y pusheó solo
(bajo riesgo) y qué quedó pendiente de aprobación humana (alto riesgo: dinero, auth, verificación
de identidad). Primera corrida: no había entradas previas.

---

## 2026-09-24 — Flujos de dinero: recuperación de deuda previa (QR / SIP)

**Commit de referencia al iniciar la auditoría:** `0c7c521` (fix: corregir verificación de
teléfono y habilitarla también para clientes)

**Área auditada:** lógica de pagos y balance (`garden-api/src/modules/payment-service/`,
`garden-api/src/modules/booking-service/booking.service.ts`, `garden-api/src/modules/wallet/`,
`garden-api/src/modules/referral/`, `garden-api/src/modules/promo-code/`). Elegida porque los
commits recientes (`git log`) ya habían tocado y cerrado carreras de datos en retiros, disputas y
canje de gift codes, pero no la recuperación de deuda previa por QR/SIP, que toca `User.balance`
directamente.

Se revisó también `referral.service.ts` y `promo-code.service.ts` (créditos/cupos con posible
doble-canje) — ambos están bien: usan el patrón de "claim atómico" (`updateMany` con condición +
`increment`) ya establecido en el proyecto. Sin hallazgos ahí.

### Hallazgo (ALTO RIESGO — no aplicado, solo reportado)

**Dónde:**
- `garden-api/src/modules/payment-service/payment.service.ts:332-348` (confirmación de pago por
  QR, `verifyPaymentByQr` o equivalente)
- `garden-api/src/modules/payment-service/payment.service.ts:547-563` (callback de confirmación
  SIP)
- Expuesto al usuario en `garden-api/src/modules/wallet/wallet.routes.ts:105` (`balance:
  Number(t.balance)` en el historial de transacciones) y renderizado en
  `garden-app/lib/screens/wallet/wallet_screen.dart:1761` (el número chico bajo el monto de cada
  transacción — "saldo después de esta transacción").

**Qué pasa:** cuando un cliente tiene saldo negativo (deuda por tiempo extra de un servicio
anterior), `initPayment()` en `booking.service.ts:1553-1555` calcula `debtAmount = |saldo actual|`
**en el momento de generar el QR/SIP** y lo graba en `booking.debtRecoveryAmount`. El monto del QR
incluye ese debtAmount. Cuando el pago se confirma —potencialmente minutos u horas después, ya
que la confirmación SIP es un callback asíncrono del banco y el QR tiene una ventana de validez—
el código hace:

```ts
await tx.user.update({
  where: { id: booking.clientId },
  data: { balance: { increment: debtRecovery } },
});
await tx.walletTransaction.create({
  data: { ..., balance: 0, /* balance se zerificó */ ... },
});
```

El incremento en sí es atómico (no hay lost update), pero el `balance: 0` grabado en el
`WalletTransaction` es un valor **hardcodeado**, no el saldo real resultante — asume que el saldo
del cliente seguía siendo exactamente `-debtRecovery` en el instante de la confirmación. Si entre
la generación del QR y su confirmación el cliente tuvo cualquier otro movimiento de saldo
(pagó otra reserva con billetera, recibió un bono de referido, canjeó un gift code, o acumuló
deuda de otro servicio con tiempo extra), el saldo real después de este incremento **no es cero**,
pero el historial de billetera que ve el cliente igual le muestra "Bs 0.00" como su saldo en ese
punto. Es un dato financiero incorrecto mostrado directamente al usuario, en el módulo de plata
más sensible de la app.

**Caso relacionado, mismo origen:** si el cliente inicia el pago de una segunda reserva *antes* de
que la primera confirme (ej. dos reservas QR pendientes en simultáneo), `initPayment()` para la
segunda reserva vuelve a leer el mismo saldo negativo (todavía no recuperado por la primera) y
vuelve a incluir el mismo `debtAmount` en el segundo QR. Si ambas confirman, la deuda se "recupera"
dos veces: el cliente termina pagando de más (el excedente) y su balance queda positivo en vez de
en cero, sin que nada en el código lo detecte o lo explique. El dinero no se pierde (el excedente
sí se acredita a su billetera), pero es una recuperación de deuda duplicada e inesperada que
tampoco quedaría bien reflejada en el ledger por el mismo bug de arriba.

**Propuesta de fix (no aplicada):** seguir el mismo patrón ya usado en
`booking.service.ts:1613-1618` (pago con billetera) y en `referral.service.ts:101-105` (bono de
referido): leer el `balance` real devuelto por el `update` (con `select: { balance: true }`) y
usar ese valor en el `WalletTransaction`, en vez de asumir `0`:

```ts
const updated = await tx.user.update({
  where: { id: booking.clientId },
  data: { balance: { increment: debtRecovery } },
  select: { balance: true },
});
await tx.walletTransaction.create({
  data: { ..., balance: Number(updated.balance), ... },
});
```

Para el caso de doble-recuperación (dos reservas con QR pendiente en simultáneo), considerar
recalcular la deuda a recuperar en el momento de la confirmación (con `SELECT ... FOR UPDATE`
sobre la fila del usuario, mismo patrón que `booking.service.ts:1547`) en vez de confiar en el
valor congelado en `booking.debtRecoveryAmount`, o cap­ear el incremento a
`Math.min(debtRecovery, Math.max(0, -saldoActualEnEseMomento))`.

**Por qué no se aplicó:** toca `User.balance` y el ledger de `WalletTransaction` directamente —
cae en la categoría de alto riesgo (dinero/balance/billetera) según la política de esta auditoría.
Queda para que el dueño del proyecto lo revise y decida el fix exacto (incluyendo si conviene
además re-conciliar manualmente algún `WalletTransaction.balance` ya grabado mal en producción).

### Sin cambios aplicados hoy
No se encontró ningún ítem de bajo riesgo (copy/texto, validación de UI, código muerto) durante
esta pasada — el foco quedó en profundidad sobre flujos de dinero en vez de cubrir más área. No
hubo commits de código; solo este log.

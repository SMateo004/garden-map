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

---

## 2026-09-25 — Política de cancelación/reembolsos (coherencia texto↔backend) y calificaciones

**Commit de referencia al iniciar la auditoría:** `2ab2fe2` (chore: registrar auditoría diaria
anterior).

**Área auditada:** coherencia entre lo que el backend realmente calcula como reembolso al
cancelar una reserva (`garden-api/src/modules/booking-service/booking.service.ts`,
`calculateRefund()`) y lo que la app le dice al usuario en dos lugares distintos
(`garden-app/lib/screens/legal/legal_screen.dart` y `garden-app/lib/data/help_center_content.dart`).
Elegida porque el propio CLAUDE.md señala explícitamente "plazos, montos, políticas que no
coinciden entre sí" como el tipo de bug a buscar, y esta área no se había tocado en los commits
recientes. También se revisó el sistema de calificaciones (ratings) buscando condiciones de
carrera.

### Hallazgo 1 (ALTO RIESGO — no aplicado, solo reportado): tres documentos de reembolso que no
concuerdan entre sí, y ninguno de los dos textos de la app describe bien lo que hace el código

**Lo que realmente hace el backend** (`booking.service.ts`, función `calculateRefund()` L2017-2086,
umbrales configurables vía `AppSettings`/`getBookingSettings()` L67-91, con estos defaults):
- `HOSPEDAJE` (L2027-2052, usa `booking.startDate`): >48h → 100% (menos cargo fijo Bs 10) · 24-48h
  → 50% (también con el cargo Bs 10 descontado) · <24h → 0%.
- **Cualquier otro `serviceType`** (`GUARDERIA`, `PASEO`, `VISITA_DOMICILIARIA`, `BAÑO_ESTETICA` —
  todos caen en la misma rama genérica, L2055-2086, usa `booking.walkDate` a mediodía, comentario
  explícito en L2055 dice "PASEO / GUARDERIA"): >12h → 100% · 6-12h → 50% · <6h → 0%. **No existe
  ninguna rama especial para Guardería ni para Baño y Estética** — ambas se tratan exactamente
  igual que un Paseo de 30 minutos.

**Lo que dice `legal_screen.dart`** (sección 7, "Política de cancelación y reembolsos", L308-324):
Hospedaje y Guardería juntos con >72h/24-72h/<24h (sin mencionar el cargo Bs 10); Paseo y Visita
domiciliaria con >12h/2-12h/<2h; y un tercer bloque "BAÑO Y ESTÉTICA" inventado con >24h 100% /
<24h 50% que no corresponde a ninguna rama real del código.

**Lo que dice `help_center_content.dart`** (L125-136): Hospedaje y Guardería juntos con
>48h/24-48h/<24h + cargo Bs 10 (coincide con la rama HOSPEDAJE del código); Paseo con >12h/6-12h/<6h
(coincide con la rama genérica). No menciona Visita domiciliaria ni Baño y Estética.

**El problema real:** los tres documentos (código, legal, ayuda) coinciden solo parcialmente entre
sí, y ninguno de los dos textos de la app refleja correctamente que **Guardería usa el umbral corto
de 12h/6h, no el largo de 48h/24h** — ambos textos prometen al usuario el trato "hospedaje" para
Guardería cuando el código en realidad la trata como un paseo. Ejemplo concreto: un cliente que
cancela una Guardería 30 horas antes, leyendo cualquiera de los dos textos, espera 100% (está
dentro de la ventana ">24h"/">48h" que ambos documentos prometen) pero el código ya la puso en la
rama <12h→<6h... en este caso 30h > 12h así que sí le da 100% igual, pero el punto de quiebre real
está en otro lado (12h/6h) que no coincide con el que el usuario cree que aplica (48h/24h) — un
cliente que cancela a las 20h antes de una Guardería cree (por ambos textos) que tiene garantizado
al menos 50% y en realidad, según el código, ya está en la rama <12h → sin reembolso. Es una
promesa de reembolso incumplida por diseño, en el módulo de dinero más sensible del negocio, y
además el bloque "Baño y Estética" en `legal_screen.dart` describe una política que simplemente no
existe en el código.

**No se aplicó ningún cambio** porque esto es, sin ambigüedad, un tema de dinero/reembolsos — cae
en la categoría de alto riesgo de esta auditoría. Además no es un simple arreglo de texto: antes de
tocar nada hay que decidir cuál de los dos comportamientos es el intencional para Guardería y Baño
y Estética —
1. Si Guardería/Baño y Estética *deberían* tratarse como Hospedaje (parece lo más razonable dado
   que Guardería es una custodia de día completo, no un paseo de 30 min) → el bug está en
   `calculateRefund()` (falta una rama `GUARDERIA`/`BAÑO_ESTETICA` que use el umbral 48h/24h con
   `startDate`), y ahí sí hay que decidir con cuidado porque afecta montos ya cobrados/reembolsados
   en reservas pasadas.
2. Si el umbral corto (12h/6h) es el intencional para Guardería/Baño y Estética → el bug está en
   los dos textos de la app, que deben separar "Guardería" de "Hospedaje" y usar 12h/6h, y
   `legal_screen.dart` debe borrar el bloque "Baño y Estética" inventado (o alinearlo a 12h/6h
   también).
Cualquiera de las dos direcciones cambia lo que el usuario cobra o recibe, así que queda
completamente para que el dueño del proyecto decida antes de tocar código o copy.

### Hallazgo 2 (informativo, sin acción — no es un bug de carrera ni de validación)

Se revisó el flujo de calificaciones buscando condiciones de carrera: tanto
`confirmReceiptByClient()` (cliente califica a cuidador, `booking.service.ts` L4656-4831) como
`rateOwner()` (cuidador califica a cliente, L5226-5275) usan el patrón atómico ya establecido
(`updateMany` con condición de guarda + recálculo de promedio dentro de la misma `$transaction`,
p. ej. L4694-4704 y L5261-5268) — sin bugs ahí. Validación de rango 1-5 presente y consistente en
`booking.validation.ts` (L344-348, L367-371) y revalidada en el server.

Se notó sí una asimetría de diseño (no un bug): la calificación del cliente al cuidador se agrega
en `CaregiverProfile.rating`/`reviewCount` (schema L168-169) y alimenta tanto el matching/orden de
búsqueda como la auto-suspensión por rating bajo (`maybeAutoSuspendForLowRating()`, L4843+),
mientras que la calificación del cuidador al cliente (`Booking.caregiverRating`, schema L677/691)
no tiene ningún campo agregado equivalente en `ClientProfile` ni ningún efecto downstream — solo se
calcula ad-hoc en el panel de admin (`admin.service.ts` L2733-2746). Puede ser intencional (los
clientes no compiten por "matching" como los cuidadores), así que se deja solo como observación
para que el dueño del proyecto confirme si es el comportamiento esperado — no se propone ni se
aplica ningún cambio.

### Sin cambios aplicados hoy
Ambos hallazgos caen en zona de dinero/diseño de producto — no se tocó código ni copy. Solo se
actualiza este log.

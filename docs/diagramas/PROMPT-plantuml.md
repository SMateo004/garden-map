# Prompt para generar los diagramas de GARDEN en PlantUML

Copiá el bloque de abajo en cualquier asistente (Claude, ChatGPT, etc.). Ya trae todo el
contexto funcional; no hace falta pasarle código.

```text
Actúa como analista funcional. Genera diagramas en PlantUML (sintaxis válida, un bloque
@startuml/@enduml por diagrama, textos en español, sin términos técnicos de programación)
para GARDEN, un marketplace de cuidado de mascotas en Santa Cruz de la Sierra, Bolivia.

PERFILES
- Dueño de mascota: se registra (verifica teléfono), crea PIN, registra mascotas, busca
  cuidadores por servicio/zona/precio, guarda favoritos, lista de espera, reserva, Meet &
  Greet opcional, paga (billetera, QR bancario o mixto; código promo, donación, NIT),
  reservas recurrentes, chatea, sigue el servicio en vivo (GPS, fotos, bitácora), SOS,
  extiende el servicio, califica 1-5, propina, disputa, billetera (retiros, gift codes,
  tarjeta de donador), referidos, veterinarias cercanas, soporte.
- Cuidador (individual con asistente de 12 pasos; profesional con código del admin;
  empresa con código y 14 pasos): verifica identidad (selfie + carnet + prueba de vida,
  3 intentos), teléfono y correo, contrato, PIN; queda en revisión; el admin aprueba,
  rechaza o pide correcciones. Luego: antecedentes (revisa IA; si es dudoso, admin),
  capacitaciones obligatorias si no tiene experiencia, NIT si es empresa. Acepta/rechaza
  reservas (3 h), reserva instantánea opcional, Meet & Greet, gestiona el servicio con
  PIN (en camino, llegué, inicia con foto, GPS, bitácora, incidentes, termina con foto),
  califica al dueño, reporta ausencia del dueño, responde disputas, cobra y retira.
- Empresa: además tiene Recepción (clientes de mostrador sin app, entradas/salidas,
  efectivo que no pasa por GARDEN) y Equipo (invita empleados con código de un solo uso).
- Empleado de empresa: opera reservas y recepción, sin billetera propia.
- Administrador: aprueba cuidadores, pagos QR manuales, retiros; resuelve disputas que la
  IA no pudo y apelaciones; emergencias; comisiones e impuestos; códigos; notificaciones
  masivas; banners; ciudades/zonas; verificaciones; finanzas, analítica, auditoría.
- Externos: Banco (confirma QR), Agentes de IA (juez de disputas, bot de soporte,
  antecedentes), Refugios (reciben donaciones), Veterinarias aliadas.

ESTADOS DE UNA RESERVA
Pendiente de Meet & Greet → Pendiente de pago → (Pago en revisión si el dueño avisa "Ya
realicé el pago" sin confirmación del banco: lo aprueba o rechaza un admin; si nadie lo revisa
antes de que venza el código se aprueba solo y se verifica después — si no llegó, se descuenta
de la billetera del dueño) → Esperando al cuidador → Confirmada → En curso → Completada.
Rechazar el pago en revisión vuelve a Pendiente de pago.
Salidas: Rechazada por el cuidador (reembolso 100%), Meet & Greet incompatible (cancelada,
reembolso 100%), Cancelada (cuidador no responde en
3 h → 100%; QR vencido; cancelación del dueño según anticipación; cancelación del
cuidador 100% + infracción; nadie inicia en 30 min = no-show), Conflicto de horario (el
dueño elige otra fecha o reembolso; 72 h para decidir).

DINERO
Total = precio del cuidador + comisión (el dueño no ve la comisión). Impuestos IVA 13 + IT 3
(16%) EN PAUSA: solo se suman si el admin los aprueba con un switch; mientras tanto no se
cobran ni se mencionan. Cuidador recibe total − comisión − impuestos (0 en pausa). Paseo de
30 o 60 min, al precio que fija el cuidador para cada duración. GARDEN retiene el dinero hasta
que el dueño califica 3-5 (se libera), 1-2 (se retiene y abre disputa) o pasan 24 h
(se libera solo). Reembolsos: hospedaje/guardería >48h 100% menos Bs 10, 24-48h 50%,
<24h 0%; paseo >12h 100%, 6-12h 50%, <6h 0%. Retiros mínimo Bs 50, los procesa un admin.

DISPUTAS
Origen: calificación 1-2 o no-show (24 h para reclamar). Una parte da razones, la otra
responde (72 h; si no, pasa al admin). El juez de IA revisa fotos, GPS, bitácora y chat.
Veredictos: gana el dueño (reembolso total), gana el cuidador (cobra su neto), parcial
(80% al cuidador, código del 20% al dueño). Si la IA falla, decide un admin. Apelación:
veredicto final del admin.

SANCIONES AUTOMÁTICAS
3 cancelaciones tardías en 90 días → suspensión que se levanta sola a los 30 días.
5 calificaciones de 1-2 estrellas → suspensión hasta que un admin la levante.

GENERA:
1. Diagrama de casos de uso con todos los actores y sus relaciones.
2. Diagrama de estados de la reserva con el actor de cada transición.
3. Diagrama de actividad con carriles (Dueño | GARDEN | Banco | Cuidador | Admin) de una
   reserva de punta a punta.
4. Diagrama de actividad del alta y vida del cuidador.
5. Diagrama de actividad de disputas.
6. Diagrama del flujo del dinero.
Usa skinparam shadowing false y nombres cortos. No inventes funciones que no estén arriba.
```

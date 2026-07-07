# Contenido para formularios de privacidad — App Store y Play Store

Copiar/pegar directo en las consolas. Basado en lo que la app realmente recolecta
(revisado en el código, no genérico). Actualizar si agregan una integración nueva
que toque datos personales.

---

## 1. Google Play Console → App content → Data safety

### ¿Recolecta o comparte datos de usuario?
**Sí.**

### Categorías de datos

| Categoría | Dato | ¿Recolectado? | ¿Compartido? | Propósito |
|---|---|---|---|---|
| Ubicación | Ubicación aproximada | Sí | No | Funcionalidad de la app (mostrar cuidadores cercanos) |
| Ubicación | Ubicación precisa | Sí | No | Funcionalidad de la app (GPS en tiempo real durante paseos) |
| Información personal | Nombre | Sí | No | Funcionalidad de la app, cuenta |
| Información personal | Correo electrónico | Sí | No | Funcionalidad de la app, cuenta |
| Información personal | Número de teléfono | Sí | No | Funcionalidad de la app, cuenta, verificación (OTP) |
| Información personal | Dirección física | Sí | No | Funcionalidad de la app (dirección de servicio) |
| Información personal | ID del usuario / documento de identidad | Sí (solo cuidadores, CI boliviana) | No | Verificación de identidad |
| Fotos y videos | Fotos | Sí | No | Funcionalidad de la app (perfil, mascota, evidencia de servicio) |
| Fotos y videos | Videos | Sí (opcional) | No | Funcionalidad de la app (evidencia de servicio) |
| Información financiera | Información de pago | Sí | No | Procesamiento de pagos de reservas |
| Mensajes | Otros mensajes en la app | Sí (chat cliente-cuidador) | No | Funcionalidad de la app |
| Identificadores del dispositivo u otros | ID de dispositivo | Sí (token FCM) | No | Notificaciones push |
| Registros de la app | Registros de fallos/diagnóstico | Sí (Sentry) | No | Analíticas/mantenimiento |

### ¿Los datos se cifran en tránsito?
**Sí** (HTTPS/TLS en toda comunicación con el backend).

### ¿Puede el usuario solicitar que se elimine su información?
**Sí** — desde la app (Perfil → Eliminar cuenta) o escribiendo a
`contactogardenbo@gmail.com` / `privacidad@garden.bo`.

### ¿Estos datos son necesarios o el usuario puede optar por no compartirlos?
Todos los datos personales listados son **necesarios** para usar la app (es un
marketplace de servicios reales, no hay modo "anónimo"). La ubicación precisa solo
se activa durante un paseo en curso.

### Terceros con los que se comparte información (para tu referencia, no van
todos en el formulario público, pero deben estar en la Política de Privacidad):
- Cloudinary (almacenamiento de imágenes)
- Firebase (notificaciones push, autenticación)
- Resend (emails transaccionales)
- AWS Rekognition (verificación de identidad / liveness)
- Anthropic (Claude — análisis automatizado de fotos y evidencia de disputas)
- Sentry (monitoreo de errores)
- Google Sign-In / Facebook Login / Sign in with Apple (autenticación social)

---

## 2. App Store Connect → App Privacy (Nutrition Label)

Para cada tipo de dato, Apple pregunta: ¿se usa para **rastrearte** (Tracking),
para **vincular a tu identidad** (Linked to you), o **no vinculado** (Not linked)?

| Tipo de dato | ¿Recolectado? | Vinculado a tu identidad | Usado para tracking |
|---|---|---|---|
| Ubicación precisa | Sí | Sí | No |
| Ubicación aproximada | Sí | Sí | No |
| Nombre | Sí | Sí | No |
| Número de teléfono | Sí | Sí | No |
| Dirección de correo | Sí | Sí | No |
| Dirección física | Sí | Sí | No |
| Fotos o videos | Sí | Sí | No |
| Información de pago | Sí | Sí | No |
| Historial de compras (reservas) | Sí | Sí | No |
| Contenido de mensajes (chat) | Sí | Sí | No |
| Identificadores de usuario (ID de cuenta) | Sí | Sí | No |
| Identificadores de dispositivo (token push) | Sí | Sí | No |
| Datos de diagnóstico (crash logs vía Sentry) | Sí | No | No |

**Tracking**: marcar **"No usamos datos para rastrear"** — Garden no comparte datos
con brokers de datos ni los usa para publicidad cruzada entre apps/sitios de
terceros. (Si en el futuro agregan píxeles de Meta/TikTok Ads con fines
publicitarios, esto cambiaría y requeriría el prompt de ATT — `NSUserTrackingUsageDescription`).

**Nota sobre login social**: como usan Google/Facebook/Apple login, Apple podría
preguntar por datos que esos SDKs recolectan — declarar igual que arriba (nombre,
email vinculados a la cuenta).

---

## 3. Notas para la sección "App Review Information" (ambas tiendas)

Pegar como nota para el revisor (traducido/adaptado según el campo de cada consola):

> Garden es un marketplace de servicios reales de cuidado de mascotas en Bolivia
> (paseos, hospedaje, guardería). No vende bienes digitales ni contenido dentro
> de la app, por lo que los pagos se procesan fuera del sistema de compras
> integradas de la tienda (esto aplica la excepción de "bienes y servicios
> físicos/reales" de las guías de Apple 3.1.1 y la política equivalente de Google
> Play sobre pagos).
>
> El pago se confirma mediante QR bancario o, mientras se completa la integración
> directa con el banco, mediante verificación manual del equipo de Garden mediante
> el mismo flujo (no hay diferencia visible para el usuario, la revisión manual es
> transparente para el flujo de pago).
>
> Cuentas de prueba:
> - Admin: reviewer.admin@gardenbo.com / ReviewGarden2026!
> - Cliente: reviewer.cliente@gardenbo.com / ReviewGarden2026!
> - Cuidador (verificado): reviewer.cuidador@gardenbo.com / ReviewGarden2026!
>
> Para probar el flujo completo de reserva y pago como Cliente, y el flujo de
> aceptación de servicio como Cuidador, usar las dos últimas cuentas. La cuenta
> Admin permite ver el panel de administración (aprobación de pagos, disputas,
> gestión de cuidadores).

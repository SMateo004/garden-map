# GARDEN MVP — Contexto del Proyecto

> Documento de referencia rápida para nuevas sesiones de desarrollo, onboarding e IA.
> Actualizado: 2026-04-07

---

## Nombre y objetivo

**GARDEN** es un marketplace boliviano de servicios de cuidado de mascotas (paseadores y hospedadores). Conecta dueños de mascotas con cuidadores verificados mediante:

- Registro y aprobación de cuidadores con verificación de identidad por IA (AWS Rekognition + Textract)
- Reservas con flujo completo de pago, escrow virtual y calificaciones
- Registro inmutable en blockchain (Polygon) de servicios y reputación
- Precios dinámicos por zona sugeridos por un agente de IA (Claude)
- App móvil (Flutter), panel web (React) y API REST (Node.js/TypeScript)

---

## Tecnologías principales

| Capa | Tecnología | Por qué |
|---|---|---|
| Mobile | Flutter (Dart 3.7+) | Cross-platform iOS/Android, una sola base de código |
| Web | React 18 + Vite + TypeScript + Tailwind CSS | Admin y caregiver dashboard en web |
| Backend | Node.js + Express + TypeScript | Ecosistema amplio, tipado estático |
| ORM / DB | Prisma 5 + PostgreSQL 15 | Migrations, type-safety, relaciones complejas |
| Auth | JWT (access + refresh) | Stateless, compatible con mobile y web |
| Pagos | Stripe API (BOB/fiat) | Única integración de pago internacional disponible en Bolivia |
| Imágenes | Cloudinary CDN | Persistencia en la nube (Render tiene filesystem efímero) |
| Archivos / IA | AWS S3 + Rekognition + Textract | Reconocimiento facial y OCR de documentos de identidad |
| Blockchain | Ethers.js → Polygon Amoy (testnet) | Escrow virtual y reputación inmutable on-chain |
| Smart Contracts | Solidity 0.8.19+ | GardenEscrow, GardenProfiles, GardenBooking |
| IA / Agentes | Anthropic Claude (`claude-sonnet-4-6`) | Precios dinámicos, disputas, sugerencias de onboarding |
| Real-time | Socket.io | Chat entre dueño y cuidador durante servicio |
| Email | Resend + Nodemailer | Verificación de email, notificaciones de reserva |
| Logs | Winston | Structured logging en producción (Render) |
| Deploy | Render.com (API) | Backend + PostgreSQL gestionados |
| Dev DB | Docker (PostgreSQL + Adminer) | Entorno local |

---

## Estructura de carpetas

```
garden-mvp/
├── garden-api/                  # Backend Node.js/Express/TypeScript
│   ├── src/
│   │   ├── modules/             # 17 módulos de funcionalidad
│   │   │   ├── admin/           # Panel de administración
│   │   │   ├── agentes/         # Monitoreo de agentes IA
│   │   │   ├── auth/            # Autenticación JWT + email
│   │   │   ├── booking-service/ # Reservas completas (ciclo de vida)
│   │   │   ├── caregiver-profile/ # Perfil + wizard de registro
│   │   │   ├── caregiver-service/ # Marketplace, búsqueda, listing
│   │   │   ├── chat/            # Mensajería in-app (Socket.io)
│   │   │   ├── client-profile/  # Perfil dueño + mascotas
│   │   │   ├── dispute/         # Resolución de conflictos
│   │   │   ├── identity/        # Verificación de identidad
│   │   │   ├── meet-and-greet/  # Coordinación de reuniones previas
│   │   │   ├── notification-service/ # Notificaciones push + in-app
│   │   │   ├── payment-service/ # Pagos Stripe + webhooks
│   │   │   ├── upload/          # Subida de imágenes (Cloudinary)
│   │   │   ├── user-service/    # Gestión de usuarios
│   │   │   ├── verification/    # IA: OCR, facial recognition, liveness
│   │   │   └── wallet/          # Billetera y transacciones del cuidador
│   │   ├── agents/              # Agentes IA autónomos
│   │   │   ├── precios.agent.ts # Precios dinámicos por zona (Claude)
│   │   │   └── reputacion.agent.ts # Scoring de reputación
│   │   ├── services/            # Servicios transversales
│   │   │   ├── blockchain.service.ts # Sync on-chain (Polygon)
│   │   │   └── claude.service.ts     # Wrapper Anthropic SDK
│   │   ├── middleware/          # Auth, CORS, logging, error handling
│   │   ├── config/              # DB, Cloudinary, env, vars
│   │   ├── shared/              # Async handler, errores, tipos
│   │   └── jobs/                # Cron jobs (ajuste de precios nocturno)
│   ├── contracts/               # Smart Contracts Solidity
│   │   ├── GardenEscrow.sol     # Escrow virtual + estados de reserva
│   │   ├── GardenProfiles.sol   # Identidades verificadas on-chain
│   │   └── GardenBooking.sol    # Registro de reservas + ratings
│   ├── prisma/
│   │   ├── schema.prisma        # Esquema completo (~700 líneas)
│   │   ├── migrations/          # 8 migraciones secuenciales
│   │   └── seed.ts              # Datos de prueba
│   └── hardhat-garden/          # Entorno Hardhat para deploy de contratos
│
├── garden-app/                  # App móvil Flutter
│   └── lib/
│       ├── screens/
│       │   ├── admin/           # Panel admin (6 pantallas)
│       │   ├── auth/            # Login + registro
│       │   ├── caregiver/       # Wizard 9 pasos, home, perfil, verificación
│       │   ├── client/          # Home, listing, reservas, mascotas
│       │   ├── service/         # Ejecución de servicio, GPS, fotos
│       │   ├── chat/            # Mensajería
│       │   ├── profile/         # Perfil, cuenta, configuración
│       │   ├── wallet/          # Billetera del cuidador
│       │   └── dispute/         # Disputa entre usuarios
│       ├── widgets/             # Componentes reutilizables
│       │   ├── pet_profile_sheet.dart  # Perfil mascota (bottom sheet)
│       │   └── garden_empty_state.dart # Estados vacíos
│       ├── theme/
│       │   └── garden_theme.dart # Colores, tipografía, fixImageUrl, GardenAvatar
│       └── main.dart            # Entry point + GoRouter
│
├── garden-web/                  # Panel web React
│   └── src/
│       ├── pages/               # 25+ páginas (admin, caregiver, client, auth)
│       ├── components/          # 26 componentes reutilizables
│       ├── api/                 # Cliente Axios + endpoints
│       ├── hooks/               # 21 custom hooks
│       └── contexts/            # Contextos de React
│
├── docs/                        # Documentación en español
│   ├── FLUJO-RESERVA-Y-NOTIFICACIONES.md
│   ├── FLUJO-APROBACION-CUIDADOR.md
│   ├── DISPONIBILIDAD-CUIDADOR.md
│   └── ... (12 archivos total)
│
├── contracts/                   # Contratos Solidity (copia raíz)
├── hardhat-garden/              # Hardhat en raíz
├── docker-compose.yml           # PostgreSQL + Adminer local
├── README-RUN.md                # Guía completa de arranque local
└── PROJECT_CONTEXT.md           # Este archivo
```

---

## Actores del sistema

| Actor | Rol | Acceso |
|---|---|---|
| **Dueño (CLIENT)** | Crea reservas, gestiona mascotas, califica servicios | App Flutter + web |
| **Cuidador (CAREGIVER)** | Se registra, ofrece servicios, acepta reservas, cobra | App Flutter |
| **Administrador (ADMIN)** | Aprueba cuidadores, resuelve disputas, configura precios | Panel web + app Flutter |
| **Sistema / IA** | Sugiere precios, verifica identidad, registra en blockchain | Automático (cron + webhooks) |

---

## Descripción de módulos

### Verificación de identidad (IA + Blockchain)
Flujo de 3 pasos: selfie en vivo → foto CI frontal → foto CI dorsal.
- `verification/verification.service.ts` — Orquesta el flujo completo
- `verification/rekognition.service.ts` — AWS Rekognition: comparación facial selfie↔CI
- `verification/ocr.service.ts` — AWS Textract: extrae nombre/CI del documento
- `verification/liveness.service.ts` — Detección de vida (pasiva/activa)
- `verification/fraud.service.ts` — Scoring de fraude + device fingerprinting
- Al aprobar: `blockchain.service.ts` sincroniza el estado on-chain en `GardenProfiles`

### Marketplace de cuidadores
- `caregiver-service/` — Búsqueda por zona, servicio, precio, disponibilidad
- `caregiver-profile/` — Wizard de registro de 9 pasos, perfil editable post-aprobación
- Filtros: zona (NORTE/SUR/CENTRO/ESTE/OESTE), tipo de servicio (PASEO/HOSPEDAJE), tamaño de mascota
- Imágenes servidas desde Cloudinary

### Reservas + Escrow
Ciclo de vida: `PENDING_PAYMENT → WAITING_CAREGIVER_APPROVAL → CONFIRMED → IN_PROGRESS → COMPLETED`
- `booking-service/booking.service.ts` — Lógica completa de reservas
- `booking-service/booking.controller.ts` — Endpoints REST
- `payment-service/` — Stripe: Payment Intent → webhook → confirma reserva
- `GardenEscrow.sol` — Estado inmutable on-chain (pagos son off-chain fiat)
- Wallet del cuidador: `wallet/` — Ganancias, comisión plataforma, historial

### Precios dinámicos (Claude IA)
- `agents/precios.agent.ts` — `sugerirPrecioOnboarding()`: sugiere precio al registrar cuidador; `calcularAjusteDinamico()`: cron nocturno ajusta precios por zona
- `jobs/` — Cron jobs usando `node-cron`
- Modelo: Claude `claude-sonnet-4-6` con respuestas JSON estructuradas
- `agentes/agentes.routes.ts` — Monitoreo de ejecuciones (`AgentLog` en DB)

### Ejecución de servicio (GPS + fotos)
- `service/service_execution_screen.dart` — App Flutter: tracking en tiempo real
- `service/gps_tracking_screen.dart` — GPS nativo (iOS/Android)
- El cuidador envía fotos del servicio → se suben a Cloudinary
- `GardenBooking.sol` — Finalización + rating registrados on-chain

### Chat en tiempo real
- `chat/chat.routes.ts` — Socket.io rooms por bookingId
- `chat/chat_screen.dart` — Interfaz Flutter bidireccional dueño ↔ cuidador

### Disputas
- `dispute/` — Flujo de disputa iniciado por dueño o cuidador
- Admin resuelve con o sin ayuda del agente de reputación (`reputacion.agent.ts`)
- Veredicto registrado en `GardenEscrow.sol` → `DisputeResolved` event on-chain

### Meet & Greet
- `meet-and-greet/` — Reunión previa al servicio coordinada en la app
- Estado: PENDING → CONFIRMED → COMPLETED

---

## Smart Contracts

**Red:** Polygon Amoy Testnet (Ethereum-compatible L2)
**Deploy:** Hardhat en `hardhat-garden/`

| Contrato | Archivo | Función |
|---|---|---|
| `GardenEscrow` | `contracts/GardenEscrow.sol` | Escrow virtual: estados de reserva, montos, resolución de disputas, ratings |
| `GardenProfiles` | `contracts/GardenProfiles.sol` | Identidades verificadas: userId, rol, estado de verificación, mascotas on-chain |
| `GardenBooking` | `contracts/GardenBooking.sol` | Registro de reservas: status, ratings acumulados por cuidador |

Variables de entorno requeridas:
```
BLOCKCHAIN_ENABLED=true
BLOCKCHAIN_RPC_URL=https://polygon-amoy.g.alchemy.com/v2/...
BLOCKCHAIN_PRIVATE_KEY=0x...
BLOCKCHAIN_CONTRACT_ADDRESS=0x...      # GardenEscrow
BLOCKCHAIN_PROFILES_ADDRESS=0x...     # GardenProfiles
```

---

## Archivos clave del backend

### Rutas principales
| Ruta base | Archivo |
|---|---|
| `/api/auth` | `src/modules/auth/auth.routes.ts` |
| `/api/caregiver` | `src/modules/caregiver-profile/caregiver-profile.routes.ts` |
| `/api/caregiver` (marketplace) | `src/modules/caregiver-service/caregiver.routes.ts` |
| `/api/booking` | `src/modules/booking-service/booking.routes.ts` |
| `/api/payment` | `src/modules/payment-service/payment.routes.ts` |
| `/api/admin` | `src/modules/admin/admin.routes.ts` |
| `/api/verification` | `src/modules/verification/verification.routes.ts` |
| `/api/client` | `src/modules/client-profile/client-profile.routes.ts` |
| `/api/notification` | `src/modules/notification-service/notification.routes.ts` |
| `/api/chat` | `src/modules/chat/chat.routes.ts` |
| `/api/wallet` | `src/modules/wallet/wallet.routes.ts` |
| `/api/dispute` | `src/modules/dispute/dispute.routes.ts` |
| `/api/meet-and-greet` | `src/modules/meet-and-greet/meet-and-greet.routes.ts` |
| `/api/upload` | `src/modules/upload/upload.routes.ts` |
| `/api/user` | `src/modules/user-service/user.routes.ts` |
| `/api/agentes` | `src/modules/agentes/agentes.routes.ts` |

### Controllers clave
| Módulo | Archivo |
|---|---|
| Auth (JWT, email verify) | `src/modules/auth/auth.controller.ts` |
| Reservas | `src/modules/booking-service/booking.controller.ts` |
| Ejecución de servicio | `src/modules/booking-service/service-execution.controller.ts` |
| Perfil cuidador | `src/modules/caregiver-profile/caregiver-profile.controller.ts` |
| Verificación identidad | `src/modules/verification/verification.controller.ts` |
| Mascotas | `src/modules/client-profile/client-pets.controller.ts` |
| Admin | `src/modules/admin/admin.controller.ts` |
| Upload (Cloudinary) | `src/modules/upload/upload.controller.ts` |

### Servicios y agentes
| Servicio | Archivo |
|---|---|
| Lógica de reservas | `src/modules/booking-service/booking.service.ts` |
| Perfil cuidador | `src/modules/caregiver-profile/caregiver-profile.service.ts` |
| Verificación IA | `src/modules/verification/verification.service.ts` |
| AWS Rekognition | `src/modules/verification/rekognition.service.ts` |
| AWS Textract OCR | `src/modules/verification/ocr.service.ts` |
| Blockchain sync | `src/services/blockchain.service.ts` |
| Claude wrapper | `src/services/claude.service.ts` |
| Precios dinámicos | `src/agents/precios.agent.ts` |
| Reputación | `src/agents/reputacion.agent.ts` |

---

## Archivos clave de Flutter

| Pantalla | Archivo |
|---|---|
| Entry point + rutas | `lib/main.dart` |
| Design system + fixImageUrl | `lib/theme/garden_theme.dart` |
| Home cuidador + reservas | `lib/screens/caregiver/caregiver_home_screen.dart` |
| Wizard registro cuidador | `lib/screens/caregiver/onboarding_wizard_screen.dart` |
| Perfil profesional (paso 7) | `lib/screens/caregiver/caregiver_profile_data_screen.dart` |
| Verificación identidad | `lib/screens/caregiver/verification_screen.dart` |
| Listing de cuidadores | `lib/screens/client/caregiver_listing_screen.dart` |
| Detalle cuidador | `lib/screens/client/caregiver_detail_screen.dart` |
| Crear reserva | `lib/screens/client/booking_creation_screen.dart` |
| Mis reservas (dueño) | `lib/screens/client/my_bookings_screen.dart` |
| Mascotas | `lib/screens/client/my_pets_screen.dart` |
| Ejecución servicio + GPS | `lib/screens/service/service_execution_screen.dart` |
| Chat | `lib/screens/chat/chat_screen.dart` |
| Billetera cuidador | `lib/screens/wallet/wallet_screen.dart` |
| Admin panel | `lib/screens/admin/admin_panel_screen.dart` |
| Admin revisión identidad | `lib/screens/admin/admin_identity_review_screen.dart` |
| Perfil mascota (sheet) | `lib/widgets/pet_profile_sheet.dart` |

---

## Base de datos (Prisma schema)

**Archivo:** `garden-api/prisma/schema.prisma`

Modelos principales:
- `User` — Auth base (email, rol: CLIENT/CAREGIVER/ADMIN)
- `CaregiverProfile` — Todo el perfil del cuidador (zona, precios, fotos, disponibilidad, estado de verificación)
- `ClientProfile` — Perfil del dueño
- `Pet` — Mascotas (photoUrl, extraPhotos, vaccinePhotos, documents, datos clínicos)
- `Booking` — Reserva con ciclo de vida completo
- `Availability` — Disponibilidad del cuidador por día y franja horaria
- `WalletTransaction` — Movimientos económicos
- `IdentityVerificationSession` — Resultados AWS
- `Review` — Calificaciones post-servicio
- `ServiceExecution` — Fotos y GPS del servicio activo
- `ChatMessage` — Mensajes en tiempo real
- `Dispute` — Conflictos y resoluciones
- `Notification` — Inbox de notificaciones
- `AgentLog` — Historial de ejecuciones de agentes IA

---

## Variables de entorno clave

```env
# Backend (garden-api/.env)
DATABASE_URL=postgresql://...
JWT_SECRET=...
STRIPE_SECRET_KEY=sk_...
CLOUDINARY_CLOUD_NAME=...
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1
BLOCKCHAIN_ENABLED=true
BLOCKCHAIN_RPC_URL=...
BLOCKCHAIN_PRIVATE_KEY=0x...
BLOCKCHAIN_CONTRACT_ADDRESS=0x...   # GardenEscrow
BLOCKCHAIN_PROFILES_ADDRESS=0x...   # GardenProfiles
ANTHROPIC_API_KEY=sk-ant-...
CLAUDE_MODEL=claude-sonnet-4-6
API_PUBLIC_URL=https://garden-api-1ldd.onrender.com
RESEND_API_KEY=re_...

# Flutter (--dart-define en build)
API_URL=https://garden-api-1ldd.onrender.com/api
```

---

## Notas de arquitectura importantes

- **Cloudinary-first para imágenes:** Todas las subidas de imágenes deben usar Cloudinary. El filesystem de Render es efímero (se borra en cada deploy). El helper `isCloudinaryConfigured()` en `src/config/cloudinary.ts` determina si usar nube o disco local.
- **`fixImageUrl()` en Flutter:** Convierte URLs `http://localhost:3000/...` a la URL pública del servidor. Las URLs de Cloudinary pasan sin cambio. Definida en `lib/theme/garden_theme.dart`.
- **`API_PUBLIC_URL` (no `API_BASE_URL`):** Variable de entorno correcta para construir URLs públicas de archivos locales en el backend.
- **`serviceAvailability` vs `serviceDetails.availability`:** Dos campos distintos en `CaregiverProfile`. El wizard guarda en ambos simultáneamente (paso 2). El marketplace lee de `serviceDetails.availability`.
- **Blockchain off-chain payments:** Los pagos son siempre fiat (Stripe). La blockchain solo registra estado, reputación y datos de confianza. No maneja fondos reales.
- **Wizard cuidador — 9 pasos (índice 0-8):**
  - 0: Servicios ofrecidos
  - 1: Zona y tipo de hogar
  - 2: Disponibilidad
  - 3: Fotos de servicio
  - 4: Perfil profesional (bio, precios, experiencia)
  - 5: Foto de perfil
  - 6: Verificación de email
  - 7: Verificación de identidad (IA)
  - 8: Revisión final
- **`_computeAndSetResumeStep()` + `_populateStateFromProfile()`:** El wizard consulta el backend al abrirse y pre-llena todos los campos con los datos guardados, reanudando en el paso correcto sin perder datos.

---

## Documentación interna

| Documento | Ruta | Contenido |
|---|---|---|
| Guía de arranque local | `README-RUN.md` | Setup completo: env, Docker, migrations, seed |
| Flujo de reservas | `docs/FLUJO-RESERVA-Y-NOTIFICACIONES.md` | Ciclo de vida completo + notificaciones |
| Flujo aprobación cuidador | `docs/FLUJO-APROBACION-CUIDADOR.md` | Estados del wizard + admin review |
| Disponibilidad | `docs/DISPONIBILIDAD-CUIDADOR.md` | Modelo de disponibilidad + sobreescrituras |
| Estado del MVP | `docs/ANALISIS-ESTADO-MVP-V2.md` | Qué está listo y qué falta |
| Pagos Stripe | `garden-api/docs/PAYMENTS_STRIPE.md` | Webhooks + Payment Intent flow |
| Schema perfil | `garden-api/docs/SCHEMA_PROFILES.md` | Detalle del modelo CaregiverProfile |
| Reset DB | `garden-api/prisma/README-RESET-DB-LIMPIO.md` | Procedimiento de reset limpio |

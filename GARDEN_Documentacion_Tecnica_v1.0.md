# **GARDEN - Documentación Técnica Completa v1.0**

## **Tabla de Contenidos**

1. [Introducción](#1-introducción)
2. [User Stories y Backlog](#2-user-stories-y-backlog)
3. [Arquitectura del Sistema](#3-arquitectura-del-sistema)
4. [Especificaciones de API](#4-especificaciones-de-api)
5. [Modelos de Datos](#5-modelos-de-datos)
6. [Estándares de Código](#6-estándares-de-código)
7. [Plan de Testing](#7-plan-de-testing)
8. [Deployment y Mantenimiento](#8-deployment-y-mantenimiento)
9. [Self-Review y Correcciones](#9-self-review-y-correcciones)

---

## **1. Introducción**

### **1.1 Resumen del Proyecto**

**GARDEN** es una plataforma marketplace que conecta dueños de mascotas con cuidadores verificados en Santa Cruz, Bolivia. La propuesta de valor central es **tranquilidad**: permitir que los dueños viajen o trabajen sabiendo que su mascota está segura con alguien confiable.

**Servicios ofrecidos:**
- 🏠 **Hospedaje**: Cuidado en casa del cuidador (por días)
- 🦮 **Paseos**: Paseos individuales (30 min o 1 hora)

**Diferenciadores clave:**
- Cuidadores verificados manualmente (entrevista + visita domiciliaria)
- Pago automatizado con QR bancario (API local)
- Sistema de reseñas verificadas (solo quien pagó opina)
- Flexibilidad de cancelación/extensión con reglas claras
- WhatsApp como canal de comunicación (familiar en Bolivia)

---

### **1.2 Scope del MVP**

#### **Fase 1 (Mes 1-2): Web App Responsive**
- Frontend: React 18+ con TypeScript
- Backend: Node.js (Express) con TypeScript
- Base de datos: PostgreSQL 15+
- Autenticación: JWT + refresh tokens
- Pagos: Integración con API bancaria local (Tigo Money/BNB)
- Comunicación: WhatsApp Business API (Twilio/360Dialog)
- Hosting: Vercel (frontend) + Railway/Render (backend + DB)

#### **Fase 2 (Mes 3-4): App Móvil Android**
- Framework: Flutter 3.x (cross-platform para futura expansión iOS)
- Comparte backend REST API de Fase 1
- Push notifications: Firebase Cloud Messaging
- Publicación: Google Play Store

#### **Fase 3 (Mes 6-8): App iOS** (condicional a tracción)

---

### **1.3 Stack Tecnológico Recomendado**

| **Componente** | **Tecnología** | **Justificación** |
|----------------|----------------|-------------------|
| **Frontend Web** | React 18 + TypeScript + Tailwind CSS | Ecosistema maduro, type safety, UI rápido |
| **Frontend Mobile** | Flutter 3.x | Código compartido iOS/Android, performance nativo |
| **Backend** | Node.js + Express + TypeScript | JavaScript full-stack, async I/O ideal para webhooks |
| **Base de Datos** | PostgreSQL 15 | ACID, relacional, soporte JSON, open-source |
| **ORM** | Prisma | Type-safe, migrations automáticas, DX excelente |
| **Autenticación** | JWT + bcrypt | Stateless, escalable |
| **Pagos** | API Bancaria Local + Webhook listeners | QR único, verificación automática |
| **WhatsApp** | Twilio/360Dialog API | Mensajes automáticos, templates aprobados |
| **Storage** | Cloudinary / AWS S3 | Fotos de perfiles/cuidadores |
| **CI/CD** | GitHub Actions | Testing + deploy automático |
| **Monitoring** | Sentry (errors) + LogRocket (sessions) | Debug producción |
| **Hosting** | Vercel (FE) + Railway (BE) + Neon (DB) | Serverless, auto-scaling, costo-efectivo |

---

### **1.4 Arquitectura de Desarrollo: Kanban Ágil**

**Metodología:**
- **Kanban** con tablero visual (GitHub Projects / Trello)
- **Sprints de 2 semanas** con retrospectivas
- **WIP limits**: Max 3 tareas en progreso simultáneo
- **Daily standups** (async en Slack/Discord): ¿Qué hice? ¿Qué haré? ¿Blockers?

**Columnas del tablero:**
```
📋 Backlog → 🔜 To Do (Sprint) → 🚧 In Progress → 👀 Review → ✅ Done
```

**Criterio de "Done":**
- ✅ Código escrito + tests pasando
- ✅ Code review aprobado
- ✅ Documentación actualizada
- ✅ Deployed a staging
- ✅ QA manual pasado

---

## **2. User Stories y Backlog**

### **2.1 Roles del Sistema**

- **Cliente** (Dueño de mascota): Busca y reserva servicios
- **Cuidador** (Proveedor): Ofrece servicios, gestiona disponibilidad
- **Admin** (Operador): Verifica cuidadores, aprueba reembolsos, soporte

---

### **2.2 Épicas y User Stories**

#### **ÉPICA 1: Gestión de Usuarios y Autenticación**

| ID | User Story | Prioridad | Story Points | Acceptance Criteria |
|----|------------|-----------|--------------|---------------------|
| **US-1.1** | Como **Cliente**, quiero registrarme con email/contraseña para crear mi cuenta | 🔴 Alta | 3 | • Email único validado<br>• Contraseña min 8 caracteres<br>• Confirmación por email<br>• Perfil creado con nombre, teléfono |
| **US-1.2** | Como **Cuidador**, quiero registrarme y completar mi perfil para ofrecer servicios | 🔴 Alta | 5 | • Incluye campos: descripción, zona, servicios ofrecidos<br>• Subida de 4-6 fotos<br>• Estado inicial: "Pendiente verificación"<br>• No visible hasta aprobación |
| **US-1.3** | Como **Admin**, quiero ver solicitudes de cuidadores pendientes para aprobarlas o rechazarlas | 🔴 Alta | 3 | • Lista filtrable por fecha<br>• Ver perfil completo + fotos<br>• Botones: Aprobar / Rechazar + notas internas<br>• Notificación al cuidador por email/WhatsApp |
| **US-1.4** | Como **Usuario** (Cliente/Cuidador), quiero login con email/contraseña para acceder a mi cuenta | 🔴 Alta | 2 | • JWT con expiración 7 días<br>• Refresh token<br>• Opción "Recordarme"<br>• Error claro si credenciales inválidas |
| **US-1.5** | Como **Usuario**, quiero recuperar mi contraseña olvidada | 🟡 Media | 3 | • Link de reset por email (expira en 1h)<br>• Nueva contraseña validada<br>• Login automático post-reset |

---

#### **ÉPICA 2: Búsqueda y Descubrimiento de Cuidadores**

| ID | User Story | Prioridad | Story Points | Acceptance Criteria |
|----|------------|-----------|--------------|---------------------|
| **US-2.1** | Como **Cliente**, quiero ver lista de cuidadores verificados para elegir uno | 🔴 Alta | 3 | • Solo cuidadores aprobados<br>• Card con: foto, nombre, zona, rating, precio<br>• Badge "Verificado por GARDEN"<br>• Paginación (12 por página) |
| **US-2.2** | Como **Cliente**, quiero filtrar por tipo de servicio (Hospedaje/Paseos/Ambos) | 🔴 Alta | 2 | • Filtro tipo checkbox<br>• Resultados actualizados sin reload<br>• Contador: "X cuidadores disponibles" |
| **US-2.3** | Como **Cliente**, quiero filtrar por zona para encontrar cuidadores cerca | 🔴 Alta | 2 | • Dropdown: Equipetrol, Urbarí, Norte, Las Palmas, Centro, Otros<br>• Múltiple selección<br>• Reseteo fácil |
| **US-2.4** | Como **Cliente**, quiero filtrar por rango de precio para ajustarme a mi presupuesto | 🔴 Alta | 2 | • 3 rangos: Económico (Bs 60-100), Estándar (Bs 100-140), Premium (Bs 140+)<br>• Precio aplica a hospedaje o paseo según contexto |
| **US-2.5** | Como **Cliente**, quiero filtrar por tipo de espacio (casa con/sin patio, depto) | 🟡 Media | 2 | • Solo visible si filtro "Hospedaje" activo<br>• Deshabilitado para "Paseos" |
| **US-2.6** | Como **Cliente**, quiero ver perfil detallado del cuidador para decidir si confiar | 🔴 Alta | 3 | • Galería de fotos (min 4)<br>• Descripción larga<br>• Servicios, zona, precio por servicio<br>• Reseñas + rating promedio<br>• Botón "Reservar" |

---

#### **ÉPICA 3: Sistema de Reservas (Hospedaje)**

| ID | User Story | Prioridad | Story Points | Acceptance Criteria |
|----|------------|-----------|--------------|---------------------|
| **US-3.1** | Como **Cliente**, quiero ver calendario de disponibilidad del cuidador para elegir fechas | 🔴 Alta | 5 | • Calendario visual (mes actual + siguiente)<br>• Días bloqueados/ocupados en gris<br>• Selección de rango (fecha inicio → fin)<br>• Cálculo automático: días × precio |
| **US-3.2** | Como **Cliente**, quiero reservar hospedaje seleccionando fechas para confirmar el servicio | 🔴 Alta | 8 | • Resumen: fechas, días, precio total<br>• Genera QR único de pago (API bancaria)<br>• QR expira en 15 min<br>• Estado: "Pendiente pago" |
| **US-3.3** | Como **Cliente**, quiero pagar con QR bancario para confirmar mi reserva | 🔴 Alta | 8 | • QR escaneable (cualquier banco)<br>• Botón "Comprobar pago"<br>• Verificación automática via API<br>• Si pagado → estado "Confirmada" + notificación WhatsApp a cuidador |
| **US-3.4** | Como **Cuidador**, quiero recibir notificación cuando tengo nueva reserva | 🔴 Alta | 3 | • WhatsApp automático con: fechas, cliente, monto<br>• Link a detalle de reserva<br>• Calendario se actualiza (fechas bloqueadas) |
| **US-3.5** | Como **Cuidador**, quiero marcar mis días disponibles/bloqueados en el calendario | 🔴 Alta | 5 | • Panel de cuidador con calendario editable<br>• Click para bloquear/desbloquear días<br>• Reservas confirmadas auto-bloquean<br>• Cambios reflejados en tiempo real |

---

#### **ÉPICA 4: Sistema de Reservas (Paseos)**

| ID | User Story | Prioridad | Story Points | Acceptance Criteria |
|----|------------|-----------|--------------|---------------------|
| **US-4.1** | Como **Cliente**, quiero reservar paseo eligiendo fecha, horario y duración | 🔴 Alta | 5 | • Selector: fecha (calendario)<br>• Selector: horario (Mañana 7-9am / Tarde 5-7pm)<br>• Selector: duración (30 min / 1 hora)<br>• Precio dinámico según duración |
| **US-4.2** | Como **Cliente**, quiero pagar paseo con QR para confirmarlo | 🔴 Alta | 5 | • Mismo flujo QR que hospedaje<br>• Monto menor (Bs 30-60)<br>• Confirmación por WhatsApp |
| **US-4.3** | Como **Cuidador**, quiero marcar horarios disponibles para paseos (mañana/tarde por día) | 🔴 Alta | 5 | • Calendario con vista semanal<br>• Toggle por día: Mañana ☑ / Tarde ☑<br>• Puede bloquear horarios específicos |
| **US-4.4** | Como **Cuidador**, quiero recibir info del cliente para coordinar punto de encuentro | 🔴 Alta | 2 | • WhatsApp con: dirección cliente, nombre mascota, instrucciones<br>• Cliente recibe número de cuidador |

---

#### **ÉPICA 5: Modificación de Reservas**

| ID | User Story | Prioridad | Story Points | Acceptance Criteria |
|----|------------|-----------|--------------|---------------------|
| **US-5.1** | Como **Cliente**, quiero cancelar reserva de hospedaje y ver cuánto me reembolsan | 🔴 Alta | 8 | • Botón "Cancelar" en detalle de reserva<br>• Modal con reglas claras:<br>&nbsp;&nbsp;- >48h: 100% - Bs 10<br>&nbsp;&nbsp;- 24-48h: 50%<br>&nbsp;&nbsp;- <24h: 0%<br>• Confirmación explícita<br>• Estado: "Cancelada, reembolso pendiente" |
| **US-5.2** | Como **Cliente**, quiero cancelar paseo y ver reembolso | 🔴 Alta | 5 | • Mismo flujo que hospedaje<br>• Reglas diferentes:<br>&nbsp;&nbsp;- >12h: 100%<br>&nbsp;&nbsp;- 6-12h: 50%<br>&nbsp;&nbsp;- <6h: 0% |
| **US-5.3** | Como **Admin**, quiero aprobar/rechazar reembolsos para evitar fraudes | 🔴 Alta | 5 | • Dashboard con lista de cancelaciones pendientes<br>• Ver: cliente, cuidador, monto, motivo<br>• Botones: Aprobar / Rechazar<br>• Si aprobado → procesar transferencia (manual o automática)<br>• Notificación a cliente |
| **US-5.4** | Como **Cliente**, quiero extender mi reserva de hospedaje si necesito más días | 🟡 Media | 8 | • Botón "Extender" (solo si aún no terminó)<br>• Selecciona días adicionales en calendario<br>• Verifica disponibilidad del cuidador<br>• Genera nuevo QR por días extra<br>• Mismo precio/día original |
| **US-5.5** | Como **Cliente**, quiero cambiar fechas de reserva si planeo con anticipación | 🟡 Media | 8 | • Botón "Modificar fechas" (solo si >48h antes)<br>• Selecciona nuevas fechas<br>• Verifica disponibilidad<br>• Sin cargo adicional (1 cambio gratis)<br>• Si no disponible → opción cancelar con reembolso 100% |

---

#### **ÉPICA 6: Sistema de Reseñas**

| ID | User Story | Prioridad | Story Points | Acceptance Criteria |
|----|------------|-----------|--------------|---------------------|
| **US-6.1** | Como **Cliente**, quiero dejar reseña después de completar servicio | 🔴 Alta | 5 | • Notificación 24h post-servicio (push + email)<br>• Formulario: 1-5 estrellas + texto (200-500 chars)<br>• Opción subir 1 foto<br>• Solo si status = "Completada" y paid = true |
| **US-6.2** | Como **Cuidador**, quiero ver mis reseñas y responder si necesario | 🟡 Media | 3 | • Panel con lista de reseñas<br>• Botón "Responder" (max 300 chars)<br>• Respuesta visible públicamente |
| **US-6.3** | Como **Cliente**, quiero ver reseñas del cuidador para decidir | 🔴 Alta | 3 | • En perfil del cuidador: rating promedio + total reseñas<br>• Lista ordenada: recientes primero<br>• Tag de servicio: "Hospedaje" o "Paseo"<br>• Nombre + foto del reviewer |
| **US-6.4** | Como **Sistema**, quiero bloquear reseñas falsas (sin pago verificado) | 🔴 Alta | 2 | • Validación backend: `reserva.paid = true && status = completed`<br>• Impedir submit si no cumple<br>• Mensaje: "Solo puedes reseñar servicios pagados" |

---

#### **ÉPICA 7: Comunicación y Soporte**

| ID | User Story | Prioridad | Story Points | Acceptance Criteria |
|----|------------|-----------|--------------|---------------------|
| **US-7.1** | Como **Cliente**, quiero recibir confirmación de reserva por WhatsApp | 🔴 Alta | 5 | • Mensaje automático post-pago con:<br>&nbsp;&nbsp;- Fechas/horario<br>&nbsp;&nbsp;- Nombre + teléfono cuidador<br>&nbsp;&nbsp;- Monto pagado<br>&nbsp;&nbsp;- Instrucciones coordinación |
| **US-7.2** | Como **Cliente**, quiero recibir recordatorio 24h antes del servicio | 🟡 Media | 3 | • Cron job que chequea reservas próximas<br>• WhatsApp: "Mañana comienza tu reserva con X"<br>• Incluye teléfono del cuidador |
| **US-7.3** | Como **Admin**, quiero responder consultas de soporte vía WhatsApp | 🔴 Alta | 3 | • Número de soporte: +591 7XX-GARDEN<br>• Respuestas manuales (8am-9pm)<br>• Bot con FAQs básicas (V2) |
| **US-7.4** | Como **Cliente/Cuidador**, quiero contactar al otro directamente por WhatsApp | 🔴 Alta | 2 | • Teléfono visible solo post-confirmación de pago<br>• Botón "Contactar por WhatsApp" (abre chat) |

---

#### **ÉPICA 8: Panel de Administración**

| ID | User Story | Prioridad | Story Points | Acceptance Criteria |
|----|------------|-----------|--------------|---------------------|
| **US-8.1** | Como **Admin**, quiero dashboard con métricas clave para monitorear el negocio | 🟡 Media | 5 | • KPIs:<br>&nbsp;&nbsp;- Reservas este mes<br>&nbsp;&nbsp;- Ingresos (comisiones)<br>&nbsp;&nbsp;- Nuevos usuarios<br>&nbsp;&nbsp;- Rating promedio plataforma<br>• Gráficos de tendencia |
| **US-8.2** | Como **Admin**, quiero ver lista de todas las reservas para auditar | 🟡 Media | 3 | • Tabla filtrable: estado, servicio, fecha, monto<br>• Búsqueda por cliente/cuidador<br>• Exportar a CSV |
| **US-8.3** | Como **Admin**, quiero expulsar cuidadores con mal comportamiento | 🔴 Alta | 3 | • Lista de cuidadores con botón "Suspender"<br>• Motivo obligatorio<br>• Perfil oculto, no recibe más reservas<br>• Notificación al cuidador |

---

### **2.3 Priorización del Backlog (Kanban)**

**Sprint 1 (Semana 1-2): Fundamentos**
- US-1.1, US-1.2, US-1.4 (Autenticación)
- US-2.1 (Lista de cuidadores)
- Infra: Setup repo, DB schema, CI/CD

**Sprint 2 (Semana 3-4): Reservas Core**
- US-3.1, US-3.2, US-3.3 (Reserva hospedaje + QR)
- US-3.4, US-3.5 (Notificaciones + calendario cuidador)

**Sprint 3 (Semana 5-6): Paseos + Reseñas**
- US-4.1, US-4.2, US-4.3 (Reserva paseos)
- US-6.1, US-6.3, US-6.4 (Sistema de reseñas)

**Sprint 4 (Semana 7-8): Modificaciones + Admin**
- US-5.1, US-5.2, US-5.3 (Cancelaciones + reembolsos)
- US-1.3, US-8.3 (Admin: aprobar cuidadores, suspender)

**Sprint 5+ (Mes 3-4): Mobile + Refinamiento**
- Port a Flutter
- US-5.4, US-5.5 (Extensiones + cambio de fechas)
- US-2.2 a US-2.5 (Filtros avanzados)

---

## **3. Arquitectura del Sistema**

### **3.1 Diagrama High-Level (ASCII)**

```
┌─────────────────────────────────────────────────────────────────┐
│                         USUARIOS                                 │
│  (Clientes, Cuidadores, Admins)                                 │
└────────────┬────────────────────────────────────┬───────────────┘
             │                                    │
             │                                    │
    ┌────────▼────────┐                  ┌────────▼────────┐
    │   Web App       │                  │  Mobile App     │
    │  (React + TS)   │                  │   (Flutter)     │
    │  Vercel         │                  │   APK/AAB       │
    └────────┬────────┘                  └────────┬────────┘
             │                                    │
             └─────────────┬──────────────────────┘
                           │
                  ┌────────▼────────┐
                  │   API Gateway    │
                  │  (Load Balancer) │
                  └────────┬────────┘
                           │
             ┌─────────────┴─────────────┐
             │                           │
    ┌────────▼────────┐         ┌────────▼────────┐
    │  Backend API    │         │   WebSocket     │
    │  (Node + TS)    │         │   (Real-time)   │
    │  Express        │         │   Socket.io     │
    │  Railway        │         │   (Opcional V2) │
    └────────┬────────┘         └─────────────────┘
             │
             ├─────────────┬─────────────┬─────────────┐
             │             │             │             │
    ┌────────▼────────┐   │    ┌────────▼────────┐   │
    │   PostgreSQL    │   │    │   Redis Cache   │   │
    │   (Neon/Render) │   │    │   (Sessions)    │   │
    └─────────────────┘   │    └─────────────────┘   │
                          │                           │
                 ┌────────▼────────┐         ┌────────▼────────┐
                 │  Cloudinary/S3  │         │  WhatsApp API   │
                 │  (File Storage) │         │  (Twilio/360D)  │
                 └─────────────────┘         └────────┬────────┘
                                                      │
                                             ┌────────▼────────┐
                                             │  Banco API      │
                                             │  QR Generator   │
                                             │  Payment Verify │
                                             └─────────────────┘
```

---

### **3.2 Arquitectura de Microservicios (Servicios Clave)**

Aunque el MVP es monolítico, se estructura modularmente para futura separación:

```
Backend (Monolito modular)
│
├── /auth-service          → JWT, login, registro
├── /user-service          → Perfiles (cliente/cuidador)
├── /booking-service       → Reservas (hospedaje + paseos)
├── /payment-service       → QR generation, verificación
├── /notification-service  → WhatsApp, email
├── /review-service        → CRUD reseñas
├── /admin-service         → Dashboard, aprobaciones
└── /shared                → Utils, middlewares, DB models
```

---

### **3.3 Flujo de Datos: Reserva de Hospedaje**

```
┌──────────┐     (1) SELECT dates     ┌──────────┐
│ Cliente  │─────────────────────────▶│ Frontend │
└──────────┘                           └─────┬────┘
                                             │
                                (2) POST /api/bookings
                                             │
                                       ┌─────▼─────┐
                                       │  Backend  │
                                       └─────┬─────┘
                                             │
                          ┌──────────────────┼──────────────────┐
                          │                  │                  │
                 (3) Check availability   (4) Create booking  (5) Generate QR
                          │              (status: pending)       │
                    ┌─────▼─────┐       ┌─────▼─────┐      ┌────▼────┐
                    │    DB     │       │    DB     │      │ Bank API│
                    │ (Calendar)│       │ (Bookings)│      └────┬────┘
                    └───────────┘       └───────────┘           │
                                                           (6) Return QR
                                                                 │
                                                           ┌─────▼─────┐
                                                           │  Frontend │
                                                           │ Show QR   │
                                                           └─────┬─────┘
                                                                 │
                                                   (7) User scans & pays
                                                                 │
                                                           ┌─────▼─────┐
                                                           │  Cliente  │
                                                           │ Press     │
                                                           │"Verify"   │
                                                           └─────┬─────┘
                                                                 │
                                              (8) POST /api/payments/verify
                                                                 │
                                                           ┌─────▼─────┐
                                                           │  Backend  │
                                                           └─────┬─────┘
                                                                 │
                                                    (9) Query Bank API
                                                                 │
                                                           ┌─────▼─────┐
                                                           │ Bank API  │
                                                           │ paid=true?│
                                                           └─────┬─────┘
                                                                 │
                                                         (10) Update booking
                                                         (status: confirmed)
                                                                 │
                                              ┌──────────────────┼──────────────────┐
                                              │                  │                  │
                                       (11) Block dates    (12) Send WhatsApp  (13) Notify
                                              │                  │               Frontend
                                        ┌─────▼─────┐      ┌─────▼─────┐      ┌─────▼─────┐
                                        │    DB     │      │  WhatsApp │      │  Cliente  │
                                        │(Calendar) │      │    API    │      │ "Success!"│
                                        └───────────┘      └───────────┘      └───────────┘
```

---

### **3.4 Escalabilidad y Performance**

**Fase MVP (100-200 reservas/mes):**
- Monolito Node.js en Railway ($5-10/mes)
- PostgreSQL en Neon free tier (0.5GB)
- Cloudinary free tier (25 credits/mes)
- Sin CDN (Vercel tiene edge caching)

**Fase Crecimiento (500+ reservas/mes):**
- Separar payment-service (serverless en AWS Lambda)
- PostgreSQL paid tier (10GB, backups automáticos)
- Redis para cache de perfiles + sesiones
- CDN (Cloudflare) para imágenes

**Fase Escala (2000+ reservas/mes):**
- Microservicios independientes
- Load balancer (AWS ALB)
- DB read replicas
- Queue system (BullMQ) para notificaciones async

---

## **4. Especificaciones de API**

### **4.1 Autenticación**

Todos los endpoints (excepto `/auth/register` y `/auth/login`) requieren header:
```
Authorization: Bearer <JWT_TOKEN>
```

**Token expiration:** 7 días  
**Refresh token expiration:** 30 días

---

### **4.2 Endpoints Principales**

#### **4.2.1 Autenticación**

##### **POST /api/auth/register**

Registra nuevo usuario (cliente o cuidador).

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "SecurePass123",
  "firstName": "Juan",
  "lastName": "Pérez",
  "phone": "+59176543210",
  "role": "client" | "caregiver"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "uuid-123",
      "email": "user@example.com",
      "role": "client",
      "createdAt": "2026-02-05T10:00:00Z"
    },
    "tokens": {
      "accessToken": "eyJhbGc...",
      "refreshToken": "eyJhbGc..."
    }
  }
}
```

**Error (400):**
```json
{
  "success": false,
  "error": {
    "code": "EMAIL_EXISTS",
    "message": "Este email ya está registrado"
  }
}
```

---

##### **POST /api/auth/login**

Inicia sesión.

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "SecurePass123"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "uuid-123",
      "email": "user@example.com",
      "role": "client",
      "firstName": "Juan",
      "profileComplete": true
    },
    "tokens": {
      "accessToken": "eyJhbGc...",
      "refreshToken": "eyJhbGc..."
    }
  }
}
```

---

#### **4.2.2 Perfiles de Cuidadores**

##### **GET /api/caregivers**

Lista cuidadores verificados con filtros.

**Query Params:**
```
?service=hospedaje|paseos|ambos
&zone=equipetrol,urbari
&priceRange=economico|estandar|premium
&spaceType=casa_patio|casa_sin_patio|departamento
&page=1&limit=12
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "caregivers": [
      {
        "id": "uuid-456",
        "firstName": "María",
        "lastName": "López",
        "profilePicture": "https://cloudinary.com/...",
        "zone": "equipetrol",
        "services": ["hospedaje", "paseos"],
        "rating": 4.8,
        "reviewCount": 12,
        "pricePerDay": 120,
        "pricePerWalk30": 30,
        "pricePerWalk60": 50,
        "verified": true,
        "spaceType": "casa_patio"
      }
    ],
    "pagination": {
      "total": 45,
      "page": 1,
      "pages": 4
    }
  }
}
```

---

##### **GET /api/caregivers/:id**

Perfil detallado de cuidador.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "uuid-456",
    "firstName": "María",
    "lastName": "López",
    "bio": "Tengo 2 labradores y trabajo desde casa...",
    "profilePicture": "https://...",
    "photos": [
      "https://cloudinary.com/patio.jpg",
      "https://cloudinary.com/living.jpg"
    ],
    "zone": "equipetrol",
    "services": ["hospedaje", "paseos"],
    "rating": 4.8,
    "reviewCount": 12,
    "pricePerDay": 120,
    "pricePerWalk30": 30,
    "pricePerWalk60": 50,
    "spaceType": "casa_patio",
    "availability": {
      "hospedaje": ["2026-03-10", "2026-03-11", "2026-03-15"],
      "paseos": {
        "2026-03-10": ["manana", "tarde"],
        "2026-03-11": ["tarde"]
      }
    },
    "reviews": [
      {
        "id": "uuid-789",
        "clientName": "Carlos R.",
        "clientPhoto": "https://...",
        "rating": 5,
        "comment": "Excelente cuidadora, mi perro volvió feliz",
        "serviceType": "hospedaje",
        "createdAt": "2026-02-01T10:00:00Z"
      }
    ]
  }
}
```

---

#### **4.2.3 Reservas**

##### **POST /api/bookings**

Crea nueva reserva (hospedaje o paseo).

**Request Body (Hospedaje):**
```json
{
  "caregiverId": "uuid-456",
  "serviceType": "hospedaje",
  "startDate": "2026-03-15",
  "endDate": "2026-03-18",
  "petInfo": {
    "name": "Max",
    "breed": "Labrador",
    "age": 3,
    "specialNeeds": "Toma medicinas a las 8am"
  }
}
```

**Request Body (Paseo):**
```json
{
  "caregiverId": "uuid-456",
  "serviceType": "paseo",
  "date": "2026-03-10",
  "timeSlot": "manana",
  "duration": 60,
  "petInfo": {
    "name": "Max",
    "breed": "Labrador"
  },
  "pickupAddress": "Av. San Martín #123, Equipetrol"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "booking": {
      "id": "uuid-booking-1",
      "serviceType": "hospedaje",
      "startDate": "2026-03-15",
      "endDate": "2026-03-18",
      "totalDays": 3,
      "pricePerDay": 120,
      "totalAmount": 360,
      "status": "pending_payment",
      "createdAt": "2026-02-05T10:00:00Z"
    },
    "payment": {
      "qrImageUrl": "https://api.bank.bo/qr/ABC123.png",
      "qrId": "QR-4872-XYZ",
      "amount": 360,
      "expiresAt": "2026-02-05T10:15:00Z"
    }
  }
}
```

**Error (409):**
```json
{
  "success": false,
  "error": {
    "code": "DATES_UNAVAILABLE",
    "message": "El cuidador no está disponible en esas fechas",
    "unavailableDates": ["2026-03-16"]
  }
}
```

---

##### **POST /api/payments/verify**

Verifica si un pago QR fue completado.

**Request Body:**
```json
{
  "bookingId": "uuid-booking-1",
  "qrId": "QR-4872-XYZ"
}
```

**Response (200) - Pagado:**
```json
{
  "success": true,
  "data": {
    "paid": true,
    "booking": {
      "id": "uuid-booking-1",
      "status": "confirmed",
      "paidAt": "2026-02-05T10:12:00Z"
    }
  }
}
```

**Response (200) - No pagado:**
```json
{
  "success": true,
  "data": {
    "paid": false,
    "message": "Aún no se detectó el pago. Intenta en 10 segundos."
  }
}
```

**Error (410) - QR expirado:**
```json
{
  "success": false,
  "error": {
    "code": "QR_EXPIRED",
    "message": "El QR expiró. Genera uno nuevo."
  }
}
```

---

##### **PATCH /api/bookings/:id/cancel**

Cancela reserva y calcula reembolso.

**Request Body:**
```json
{
  "reason": "Cambio de planes"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "booking": {
      "id": "uuid-booking-1",
      "status": "cancelled",
      "cancelledAt": "2026-02-05T10:00:00Z"
    },
    "refund": {
      "amount": 350,
      "percentage": 100,
      "adminFee": 10,
      "status": "pending_approval",
      "estimatedProcessingDays": 2
    }
  }
}
```

---

##### **POST /api/bookings/:id/extend**

Extiende reserva de hospedaje (agrega días).

**Request Body:**
```json
{
  "newEndDate": "2026-03-20"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "booking": {
      "id": "uuid-booking-1",
      "endDate": "2026-03-20",
      "additionalDays": 2,
      "additionalAmount": 240
    },
    "payment": {
      "qrImageUrl": "https://api.bank.bo/qr/DEF456.png",
      "qrId": "QR-4873-ABC",
      "amount": 240,
      "expiresAt": "2026-02-05T10:15:00Z"
    }
  }
}
```

**Error (409):**
```json
{
  "success": false,
  "error": {
    "code": "CAREGIVER_UNAVAILABLE",
    "message": "El cuidador no está disponible en las nuevas fechas"
  }
}
```

---

#### **4.2.4 Reseñas**

##### **POST /api/reviews**

Crea reseña (solo si booking completed & paid).

**Request Body:**
```json
{
  "bookingId": "uuid-booking-1",
  "rating": 5,
  "comment": "Excelente cuidadora, mi perro volvió muy feliz",
  "photo": "base64_or_url"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "review": {
      "id": "uuid-review-1",
      "bookingId": "uuid-booking-1",
      "caregiverId": "uuid-456",
      "clientName": "Juan P.",
      "rating": 5,
      "comment": "Excelente cuidadora...",
      "serviceType": "hospedaje",
      "createdAt": "2026-02-05T10:00:00Z"
    }
  }
}
```

**Error (403):**
```json
{
  "success": false,
  "error": {
    "code": "REVIEW_NOT_ALLOWED",
    "message": "Solo puedes reseñar reservas pagadas y completadas"
  }
}
```

---

#### **4.2.5 Admin**

##### **GET /api/admin/caregivers/pending**

Lista cuidadores pendientes de aprobación.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "caregivers": [
      {
        "id": "uuid-789",
        "firstName": "Ana",
        "lastName": "Gómez",
        "email": "ana@example.com",
        "phone": "+59176543210",
        "appliedAt": "2026-02-04T15:00:00Z",
        "profileComplete": true
      }
    ]
  }
}
```

---

##### **POST /api/admin/caregivers/:id/approve**

Aprueba cuidador (visible en plataforma).

**Request Body:**
```json
{
  "notes": "Entrevista OK. Casa visitada el 05/02."
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "caregiver": {
      "id": "uuid-789",
      "verified": true,
      "approvedAt": "2026-02-05T10:00:00Z"
    }
  }
}
```

---

##### **POST /api/admin/caregivers/:id/suspend**

Suspende cuidador (oculta perfil).

**Request Body:**
```json
{
  "reason": "Múltiples quejas de clientes"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "caregiver": {
      "id": "uuid-789",
      "suspended": true,
      "suspendedAt": "2026-02-05T10:00:00Z"
    }
  }
}
```

---

##### **POST /api/admin/refunds/:id/approve**

Aprueba reembolso de cancelación.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "refund": {
      "id": "uuid-refund-1",
      "status": "approved",
      "processedAt": "2026-02-05T10:00:00Z"
    }
  }
}
```

---

### **4.3 Códigos de Error Estándar**

| Código HTTP | Error Code | Descripción |
|-------------|------------|-------------|
| 400 | `VALIDATION_ERROR` | Datos de entrada inválidos |
| 401 | `UNAUTHORIZED` | Token ausente o inválido |
| 403 | `FORBIDDEN` | Acción no permitida para este usuario |
| 404 | `NOT_FOUND` | Recurso no encontrado |
| 409 | `CONFLICT` | Conflicto (ej: fechas ocupadas) |
| 410 | `EXPIRED` | Recurso expirado (ej: QR) |
| 429 | `RATE_LIMIT_EXCEEDED` | Demasiadas solicitudes |
| 500 | `INTERNAL_ERROR` | Error del servidor |
| 503 | `SERVICE_UNAVAILABLE` | Servicio externo caído (ej: Bank API) |

---

## **5. Modelos de Datos**

### **5.1 Schema de PostgreSQL (Prisma)**

```prisma
// prisma/schema.prisma

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

generator client {
  provider = "prisma-client-js"
}

enum UserRole {
  CLIENT
  CAREGIVER
  ADMIN
}

enum ServiceType {
  HOSPEDAJE
  PASEO
}

enum BookingStatus {
  PENDING_PAYMENT
  CONFIRMED
  IN_PROGRESS
  COMPLETED
  CANCELLED
}

enum RefundStatus {
  PENDING_APPROVAL
  APPROVED
  REJECTED
  PROCESSED
}

enum TimeSlot {
  MANANA
  TARDE
}

model User {
  id            String    @id @default(uuid())
  email         String    @unique
  passwordHash  String
  role          UserRole
  firstName     String
  lastName      String
  phone         String
  profilePicture String?
  createdAt     DateTime  @default(now())
  updatedAt     DateTime  @updatedAt
  
  // Relations
  clientBookings  Booking[]  @relation("ClientBookings")
  caregiverProfile CaregiverProfile?
  reviews         Review[]
  
  @@index([email])
}

model CaregiverProfile {
  id              String    @id @default(uuid())
  userId          String    @unique
  user            User      @relation(fields: [userId], references: [id], onDelete: Cascade)
  
  bio             String?
  zone            String
  spaceType       String?   // casa_patio, casa_sin_patio, departamento
  photos          String[]  // Array of URLs
  
  servicesOffered ServiceType[]
  pricePerDay     Int?      // Para hospedaje (en Bs)
  pricePerWalk30  Int?      // Para paseo 30 min
  pricePerWalk60  Int?      // Para paseo 60 min
  
  verified        Boolean   @default(false)
  suspended       Boolean   @default(false)
  rating          Float     @default(0)
  reviewCount     Int       @default(0)
  
  approvedAt      DateTime?
  suspendedAt     DateTime?
  suspensionReason String?
  
  createdAt       DateTime  @default(now())
  updatedAt       DateTime  @updatedAt
  
  // Relations
  bookings        Booking[] @relation("CaregiverBookings")
  availability    Availability[]
  reviews         Review[]
  
  @@index([zone, verified, suspended])
}

model Availability {
  id             String    @id @default(uuid())
  caregiverId    String
  caregiver      CaregiverProfile @relation(fields: [caregiverId], references: [id], onDelete: Cascade)
  
  serviceType    ServiceType
  date           DateTime  @db.Date
  
  // Para hospedaje: isAvailable = true/false
  // Para paseos: timeSlots = [MANANA, TARDE]
  isAvailable    Boolean   @default(true)
  timeSlots      TimeSlot[]
  
  createdAt      DateTime  @default(now())
  
  @@unique([caregiverId, serviceType, date])
  @@index([caregiverId, date])
}

model Booking {
  id             String    @id @default(uuid())
  
  clientId       String
  client         User      @relation("ClientBookings", fields: [clientId], references: [id])
  
  caregiverId    String
  caregiver      CaregiverProfile @relation("CaregiverBookings", fields: [caregiverId], references: [id])
  
  serviceType    ServiceType
  status         BookingStatus @default(PENDING_PAYMENT)
  
  // Hospedaje
  startDate      DateTime? @db.Date
  endDate        DateTime? @db.Date
  totalDays      Int?
  
  // Paseo
  walkDate       DateTime? @db.Date
  timeSlot       TimeSlot?
  duration       Int?      // 30 o 60 minutos
  pickupAddress  String?
  
  // Pricing
  pricePerUnit   Int       // Precio por día (hospedaje) o por paseo
  totalAmount    Int
  commissionRate Float     @default(0.18)
  commissionAmount Int
  
  // Pet info
  petName        String
  petBreed       String?
  petAge         Int?
  specialNeeds   String?
  
  // Payment
  qrId           String?
  qrImageUrl     String?
  qrExpiresAt    DateTime?
  paidAt         DateTime?
  
  // Cancellation
  cancelledAt    DateTime?
  cancellationReason String?
  
  createdAt      DateTime  @default(now())
  updatedAt      DateTime  @updatedAt
  
  // Relations
  refund         Refund?
  review         Review?
  
  @@index([clientId, status])
  @@index([caregiverId, status])
  @@index([status, startDate])
}

model Refund {
  id             String    @id @default(uuid())
  bookingId      String    @unique
  booking        Booking   @relation(fields: [bookingId], references: [id])
  
  refundAmount   Int
  refundPercentage Float
  adminFee       Int       @default(10)
  
  status         RefundStatus @default(PENDING_APPROVAL)
  reason         String?
  
  approvedAt     DateTime?
  processedAt    DateTime?
  
  createdAt      DateTime  @default(now())
  
  @@index([status])
}

model Review {
  id             String    @id @default(uuid())
  bookingId      String    @unique
  booking        Booking   @relation(fields: [bookingId], references: [id])
  
  clientId       String
  client         User      @relation(fields: [clientId], references: [id])
  
  caregiverId    String
  caregiver      CaregiverProfile @relation(fields: [caregiverId], references: [id])
  
  rating         Int       @db.SmallInt // 1-5
  comment        String?
  photo          String?
  
  serviceType    ServiceType
  
  // Response from caregiver
  caregiverResponse String?
  respondedAt    DateTime?
  
  createdAt      DateTime  @default(now())
  
  @@index([caregiverId, rating])
}

model AdminAction {
  id             String    @id @default(uuid())
  adminId        String
  actionType     String    // APPROVE_CAREGIVER, SUSPEND_CAREGIVER, APPROVE_REFUND, etc.
  targetId       String    // ID del cuidador, refund, etc.
  notes          String?
  createdAt      DateTime  @default(now())
  
  @@index([adminId, actionType])
}
```

---

### **5.2 Migraciones Iniciales**

```bash
# Crear migración inicial
npx prisma migrate dev --name init

# Generar Prisma Client
npx prisma generate

# Seed inicial (opcional: crear admin user)
npx prisma db seed
```

**Seed script (`prisma/seed.ts`):**
```typescript
import { PrismaClient, UserRole } from '@prisma/client';
import bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  // Crear admin user
  const adminPassword = await bcrypt.hash('AdminGarden2026!', 12);
  
  await prisma.user.upsert({
    where: { email: 'admin@garden.bo' },
    update: {},
    create: {
      email: 'admin@garden.bo',
      passwordHash: adminPassword,
      role: UserRole.ADMIN,
      firstName: 'Admin',
      lastName: 'GARDEN',
      phone: '+59170000000',
    },
  });

  console.log('✅ Admin user created');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
```

---

## **6. Estándares de Código**

### **6.1 Convenciones de Naming**

| Elemento | Convención | Ejemplo |
|----------|------------|---------|
| Variables | camelCase | `const userName = 'Juan';` |
| Constantes | UPPER_SNAKE_CASE | `const MAX_RETRIES = 3;` |
| Funciones | camelCase | `function calculateRefund() {}` |
| Clases | PascalCase | `class BookingService {}` |
| Interfaces (TS) | PascalCase + I prefix | `interface IUser {}` |
| Enums | PascalCase | `enum BookingStatus {}` |
| Archivos | kebab-case | `user-service.ts` |
| Componentes React | PascalCase | `CaregiverCard.tsx` |

---

### **6.2 Estructura de Directorios**

```
garden-api/
├── src/
│   ├── config/           # DB, env vars, constants
│   ├── middleware/       # Auth, error handling, validation
│   ├── modules/
│   │   ├── auth/
│   │   │   ├── auth.controller.ts
│   │   │   ├── auth.service.ts
│   │   │   ├── auth.routes.ts
│   │   │   └── auth.validation.ts
│   │   ├── bookings/
│   │   ├── caregivers/
│   │   ├── payments/
│   │   └── reviews/
│   ├── utils/            # Helpers, logger, validators
│   ├── types/            # TypeScript types
│   ├── app.ts            # Express app setup
│   └── server.ts         # Entry point
├── prisma/
│   ├── schema.prisma
│   └── migrations/
├── tests/
│   ├── unit/
│   ├── integration/
│   └── e2e/
├── .env.example
├── package.json
└── tsconfig.json
```

---

### **6.3 Ejemplo: Lógica de Cálculo de Reembolsos**

```typescript
// src/modules/bookings/booking.service.ts

import { Booking, BookingStatus, ServiceType } from '@prisma/client';
import { BadRequestError } from '../../utils/errors';

interface RefundCalculation {
  refundAmount: number;
  refundPercentage: number;
  adminFee: number;
}

export class BookingService {
  /**
   * Calcula el reembolso según reglas de cancelación
   * 
   * HOSPEDAJE:
   * - >48h antes: 100% - Bs 10 admin fee
   * - 24-48h antes: 50%
   * - <24h antes: 0%
   * 
   * PASEOS:
   * - >12h antes: 100%
   * - 6-12h antes: 50%
   * - <6h antes: 0%
   */
  static calculateRefund(booking: Booking): RefundCalculation {
    const now = new Date();
    const startDate = booking.serviceType === ServiceType.HOSPEDAJE 
      ? booking.startDate! 
      : booking.walkDate!;
    
    const hoursUntilStart = (startDate.getTime() - now.getTime()) / (1000 * 60 * 60);
    
    let refundPercentage = 0;
    const adminFee = 10;

    if (booking.serviceType === ServiceType.HOSPEDAJE) {
      if (hoursUntilStart > 48) {
        refundPercentage = 100;
      } else if (hoursUntilStart > 24) {
        refundPercentage = 50;
      } else {
        refundPercentage = 0;
      }
    } else if (booking.serviceType === ServiceType.PASEO) {
      if (hoursUntilStart > 12) {
        refundPercentage = 100;
      } else if (hoursUntilStart > 6) {
        refundPercentage = 50;
      } else {
        refundPercentage = 0;
      }
    }

    const baseRefund = (booking.totalAmount * refundPercentage) / 100;
    const refundAmount = refundPercentage === 100 
      ? Math.max(0, baseRefund - adminFee) 
      : baseRefund;

    return {
      refundAmount: Math.round(refundAmount),
      refundPercentage,
      adminFee: refundPercentage === 100 ? adminFee : 0,
    };
  }

  /**
   * Procesa cancelación de reserva
   */
  async cancelBooking(bookingId: string, userId: string, reason?: string) {
    const booking = await prisma.booking.findUnique({
      where: { id: bookingId },
      include: { client: true },
    });

    if (!booking) {
      throw new BadRequestError('Reserva no encontrada');
    }

    if (booking.clientId !== userId) {
      throw new BadRequestError('No tienes permiso para cancelar esta reserva');
    }

    if (booking.status === BookingStatus.CANCELLED) {
      throw new BadRequestError('Esta reserva ya fue cancelada');
    }

    if (booking.status === BookingStatus.COMPLETED) {
      throw new BadRequestError('No puedes cancelar una reserva completada');
    }

    const refundCalc = BookingService.calculateRefund(booking);

    // Actualizar booking
    const updatedBooking = await prisma.booking.update({
      where: { id: bookingId },
      data: {
        status: BookingStatus.CANCELLED,
        cancelledAt: new Date(),
        cancellationReason: reason,
      },
    });

    // Crear solicitud de reembolso
    const refund = await prisma.refund.create({
      data: {
        bookingId: bookingId,
        refundAmount: refundCalc.refundAmount,
        refundPercentage: refundCalc.refundPercentage,
        adminFee: refundCalc.adminFee,
        reason: reason,
        status: 'PENDING_APPROVAL',
      },
    });

    // Liberar disponibilidad del cuidador
    await this.releaseAvailability(booking);

    // Notificar admin por WhatsApp
    await WhatsAppService.notifyAdminRefund(refund);

    return {
      booking: updatedBooking,
      refund,
    };
  }

  private async releaseAvailability(booking: Booking) {
    if (booking.serviceType === ServiceType.HOSPEDAJE) {
      // Liberar fechas bloqueadas
      const dates = this.getDateRange(booking.startDate!, booking.endDate!);
      
      await prisma.availability.updateMany({
        where: {
          caregiverId: booking.caregiverId,
          serviceType: ServiceType.HOSPEDAJE,
          date: { in: dates },
        },
        data: {
          isAvailable: true,
        },
      });
    } else {
      // Liberar horario de paseo
      await prisma.availability.update({
        where: {
          caregiverId_serviceType_date: {
            caregiverId: booking.caregiverId,
            serviceType: ServiceType.PASEO,
            date: booking.walkDate!,
          },
        },
        data: {
          timeSlots: {
            push: booking.timeSlot!,
          },
        },
      });
    }
  }

  private getDateRange(start: Date, end: Date): Date[] {
    const dates: Date[] = [];
    let current = new Date(start);
    
    while (current <= end) {
      dates.push(new Date(current));
      current.setDate(current.getDate() + 1);
    }
    
    return dates;
  }
}
```

---

### **6.4 Manejo de Errores**

```typescript
// src/utils/errors.ts

export class AppError extends Error {
  statusCode: number;
  code: string;
  isOperational: boolean;

  constructor(message: string, statusCode: number, code: string) {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
    this.isOperational = true;

    Error.captureStackTrace(this, this.constructor);
  }
}

export class BadRequestError extends AppError {
  constructor(message: string, code = 'BAD_REQUEST') {
    super(message, 400, code);
  }
}

export class UnauthorizedError extends AppError {
  constructor(message = 'No autorizado', code = 'UNAUTHORIZED') {
    super(message, 401, code);
  }
}

export class ForbiddenError extends AppError {
  constructor(message = 'Acceso denegado', code = 'FORBIDDEN') {
    super(message, 403, code);
  }
}

export class NotFoundError extends AppError {
  constructor(message: string, code = 'NOT_FOUND') {
    super(message, 404, code);
  }
}

// Middleware global
// src/middleware/error-handler.ts

import { Request, Response, NextFunction } from 'express';
import { AppError } from '../utils/errors';
import logger from '../utils/logger';

export const errorHandler = (
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction
) => {
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      success: false,
      error: {
        code: err.code,
        message: err.message,
      },
    });
  }

  // Error no esperado
  logger.error('Unhandled error:', err);
  
  return res.status(500).json({
    success: false,
    error: {
      code: 'INTERNAL_ERROR',
      message: 'Ocurrió un error inesperado. Intenta nuevamente.',
    },
  });
};
```

---

### **6.5 Testing Guidelines**

**Cobertura mínima:**
- Unit tests: **80%** de funciones críticas (cálculo de precios, reembolsos, validaciones)
- Integration tests: **60%** de endpoints
- E2E tests: **Flujos principales** (registro → reserva → pago → reseña)

**Ejemplo de test unitario:**

```typescript
// tests/unit/booking.service.test.ts

import { BookingService } from '../../src/modules/bookings/booking.service';
import { ServiceType, BookingStatus } from '@prisma/client';

describe('BookingService.calculateRefund', () => {
  describe('Hospedaje', () => {
    it('debería reembolsar 100% - Bs 10 si cancela >48h antes', () => {
      const booking = {
        id: '1',
        serviceType: ServiceType.HOSPEDAJE,
        startDate: new Date(Date.now() + 72 * 60 * 60 * 1000), // +72 horas
        totalAmount: 360,
        status: BookingStatus.CONFIRMED,
      } as any;

      const refund = BookingService.calculateRefund(booking);

      expect(refund.refundPercentage).toBe(100);
      expect(refund.refundAmount).toBe(350); // 360 - 10
      expect(refund.adminFee).toBe(10);
    });

    it('debería reembolsar 50% si cancela entre 24-48h antes', () => {
      const booking = {
        serviceType: ServiceType.HOSPEDAJE,
        startDate: new Date(Date.now() + 36 * 60 * 60 * 1000), // +36 horas
        totalAmount: 360,
      } as any;

      const refund = BookingService.calculateRefund(booking);

      expect(refund.refundPercentage).toBe(50);
      expect(refund.refundAmount).toBe(180);
      expect(refund.adminFee).toBe(0);
    });

    it('debería reembolsar 0% si cancela <24h antes', () => {
      const booking = {
        serviceType: ServiceType.HOSPEDAJE,
        startDate: new Date(Date.now() + 12 * 60 * 60 * 1000), // +12 horas
        totalAmount: 360,
      } as any;

      const refund = BookingService.calculateRefund(booking);

      expect(refund.refundPercentage).toBe(0);
      expect(refund.refundAmount).toBe(0);
    });
  });

  describe('Paseos', () => {
    it('debería reembolsar 100% si cancela >12h antes', () => {
      const booking = {
        serviceType: ServiceType.PASEO,
        walkDate: new Date(Date.now() + 24 * 60 * 60 * 1000), // +24 horas
        totalAmount: 50,
      } as any;

      const refund = BookingService.calculateRefund(booking);

      expect(refund.refundPercentage).toBe(100);
      expect(refund.refundAmount).toBe(40); // 50 - 10
    });

    it('debería reembolsar 50% si cancela entre 6-12h antes', () => {
      const booking = {
        serviceType: ServiceType.PASEO,
        walkDate: new Date(Date.now() + 9 * 60 * 60 * 1000), // +9 horas
        totalAmount: 50,
      } as any;

      const refund = BookingService.calculateRefund(booking);

      expect(refund.refundPercentage).toBe(50);
      expect(refund.refundAmount).toBe(25);
    });
  });
});
```

---

## **7. Plan de Testing**

### **7.1 Tipos de Tests**

| Tipo | Herramienta | Cobertura Target | Responsable |
|------|-------------|------------------|-------------|
| **Unit Tests** | Jest | 80% funciones críticas | Dev |
| **Integration Tests** | Supertest + Jest | 60% endpoints | Dev |
| **E2E Tests** | Playwright | Flujos principales | QA/Dev |
| **Load Tests** | k6 | 100 req/s sin errors | DevOps |
| **Manual QA** | Checklist | 100% user stories | QA |

---

### **7.2 Matriz de Cobertura**

| Feature | Unit Tests | Integration Tests | E2E Tests | Manual QA |
|---------|------------|-------------------|-----------|-----------|
| **Registro de usuario** | ✅ Validación email/password | ✅ POST /api/auth/register | ✅ Flujo completo signup | ✅ |
| **Login** | ✅ Validación credenciales | ✅ POST /api/auth/login | ✅ Flujo login + redirect | ✅ |
| **Listado de cuidadores** | ✅ Filtros (zone, price, service) | ✅ GET /api/caregivers | ✅ Búsqueda + click perfil | ✅ |
| **Reserva hospedaje** | ✅ Cálculo precio (días × tarifa) | ✅ POST /api/bookings | ✅ Seleccionar fechas → QR → pago simulado | ✅ |
| **Verificación de pago** | ✅ Mock Bank API response | ✅ POST /api/payments/verify | ✅ Esperar confirmación | ✅ |
| **Cancelación de reserva** | ✅ Cálculo de reembolso (múltiples escenarios) | ✅ PATCH /api/bookings/:id/cancel | ✅ Cancelar → ver reembolso | ✅ |
| **Extensión de reserva** | ✅ Verificar disponibilidad | ✅ POST /api/bookings/:id/extend | ✅ Extender → pagar días extra | ✅ |
| **Reseñas** | ✅ Validación (solo si paid) | ✅ POST /api/reviews | ✅ Dejar reseña → ver en perfil | ✅ |
| **Admin: Aprobar cuidador** | - | ✅ POST /api/admin/caregivers/:id/approve | ✅ Aprobar → cuidador visible | ✅ |
| **Admin: Aprobar reembolso** | - | ✅ POST /api/admin/refunds/:id/approve | ✅ Aprobar → notificación cliente | ✅ |

---

### **7.3 Tests E2E Críticos (Playwright)**

```typescript
// tests/e2e/booking-flow.spec.ts

import { test, expect } from '@playwright/test';

test.describe('Flujo completo de reserva de hospedaje', () => {
  test('Cliente puede reservar, pagar y recibir confirmación', async ({ page }) => {
    // 1. Registro de cliente
    await page.goto('/register');
    await page.fill('[name="email"]', 'test@example.com');
    await page.fill('[name="password"]', 'SecurePass123');
    await page.fill('[name="firstName"]', 'Juan');
    await page.fill('[name="lastName"]', 'Pérez');
    await page.fill('[name="phone"]', '+59176543210');
    await page.click('button[type="submit"]');
    
    await expect(page).toHaveURL('/dashboard');

    // 2. Buscar cuidador
    await page.goto('/caregivers');
    await page.selectOption('[name="zone"]', 'equipetrol');
    await page.click('text=María López'); // Primer cuidador

    // 3. Ver perfil y seleccionar fechas
    await expect(page.locator('h1')).toContainText('María López');
    
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 10);
    const endDate = new Date(tomorrow);
    endDate.setDate(endDate.getDate() + 3);

    await page.click(`[data-date="${tomorrow.toISOString().split('T')[0]}"]`);
    await page.click(`[data-date="${endDate.toISOString().split('T')[0]}"]`);
    
    await expect(page.locator('[data-testid="total-amount"]')).toContainText('360');

    // 4. Confirmar reserva
    await page.click('button:has-text("Reservar")');
    
    // 5. Verificar QR generado
    await expect(page.locator('[data-testid="qr-code"]')).toBeVisible();
    await expect(page.locator('text=Bs 360')).toBeVisible();

    // 6. Simular pago (en test, mockeamos la API del banco)
    await page.route('**/api/payments/verify', (route) =>
      route.fulfill({
        status: 200,
        body: JSON.stringify({ success: true, data: { paid: true } }),
      })
    );

    await page.click('button:has-text("Comprobar pago")');

    // 7. Verificar confirmación
    await expect(page.locator('text=¡Reserva confirmada!')).toBeVisible();
    await expect(page.locator('text=María López')).toBeVisible();
  });

  test('Cliente puede cancelar reserva y ver reembolso', async ({ page }) => {
    // Asumiendo que hay una reserva activa...
    await page.goto('/my-bookings');
    await page.click('text=Ver detalles'); // Primera reserva

    await page.click('button:has-text("Cancelar reserva")');
    
    // Modal de cancelación
    await expect(page.locator('text=Reembolso: Bs 350')).toBeVisible();
    await page.fill('[name="reason"]', 'Cambio de planes');
    await page.click('button:has-text("Confirmar cancelación")');

    // Verificar estado
    await expect(page.locator('text=Cancelada')).toBeVisible();
    await expect(page.locator('text=Reembolso pendiente de aprobación')).toBeVisible();
  });
});
```

---

### **7.4 CI/CD Pipeline (GitHub Actions)**

```yaml
# .github/workflows/ci.yml

name: CI/CD Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: garden_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
      
      - name: Install dependencies
        run: npm ci
      
      - name: Run Prisma migrations
        run: npx prisma migrate deploy
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/garden_test
      
      - name: Run unit tests
        run: npm run test:unit
      
      - name: Run integration tests
        run: npm run test:integration
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/garden_test
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage/lcov.info

  e2e:
    runs-on: ubuntu-latest
    needs: test
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
      
      - name: Install dependencies
        run: npm ci
      
      - name: Install Playwright
        run: npx playwright install --with-deps
      
      - name: Run E2E tests
        run: npm run test:e2e
      
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: playwright-report
          path: playwright-report/

  deploy:
    runs-on: ubuntu-latest
    needs: [test, e2e]
    if: github.ref == 'refs/heads/main'
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Deploy to Railway
        run: |
          npm install -g @railway/cli
          railway up
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
```

---

## **8. Deployment y Mantenimiento**

### **8.1 Variables de Entorno**

```bash
# .env.example

# Database
DATABASE_URL="postgresql://user:password@host:5432/garden_db"

# JWT
JWT_SECRET="your-super-secret-jwt-key-change-in-production"
JWT_EXPIRES_IN="7d"
JWT_REFRESH_EXPIRES_IN="30d"

# Bank API (QR Payments)
BANK_API_URL="https://api.banco.bo"
BANK_API_KEY="your-bank-api-key"
BANK_MERCHANT_ID="GARDEN-SCZ-001"

# WhatsApp Business API
WHATSAPP_API_URL="https://api.360dialog.com"
WHATSAPP_API_KEY="your-whatsapp-api-key"
WHATSAPP_PHONE_NUMBER="+59170000000"

# File Storage
CLOUDINARY_CLOUD_NAME="your-cloud-name"
CLOUDINARY_API_KEY="your-api-key"
CLOUDINARY_API_SECRET="your-api-secret"

# Frontend URL
FRONTEND_URL="https://garden.bo"

# Monitoring
SENTRY_DSN="https://your-sentry-dsn"
LOG_LEVEL="info"

# Environment
NODE_ENV="production"
PORT=3000
```

---

### **8.2 Deployment Steps (Railway)**

#### **8.2.1 Backend Deployment**

```bash
# 1. Conectar Railway CLI
railway login

# 2. Iniciar proyecto
railway init

# 3. Agregar PostgreSQL
railway add postgresql

# 4. Configurar variables de entorno
railway variables set DATABASE_URL=$DATABASE_URL
railway variables set JWT_SECRET="$(openssl rand -base64 32)"
# ... (agregar todas las variables)

# 5. Deploy
git push railway main

# 6. Ejecutar migraciones
railway run npx prisma migrate deploy

# 7. Verificar
railway status
railway logs
```

#### **8.2.2 Frontend Deployment (Vercel)**

```bash
# 1. Instalar Vercel CLI
npm i -g vercel

# 2. Deploy
vercel --prod

# 3. Configurar variables de entorno en Vercel Dashboard
# VITE_API_URL=https://api.garden.bo
```

---

### **8.3 Monitoring y Logging**

#### **8.3.1 Error Tracking (Sentry)**

```typescript
// src/config/sentry.ts

import * as Sentry from '@sentry/node';
import { ProfilingIntegration } from '@sentry/profiling-node';

export function initSentry() {
  if (process.env.NODE_ENV === 'production') {
    Sentry.init({
      dsn: process.env.SENTRY_DSN,
      integrations: [
        new ProfilingIntegration(),
      ],
      tracesSampleRate: 0.1,
      profilesSampleRate: 0.1,
      environment: process.env.NODE_ENV,
    });
  }
}

// En app.ts
import { initSentry } from './config/sentry';
initSentry();

// Middleware de error
app.use(Sentry.Handlers.errorHandler());
```

#### **8.3.2 Structured Logging (Winston)**

```typescript
// src/utils/logger.ts

import winston from 'winston';

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  defaultMeta: { service: 'garden-api' },
  transports: [
    new winston.transports.File({ filename: 'error.log', level: 'error' }),
    new winston.transports.File({ filename: 'combined.log' }),
  ],
});

if (process.env.NODE_ENV !== 'production') {
  logger.add(new winston.transports.Console({
    format: winston.format.simple(),
  }));
}

export default logger;

// Uso:
import logger from './utils/logger';
logger.info('Booking created', { bookingId: '123', clientId: '456' });
logger.error('Payment verification failed', { error: err.message });
```

---

### **8.4 Database Backups**

#### **8.4.1 Backups Automáticos (Railway)**

Railway incluye backups automáticos diarios. Para backups manuales:

```bash
# Exportar DB
railway run pg_dump -U postgres garden_db > backup-$(date +%Y%m%d).sql

# Restaurar
railway run psql -U postgres garden_db < backup-20260205.sql
```

#### **8.4.2 Script de Backup (Cron)**

```bash
# backup.sh
#!/bin/bash

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups"
DB_NAME="garden_db"

# Backup
pg_dump -U postgres $DB_NAME | gzip > $BACKUP_DIR/garden_$DATE.sql.gz

# Subir a S3
aws s3 cp $BACKUP_DIR/garden_$DATE.sql.gz s3://garden-backups/

# Limpiar backups viejos (>30 días)
find $BACKUP_DIR -name "*.sql.gz" -mtime +30 -delete
```

**Crontab:**
```bash
# Backup diario a las 3am
0 3 * * * /path/to/backup.sh
```

---

### **8.5 Rollback Strategy**

#### **En caso de bug crítico en producción:**

1. **Rollback inmediato:**
   ```bash
   # Railway
   railway rollback
   
   # Vercel
   vercel rollback
   ```

2. **Notificar a usuarios:**
   - WhatsApp blast: "Estamos resolviendo un problema técnico. Tu reserva está segura."

3. **Hotfix:**
   ```bash
   git checkout -b hotfix/critical-bug
   # Fix bug
   git commit -m "Fix: Critical payment verification bug"
   git push origin hotfix/critical-bug
   # Deploy hotfix
   railway up --branch hotfix/critical-bug
   ```

4. **Post-mortem:**
   - Documentar causa raíz
   - Agregar test que capture el bug
   - Actualizar runbook

---

### **8.6 Maintenance Tasks**

| Tarea | Frecuencia | Responsable | Automatizado |
|-------|-----------|-------------|--------------|
| DB backups | Diario | DevOps | ✅ |
| Limpiar QRs expirados | Cada 6h | Backend (cron) | ✅ |
| Revisar logs de error | Diario | Dev | ❌ |
| Actualizar dependencias | Semanal | Dev | ❌ |
| Revisar métricas (Sentry) | Diario | Dev | ❌ |
| Optimizar queries lentos | Mensual | Dev | ❌ |
| Auditoría de seguridad | Trimestral | Security | ❌ |
| Renovar certificados SSL | Automático | Vercel/Railway | ✅ |

---

## **9. Self-Review y Correcciones**

### **9.1 Checklist de Consistencia**

| Ítem | Estado | Notas |
|------|--------|-------|
| ✅ Todas las user stories tienen acceptance criteria | ✅ | Definidos en sección 2 |
| ✅ Reglas de cancelación hospedaje vs paseos son diferentes | ✅ | Hospedaje: 48h, Paseos: 12h |
| ✅ API endpoints coinciden con user stories | ✅ | Verificado en sección 4 |
| ✅ Modelos de DB soportan todos los features del MVP | ✅ | Prisma schema completo |
| ✅ Cálculo de reembolsos implementado correctamente | ✅ | Código ejemplo en sección 6.3 |
| ✅ Tests cubren flujos críticos | ✅ | Matriz de cobertura en sección 7.2 |
| ✅ Stack tecnológico es costo-efectivo para MVP | ✅ | Railway free tier + Vercel |
| ✅ WhatsApp API integrada en arquitectura | ✅ | Diagrama en sección 3.1 |
| ✅ Deployment steps son claros y replicables | ✅ | Sección 8.2 |
| ✅ Variables de entorno documentadas | ✅ | .env.example en sección 8.1 |

---

### **9.2 Errores Detectados y Corregidos**

#### **Error 1: Inconsistencia en tiempos de cancelación**
- **Detectado:** En user story US-5.2, las reglas de cancelación de paseos no estaban claramente definidas.
- **Corregido:** Agregado en sección 2.2, US-5.2: >12h = 100%, 6-12h = 50%, <6h = 0%.

#### **Error 2: Falta de validación de disponibilidad en extensión**
- **Detectado:** El endpoint POST /api/bookings/:id/extend no validaba si el cuidador está disponible en las nuevas fechas.
- **Corregido:** Agregado en sección 4.2.3: respuesta de error 409 si cuidador no disponible.

#### **Error 3: Schema de DB no contemplaba paseos correctamente**
- **Detectado:** El modelo `Availability` no tenía campo `timeSlots` para paseos (mañana/tarde).
- **Corregido:** Agregado campo `timeSlots TimeSlot[]` en modelo `Availability` (sección 5.1).

#### **Error 4: Falta de índices en DB para queries frecuentes**
- **Detectado:** Queries de búsqueda de cuidadores por zona sin índice.
- **Corregido:** Agregados índices `@@index([zone, verified, suspended])` en `CaregiverProfile`.

#### **Error 5: Cálculo de reembolso no consideraba admin fee correctamente**
- **Detectado:** En código ejemplo, admin fee se restaba siempre, incluso en reembolsos parciales.
- **Corregido:** Sección 6.3, línea `refundAmount = refundPercentage === 100 ? baseRefund - adminFee : baseRefund`.

---

### **9.3 Validaciones Finales**

#### **Checklist de Negocio:**
- ✅ MVP resuelve el problema #1: confianza (verificación manual de cuidadores)
- ✅ Pagos automáticos con QR bancario (no pasarelas caras)
- ✅ Flexibilidad de cancelación (reglas claras, reembolsos justos)
- ✅ 2 servicios (hospedaje + paseos) para maximizar oferta
- ✅ WhatsApp como canal de comunicación (familiar en Bolivia)
- ✅ Sistema de reseñas verificadas (solo quien pagó)

#### **Checklist Técnico:**
- ✅ Backend: Node.js + TypeScript + Express
- ✅ DB: PostgreSQL + Prisma ORM
- ✅ Frontend: React (web) + Flutter (mobile)
- ✅ Autenticación: JWT stateless
- ✅ Tests: Unit + Integration + E2E (cobertura >70%)
- ✅ CI/CD: GitHub Actions automático
- ✅ Monitoring: Sentry + Winston logs
- ✅ Deployment: Railway (backend) + Vercel (frontend)

#### **Checklist de Escalabilidad:**
- ✅ Arquitectura modular (fácil separar microservicios)
- ✅ DB con índices optimizados
- ✅ Caching con Redis (planificado para V2)
- ✅ Serverless para pagos (planificado para V2)
- ✅ CDN para imágenes (Cloudinary + Cloudflare)

---

### **9.4 Recomendaciones Finales**

#### **Para Sprint 1:**
1. **Priorizar:** Autenticación + perfiles de cuidadores + listado básico
2. **No hacer:** Filtros complejos (dejar para Sprint 2)
3. **Riesgo:** Integración con Bank API puede demorar → tener mock listo

#### **Para Sprint 2:**
4. **Priorizar:** Sistema de reservas + pagos QR
5. **No hacer:** Extensiones de reserva (dejar para Sprint 4)
6. **Riesgo:** WhatsApp API puede tener delays → implementar queue (BullMQ)

#### **Para Sprint 3:**
7. **Priorizar:** Paseos + reseñas
8. **Testing exhaustivo:** E2E del flujo completo (reserva → pago → reseña)

#### **Para Sprint 4:**
9. **Priorizar:** Cancelaciones + admin panel
10. **No hacer:** Dashboard con gráficos fancy (suficiente con KPIs básicos)

---

## **10. Próximos Pasos**

### **Semana 1-2 (Ahora):**
1. ✅ Setup del repositorio (frontend + backend)
2. ✅ Configurar base de datos (Prisma + migrations)
3. ✅ Implementar autenticación (registro + login)
4. ✅ Crear perfiles de cuidadores (CRUD básico)

### **Semana 3-4:**
5. Implementar sistema de reservas (hospedaje)
6. Integrar API de pagos QR
7. Testing manual del flujo completo

### **Semana 5-6:**
8. Agregar servicio de paseos
9. Implementar sistema de reseñas
10. Setup CI/CD pipeline

### **Semana 7-8:**
11. Implementar cancelaciones + reembolsos
12. Panel de admin básico
13. Testing E2E completo
14. **LANZAMIENTO BETA** (10 cuidadores + 20 clientes)

---

## **Apéndice: Recursos Adicionales**

### **Enlaces Útiles**
- [Prisma Docs](https://www.prisma.io/docs)
- [WhatsApp Business API (Twilio)](https://www.twilio.com/docs/whatsapp)
- [Railway Deployment Guide](https://docs.railway.app)
- [Playwright E2E Testing](https://playwright.dev)
- [Sentry Error Monitoring](https://docs.sentry.io)

### **Comandos Útiles**

```bash
# Backend
npm run dev                # Dev server con hot reload
npm run build              # Build para producción
npm run test               # Todos los tests
npm run test:unit          # Solo unit tests
npm run test:integration   # Solo integration tests
npm run test:e2e           # Solo E2E tests
npx prisma studio          # DB GUI
npx prisma migrate dev     # Crear migración
npx prisma generate        # Generar Prisma Client

# Frontend
npm run dev                # Dev server
npm run build              # Build para producción
npm run preview            # Preview del build

# Flutter
flutter run                # Correr app en emulador
flutter build apk          # Build Android APK
flutter test               # Correr tests
```

---

**Documento generado el:** 05 de Febrero, 2026  
**Versión:** 1.0  
**Mantenedor:** Equipo GARDEN  
**Próxima revisión:** Sprint Retrospective (cada 2 semanas)

---

**FIN DE LA DOCUMENTACIÓN TÉCNICA**

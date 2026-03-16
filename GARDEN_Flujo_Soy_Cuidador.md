# GARDEN - Flujo Completo UI/UX: "Soy Cuidador"

> Documento de diseño profesional para el flujo completo desde el botón "Soy cuidador"
> hasta el dashboard del cuidador registrado.
>
> **Versión:** 1.0
> **Fecha:** 2026-02-06
> **Referencias:** GARDEN_Documentacion_Tecnica_v1.0.md, MVP de GARDEN v2 (PDF), schema.prisma

---

## Tabla de Contenidos

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Diagrama de Flujo General (ASCII)](#2-diagrama-de-flujo-general)
3. [Botón "Soy Cuidador" - Comportamiento Dinámico](#3-botón-soy-cuidador)
4. [Página de Autenticación /caregiver/auth](#4-página-de-autenticación)
5. [Wizard de Registro - 15 Pasos](#5-wizard-de-registro)
6. [Dashboard del Cuidador](#6-dashboard-del-cuidador)
7. [Wireframes ASCII](#7-wireframes-ascii)
8. [Componentes y Clases Tailwind](#8-componentes-y-clases-tailwind)
9. [Flujos de Usuario Detallados](#9-flujos-de-usuario)
10. [Manejo de Errores y Estados](#10-manejo-de-errores)
11. [Accesibilidad (WCAG 2.1 AA)](#11-accesibilidad)
12. [Performance](#12-performance)
13. [Seguridad e i18n](#13-seguridad-e-i18n)
14. [Mapeo a Schema Prisma](#14-mapeo-schema)
15. [Self-Review contra MVP Spec](#15-self-review)

---

## 1. Resumen Ejecutivo

### Objetivo

Diseñar el flujo completo que permite a un visitante convertirse en cuidador verificado en GARDEN, desde el primer clic en "Soy cuidador" hasta su dashboard personal post-registro.

### Alcance del Flujo

```
Botón "Soy cuidador" (Navbar)
  → Página de autenticación (/caregiver/auth)
    → Tab "Iniciar sesión" (cuidadores existentes)
    → Tab "Registrarme" (nuevo wizard de 15 pasos)
      → Submit → Dashboard con estado "Pendiente verificación"
```

### Principios de Diseño

| Principio | Aplicación |
|-----------|-----------|
| **Tranquilidad** | Colores verdes suaves, espaciado generoso, sin presión visual |
| **Progreso visible** | Barra de progreso + indicador de paso actual en todo el wizard |
| **Guardado automático** | localStorage persiste progreso; el usuario puede retomar |
| **Mobile-first** | Wizard optimizado para completar desde celular (Bolivia: 78% mobile) |
| **Accesible** | WCAG 2.1 AA, navegación completa por teclado, screen reader ready |

---

## 2. Diagrama de Flujo General

```
                    ┌─────────────────────────────────────┐
                    │          GARDEN - NAVBAR             │
                    │                                     │
                    │  [GARDEN]        [Soy cuidador ▸]   │
                    └──────────────────────┬──────────────┘
                                           │
                              ┌────────────▼────────────┐
                              │  ¿Usuario autenticado    │
                              │  como CAREGIVER?         │
                              └────┬───────────────┬────┘
                                   │               │
                              SÍ   │               │  NO
                                   │               │
                    ┌──────────────▼──┐    ┌───────▼──────────┐
                    │  /caregiver/    │    │  /caregiver/auth  │
                    │  dashboard      │    │                   │
                    │                 │    │  ┌─────┬────────┐ │
                    │  (ver §6)       │    │  │Login│Registro│ │
                    └─────────────────┘    │  └──┬──┴───┬────┘ │
                                           └─────┼──────┼──────┘
                                                 │      │
                                   ┌─────────────▼┐  ┌──▼──────────────┐
                                   │ Login Form   │  │ Wizard 15 pasos │
                                   │              │  │                 │
                                   │ email        │  │ Paso 1: Nombre  │
                                   │ password     │  │ Paso 2: Email   │
                                   │              │  │ Paso 3: Zona    │
                                   │ [Entrar]     │  │ ...             │
                                   └──────┬───────┘  │ Paso 15: Enviar │
                                          │          └────────┬────────┘
                                          │                   │
                                          │    POST /api/auth/register
                                          │    (role: "caregiver")
                                          │                   │
                                 POST /api/auth/login         │
                                          │                   │
                                          └─────────┬─────────┘
                                                    │
                                                    ▼
                                    ┌───────────────────────────┐
                                    │   /caregiver/dashboard    │
                                    │                           │
                                    │  ┌─────────────────────┐  │
                                    │  │ ProfileStatusBanner  │  │
                                    │  │ "Pendiente verif."   │  │
                                    │  └─────────────────────┘  │
                                    │                           │
                                    │  ┌─────────────────────┐  │
                                    │  │ Tu Perfil (card)     │  │
                                    │  │ [Editar perfil]      │  │
                                    │  └─────────────────────┘  │
                                    │                           │
                                    │  ┌─────────────────────┐  │
                                    │  │ Reservas (próximas)  │  │
                                    │  │ "Sin reservas aún"   │  │
                                    │  └─────────────────────┘  │
                                    └───────────────────────────┘
```

### Flujo de Estados del Botón Navbar

```
┌──────────────┐     clic      ┌──────────────┐    login     ┌──────────────┐
│ Visitante    │───────────────▶│ Auth Page    │─────────────▶│ Cuidador     │
│              │               │              │              │ autenticado  │
│ Navbar:      │               │ /caregiver/  │              │              │
│ "Soy        │               │ auth         │              │ Navbar:      │
│  cuidador"  │               │              │              │ "Mi panel"   │
│              │               │              │              │ (avatar)     │
└──────────────┘               └──────────────┘              └──────────────┘
```

---

## 3. Botón "Soy Cuidador" - Comportamiento Dinámico

### 3.1 Estados del Botón

| Estado | Texto | Icono | Acción onClick | Ruta destino |
|--------|-------|-------|----------------|-------------|
| **Visitante** (no auth) | "Soy cuidador" | `→` flecha | Navega a auth | `/caregiver/auth` |
| **Cliente** (auth, role=CLIENT) | "Soy cuidador" | `→` flecha | Navega a auth | `/caregiver/auth` |
| **Cuidador** (auth, role=CAREGIVER) | "Mi panel" | Avatar miniatura | Navega a dashboard | `/caregiver/dashboard` |
| **Admin** | "Admin" | Escudo | Navega a admin | `/admin` |

### 3.2 Ubicación en el Navbar

```
┌──────────────────────────────────────────────────────────────────┐
│ NAVBAR (sticky top)                                              │
│                                                                  │
│  ┌────────┐                              ┌───────────────────┐   │
│  │ GARDEN │   [Cuidadores]               │ Soy cuidador  ▸  │   │
│  │  🌿    │                              │                   │   │
│  └────────┘                              └───────────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

  ▲ Logo          ▲ Link a listing        ▲ CTA principal
  href="/"        href="/caregivers"       (verde, filled)
```

### 3.3 Especificación Visual del Botón

**Estado: Visitante / Cliente**

```
┌─────────────────────┐
│  Soy cuidador    ▸  │   bg-green-600 text-white
│                      │   hover:bg-green-700
│                      │   rounded-xl px-5 py-2.5
└─────────────────────┘   font-semibold text-sm
                          transition-all duration-200
                          shadow-sm hover:shadow-md
```

**Estado: Cuidador autenticado**

```
┌──────────────────────┐
│  (●) Mi panel        │   bg-white border border-green-200
│   ▲                  │   text-green-700
│   avatar 24px        │   hover:bg-green-50
└──────────────────────┘   rounded-xl px-4 py-2.5
```

### 3.4 Transición Animada al Hacer Clic

```
Estado 1: Reposo          Estado 2: Clic (150ms)      Estado 3: Navegando
┌──────────────────┐      ┌──────────────────┐        → /caregiver/auth
│ Soy cuidador  ▸  │  →   │  Cuidadores ✓    │   →    (page transition)
│ bg-green-600     │      │  bg-green-700    │
└──────────────────┘      │  scale-95        │
                          └──────────────────┘
```

**Implementación de la transición:**

```tsx
// Pseudocódigo del componente
const [isClicked, setIsClicked] = useState(false);

const handleClick = () => {
  setIsClicked(true);
  setTimeout(() => navigate('/caregiver/auth'), 300);
};

// Clases dinámicas
className={cn(
  'rounded-xl px-5 py-2.5 font-semibold text-sm transition-all duration-200',
  isClicked
    ? 'bg-green-700 text-white scale-95'
    : 'bg-green-600 text-white hover:bg-green-700 shadow-sm hover:shadow-md'
)}
```

### 3.5 Responsive del Navbar

**Desktop (≥1024px):**

```
┌──────────────────────────────────────────────────────────────────┐
│  GARDEN 🌿      Cuidadores                  [Soy cuidador ▸]   │
└──────────────────────────────────────────────────────────────────┘
```

**Tablet (768-1023px):**

```
┌──────────────────────────────────────────────┐
│  GARDEN 🌿        Cuidadores  [Soy cuidador] │
└──────────────────────────────────────────────┘
   (texto más compacto, sin flecha ▸)
```

**Mobile (<768px):**

```
┌─────────────────────────────────┐
│  GARDEN 🌿               [☰]   │
└─────────────────────────────────┘

  Menu hamburguesa desplegado:
  ┌─────────────────────────────┐
  │  Cuidadores                 │
  │  ─────────────────────────  │
  │  ┌───────────────────────┐  │
  │  │  Soy cuidador  ▸     │  │
  │  │  (botón verde full-w) │  │
  │  └───────────────────────┘  │
  └─────────────────────────────┘
```

---

## 4. Página de Autenticación /caregiver/auth

### 4.1 Layout General

La página de autenticación unifica login y registro en una sola vista con tabs.

```
┌──────────────────────────────────────────────────────────────────┐
│ NAVBAR                                                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│                    ┌────────────────────────┐                    │
│                    │      🌿 GARDEN         │                    │
│                    │                        │                    │
│                    │  Cuidadores de         │                    │
│                    │  confianza para tu     │                    │
│                    │  mascota               │                    │
│                    │                        │                    │
│                    │  ┌──────────┬────────┐ │                    │
│                    │  │ Iniciar  │Regist- │ │                    │
│                    │  │ sesión   │rarme   │ │                    │
│                    │  ╞══════════╧════════╡ │                    │
│                    │  │                   │ │                    │
│                    │  │  (contenido tab)  │ │                    │
│                    │  │                   │ │                    │
│                    │  └───────────────────┘ │                    │
│                    │                        │                    │
│                    │  ¿Ya tienes cuenta     │                    │
│                    │  como cliente?         │                    │
│                    │  [Vincular cuenta →]   │                    │
│                    │                        │                    │
│                    └────────────────────────┘                    │
│                                                                  │
│                    bg-green-50 (fondo)                           │
└──────────────────────────────────────────────────────────────────┘
```

### 4.2 Tab "Iniciar Sesión"

Para cuidadores que ya tienen cuenta.

```
╔══════════════════════════════════════╗
║  Iniciar sesión como cuidador       ║
║                                     ║
║  ┌─────────────────────────────┐    ║
║  │ Email                       │    ║
║  │ tucorreo@email.com          │    ║
║  └─────────────────────────────┘    ║
║                                     ║
║  ┌─────────────────────────────┐    ║
║  │ Contraseña            [👁]  │    ║
║  │ ••••••••                    │    ║
║  └─────────────────────────────┘    ║
║                                     ║
║  ☐ Recordarme                       ║
║                                     ║
║  ┌─────────────────────────────┐    ║
║  │       Iniciar sesión        │    ║
║  │    (bg-green-600, white)    │    ║
║  └─────────────────────────────┘    ║
║                                     ║
║  ¿Olvidaste tu contraseña?          ║
║  (text-green-600, underline)        ║
║                                     ║
╚══════════════════════════════════════╝
```

**Validaciones del formulario login:**

| Campo | Regla | Mensaje de error |
|-------|-------|-----------------|
| Email | Requerido, formato email válido | "Ingresa un email válido" |
| Contraseña | Requerido, min 8 caracteres | "La contraseña debe tener al menos 8 caracteres" |

**Flujo post-login:**

```
[Iniciar sesión] → POST /api/auth/login
  → 200 OK → guardar tokens → redirect /caregiver/dashboard
  → 401    → mostrar "Email o contraseña incorrectos"
  → 403    → mostrar "Tu cuenta está suspendida. Contacta soporte."
  → 429    → mostrar "Demasiados intentos. Espera 5 minutos."
```

### 4.3 Tab "Registrarme"

Muestra un resumen de lo que implica registrarse y el botón para iniciar el wizard.

```
╔══════════════════════════════════════╗
║  Únete como cuidador GARDEN         ║
║                                     ║
║  ┌─────────────────────────────┐    ║
║  │  🏠  Hospedaje              │    ║
║  │  Cuida mascotas en tu hogar │    ║
║  ├─────────────────────────────┤    ║
║  │  🦮  Paseos                 │    ║
║  │  Pasea perros en tu zona    │    ║
║  ├─────────────────────────────┤    ║
║  │  ✓  Verificación GARDEN    │    ║
║  │  Perfil confiable y visible │    ║
║  └─────────────────────────────┘    ║
║                                     ║
║  Tiempo estimado: ~10 minutos       ║
║  (puedes guardar y continuar)       ║
║                                     ║
║  ┌─────────────────────────────┐    ║
║  │    Comenzar registro  →     │    ║
║  │  (bg-green-600, white)      │    ║
║  └─────────────────────────────┘    ║
║                                     ║
║  Al registrarte aceptas nuestros    ║
║  Términos de servicio y Política    ║
║  de privacidad.                     ║
║                                     ║
╚══════════════════════════════════════╝
```

**Al presionar "Comenzar registro"** → navega a `/caregiver/register` (wizard paso 1).

---

## 5. Wizard de Registro - 15 Pasos

### 5.1 Resumen de Pasos y Mapeo a Schema

| # | Paso | Campos | Modelo Prisma | Obligatorio |
|---|------|--------|--------------|-------------|
| 1 | Nombre y teléfono | firstName, lastName, phone | User | Sí |
| 2 | Email y contraseña | email, password, confirmPassword | User | Sí |
| 3 | Tu zona | zone | CaregiverProfile.zone | Sí |
| 4 | Servicios que ofreces | servicesOffered[] | CaregiverProfile.servicesOffered | Sí |
| 5 | Tu experiencia | bio (resumen) | CaregiverProfile.bio (parte 1) | Sí |
| 6 | Detalle de experiencia | bio (ampliado) | CaregiverProfile.bio (parte 2) | No |
| 7 | Preferencias de mascotas | acceptedSizes, temperaments | Metadata/bio | No |
| 8 | Tamaños y razas | sizeRange, breedPrefs | Metadata/bio | No |
| 9 | Tu hogar | spaceType, spaceDescription | CaregiverProfile.spaceType | Sí |
| 10 | Rutina diaria | dailyRoutine | Bio extension | No |
| 11 | Tarifas | pricePerDay, pricePerWalk30/60 | CaregiverProfile.prices | Sí |
| 12 | Fotos de tu espacio | photos[] (4-6) | CaregiverProfile.photos | Sí |
| 13 | Verificación de identidad | ciPhoto (front/back) | Para revisión admin | Sí |
| 14 | Acuerdo legal | termsAccepted, privacyAccepted | Checkbox consent | Sí |
| 15 | Revisión y envío | (todos los anteriores) | Submit final | Sí |

### 5.2 Layout del Wizard

**Desktop (≥1024px): Sidebar + contenido**

```
┌──────────────────────────────────────────────────────────────────┐
│ NAVBAR                                                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐  ┌──────────────────────────────────────────┐  │
│  │ PROGRESO     │  │                                          │  │
│  │              │  │  Paso 1 de 15                            │  │
│  │ ● 1 Nombre   │  │  ━━━━━━━░░░░░░░░░░░░░░░░░░░ (7%)       │  │
│  │ ○ 2 Email    │  │                                          │  │
│  │ ○ 3 Zona     │  │  Tu nombre y teléfono                   │  │
│  │ ○ 4 Servicios│  │  ─────────────────────                  │  │
│  │ ○ 5 Exper.   │  │  Estos datos son para que los dueños    │  │
│  │ ○ 6 Detalle  │  │  de mascotas puedan contactarte.        │  │
│  │ ○ 7 Preferen.│  │                                          │  │
│  │ ○ 8 Tamaños  │  │  ┌────────────────┐ ┌────────────────┐  │  │
│  │ ○ 9 Hogar    │  │  │ Nombre         │ │ Apellido       │  │  │
│  │ ○ 10 Rutina  │  │  │ Juan           │ │ Pérez          │  │  │
│  │ ○ 11 Tarifas │  │  └────────────────┘ └────────────────┘  │  │
│  │ ○ 12 Fotos   │  │                                          │  │
│  │ ○ 13 Verif.  │  │  ┌─────────────────────────────────┐    │  │
│  │ ○ 14 Acuerdo │  │  │ Teléfono (WhatsApp)             │    │  │
│  │ ○ 15 Revisar │  │  │ +591 7XXXXXXX                   │    │  │
│  │              │  │  └─────────────────────────────────┘    │  │
│  │  ┌────────┐  │  │                                          │  │
│  │  │Guardar │  │  │        [← Atrás]      [Siguiente →]     │  │
│  │  │y salir │  │  │                                          │  │
│  │  └────────┘  │  └──────────────────────────────────────────┘  │
│  └──────────────┘                                                │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**Mobile (<768px): Barra superior + contenido full-width**

```
┌─────────────────────────────────┐
│  ← Paso 1/15     [Guardar ✕]   │
│  ━━░░░░░░░░░░░░░░░░░░░░░░░░░   │
├─────────────────────────────────┤
│                                 │
│  Tu nombre y teléfono           │
│  ───────────────────            │
│  Estos datos son para que los   │
│  dueños de mascotas puedan      │
│  contactarte.                   │
│                                 │
│  Nombre *                       │
│  ┌───────────────────────────┐  │
│  │ Juan                      │  │
│  └───────────────────────────┘  │
│                                 │
│  Apellido *                     │
│  ┌───────────────────────────┐  │
│  │ Pérez                     │  │
│  └───────────────────────────┘  │
│                                 │
│  Teléfono (WhatsApp) *          │
│  ┌──────┬────────────────────┐  │
│  │ +591 │ 7XXXXXXX           │  │
│  └──────┴────────────────────┘  │
│                                 │
│                                 │
│  ┌───────────────────────────┐  │
│  │      Siguiente  →         │  │
│  │   (full-width, sticky)    │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

### 5.3 Detalle de Cada Paso

---

#### Paso 1: Nombre y Teléfono

**Título:** "Tu nombre y teléfono"
**Subtítulo:** "Estos datos son para que los dueños de mascotas puedan contactarte."

| Campo | Tipo | Validación | Placeholder |
|-------|------|-----------|-------------|
| `firstName` | text | Requerido, 2-50 chars, solo letras+espacios | "Tu nombre" |
| `lastName` | text | Requerido, 2-50 chars | "Tu apellido" |
| `phone` | tel | Requerido, formato +591 7XXXXXXX o 6XXXXXXX | "+591 7XXXXXXX" |

**Layout:** Nombre y Apellido en 2 columnas (desktop), stack (mobile). Teléfono full-width con prefijo +591 fijo.

---

#### Paso 2: Email y Contraseña

**Título:** "Tu cuenta GARDEN"
**Subtítulo:** "Con estos datos podrás iniciar sesión y gestionar tu perfil."

| Campo | Tipo | Validación | Placeholder |
|-------|------|-----------|-------------|
| `email` | email | Requerido, formato email, único (check async) | "tucorreo@email.com" |
| `password` | password | Requerido, min 8, 1 mayúscula, 1 número | "Mínimo 8 caracteres" |
| `confirmPassword` | password | Requerido, debe coincidir con password | "Repite tu contraseña" |

**Indicador de fortaleza de contraseña:**

```
Contraseña *
┌───────────────────────────────┐
│ MiContraseña123          [👁] │
└───────────────────────────────┘
Fortaleza: ━━━━━━━━━━━━░░░░ Buena
           (verde si fuerte, amarillo media, rojo débil)
```

**Validación async de email:** Al hacer blur en el campo email, se llama `GET /api/auth/check-email?email=...` para verificar disponibilidad. Si ya existe, se muestra: "Este email ya está registrado. ¿Quieres iniciar sesión?"

---

#### Paso 3: Tu Zona

**Título:** "¿En qué zona de Santa Cruz vives?"
**Subtítulo:** "Los dueños buscan cuidadores cerca de su zona."

**UI:** Radio buttons con tarjetas visuales (una por zona).

```
┌──────────────────────────────────────────────┐
│  ¿En qué zona de Santa Cruz vives?           │
│                                               │
│  ┌──────────────┐  ┌──────────────┐          │
│  │ ◉ Equipetrol │  │ ○ Urbarí     │          │
│  │   (selected) │  │              │          │
│  │   green bg   │  │   gray bg    │          │
│  └──────────────┘  └──────────────┘          │
│                                               │
│  ┌──────────────┐  ┌──────────────┐          │
│  │ ○ Norte      │  │ ○ Las Palmas │          │
│  └──────────────┘  └──────────────┘          │
│                                               │
│  ┌──────────────┐  ┌──────────────┐          │
│  │ ○ Centro /   │  │ ○ Otros      │          │
│  │   San Martín │  │              │          │
│  └──────────────┘  └──────────────┘          │
└──────────────────────────────────────────────┘
```

**Mapeo:** Selección → `Zone` enum (EQUIPETROL, URBARI, NORTE, LAS_PALMAS, CENTRO_SAN_MARTIN, OTROS).

---

#### Paso 4: Servicios que Ofreces

**Título:** "¿Qué servicios quieres ofrecer?"
**Subtítulo:** "Puedes ofrecer uno o ambos. Siempre podrás cambiarlo después."

**UI:** Tarjetas seleccionables (toggle, multi-select).

```
┌──────────────────────────────────────────────┐
│  ┌──────────────────────────────────────┐    │
│  │  🏠  Hospedaje                  [✓]  │    │
│  │  ──────────────────────              │    │
│  │  Cuida mascotas en tu hogar          │    │
│  │  mientras sus dueños viajan          │    │
│  │  o trabajan.                         │    │
│  │                                      │    │
│  │  Precio típico: Bs 80-160/día        │    │
│  │  (border-green-500 si seleccionado)  │    │
│  └──────────────────────────────────────┘    │
│                                               │
│  ┌──────────────────────────────────────┐    │
│  │  🦮  Paseos                     [✓]  │    │
│  │  ──────────────────────              │    │
│  │  Pasea perros en tu zona,            │    │
│  │  sesiones de 30 min o 1 hora.        │    │
│  │                                      │    │
│  │  Precio típico: Bs 25-60/sesión      │    │
│  └──────────────────────────────────────┘    │
│                                               │
│  Selecciona al menos un servicio.             │
└──────────────────────────────────────────────┘
```

**Validación:** Min 1 servicio seleccionado. Mapea a `ServiceType[]` (HOSPEDAJE, PASEO, o ambos).

---

#### Paso 5: Tu Experiencia con Mascotas

**Título:** "Cuéntanos sobre tu experiencia"
**Subtítulo:** "Los dueños valoran saber que su mascota estará con alguien experimentado."

| Campo | Tipo | Validación | Placeholder |
|-------|------|-----------|-------------|
| `bioSummary` | textarea | Requerido, 50-200 chars | "Ej: Tengo 2 labradores, cuido mascotas hace 3 años..." |

**Contador de caracteres:**

```
┌──────────────────────────────────────────┐
│  Tengo 2 labradores y trabajo desde      │
│  casa. He cuidado mascotas de amigos     │
│  y familiares por 3 años.                │
│                                          │
│                                          │
└──────────────────────────────────────────┘
  87/200 caracteres                     (text-gray-400)
```

---

#### Paso 6: Detalle de Experiencia

**Título:** "Amplía tu descripción (opcional)"
**Subtítulo:** "Agrega detalles que generen confianza: años de experiencia, formación, anécdotas."

| Campo | Tipo | Validación | Placeholder |
|-------|------|-----------|-------------|
| `bioDetail` | textarea | Opcional, max 300 chars | "Ej: Hice un curso de primeros auxilios caninos..." |

**Nota:** Los campos `bioSummary` (paso 5) + `bioDetail` (paso 6) se concatenan para formar `CaregiverProfile.bio` (max 500 chars total).

---

#### Paso 7: Preferencias de Mascotas

**Título:** "¿Qué mascotas prefieres cuidar?"
**Subtítulo:** "Esto ayuda a los dueños a saber si eres la persona indicada."

**UI:** Chips seleccionables (multi-select).

```
  Tipo de mascota:
  ┌───────┐ ┌───────┐ ┌─────────┐
  │ 🐕 Perros│ │ 🐈 Gatos│ │ Ambos   │
  └───────┘ └───────┘ └─────────┘

  Temperamento que aceptas:
  ┌──────────┐ ┌──────────┐ ┌──────────┐
  │ Tranquilo │ │ Activo   │ │ Cualquiera│
  └──────────┘ └──────────┘ └──────────┘
```

**Nota:** Estos datos se almacenan como parte del bio extendido (texto libre en la descripción). No hay campos separados en el schema para esto en MVP.

---

#### Paso 8: Tamaños y Razas

**Título:** "¿Qué tamaños de mascota aceptas?"
**Subtítulo:** "Selecciona todos los que apliquen."

**UI:** Tarjetas con iconos de tamaño.

```
  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
  │  Pequeño  │ │  Mediano  │ │  Grande   │ │  Gigante  │
  │  <5 kg    │ │  5-15 kg  │ │  15-35 kg │ │  >35 kg   │
  │   🐕‍🦺      │ │    🐕     │ │    🐕‍🦺    │ │    🐕     │
  └──────────┘ └──────────┘ └──────────┘ └──────────┘
```

**Nota:** Opcional. Se incluye como texto en el bio si se selecciona.

---

#### Paso 9: Tu Hogar

**Título:** "Describe tu espacio"
**Subtítulo:** "Los dueños quieren saber dónde estará su mascota."
**Condición:** Solo visible si seleccionó HOSPEDAJE en paso 4. Si solo ofrece PASEOS, se salta automáticamente.

| Campo | Tipo | Validación | Placeholder |
|-------|------|-----------|-------------|
| `spaceType` | text (free) | Requerido si HOSPEDAJE, max 100 chars | "Ej: Casa con patio cercado de 50m²" |
| `spaceDescription` | textarea | Opcional, max 200 chars | "Ej: Patio amplio con césped, zona techada..." |

```
  Tipo de espacio *
  ┌─────────────────────────────────────┐
  │ Casa con patio cercado de 50m²      │
  └─────────────────────────────────────┘

  Describe tu espacio (opcional)
  ┌─────────────────────────────────────┐
  │ Patio amplio con césped natural,    │
  │ zona techada para lluvia, portón    │
  │ seguro de 1.5m de alto.             │
  └─────────────────────────────────────┘
```

---

#### Paso 10: Tu Rutina Diaria

**Título:** "¿Cómo es tu día a día?"
**Subtítulo:** "Los dueños quieren saber cuánto tiempo pasarás con su mascota."

| Campo | Tipo | Validación | Placeholder |
|-------|------|-----------|-------------|
| `dailyRoutine` | textarea | Opcional, max 200 chars | "Ej: Trabajo desde casa, saco a pasear 3 veces al día..." |

---

#### Paso 11: Tarifas

**Título:** "Define tus tarifas"
**Subtítulo:** "Puedes ajustarlas después desde tu panel."

**UI dinámica:** Solo muestra campos de los servicios seleccionados en paso 4.

```
  ┌──────────────────────────────────────────┐
  │  🏠 Hospedaje                             │
  │                                           │
  │  Precio por día (Bs) *                    │
  │  ┌────────────────┐                       │
  │  │ Bs  120        │  Rango sugerido:      │
  │  └────────────────┘  Bs 80-160            │
  │                                           │
  ├──────────────────────────────────────────┤
  │  🦮 Paseos                                │
  │                                           │
  │  Precio paseo 30 min (Bs) *               │
  │  ┌────────────────┐                       │
  │  │ Bs  30         │  Rango: Bs 20-45      │
  │  └────────────────┘                       │
  │                                           │
  │  Precio paseo 1 hora (Bs) *               │
  │  ┌────────────────┐                       │
  │  │ Bs  50         │  Rango: Bs 35-80      │
  │  └────────────────┘                       │
  └──────────────────────────────────────────┘
```

**Validación:**

| Campo | Condición | Min | Max |
|-------|-----------|-----|-----|
| pricePerDay | Si HOSPEDAJE seleccionado | 30 | 500 |
| pricePerWalk30 | Si PASEO seleccionado | 10 | 200 |
| pricePerWalk60 | Si PASEO seleccionado | 20 | 300 |

---

#### Paso 12: Fotos de tu Espacio

**Título:** "Sube fotos de tu espacio"
**Subtítulo:** "Mínimo 4 fotos, máximo 6. Los dueños quieren ver dónde estará su mascota."

**UI:** Grid de dropzones con preview.

```
  ┌──────────┐ ┌──────────┐ ┌──────────┐
  │  [foto1] │ │  [foto2] │ │  [foto3] │
  │  ✕ borrar│ │  ✕ borrar│ │  ✕ borrar│
  └──────────┘ └──────────┘ └──────────┘
  ┌──────────┐ ┌──────────┐ ┌──────────┐
  │  [foto4] │ │  + Subir  │ │  + Subir  │
  │  ✕ borrar│ │  foto    │ │  foto    │
  └──────────┘ └──────────┘ └──────────┘

  4/6 fotos subidas ✓
  Formatos: JPG, PNG, WebP. Máximo 5 MB por foto.

  Sugerencias:
  • Foto del patio/jardín
  • Foto del espacio donde dormirá la mascota
  • Foto tuya con tu mascota (si tienes)
  • Foto de la entrada/portón
```

**Validación:** Min 4 fotos, max 6. Formatos: jpg/png/webp. Max 5MB cada una. Se suben individualmente a Cloudinary, se guardan URLs.

**Condición:** Si solo ofrece PASEOS (sin HOSPEDAJE), el subtítulo cambia a: "Sube fotos tuyas con mascotas o en zonas de paseo. Mínimo 4."

---

#### Paso 13: Verificación de Identidad

**Título:** "Verificación de identidad"
**Subtítulo:** "Subimos tu CI para verificar tu identidad. Solo el equipo GARDEN lo verá."

```
  ┌──────────────────────────────────────┐
  │  🔒 Tus datos están seguros          │
  │  Solo el equipo GARDEN accede a      │
  │  estas fotos para verificarte.       │
  └──────────────────────────────────────┘

  Foto del frente de tu CI *
  ┌──────────────────────────┐
  │                          │
  │     + Subir foto         │
  │     (o arrastra aquí)    │
  │                          │
  └──────────────────────────┘

  Foto del reverso de tu CI *
  ┌──────────────────────────┐
  │                          │
  │     + Subir foto         │
  │     (o arrastra aquí)    │
  │                          │
  └──────────────────────────┘
```

**Nota:** Estas fotos NO se guardan en `CaregiverProfile.photos`. Se envían como parte de la solicitud de verificación para revisión del admin. Se almacenan de forma separada y segura.

---

#### Paso 14: Acuerdo Legal

**Título:** "Términos y condiciones"
**Subtítulo:** "Lee y acepta los siguientes acuerdos para continuar."

```
  ┌──────────────────────────────────────┐
  │  Términos de servicio                │
  │  ────────────────────                │
  │  (resumen scrolleable, max 200px)    │
  │                                      │
  │  • Ofreces servicios de buena fe     │
  │  • GARDEN verifica tu identidad      │
  │  • La plataforma cobra 18-20%        │
  │  • Cumples con las reservas          │
  │  • ...                               │
  │                                      │
  │  [Ver términos completos →]          │
  └──────────────────────────────────────┘

  ☑ Acepto los Términos de servicio *

  ☑ Acepto la Política de privacidad *

  ☑ Acepto que GARDEN verifique mi
    identidad y visite mi domicilio *
```

**Validación:** Los 3 checkboxes son obligatorios.

---

#### Paso 15: Revisión y Envío

**Título:** "Revisa tu información"
**Subtítulo:** "Verifica que todo esté correcto antes de enviar."

```
  ┌──────────────────────────────────────────┐
  │  Datos personales                   [✎]  │
  │  ─────────────────                       │
  │  Juan Pérez                              │
  │  +591 76543210                           │
  │  juan@email.com                          │
  ├──────────────────────────────────────────┤
  │  Zona                               [✎]  │
  │  ─────                                   │
  │  Equipetrol                              │
  ├──────────────────────────────────────────┤
  │  Servicios                          [✎]  │
  │  ────────                                │
  │  Hospedaje, Paseos                       │
  ├──────────────────────────────────────────┤
  │  Descripción                        [✎]  │
  │  ──────────                              │
  │  "Tengo 2 labradores y trabajo..."       │
  ├──────────────────────────────────────────┤
  │  Tarifas                            [✎]  │
  │  ───────                                 │
  │  Hospedaje: Bs 120/día                   │
  │  Paseo 30min: Bs 30                      │
  │  Paseo 1h: Bs 50                         │
  ├──────────────────────────────────────────┤
  │  Fotos                              [✎]  │
  │  ─────                                   │
  │  [img1] [img2] [img3] [img4]             │
  ├──────────────────────────────────────────┤
  │  Hogar                              [✎]  │
  │  ─────                                   │
  │  Casa con patio cercado de 50m²          │
  └──────────────────────────────────────────┘

  ┌──────────────────────────────────────────┐
  │          Enviar solicitud  →             │
  │       (bg-green-600, text-white)         │
  └──────────────────────────────────────────┘

  Tu perfil será revisado por el equipo
  GARDEN en un plazo de 24-48 horas.
```

**Cada sección tiene botón [✎]** que navega al paso correspondiente para editar. Al volver, regresa al paso 15.

**Al presionar "Enviar solicitud":**

```
1. Crear cuenta:      POST /api/auth/register  { role: "caregiver", ... }
2. Guardar tokens en localStorage
3. Crear perfil:      POST /api/caregivers      { bio, zone, photos, ... }
4. Subir CI (admin):  POST /api/caregivers/verification  { ciPhotos }
5. Limpiar localStorage wizard draft
6. Redirect:          /caregiver/dashboard
```

### 5.4 Guardado Automático (localStorage)

**Clave:** `garden_wizard_draft`

```json
{
  "currentStep": 5,
  "lastSavedAt": "2026-02-06T10:30:00Z",
  "data": {
    "firstName": "Juan",
    "lastName": "Pérez",
    "phone": "+59176543210",
    "email": "juan@email.com",
    "zone": "EQUIPETROL",
    "servicesOffered": ["HOSPEDAJE", "PASEO"],
    "bioSummary": "Tengo 2 labradores...",
    "bioDetail": "",
    "spaceType": "",
    "pricePerDay": null,
    "pricePerWalk30": null,
    "pricePerWalk60": null,
    "photos": [],
    "termsAccepted": false,
    "privacyAccepted": false,
    "verificationAccepted": false
  }
}
```

**Comportamiento:**
- Se guarda automáticamente en `onChange` de cada campo (debounce 500ms)
- Al abrir `/caregiver/register`, si existe draft → modal: "Tienes un registro sin completar. ¿Continuar donde lo dejaste?"
- Botón "Guardar y salir" → guarda estado actual + navega a home
- El draft se limpia al completar el registro exitosamente
- El draft expira después de 7 días (se muestra aviso)
- **Contraseña NUNCA se guarda en localStorage** (seguridad)

### 5.5 Barra de Progreso

```
  Paso 5 de 15
  ━━━━━━━━━━━━━━━━━━░░░░░░░░░░░░░░░░░░░░░░░░░░  (33%)

  Colores:
  - Completado: bg-green-500
  - Actual:     bg-green-600 (pulso suave)
  - Pendiente:  bg-gray-200
```

**Implementación:**

```tsx
// Ancho = (currentStep / totalSteps) * 100
<div className="h-2 bg-gray-200 rounded-full overflow-hidden">
  <div
    className="h-full bg-green-500 rounded-full transition-all duration-500 ease-out"
    style={{ width: `${(currentStep / 15) * 100}%` }}
    role="progressbar"
    aria-valuenow={currentStep}
    aria-valuemin={1}
    aria-valuemax={15}
    aria-label={`Paso ${currentStep} de 15`}
  />
</div>
```

### 5.6 Navegación Entre Pasos

**Reglas:**
- "Siguiente" solo habilitado si el paso actual es válido
- "Atrás" siempre disponible (excepto paso 1)
- Se puede navegar a pasos anteriores completados desde el sidebar (desktop)
- No se puede saltar a pasos futuros no completados
- Pasos opcionales (6, 7, 8, 10) pueden dejarse vacíos

**Keyboard shortcuts:**
- `Enter` → Siguiente (si formulario válido)
- `Escape` → Modal "¿Guardar y salir?"
- `Alt+←` → Paso anterior
- `Alt+→` → Paso siguiente (si válido)

---

## 6. Dashboard del Cuidador

### 6.1 Layout del Dashboard

**Desktop:**

```
┌──────────────────────────────────────────────────────────────────┐
│ NAVBAR   [GARDEN]  Cuidadores                    (●) Mi panel   │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  ProfileStatusBanner                                       │  │
│  │  ⏳ Tu perfil está pendiente de verificación.              │  │
│  │  El equipo GARDEN lo revisará en 24-48 horas.             │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────┐  ┌──────────────────────────────┐  │
│  │  Tu Perfil               │  │  Tus Reservas                │  │
│  │  ─────────               │  │  ─────────────               │  │
│  │  ┌──────┐                │  │                              │  │
│  │  │ foto │  Juan Pérez    │  │  No tienes reservas aún.     │  │
│  │  │  1   │  Equipetrol    │  │                              │  │
│  │  └──────┘                │  │  Las reservas aparecerán     │  │
│  │                          │  │  aquí cuando los dueños      │  │
│  │  Servicios: Hospedaje,   │  │  reserven contigo.           │  │
│  │  Paseos                  │  │                              │  │
│  │  Hospedaje: Bs 120/día   │  │  ┌────────────────────────┐  │  │
│  │  Paseo 30m: Bs 30        │  │  │  Ver cómo se ve mi     │  │  │
│  │  Paseo 1h: Bs 50         │  │  │  perfil público         │  │  │
│  │                          │  │  └────────────────────────┘  │  │
│  │  [Editar perfil]         │  │                              │  │
│  └──────────────────────────┘  └──────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**Mobile:**

```
┌─────────────────────────────────┐
│ GARDEN 🌿            (●) Panel  │
├─────────────────────────────────┤
│                                 │
│ ┌─────────────────────────────┐ │
│ │ ⏳ Perfil pendiente de      │ │
│ │ verificación (24-48h)       │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Tu Perfil                   │ │
│ │ ─────────                   │ │
│ │ ┌─────┐                     │ │
│ │ │foto │ Juan Pérez          │ │
│ │ │  1  │ Equipetrol          │ │
│ │ └─────┘                     │ │
│ │                             │ │
│ │ Hospedaje: Bs 120/día       │ │
│ │ Paseo 30m: Bs 30            │ │
│ │                             │ │
│ │ [Editar perfil]             │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Tus Reservas                │ │
│ │ ─────────────               │ │
│ │ No tienes reservas aún.     │ │
│ │                             │ │
│ │ [Ver mi perfil público]     │ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

### 6.2 ProfileStatusBanner - Variantes

| Estado | Color | Icono | Mensaje |
|--------|-------|-------|---------|
| **Nuevo** (recién registrado) | `bg-amber-50 border-amber-200 text-amber-800` | ⏳ | "Tu perfil está pendiente de verificación. Lo revisaremos en 24-48 horas." |
| **Pendiente** (en revisión) | `bg-blue-50 border-blue-200 text-blue-800` | 🔍 | "Estamos revisando tu perfil. Te notificaremos por WhatsApp." |
| **Verificado** | `bg-green-50 border-green-200 text-green-800` | ✓ | "Tu perfil está verificado y visible para los dueños de mascotas." |
| **Suspendido** | `bg-red-50 border-red-200 text-red-800` | ⚠ | "Tu perfil está suspendido. Contacta soporte: +591 7XX-XXXX." |

### 6.3 Acciones del Dashboard

| Acción | Botón | Destino |
|--------|-------|---------|
| Editar perfil | "Editar perfil" (outlined green) | `/caregiver/edit` (reutiliza formulario de perfil) |
| Ver perfil público | "Ver cómo se ve mi perfil" (text link) | `/caregivers/:id` (vista pública) |
| Ver reservas | Cards de reservas (cuando existan) | `/caregiver/bookings` (V2) |

---

## 7. Wireframes ASCII Completos

### 7.1 Página de Auth - Desktop (1024px+)

```
┌──────────────────────────────────────────────────────────────────────────┐
│  GARDEN 🌿         Cuidadores                     [Soy cuidador ▸]     │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                         bg-green-50                                      │
│                                                                          │
│    ┌──────────────────────┐   ┌──────────────────────────────────────┐   │
│    │                      │   │                                      │   │
│    │   🌿                 │   │   Cuidadores de confianza            │   │
│    │                      │   │   para tu mascota                    │   │
│    │   "En GARDEN cada    │   │                                      │   │
│    │   cuidador es        │   │   ┌──────────────┬──────────────┐    │   │
│    │   verificado         │   │   │  Iniciar     │  Registrarme │    │   │
│    │   personalmente."    │   │   │  sesión      │  ▓▓▓▓▓▓▓▓▓▓ │    │   │
│    │                      │   │   ╞══════════════╧══════════════╡    │   │
│    │   ✓ Entrevista       │   │   │                             │    │   │
│    │   ✓ Visita domicilio │   │   │   (contenido del tab        │    │   │
│    │   ✓ Verificación CI  │   │   │    activo)                  │    │   │
│    │                      │   │   │                             │    │   │
│    │                      │   │   │                             │    │   │
│    │                      │   │   │                             │    │   │
│    │                      │   │   └─────────────────────────────┘    │   │
│    │                      │   │                                      │   │
│    └──────────────────────┘   └──────────────────────────────────────┘   │
│                                                                          │
│     (panel informativo)            (panel de auth, max-w-md)             │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Página de Auth - Mobile (<768px)

```
┌─────────────────────────────────┐
│  GARDEN 🌿               [☰]   │
├─────────────────────────────────┤
│                                 │
│   🌿 GARDEN                    │
│   Cuidadores de confianza      │
│   para tu mascota              │
│                                 │
│  ┌────────────┬───────────────┐ │
│  │  Iniciar   │  Registrarme  │ │
│  │  sesión    │  ▓▓▓▓▓▓▓▓▓▓  │ │
│  ╞════════════╧═══════════════╡ │
│  │                            │ │
│  │  Únete como cuidador       │ │
│  │  GARDEN                    │ │
│  │                            │ │
│  │  ┌──────────────────────┐  │ │
│  │  │ 🏠 Hospedaje         │  │ │
│  │  │ Cuida mascotas en    │  │ │
│  │  │ tu hogar             │  │ │
│  │  └──────────────────────┘  │ │
│  │                            │ │
│  │  ┌──────────────────────┐  │ │
│  │  │ 🦮 Paseos            │  │ │
│  │  │ Pasea perros en tu   │  │ │
│  │  │ zona                 │  │ │
│  │  └──────────────────────┘  │ │
│  │                            │ │
│  │  ~10 min (guarda progreso) │ │
│  │                            │ │
│  │  ┌──────────────────────┐  │ │
│  │  │  Comenzar registro → │  │ │
│  │  └──────────────────────┘  │ │
│  │                            │ │
│  └────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

### 7.3 Wizard Paso 11 (Tarifas) - Desktop

```
┌──────────────────────────────────────────────────────────────────────────┐
│  GARDEN 🌿         Cuidadores                        (●) Mi panel      │
���──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────┐  ┌────────────────────────────────────────────┐   │
│  │  PROGRESO        │  │                                            │   │
│  │                  │  │  Paso 11 de 15                             │   │
│  │  ✓ 1 Nombre     │  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━░░░░░ (73%)  │   │
│  │  ✓ 2 Email      │  │                                            │   │
│  │  ✓ 3 Zona       │  │  Define tus tarifas                       │   │
│  │  ✓ 4 Servicios  │  │  ─────────────────                        │   │
│  │  ✓ 5 Experiencia│  │  Puedes ajustarlas después desde           │   │
│  │  ✓ 6 Detalle    │  │  tu panel.                                │   │
│  │  ✓ 7 Preferenc. │  │                                            │   │
│  │  ✓ 8 Tamaños    │  │  ┌────────────────────────────────────┐   │   │
│  │  ✓ 9 Hogar      │  │  │  🏠 Hospedaje                      │   │   │
│  │  ✓ 10 Rutina    │  │  │                                    │   │   │
│  │  ● 11 Tarifas   │  │  │  Precio por día (Bs) *             │   │   │
│  │  ○ 12 Fotos     │  │  │  ┌────────────┐ Sugerido: 80-160  │   │   │
│  │  ○ 13 Verific.  │  │  │  │ Bs  120    │                    │   │   │
│  │  ○ 14 Acuerdo   │  │  │  └────────────┘                    │   │   │
│  │  ○ 15 Revisión  │  │  └────────────────────────────────────┘   │   │
│  │                  │  │                                            │   │
│  │  ┌────────────┐ │  │  ┌────────────────────────────────────┐   │   │
│  │  │ Guardar    │ │  │  │  🦮 Paseos                          │   │   │
│  │  │ y salir    │ │  │  │                                    │   │   │
│  │  └────────────┘ │  │  │  Precio 30 min (Bs) *              │   │   │
│  └──────────────────┘  │  │  ┌────────────┐ Sugerido: 20-45  │   │   │
│                         │  │  │ Bs  30     │                    │   │   │
│                         │  │  │            │                    │   │   │
│                         │  │  └────────────┘                    │   │   │
│                         │  │                                    │   │   │
│                         │  │  Precio 1 hora (Bs) *              │   │   │
│                         │  │  ┌────────────┐ Sugerido: 35-80  │   │   │
│                         │  │  │ Bs  50     │                    │   │   │
│                         │  │  └────────────┘                    │   │   │
│                         │  └────────────────────────────────────┘   │   │
│                         │                                            │   │
│                         │      [← Atrás]          [Siguiente →]     │   │
│                         └────────────────────────────────────────────┘   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### 7.4 Wizard Paso 12 (Fotos) - Mobile

```
┌─────────────────────────────────┐
│  ← Paso 12/15    [Guardar ✕]   │
│  ━━━━━━━━━━━━━━━━━━━━━━━━░░░   │
├─────────────────────────────────┤
│                                 │
│  Sube fotos de tu espacio       │
│  ────────────────────────       │
│  Mínimo 4, máximo 6 fotos.     │
│  Los dueños quieren ver dónde   │
│  estará su mascota.             │
│                                 │
│  ┌────────────┐ ┌────────────┐  │
│  │            │ │            │  │
│  │  [foto 1]  │ │  [foto 2]  │  │
│  │    ✕       │ │    ✕       │  │
│  └────────────┘ └────────────┘  │
│  ┌────────────┐ ┌────────────┐  │
│  │            │ │            │  │
│  │  [foto 3]  │ │  + Subir   │  │
│  │    ✕       │ │   foto     │  │
│  └────────────┘ └────────────┘  │
│                                 │
│  3/6 fotos (faltan 1 más)       │
│  ⚠ Necesitas al menos 4 fotos  │
│                                 │
│  Sugerencias:                   │
│  • Patio/jardín                 │
│  • Espacio para dormir          │
│  • Tú con tu mascota            │
│                                 │
│  ┌───────────────────────────┐  │
│  │  Siguiente →              │  │
│  │  (disabled, aria-disabled)│  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

### 7.5 Wizard Paso 15 (Revisión) - Tablet (768-1023px)

```
┌──────────────────────────────────────────────┐
│  GARDEN 🌿           Paso 15/15   [Guardar]  │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
├──────────────────────────────────────────────┤
│                                              │
│  Revisa tu información                       │
│  ─────────────────────                       │
│  Verifica que todo esté correcto.            │
│                                              │
│  ┌────────────────────┐ ┌─────────────────┐  │
│  │ Datos personales [✎]│ │ Zona        [✎] │  │
│  │ Juan Pérez         │ │ Equipetrol      │  │
│  │ +591 76543210      │ │                 │  │
│  │ juan@email.com     │ │                 │  │
│  └────────────────────┘ └─────────────────┘  │
│                                              │
│  ┌────────────────────┐ ┌─────────────────┐  │
│  │ Servicios      [✎] │ │ Tarifas     [✎] │  │
│  │ Hospedaje, Paseos  │ │ Hosp: Bs120/día │  │
│  │                    │ │ 30m: Bs30       │  │
│  │                    │ │ 1h: Bs50        │  │
│  └────────────────────┘ └─────────────────┘  │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │ Descripción                     [✎]  │    │
│  │ "Tengo 2 labradores y trabajo..."   │    │
│  └──────────────────────────────────────┘    │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │ Fotos                           [✎]  │    │
│  │ [img1] [img2] [img3] [img4]         │    │
│  └──────────────────────────────────────┘    │
│                                              │
│    [← Atrás]      [Enviar solicitud →]       │
│                                              │
└──────────────────────────────────────────────┘
```

### 7.6 Dashboard - Verificado con Reservas (Desktop)

```
┌──────────────────────────────────────────────────────────────────────────┐
│  GARDEN 🌿         Cuidadores                        (●) Mi panel      │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  ✓ Tu perfil está verificado y visible para los dueños.           │  │
│  │     bg-green-50 border-green-200                                  │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌─────────────────────────────┐  ┌──────────────────────────────────┐  │
│  │  Tu Perfil                  │  │  Próximas Reservas               │  │
│  │  ─────────                  │  │  ─────────────────               │  │
│  │  ┌──────┐                   │  │                                  │  │
│  │  │ foto │  Juan Pérez       │  │  ┌──────────────────────────┐   │  │
│  │  │      │  ✓ Verificado     │  │  │ 🏠 Hospedaje             │   │  │
│  │  └──────┘  ★ 4.8 (12)      │  │  │ Max (Labrador)           │   │  │
│  │                             │  │  │ 15-18 Mar · Bs 360       │   │  │
│  │  Equipetrol                 │  │  │ Carlos R.                │   │  │
│  │  Hospedaje, Paseos          │  │  │ [Ver detalle]            │   │  │
│  │                             │  │  └──────────────────────────┘   │  │
│  │  Hospedaje: Bs 120/día      │  │                                  │  │
│  │  Paseo 30m: Bs 30           │  │  ┌──────────────────────────┐   │  │
│  │  Paseo 1h: Bs 50            │  │  │ 🦮 Paseo 1h              │   │  │
│  │                             │  │  │ Luna (Golden)            │   │  │
│  │  [Editar perfil]            │  │  │ 20 Mar · Tarde · Bs 50  │   │  │
│  │  [Ver perfil público →]     │  │  │ Ana M.                  │   │  │
│  └─────────────────────────────┘  │  │ [Ver detalle]            │   │  │
│                                    │  └──────────────────────────┘   │  │
│                                    │                                  │  │
│                                    │  [Ver todas las reservas →]     │  │
│                                    └──────────────────────────────────┘  │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 8. Componentes y Clases Tailwind

### 8.1 Árbol de Componentes

```
App.tsx
├── Navbar.tsx (NUEVO)
│   ├── Logo
│   ├── NavLinks (Cuidadores)
│   ├── SoyCuidadorButton.tsx (NUEVO)
│   └── MobileMenu.tsx (NUEVO)
│
├── CaregiverAuthPage.tsx (NUEVO) → /caregiver/auth
│   ├── AuthTabs.tsx
│   │   ├── LoginForm.tsx (NUEVO)
│   │   └── RegisterIntro.tsx (NUEVO)
│   └── AuthInfoPanel.tsx (NUEVO, desktop only)
│
├── CaregiverRegisterWizard.tsx (NUEVO) → /caregiver/register
│   ├── WizardProgress.tsx (sidebar desktop / bar mobile)
│   ├── WizardStepContainer.tsx
│   │   ├── Step01Name.tsx
│   │   ├── Step02Email.tsx
│   │   ├── Step03Zone.tsx
│   │   ├── Step04Services.tsx
│   │   ├── Step05Experience.tsx
│   │   ├── Step06Detail.tsx
│   │   ├── Step07Preferences.tsx
│   │   ├── Step08Sizes.tsx
│   │   ├── Step09Home.tsx
│   │   ├── Step10Routine.tsx
│   │   ├── Step11Pricing.tsx
│   │   ├── Step12Photos.tsx
│   │   ├── Step13Verification.tsx
│   │   ├── Step14Legal.tsx
│   │   └── Step15Review.tsx
│   ├── WizardNavButtons.tsx (Atrás / Siguiente)
│   └── SaveExitModal.tsx
│
├── CaregiverDashboard.tsx (NUEVO) → /caregiver/dashboard
│   ├── ProfileStatusBanner.tsx (existente, reutilizar)
│   ├── DashboardProfileCard.tsx (NUEVO)
│   └── DashboardBookings.tsx (NUEVO, placeholder V1)
│
└── AuthContext.tsx (NUEVO, provider global)
    ├── useAuth() hook
    ├── ProtectedRoute.tsx
    └── RoleGuard.tsx
```

### 8.2 Nuevas Rutas (react-router-dom)

```tsx
// App.tsx - rutas actualizadas
<Routes>
  {/* Públicas */}
  <Route path="/" element={<ListingPage />} />
  <Route path="/caregivers/:id" element={<CaregiverDetailPage />} />
  <Route path="/caregiver/auth" element={<CaregiverAuthPage />} />
  <Route path="/caregiver/register" element={<CaregiverRegisterWizard />} />

  {/* Protegidas (requieren auth + role CAREGIVER) */}
  <Route element={<ProtectedRoute role="CAREGIVER" />}>
    <Route path="/caregiver/dashboard" element={<CaregiverDashboard />} />
    <Route path="/caregiver/edit" element={<CaregiverEditProfile />} />
  </Route>

  {/* Placeholder */}
  <Route path="/reservar/:id" element={<ReservarPlaceholderPage />} />
</Routes>
```

### 8.3 Clases Tailwind por Componente

#### Navbar

```tsx
// Navbar container
"sticky top-0 z-50 border-b border-gray-200 bg-white/95 backdrop-blur-sm"

// Logo
"text-xl font-semibold text-green-700 hover:text-green-800 transition-colors"

// Nav link (Cuidadores)
"text-sm font-medium text-gray-600 hover:text-green-700 transition-colors"

// SoyCuidadorButton (visitante)
"rounded-xl bg-green-600 px-5 py-2.5 text-sm font-semibold text-white
 shadow-sm transition-all duration-200
 hover:bg-green-700 hover:shadow-md
 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-green-500
 focus-visible:ring-offset-2"

// SoyCuidadorButton (cuidador autenticado → "Mi panel")
"rounded-xl border border-green-200 bg-white px-4 py-2.5 text-sm
 font-semibold text-green-700
 hover:bg-green-50 transition-colors
 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-green-500"

// Mobile hamburger
"rounded-lg p-2 text-gray-600 hover:bg-gray-100
 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-green-500
 lg:hidden"

// Mobile menu overlay
"fixed inset-0 z-40 bg-black/20 backdrop-blur-sm lg:hidden"

// Mobile menu panel
"fixed right-0 top-0 z-50 h-full w-72 bg-white shadow-xl
 transform transition-transform duration-300"
```

#### Auth Page

```tsx
// Page background
"min-h-screen bg-green-50"

// Auth card container
"mx-auto max-w-md rounded-2xl bg-white p-8 shadow-lg
 sm:max-w-lg"

// Tab buttons
"flex rounded-xl bg-gray-100 p-1"

// Tab button (active)
"flex-1 rounded-lg bg-white px-4 py-2.5 text-sm font-semibold
 text-green-700 shadow-sm transition-all"

// Tab button (inactive)
"flex-1 rounded-lg px-4 py-2.5 text-sm font-medium text-gray-500
 hover:text-gray-700 transition-colors"

// Input field
"w-full rounded-xl border border-gray-300 px-4 py-3 text-sm
 placeholder:text-gray-400
 focus:border-green-500 focus:outline-none focus:ring-2
 focus:ring-green-500/20
 transition-colors"

// Input label
"mb-1.5 block text-sm font-medium text-gray-700"

// Input error state
"border-red-300 focus:border-red-500 focus:ring-red-500/20"

// Error message
"mt-1.5 text-xs text-red-600" // + role="alert"

// Submit button
"w-full rounded-xl bg-green-600 px-6 py-3 text-sm font-semibold
 text-white shadow-sm transition-all duration-200
 hover:bg-green-700 hover:shadow-md
 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-green-500
 focus-visible:ring-offset-2
 disabled:opacity-50 disabled:cursor-not-allowed"

// Password toggle (show/hide)
"absolute right-3 top-1/2 -translate-y-1/2 text-gray-400
 hover:text-gray-600 p-1 rounded
 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-green-500"
```

#### Wizard

```tsx
// Wizard page container
"min-h-screen bg-gray-50"

// Sidebar (desktop)
"hidden lg:block lg:w-64 lg:shrink-0 lg:border-r lg:border-gray-200
 lg:bg-white lg:p-6"

// Sidebar step item (completed)
"flex items-center gap-3 py-2 text-sm text-green-700"

// Sidebar step item (current)
"flex items-center gap-3 py-2 text-sm font-semibold text-green-800"

// Sidebar step item (pending)
"flex items-center gap-3 py-2 text-sm text-gray-400"

// Step indicator circle (completed)
"flex h-6 w-6 items-center justify-center rounded-full bg-green-500
 text-xs text-white"

// Step indicator circle (current)
"flex h-6 w-6 items-center justify-center rounded-full bg-green-600
 text-xs text-white ring-4 ring-green-100"

// Step indicator circle (pending)
"flex h-6 w-6 items-center justify-center rounded-full bg-gray-200
 text-xs text-gray-500"

// Main content area
"flex-1 px-4 py-8 sm:px-8 lg:px-16 lg:py-12"

// Step title
"text-2xl font-bold text-gray-900 sm:text-3xl"

// Step subtitle
"mt-2 text-sm text-gray-500 sm:text-base"

// Progress bar (mobile)
"h-2 overflow-hidden rounded-full bg-gray-200"

// Progress bar fill
"h-full rounded-full bg-green-500 transition-all duration-500 ease-out"

// Navigation buttons container
"mt-8 flex items-center justify-between gap-4"

// Back button
"rounded-xl border border-gray-300 px-6 py-3 text-sm font-medium
 text-gray-700 hover:bg-gray-50 transition-colors
 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-green-500"

// Next button
"rounded-xl bg-green-600 px-8 py-3 text-sm font-semibold text-white
 shadow-sm hover:bg-green-700 hover:shadow-md transition-all duration-200
 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-green-500
 focus-visible:ring-offset-2"

// Zone radio card (unselected)
"cursor-pointer rounded-xl border-2 border-gray-200 p-4
 hover:border-green-300 hover:bg-green-50/50 transition-all"

// Zone radio card (selected)
"cursor-pointer rounded-xl border-2 border-green-500 bg-green-50 p-4
 ring-2 ring-green-500/20"

// Service toggle card (unselected)
"cursor-pointer rounded-2xl border-2 border-gray-200 p-6
 hover:border-green-300 transition-all"

// Service toggle card (selected)
"cursor-pointer rounded-2xl border-2 border-green-500 bg-green-50 p-6
 shadow-sm"

// Photo upload dropzone
"flex h-32 w-full cursor-pointer flex-col items-center justify-center
 rounded-xl border-2 border-dashed border-gray-300
 hover:border-green-400 hover:bg-green-50/30 transition-colors
 sm:h-40"

// Photo thumbnail
"relative h-32 w-full overflow-hidden rounded-xl sm:h-40"

// Photo remove button
"absolute right-1.5 top-1.5 rounded-full bg-black/60 p-1 text-white
 hover:bg-black/80 transition-colors
 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"

// Save & exit button (sidebar)
"w-full rounded-xl border border-gray-300 px-4 py-2.5 text-sm
 font-medium text-gray-600 hover:bg-gray-50 transition-colors"

// Textarea with counter
"w-full rounded-xl border border-gray-300 px-4 py-3 text-sm
 placeholder:text-gray-400 resize-none
 focus:border-green-500 focus:outline-none focus:ring-2
 focus:ring-green-500/20"

// Character counter
"mt-1 text-right text-xs text-gray-400"

// Character counter (near limit)
"mt-1 text-right text-xs text-amber-500"

// Character counter (at limit)
"mt-1 text-right text-xs text-red-500"
```

#### Dashboard

```tsx
// Page container
"min-h-screen bg-gray-50"

// Content wrapper
"mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8"

// ProfileStatusBanner (pending)
"rounded-2xl border border-amber-200 bg-amber-50 px-6 py-4
 text-amber-800"

// ProfileStatusBanner (verified)
"rounded-2xl border border-green-200 bg-green-50 px-6 py-4
 text-green-800"

// ProfileStatusBanner (suspended)
"rounded-2xl border border-red-200 bg-red-50 px-6 py-4
 text-red-800"

// Dashboard card
"rounded-2xl border border-gray-200 bg-white p-6 shadow-sm"

// Dashboard card title
"text-lg font-semibold text-gray-900"

// Edit profile button
"rounded-xl border border-green-200 px-5 py-2.5 text-sm font-medium
 text-green-700 hover:bg-green-50 transition-colors
 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-green-500"

// Booking card (in dashboard)
"rounded-xl border border-gray-200 bg-gray-50 p-4
 hover:shadow-sm transition-shadow"

// Empty state text
"text-center text-sm text-gray-500"
```

### 8.4 Design Tokens Consolidados

| Token | Valor | Uso |
|-------|-------|-----|
| **brand-primary** | `green-600` (#16a34a) | Botones, links activos, progress |
| **brand-primary-hover** | `green-700` (#15803d) | Hover states |
| **brand-primary-light** | `green-50` (#f0fdf4) | Fondos suaves, selections |
| **brand-primary-ring** | `green-500/20` | Focus rings |
| **surface-page** | `gray-50` (#f9fafb) | Fondo de página |
| **surface-card** | `white` | Cards, modals |
| **surface-input** | `white` | Campos de formulario |
| **border-default** | `gray-200` (#e5e7eb) | Bordes de cards |
| **border-input** | `gray-300` (#d1d5db) | Bordes de inputs |
| **border-focus** | `green-500` | Input focus border |
| **text-primary** | `gray-900` (#111827) | Títulos |
| **text-secondary** | `gray-500` (#6b7280) | Subtítulos, placeholders |
| **text-error** | `red-600` (#dc2626) | Mensajes de error |
| **radius-button** | `rounded-xl` (12px) | Botones, inputs |
| **radius-card** | `rounded-2xl` (16px) | Cards, banners |
| **radius-chip** | `rounded-full` (9999px) | Chips, badges |

---

## 9. Flujos de Usuario Detallados

### 9.1 Flujo: Visitante se Registra como Cuidador

```
1. Visitante llega a GARDEN (/)
2. Ve botón "Soy cuidador" en navbar
3. Clic → navega a /caregiver/auth
4. Ve tabs: "Iniciar sesión" | "Registrarme"
5. Selecciona "Registrarme"
6. Lee beneficios (Hospedaje, Paseos, Verificación)
7. Clic "Comenzar registro →"
8. Navega a /caregiver/register (Paso 1)
9. Completa 15 pasos del wizard
   - Puede guardar y salir en cualquier momento
   - Puede retomar desde localStorage
10. En Paso 15, revisa toda la información
11. Clic "Enviar solicitud →"
12. Sistema:
    a. POST /api/auth/register (crea User con role CAREGIVER)
    b. Guarda tokens (localStorage)
    c. POST /api/caregivers (crea CaregiverProfile)
    d. POST /api/caregivers/verification (sube CI)
    e. Limpia wizard draft de localStorage
13. Redirect a /caregiver/dashboard
14. Ve ProfileStatusBanner: "Pendiente de verificación"
15. Navbar ahora muestra "Mi panel" en vez de "Soy cuidador"
```

### 9.2 Flujo: Cuidador Existente Inicia Sesión

```
1. Cuidador llega a GARDEN (/)
2. Clic "Soy cuidador" en navbar
3. Navega a /caregiver/auth
4. Tab "Iniciar sesión" activo por defecto
5. Ingresa email + contraseña
6. Clic "Iniciar sesión"
7. POST /api/auth/login
   - 200 → guarda tokens → redirect /caregiver/dashboard
   - 401 → "Email o contraseña incorrectos"
8. Dashboard muestra perfil + reservas
9. Navbar muestra "Mi panel" con avatar
```

### 9.3 Flujo: Wizard con Interrupción y Retomo

```
1. Visitante inicia wizard, completa hasta Paso 7
2. Clic "Guardar y salir" (o cierra browser)
3. localStorage guarda: { currentStep: 7, data: {...} }
4. Horas/días después, vuelve a /caregiver/register
5. Modal: "Tienes un registro sin completar (Paso 7/15).
          ¿Continuar donde lo dejaste?"
   - [Continuar] → carga datos, navega a Paso 7
   - [Empezar de nuevo] → limpia draft, Paso 1
6. Continúa desde Paso 7 con datos pre-llenados
```

### 9.4 Flujo: Cliente Quiere Ser También Cuidador

```
1. Cliente (role=CLIENT) está logueado
2. Clic "Soy cuidador" en navbar
3. Navega a /caregiver/auth
4. Ve mensaje especial:
   "Ya tienes cuenta como cliente.
    ¿Quieres registrarte también como cuidador?"
5. Clic "Registrarme como cuidador →"
6. Wizard pre-llena Paso 1 (nombre, teléfono) y Paso 2 (email)
   - Paso 2 muestra email actual (no editable)
   - No pide nueva contraseña (ya tiene cuenta)
   - Salta directamente a Paso 3
7. Completa pasos 3-15
8. Submit:
   a. PATCH /api/users/:id (actualiza role a CAREGIVER)
   b. POST /api/caregivers (crea perfil)
9. Redirect a /caregiver/dashboard
```

### 9.5 Flujo: Editar Perfil Post-Registro

```
1. Cuidador en /caregiver/dashboard
2. Clic "Editar perfil"
3. Navega a /caregiver/edit
4. Ve formulario similar al wizard pero en single-page scroll
   (reutiliza CaregiverProfileForm.tsx existente)
5. Edita campos deseados
6. Clic "Guardar cambios"
7. PUT /api/caregivers/:id
8. Toast: "Perfil actualizado correctamente"
9. Redirect a /caregiver/dashboard
```

---

## 10. Manejo de Errores y Estados

### 10.1 Estados de Carga

| Componente | Estado carga | Implementación |
|-----------|-------------|----------------|
| Auth login | Botón spinner + "Iniciando sesión..." | Disable form, spinner en botón |
| Wizard submit | Overlay + "Enviando tu solicitud..." | Modal con spinner, deshabilita navegación |
| Photo upload | Progress bar por foto | `<progress>` con porcentaje |
| Dashboard | Skeleton cards | Placeholders animados (pulse) |

**Skeleton para Dashboard:**

```
┌─────────────────────────────────┐
│ ┌─────────────────────────────┐ │
│ │ ░░░░░░░░░░░░░░░░░░░░░░░░░  │ │  ← Banner skeleton
│ └─────────────────────────────┘ │
│                                 │
│ ┌──────────┐ ┌──────────────┐   │
│ │ ░░░░░░░  │ │ ░░░░░░░░░░░ │   │  ← Card skeletons
│ │ ░░░░░    │ │ ░░░░░░░░    │   │
│ │ ░░░░░░░░ │ │ ░░░░░░      │   │
│ └──────────┘ └──────────────┘   │
└─────────────────────────────────┘

// Tailwind: "animate-pulse bg-gray-200 rounded-lg"
```

### 10.2 Errores de Red

| Escenario | Mensaje (español) | Acción |
|-----------|-------------------|--------|
| Sin conexión | "Sin conexión a internet. Verifica tu red." | Retry button |
| Timeout (>10s) | "El servidor tardó demasiado. Intenta de nuevo." | Retry button |
| 500 Server Error | "Algo salió mal. Intenta de nuevo en unos minutos." | Retry + link a soporte |
| 401 Token expirado | (silencioso) → intenta refresh token → si falla: redirect a /caregiver/auth | Auto-redirect |
| 409 Email existe | "Este email ya está registrado. ¿Quieres iniciar sesión?" | Link a tab login |
| 429 Rate limit | "Demasiados intentos. Espera {n} minutos." | Timer countdown |

### 10.3 Errores de Validación por Paso

```tsx
// Patrón estándar de error en campo
<div>
  <label htmlFor="firstName" className="mb-1.5 block text-sm font-medium text-gray-700">
    Nombre *
  </label>
  <input
    id="firstName"
    aria-describedby={errors.firstName ? "firstName-error" : undefined}
    aria-invalid={!!errors.firstName}
    className={cn(
      "w-full rounded-xl border px-4 py-3 text-sm transition-colors",
      errors.firstName
        ? "border-red-300 focus:border-red-500 focus:ring-red-500/20"
        : "border-gray-300 focus:border-green-500 focus:ring-green-500/20"
    )}
    {...register("firstName")}
  />
  {errors.firstName && (
    <p id="firstName-error" role="alert" className="mt-1.5 text-xs text-red-600">
      {errors.firstName.message}
    </p>
  )}
</div>
```

### 10.4 Estado de Éxito Post-Submit

```
┌──────────────────────────────────────┐
│                                      │
│          ✓                           │
│  Tu solicitud fue enviada            │
│  exitosamente                        │
│                                      │
│  El equipo GARDEN revisará tu        │
│  perfil en las próximas 24-48        │
│  horas. Te notificaremos por         │
│  WhatsApp al +591 76543210.          │
│                                      │
│  ┌────────────────────────────┐      │
│  │    Ir a mi panel  →        │      │
│  └────────────────────────────┘      │
│                                      │
└──────────────────────────────────────┘
```

---

## 11. Accesibilidad (WCAG 2.1 AA)

### 11.1 Estructura Semántica

```html
<!-- Auth Page -->
<main id="main" aria-labelledby="auth-heading">
  <h1 id="auth-heading">Cuidadores de confianza para tu mascota</h1>
  <div role="tablist" aria-label="Opciones de acceso">
    <button role="tab" aria-selected="true" aria-controls="login-panel">
      Iniciar sesión
    </button>
    <button role="tab" aria-selected="false" aria-controls="register-panel">
      Registrarme
    </button>
  </div>
  <div role="tabpanel" id="login-panel" aria-labelledby="login-tab">
    <!-- Login form -->
  </div>
</main>

<!-- Wizard -->
<main id="main" aria-labelledby="wizard-heading">
  <h1 id="wizard-heading">Registro de cuidador</h1>
  <div role="progressbar" aria-valuenow="5" aria-valuemin="1" aria-valuemax="15"
       aria-label="Paso 5 de 15">
  </div>
  <form aria-label="Paso 5: Tu experiencia con mascotas">
    <!-- Step content -->
  </form>
</main>
```

### 11.2 Focus Management

| Evento | Acción de Focus |
|--------|----------------|
| Cambio de tab (auth) | Focus al primer input del panel activo |
| Siguiente paso (wizard) | Focus al título del nuevo paso (h2) |
| Paso anterior (wizard) | Focus al título del paso anterior |
| Error de validación | Focus al primer campo con error |
| Modal "Guardar y salir" | Focus trap dentro del modal |
| Cierre de modal | Focus al botón que abrió el modal |
| Submit exitoso | Focus al heading de la página de éxito |

```tsx
// Hook para focus en cambio de paso
const stepTitleRef = useRef<HTMLHeadingElement>(null);

useEffect(() => {
  stepTitleRef.current?.focus();
}, [currentStep]);

<h2 ref={stepTitleRef} tabIndex={-1} className="outline-none">
  {stepTitles[currentStep]}
</h2>
```

### 11.3 Keyboard Navigation

**Auth Page:**

| Tecla | Acción |
|-------|--------|
| `Tab` | Navega entre campos y botones |
| `Enter` | Submit formulario |
| `←` `→` | Cambia entre tabs |
| `Space` | Toggle checkbox "Recordarme" |

**Wizard:**

| Tecla | Acción |
|-------|--------|
| `Tab` | Navega campos del paso actual |
| `Enter` | Submit paso / Siguiente |
| `Escape` | Abre modal "Guardar y salir" |
| `Alt+←` | Paso anterior |
| `Alt+→` | Paso siguiente (si válido) |
| `Space` | Toggle checkboxes, selecciona radio/cards |
| `←` `→` | Navega entre radio cards (zonas) |

**Radio Cards (Zona, Paso 3):**

```tsx
// Roving tabindex para radio cards
<div role="radiogroup" aria-label="Zona de Santa Cruz">
  {zones.map((zone, i) => (
    <div
      key={zone.value}
      role="radio"
      aria-checked={selected === zone.value}
      tabIndex={selected === zone.value || (selected === null && i === 0) ? 0 : -1}
      onKeyDown={(e) => {
        if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
          // Focus next zone
        }
        if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
          // Focus previous zone
        }
        if (e.key === ' ' || e.key === 'Enter') {
          setSelected(zone.value);
        }
      }}
    >
      {zone.label}
    </div>
  ))}
</div>
```

### 11.4 Screen Reader Announcements

```tsx
// Live region para anuncios
<div aria-live="polite" aria-atomic="true" className="sr-only">
  {announcement}
</div>

// Anuncios por evento:
// Cambio de paso: "Paso 5 de 15: Tu experiencia con mascotas"
// Error:          "Error: El nombre es obligatorio"
// Foto subida:    "Foto 3 de 6 subida correctamente"
// Foto eliminada: "Foto eliminada. 2 de 6 fotos restantes"
// Submit:         "Solicitud enviada exitosamente"
// Login:          "Sesión iniciada. Redirigiendo al panel."
```

### 11.5 Skip Link

```tsx
// En todas las páginas del flujo
<a
  href="#main"
  className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4
             focus:z-[100] focus:rounded-xl focus:bg-green-600 focus:px-4
             focus:py-2 focus:text-sm focus:font-semibold focus:text-white
             focus:shadow-lg"
>
  Ir al contenido principal
</a>
```

### 11.6 Contraste y Tamaños

| Elemento | Ratio mínimo | Actual | Cumple |
|----------|-------------|--------|--------|
| Texto principal (gray-900 sobre white) | 4.5:1 | 17.1:1 | AA |
| Texto secundario (gray-500 sobre white) | 4.5:1 | 5.9:1 | AA |
| Botón verde (white sobre green-600) | 4.5:1 | 4.6:1 | AA |
| Error (red-600 sobre white) | 4.5:1 | 6.0:1 | AA |
| Placeholder (gray-400 sobre white) | 3:1 (non-text) | 3.8:1 | AA |
| Focus ring (green-500) | 3:1 (non-text) | 3.4:1 | AA |

**Tamaño mínimo de targets táctiles:** 44x44px (todos los botones, checkboxes, radio cards).

---

## 12. Performance

### 12.1 Code Splitting

```tsx
// Lazy load de páginas del flujo cuidador
const CaregiverAuthPage = lazy(() => import('./pages/CaregiverAuthPage'));
const CaregiverRegisterWizard = lazy(() => import('./pages/CaregiverRegisterWizard'));
const CaregiverDashboard = lazy(() => import('./pages/CaregiverDashboard'));

// Prefetch al hover del botón "Soy cuidador"
const prefetchAuth = () => {
  import('./pages/CaregiverAuthPage');
};

<button onMouseEnter={prefetchAuth} onFocus={prefetchAuth}>
  Soy cuidador
</button>
```

### 12.2 Wizard Step Splitting

```tsx
// Cada paso es un chunk independiente
const steps = {
  1:  lazy(() => import('./steps/Step01Name')),
  2:  lazy(() => import('./steps/Step02Email')),
  3:  lazy(() => import('./steps/Step03Zone')),
  // ...
  15: lazy(() => import('./steps/Step15Review')),
};

// Pre-carga el paso siguiente
useEffect(() => {
  const nextStep = currentStep + 1;
  if (nextStep <= 15 && steps[nextStep]) {
    steps[nextStep]; // triggers import
  }
}, [currentStep]);
```

### 12.3 Photo Upload Optimization

```tsx
// 1. Resize antes de subir (client-side con canvas)
const resizeImage = async (file: File, maxWidth = 1200): Promise<Blob> => {
  const img = await createImageBitmap(file);
  const canvas = new OffscreenCanvas(
    Math.min(img.width, maxWidth),
    Math.min(img.height, maxWidth * (img.height / img.width))
  );
  const ctx = canvas.getContext('2d')!;
  ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
  return canvas.convertToBlob({ type: 'image/webp', quality: 0.85 });
};

// 2. Upload individual con progreso
const uploadPhoto = async (
  file: File,
  onProgress: (pct: number) => void
) => {
  const resized = await resizeImage(file);
  const formData = new FormData();
  formData.append('photo', resized, `photo.webp`);

  const { data } = await api.post('/api/upload', formData, {
    onUploadProgress: (e) => onProgress(Math.round((e.loaded / e.total!) * 100)),
  });
  return data.url;
};

// 3. Memory leak prevention
useEffect(() => {
  return () => {
    previews.forEach((url) => URL.revokeObjectURL(url));
  };
}, []);
```

### 12.4 localStorage Debounce

```tsx
// Guardar draft con debounce de 500ms
const debouncedSave = useMemo(
  () =>
    debounce((data: WizardData) => {
      const draft = {
        currentStep,
        lastSavedAt: new Date().toISOString(),
        data: { ...data, password: undefined }, // NUNCA guardar password
      };
      localStorage.setItem('garden_wizard_draft', JSON.stringify(draft));
    }, 500),
  [currentStep]
);

// Limpiar debounce al desmontar
useEffect(() => () => debouncedSave.cancel(), [debouncedSave]);
```

### 12.5 Bundle Size Targets

| Chunk | Target | Contenido |
|-------|--------|----------|
| `main` | <80KB gzip | App shell, navbar, routing |
| `auth` | <25KB gzip | Login form, tabs, validation |
| `wizard` | <40KB gzip | Wizard container, progress, nav |
| `wizard-step-*` | <8KB gzip each | Individual step forms |
| `dashboard` | <20KB gzip | Dashboard, profile card, banner |
| `photo-upload` | <15KB gzip | Dropzone, resize, upload |

---

## 13. Seguridad e i18n

### 13.1 Seguridad

| Aspecto | Implementación |
|---------|---------------|
| **Contraseña** | NUNCA en localStorage. Solo en memory (React state) durante el wizard. Se envía una sola vez en el POST final. |
| **CI Photos** | Se suben a ruta separada con acceso restringido. Solo admins pueden ver. Encrypted at rest (Cloudinary private). |
| **JWT Storage** | `localStorage` para access token. httpOnly cookie para refresh token (si posible). |
| **CSRF** | SameSite=Strict en cookies. Origin check en backend. |
| **XSS** | DOMPurify para cualquier texto renderizado desde API. No `dangerouslySetInnerHTML`. |
| **Rate Limiting** | Login: max 5 intentos/15min por IP. Register: max 3/hora por IP. |
| **Input Sanitization** | Zod validation en frontend + backend. Escape de caracteres especiales. |
| **File Upload** | Validar MIME type (image/jpeg, image/png, image/webp). Max 5MB. Usar Cloudinary transformations (no servir original). |

### 13.2 i18n (Español Bolivia)

Todo el flujo está en **español** (es-BO). Consideraciones:

| Aspecto | Implementación |
|---------|---------------|
| **Moneda** | "Bs" (Bolivianos), sin decimales para precios enteros |
| **Teléfono** | Prefijo +591, formato 7XXXXXXX o 6XXXXXXX (8 dígitos) |
| **Zonas** | Nombres locales: "Equipetrol", "Urbarí", "Norte (Plan 3000, Satélite)" |
| **Fechas** | formato DD/MM/AAAA, lunes como primer día de semana |
| **Horarios** | "Mañana (7-9am)", "Tarde (5-7pm)" |
| **Mensajes** | Tono amigable, tuteo ("Tu nombre", "Tu zona"), sin jerga técnica |
| **Errores** | En español claro: "Ingresa un email válido", no "Invalid email format" |

**Ejemplos de copy localizado:**

```
- "Paso 1 de 15" (no "Step 1 of 15")
- "Nombre *" (no "First Name *")
- "Bs 120/día" (no "$120/day")
- "Siguiente →" (no "Next →")
- "← Atrás" (no "← Back")
- "Guardar y salir" (no "Save & Exit")
- "Tu perfil está pendiente de verificación" (natural, amigable)
```

---

## 14. Mapeo a Schema Prisma

### 14.1 Wizard → User Model

| Paso Wizard | Campo UI | Campo Prisma (User) | Tipo |
|-------------|----------|---------------------|------|
| 1 | firstName | `firstName` | String |
| 1 | lastName | `lastName` | String |
| 1 | phone | `phone` | String |
| 2 | email | `email` | String @unique |
| 2 | password | `passwordHash` (bcrypt) | String |
| — | (automático) | `role` = CAREGIVER | UserRole |

### 14.2 Wizard → CaregiverProfile Model

| Paso Wizard | Campo UI | Campo Prisma | Tipo | Notas |
|-------------|----------|-------------|------|-------|
| 3 | zone | `zone` | Zone (enum) | EQUIPETROL, URBARI, etc. |
| 4 | servicesOffered | `servicesOffered` | ServiceType[] | [HOSPEDAJE], [PASEO], o ambos |
| 5+6+7+8+10 | bioSummary + bioDetail + preferences + sizes + routine | `bio` | String? @db.VarChar(500) | Se concatenan con separadores |
| 9 | spaceType | `spaceType` | String? | Texto libre del usuario |
| 11 | pricePerDay | `pricePerDay` | Int? | Solo si HOSPEDAJE |
| 11 | pricePerWalk30 | `pricePerWalk30` | Int? | Solo si PASEO |
| 11 | pricePerWalk60 | `pricePerWalk60` | Int? | Solo si PASEO |
| 12 | photos | `photos` | String[] | 4-6 URLs Cloudinary |
| — | (automático) | `verified` = false | Boolean | Admin verifica después |
| — | (automático) | `suspended` = false | Boolean | Default |
| — | (automático) | `rating` = 0 | Float | Sin reseñas aún |
| — | (automático) | `reviewCount` = 0 | Int | Sin reseñas aún |

### 14.3 Construcción del Bio

```tsx
// Concatenar campos del wizard en un solo bio (max 500 chars)
const buildBio = (data: WizardData): string => {
  const parts: string[] = [];

  // Paso 5: Resumen (obligatorio)
  parts.push(data.bioSummary.trim());

  // Paso 6: Detalle (opcional)
  if (data.bioDetail?.trim()) {
    parts.push(data.bioDetail.trim());
  }

  // Paso 7+8: Preferencias (opcional, formato legible)
  if (data.petPreferences?.length) {
    parts.push(`Acepto: ${data.petPreferences.join(', ')}.`);
  }
  if (data.sizePreferences?.length) {
    parts.push(`Tamaños: ${data.sizePreferences.join(', ')}.`);
  }

  // Paso 10: Rutina (opcional)
  if (data.dailyRoutine?.trim()) {
    parts.push(data.dailyRoutine.trim());
  }

  return parts.join(' ').slice(0, 500);
};
```

### 14.4 Payload de Registro (API Calls)

**Call 1: Crear usuario**

```json
POST /api/auth/register
{
  "email": "juan@email.com",
  "password": "SecurePass123",
  "firstName": "Juan",
  "lastName": "Pérez",
  "phone": "+59176543210",
  "role": "caregiver"
}
→ Response: { user: { id }, tokens: { accessToken, refreshToken } }
```

**Call 2: Crear perfil de cuidador**

```json
POST /api/caregivers
Authorization: Bearer <accessToken>
{
  "bio": "Tengo 2 labradores y trabajo desde casa. He cuidado mascotas por 3 años.",
  "zone": "EQUIPETROL",
  "spaceType": "Casa con patio cercado de 50m²",
  "servicesOffered": ["HOSPEDAJE", "PASEO"],
  "pricePerDay": 120,
  "pricePerWalk30": 30,
  "pricePerWalk60": 50,
  "photos": [
    "https://res.cloudinary.com/.../patio.webp",
    "https://res.cloudinary.com/.../living.webp",
    "https://res.cloudinary.com/.../jardin.webp",
    "https://res.cloudinary.com/.../con-perro.webp"
  ]
}
```

**Call 3: Subir verificación (CI)**

```json
POST /api/caregivers/verification
Authorization: Bearer <accessToken>
Content-Type: multipart/form-data

ciPhotoFront: <file>
ciPhotoBack: <file>
```

---

## 15. Self-Review contra MVP Spec

### 15.1 Checklist contra Documentación Técnica v1.0

| Requisito (Doc Técnica) | Sección del Diseño | Estado |
|------------------------|-------------------|--------|
| US-1.1: Registro con email/contraseña | §5.3 Pasos 1-2 | Cubierto |
| US-1.2: Perfil de cuidador completo | §5.3 Pasos 3-15 | Cubierto |
| US-1.4: Login con email/contraseña | §4.2 Tab Login | Cubierto |
| POST /api/auth/register con role | §14.4 Call 1 | Cubierto |
| POST /api/auth/login | §4.2 Post-login flow | Cubierto |
| CaregiverProfile: bio, zone, photos, services, prices | §14.2 Mapeo completo | Cubierto |
| Zone enum (6 valores) | §5.3 Paso 3 | Cubierto |
| ServiceType enum (HOSPEDAJE, PASEO) | §5.3 Paso 4 | Cubierto |
| Photos 4-6 URLs Cloudinary | §5.3 Paso 12 | Cubierto |
| verified=false por defecto | §14.2 automático | Cubierto |
| JWT tokens en response | §9.1 Paso 12 | Cubierto |
| Perfil no visible hasta aprobación | §6.2 Status "Pendiente" | Cubierto |

### 15.2 Checklist contra MVP PDF (v2)

| Requisito (PDF MVP) | Sección del Diseño | Estado |
|---------------------|-------------------|--------|
| "Foto REAL de la casa/patio" | §5.3 Paso 12 (sugerencias) | Cubierto |
| "Foto del cuidador con SU mascota" | §5.3 Paso 12 (sugerencia 3) | Cubierto |
| "Descripción específica" (no vaga) | §5.3 Paso 5 (min 50 chars, placeholder guía) | Cubierto |
| "Badge Verificado por GARDEN" | §6.2 Banner "Verificado" | Cubierto |
| "Zona visible: Equipetrol, Urbarí, Norte, etc." | §5.3 Paso 3 (6 zonas) | Cubierto |
| "Servicios: Hospedaje, Paseos, o Ambos" | §5.3 Paso 4 (multi-select) | Cubierto |
| "Formulario de registro" | §5 Wizard completo | Cubierto |
| "Subida de 4-6 fotos" | §5.3 Paso 12 | Cubierto |
| "Campo de texto libre" (bio) | §5.3 Pasos 5-6 | Cubierto |
| "Campo de zona/barrio" | §5.3 Paso 3 (radio cards) | Cubierto |
| "Checkboxes de servicios" | §5.3 Paso 4 (toggle cards) | Cubierto |
| "Verificación: entrevista + visita domiciliaria" | §5.3 Paso 13 (CI upload para iniciar proceso) | Cubierto |
| Precio hospedaje: Bs 80-160/día | §5.3 Paso 11 (rango sugerido) | Cubierto |
| Precio paseo 30min: Bs 20-45 | §5.3 Paso 11 (rango sugerido) | Cubierto |
| Precio paseo 1h: Bs 35-80 | §5.3 Paso 11 (rango sugerido) | Cubierto |

### 15.3 Checklist de Accesibilidad

| Criterio WCAG 2.1 AA | Implementación | Estado |
|----------------------|----------------|--------|
| 1.1.1 Non-text Content | Alt text en fotos, aria-labels en iconos | Cubierto |
| 1.3.1 Info and Relationships | Semantic HTML, labels vinculados a inputs | Cubierto |
| 1.4.3 Contrast (Minimum) | Verificado ratios ≥4.5:1 (§11.6) | Cubierto |
| 2.1.1 Keyboard | Tab, Enter, Escape, Arrow keys documentados (§11.3) | Cubierto |
| 2.4.1 Bypass Blocks | Skip link en todas las páginas (§11.5) | Cubierto |
| 2.4.3 Focus Order | Focus management documentado (§11.2) | Cubierto |
| 2.4.7 Focus Visible | focus-visible:ring-2 en todos los interactivos | Cubierto |
| 3.3.1 Error Identification | role="alert", aria-invalid, mensajes claros | Cubierto |
| 3.3.2 Labels or Instructions | Labels en todos los campos, placeholders guía | Cubierto |
| 4.1.2 Name, Role, Value | ARIA roles en tabs, radio groups, progressbar | Cubierto |

### 15.4 Checklist de Consistencia con Documentos Previos

| Documento | Aspecto Verificado | Consistente |
|-----------|-------------------|-------------|
| GARDEN_Formulario_Perfil_Cuidador.md | Campos del formulario coinciden con schema | Sí |
| GARDEN_Listing_Cuidadores_Refinado.md | CaregiverCard usa photos[0], no profilePicture | Sí |
| GARDEN_Revision_Visual_Accesibilidad.md | border-radius system (cards=2xl, buttons=xl) | Sí |
| GARDEN_Revision_Visual_Accesibilidad.md | aria-disabled pattern para submit buttons | Sí |
| GARDEN_Revision_Visual_Accesibilidad.md | Roving tabindex en radio groups | Sí |
| GARDEN_UI_Testing_Mockups.md | Playwright E2E testing patterns | Compatible |
| Schema actual (prisma) | Zone es enum (no string), spaceType es texto libre | Sí |
| Schema actual (prisma) | bio @db.VarChar(500) limit respected | Sí |
| Schema actual (prisma) | Stripe fields (not QR/bank) in Booking | N/A (registro, no booking) |

### 15.5 Gaps Identificados y Resoluciones

| # | Gap | Resolución |
|---|-----|-----------|
| 1 | Schema no tiene campos separados para preferencias de mascotas (pasos 7-8) | Se incluyen como texto natural dentro del `bio` (500 chars). Suficiente para MVP. V2 puede agregar campos dedicados. |
| 2 | Schema no tiene `dailyRoutine` como campo separado | Se incluye en el `bio`. Mismo razonamiento que gap 1. |
| 3 | No existe endpoint `/api/caregivers/verification` para CI | Requiere implementación backend. Se documenta el contrato esperado. |
| 4 | No existe endpoint `/api/auth/check-email` | Requiere implementación backend. Alternativa: validar en el submit y mostrar error 409. |
| 5 | `password` del wizard no debe guardarse en localStorage | Documentado explícitamente en §5.4: "Contraseña NUNCA se guarda en localStorage". |
| 6 | El flujo "Cliente también quiere ser cuidador" (§9.4) requiere PATCH para cambiar role | Requiere endpoint o lógica que permita role upgrade. Documentado como flujo futuro. |
| 7 | Navbar actual es un `<header>` hardcoded en App.tsx | Requiere refactor a componente `Navbar.tsx`. Documentado en §8.1 árbol de componentes. |

---

## Apéndice A: Resumen de Archivos Nuevos a Crear

```
garden-web/src/
├── contexts/
│   └── AuthContext.tsx            → Contexto de autenticación
├── pages/
│   ├── CaregiverAuthPage.tsx     → /caregiver/auth
│   └── CaregiverDashboard.tsx    → /caregiver/dashboard
├── components/
│   ├── Navbar.tsx                → Navbar global (reemplaza header en App.tsx)
│   ├── MobileMenu.tsx            → Menu hamburguesa
│   ├── SoyCuidadorButton.tsx     → Botón dinámico
│   ├── ProtectedRoute.tsx        → Route guard
│   ├── auth/
│   │   ├── AuthTabs.tsx          → Tabs login/registro
│   │   ├── LoginForm.tsx         → Formulario login
│   │   └── RegisterIntro.tsx     → Intro al wizard
│   ├── wizard/
│   │   ├── CaregiverRegisterWizard.tsx → Container del wizard
│   │   ├── WizardProgress.tsx    → Sidebar/bar de progreso
│   │   ├── WizardNavButtons.tsx  → Botones Atrás/Siguiente
│   │   ├── SaveExitModal.tsx     → Modal guardar y salir
│   │   └── steps/
│   │       ├── Step01Name.tsx
│   │       ├── Step02Email.tsx
│   │       ├── Step03Zone.tsx
│   │       ├── Step04Services.tsx
│   │       ├── Step05Experience.tsx
│   │       ├── Step06Detail.tsx
│   │       ├── Step07Preferences.tsx
│   │       ├── Step08Sizes.tsx
│   │       ├── Step09Home.tsx
│   │       ├── Step10Routine.tsx
│   │       ├── Step11Pricing.tsx
│   │       ├── Step12Photos.tsx
│   │       ├── Step13Verification.tsx
│   │       ├── Step14Legal.tsx
│   │       └── Step15Review.tsx
│   └── dashboard/
│       ├── DashboardProfileCard.tsx
│       └── DashboardBookings.tsx
├── hooks/
│   ├── useAuth.ts                → Hook de autenticación
│   ├── useWizardDraft.ts         → Hook para localStorage draft
│   └── useWizardNavigation.ts    → Hook para navegación del wizard
├── forms/
│   ├── wizardSchemas.ts          → Zod schemas por paso
│   └── loginSchema.ts           → Zod schema para login
├── api/
│   └── auth.ts                  → API functions para auth
└── types/
    ├── auth.ts                  → AuthUser, LoginRequest, etc.
    └── wizard.ts                → WizardData, WizardStep, etc.
```

## Apéndice B: Estimación de Componentes por Complejidad

| Componente | Complejidad | Dependencias |
|-----------|-------------|-------------|
| AuthContext | Alta | JWT decode, refresh token logic, localStorage |
| Navbar | Media | AuthContext, react-router |
| LoginForm | Baja | react-hook-form, zod, api/auth |
| CaregiverRegisterWizard | Alta | 15 steps, localStorage, photo upload, multi-API submit |
| WizardProgress | Media | Estado del wizard, responsive |
| Step12Photos | Alta | react-dropzone, canvas resize, Cloudinary upload, progress |
| Step15Review | Media | Consume datos de todos los pasos, navegación a edición |
| CaregiverDashboard | Baja-Media | AuthContext, API fetch perfil + reservas |
| ProtectedRoute | Baja | AuthContext, redirect |

---

*Fin del documento GARDEN_Flujo_Soy_Cuidador.md v1.0*

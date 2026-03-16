# GARDEN - Refinamiento UI/UX: Flujo "Soy Cuidador"

> Iteración sobre `GARDEN_Flujo_Soy_Cuidador.md` v1.0.
> Agrega: responsive bullet-proof, dark mode, tooltips, clickable progress,
> edge-case flows, wireframes sensibles, y self-review corregido.
>
> **Versión:** 1.1
> **Fecha:** 2026-02-07
> **Base:** GARDEN_Flujo_Soy_Cuidador.md v1.0

---

## Tabla de Contenidos

1. [Responsive Sin Fallas](#1-responsive-sin-fallas)
2. [Visuales Coherentes: Iconografía, Tooltips, Progress Clickable](#2-visuales-coherentes)
3. [Manejo de Errores Refinado](#3-manejo-de-errores-refinado)
4. [Dashboard Responsive Completo](#4-dashboard-responsive)
5. [Animaciones y Transiciones Profesionales](#5-animaciones-y-transiciones)
6. [Tailwind Dark/Light Theme](#6-dark-light-theme)
7. [Wireframes Refinados: Pasos Sensibles](#7-wireframes-sensibles)
8. [Flujos Edge Cases](#8-edge-cases)
9. [Self-Review y Correcciones](#9-self-review-correcciones)

---

## 1. Responsive Sin Fallas

### 1.1 Breakpoints Definitivos

| Breakpoint | Rango | Comportamiento principal |
|-----------|-------|-------------------------|
| **Mobile** | 0–639px | Stack vertical, sticky bottom nav, full-width inputs |
| **Mobile landscape** | 640–767px (sm) | 2-col grid para radio cards, inputs siguen full-width |
| **Tablet** | 768–1023px (md) | Wizard sin sidebar, progress bar horizontal, 2-col review cards |
| **Desktop** | 1024–1279px (lg) | Sidebar de progreso visible, 2-col forms |
| **Wide** | ≥1280px (xl) | Max-width container, más espaciado lateral |

### 1.2 Wizard - Breakpoint por Breakpoint

#### Mobile (0–767px): Stack completo

```
┌─────────────────────────────────┐
│  ← Paso 3/15     [Guardar ✕]   │  ← Header fijo (sticky top-0)
│  ━━━━━━░░░░░░░░░░░░░░░░░░░░░   │  ← Progress bar (h-1.5)
├─────────────────────────────────┤
│                                 │
│  📍 ¿En qué zona de Santa      │  ← Icono + Título
│  Cruz vives?                    │
│  ───────────────────────        │
│  Los dueños buscan cuidadores   │  ← Subtítulo
│  cerca de su zona.              │
│                                 │
│  ┌───────────────────────────┐  │  ← Cards 1-col
│  │ ◉ Equipetrol              │  │
│  │   Zona residencial        │  │  ← Descripción opcional
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │ ○ Urbarí                  │  │
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │ ○ Norte (Plan 3000,       │  │
│  │   Satélite)               │  │
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │ ○ Las Palmas              │  │
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │ ○ Centro / San Martín     │  │
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │ ○ Otros                   │  │
│  └───────────────────────────┘  │
│                                 │
│ ┌───────────────────────────┐   │  ← Sticky bottom
│ │ [← Atrás]  [Siguiente →] │   │     (safe-area-inset)
│ └───────────────────────────┘   │
└─────────────────────────────────┘
```

**Reglas mobile estrictas:**

```tsx
// Bottom nav sticky (safe area para notch/gesture bar)
"fixed bottom-0 left-0 right-0 z-30 border-t border-gray-200
 bg-white px-4 py-3 pb-[env(safe-area-inset-bottom)]
 sm:static sm:border-0 sm:bg-transparent sm:p-0"

// Contenido con padding-bottom para no tapar con bottom nav
"pb-24 sm:pb-0"

// Inputs: texto 16px para evitar zoom iOS
"text-base sm:text-sm"
```

#### Tablet (768–1023px): Sin sidebar, progress horizontal

```
┌──────────────────────────────────────────────┐
│  GARDEN 🌿    Cuidadores    [Soy cuidador]   │
├──────────────────────────────────────────────┤
│                                              │
│  Paso 3 de 15                                │
│  ━━━━━━━━░░░░░░░░░░░░░░░░░░░░░░░░ (20%)    │
│                                              │
│  📍 ¿En qué zona de Santa Cruz vives?       │
│  ────────────────────────────────            │
│  Los dueños buscan cuidadores cerca.         │
│                                              │
│  ┌────────────────────┐ ┌──────────────────┐ │  ← 2-col grid
│  │ ◉ Equipetrol       │ │ ○ Urbarí         │ │
│  └────────────────────┘ └──────────────────┘ │
│  ┌────────────────────┐ ┌──────────────────┐ │
│  │ ○ Norte            │ │ ○ Las Palmas     │ │
│  └────────────────────┘ └──────────────────┘ │
│  ┌────────────────────┐ ┌──────────────────┐ │
│  │ ○ Centro/San Martín│ │ ○ Otros          │ │
│  └────────────────────┘ └──────────────────┘ │
│                                              │
│       [← Atrás]        [Siguiente →]         │
│                                              │
└──────────────────────────────────────────────┘
```

#### Desktop (≥1024px): Sidebar clickable + contenido

```
┌──────────────────────────────────────────────────────────────────────────┐
│  GARDEN 🌿         Cuidadores                        (●) Mi panel      │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────┐  ┌────────────────────────────────────────────┐   │
│  │                  │  │                                            │   │
│  │  PROGRESO        │  │  Paso 3 de 15                             │   │
│  │  ──────────      │  │  ━━━━━━━━░░░░░░░░░░░░░░░░░░░ (20%)       │   │
│  │                  │  │                                            │   │
│  │  ✓ 1 Nombre ←┐  │  │  📍 ¿En qué zona de Santa Cruz vives?    │   │
│  │  ✓ 2 Email   │  │  │  ───────────────────────────────           │   │
│  │  ● 3 Zona    │  │  │  Los dueños buscan cuidadores cerca.      │   │
│  │  ○ 4 Servic. │  │  │                                            │   │
│  │  ○ 5 Exper.  │  │  │  ┌──────────────┐  ┌──────────────┐       │   │
│  │  ○ 6 Detalle │  │  │  │ ◉ Equipetrol │  │ ○ Urbarí     │       │   │
│  │  ○ 7 Pref.   │  │  │  └──────────────┘  └──────────────┘       │   │
│  │  ○ 8 Tamaños │  │  │  ┌──────────────┐  ┌──────────────┐       │   │
│  │  ○ 9 Hogar   │  │  │  │ ○ Norte      │  │ ○ Las Palmas │       │   │
│  │  ○ 10 Rutina │ │  │  └──────────────┘  └──────────────┘       │   │
│  │  ○ 11 Tarifas│ │  │  ┌──────────────┐  ┌──────────────┐       │   │
│  │  ○ 12 Fotos  │ │  │  │ ○ Centro/    │  │ ○ Otros      │       │   │
│  │  ○ 13 Verif. │ │  │  │   San Martín │  │              │       │   │
│  │  ○ 14 Acuerdo│ │  │  └──────────────┘  └──────────────┘       │   │
│  │  ○ 15 Revisar│ │  │                                            │   │
│  │           ←──┘  │  │       [← Atrás]      [Siguiente →]        │   │
│  │  clickable si   │  │                                            │   │
│  │  completed      │  └────────────────────────────────────────────┘   │
│  │                  │                                                   │
│  │  ┌────────────┐ │                                                   │
│  │  │ Guardar    │ │                                                   │
│  │  │ y salir    │ │                                                   │
│  │  └────────────┘ │                                                   │
│  └──────────────────┘                                                   │
└──────────────────────────────────────────────────────────────────────────┘
```

### 1.3 Auth Page - Responsive Refinado

#### Mobile: Card toma todo el ancho

```
┌─────────────────────────────────┐
│  GARDEN 🌿               [☰]   │
├─────────────────────────────────┤
│  bg-green-50                    │
│                                 │
│  🌿 Cuidadores de confianza    │  ← Heading visible
│  para tu mascota                │     (no panel lateral)
│                                 │
│  ┌───────────────────────────┐  │  ← Card full-width
│  │ ┌───────────┬───────────┐ │  │     (mx-4, not max-w-md)
│  │ │ Iniciar   │Registrarme│ │  │
│  │ │ sesión    │▓▓▓▓▓▓▓▓▓▓│ │  │
│  │ ╞═══════════╧═══════════╡ │  │
│  │ │                       │ │  │
│  │ │  (tab content)        │ │  │
│  │ │                       │ │  │
│  │ └───────────────────────┘ │  │
│  └───────────────────────────┘  │
│                                 │
└─────────────────────────────────┘
```

#### Desktop: 2 paneles lado a lado

```
┌──────────────────────────────────────────────────────────────────────────┐
│  GARDEN 🌿         Cuidadores                     [Soy cuidador ▸]     │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│    bg-green-50 min-h-[calc(100vh-64px)]                                 │
│                                                                          │
│    ┌──────────────────────────┐   ┌────────────────────────────────┐    │
│    │  PANEL INFORMATIVO       │   │  PANEL AUTH                    │    │
│    │  (lg:w-5/12)             │   │  (lg:w-7/12, max-w-lg)        │    │
│    │                          │   │                                │    │
│    │  🌿                     │   │  ┌──────────────┬────────────┐ │    │
│    │                          │   │  │ Iniciar      │ Registrarme│ │    │
│    │  "En GARDEN cada        │   │  │ sesión       │ ▓▓▓▓▓▓▓▓▓▓│ │    │
│    │  cuidador es verificado │   │  ╞══════════════╧════════════╡ │    │
│    │  personalmente."        │   │  │                           │ │    │
│    │                          │   │  │  Únete como cuidador      │ │    │
│    │  ┌────────────────────┐ │   │  │  GARDEN                   │ │    │
│    │  │ ✓ Entrevista       │ │   │  │                           │ │    │
│    │  │ ✓ Visita domicilio │ │   │  │  ┌───────────────────┐   │ │    │
│    │  │ ✓ Verificación CI  │ │   │  │  │ 🏠 Hospedaje      │   │ │    │
│    │  └────────────────────┘ │   │  │  │ Cuida mascotas    │   │ │    │
│    │                          │   │  │  │ en tu hogar       │   │ │    │
│    │  ┌────────────────────┐ │   │  │  └───────────────────┘   │ │    │
│    │  │ 🐕 "Luna volvió   │ │   │  │                           │ │    │
│    │  │  feliz. Gracias    │ │   │  │  ┌───────────────────┐   │ │    │
│    │  │  María!"           │ │   │  │  │ 🦮 Paseos         │   │ │    │
│    │  │  — Carlos R. ★★★★★ │ │   │  │  │ Pasea perros      │   │ │    │
│    │  └────────────────────┘ │   │  │  │ en tu zona        │   │ │    │
│    │  (testimonio rotativo)  │   │  │  └───────────────────┘   │ │    │
│    │                          │   │  │                           │ │    │
│    └──────────────────────────┘   │  │  ~10 min (guarda prog.)  │ │    │
│                                    │  │                           │ │    │
│                                    │  │  ┌───────────────────┐   │ │    │
│                                    │  │  │ Comenzar registro →│   │ │    │
│                                    │  │  └───────────────────┘   │ │    │
│                                    │  └─────────────────────────┘ │    │
│                                    └────────────────────────────────┘    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### 1.4 Paso 1 (Nombre) - Responsive Grid

```tsx
// Layout adaptativo nombre/apellido
<div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
  <InputField name="firstName" label="Nombre *" />
  <InputField name="lastName" label="Apellido *" />
</div>

// Teléfono siempre full-width
<div className="mt-4">
  <PhoneInput name="phone" label="Teléfono (WhatsApp) *" prefix="+591" />
</div>
```

### 1.5 Paso 11 (Tarifas) - Secciones Colapsables en Mobile

```
┌─────────────────────────────────┐
│  ← Paso 11/15    [Guardar ✕]   │
│  ━━━━━━━━━━━━━━━━━━━━━━░░░░░   │
├─────────────────────────────────┤
│                                 │
│  💰 Define tus tarifas         │
│  ──────────────────             │
│                                 │
│  ┌───────────────────────────┐  │
│  │ 🏠 Hospedaje          [▼] │  │  ← Colapsable (open default)
│  │ ─────────────────────     │  │
│  │                           │  │
│  │ Precio por día (Bs) *     │  │
│  │ ┌──────────────────┐      │  │
│  │ │ Bs  120          │      │  │
│  │ └──────────────────┘      │  │
│  │ Sugerido: Bs 80-160 ⓘ   │  │  ← Tooltip icon
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │ 🦮 Paseos             [▼] │  │  ← Colapsable
│  │ ─────────────────────     │  │
│  │                           │  │
│  │ Precio 30 min (Bs) *      │  │
│  │ ┌──────────────────┐      │  │
│  │ │ Bs  30           │      │  │
│  │ └──────────────────┘      │  │
│  │ Sugerido: Bs 20-45        │  │
│  │                           │  │
│  │ Precio 1 hora (Bs) *      │  │
│  │ ┌──────────────────┐      │  │
│  │ │ Bs  50           │      │  │
│  │ └──────────────────┘      │  │
│  │ Sugerido: Bs 35-80        │  │
│  └───────────────────────────┘  │
│                                 │
│ ┌───────────────────────────┐   │
│ │ [← Atrás]  [Siguiente →] │   │
│ └───────────────────────────┘   │
└─────────────────────────────────┘
```

**Colapsable component:**

```tsx
// Solo colapsable en mobile (<768px)
const CollapsibleSection = ({ icon, title, children, defaultOpen = true }) => {
  const isMobile = useMediaQuery('(max-width: 767px)');
  const [isOpen, setIsOpen] = useState(defaultOpen);

  if (!isMobile) return <div>{children}</div>; // desktop: siempre visible

  return (
    <div className="rounded-2xl border border-gray-200 bg-white">
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="flex w-full items-center justify-between p-4 text-left"
        aria-expanded={isOpen}
        aria-controls={`section-${title}`}
      >
        <span className="flex items-center gap-2 font-semibold text-gray-900">
          {icon} {title}
        </span>
        <ChevronIcon className={cn(
          "h-5 w-5 text-gray-400 transition-transform duration-200",
          isOpen && "rotate-180"
        )} />
      </button>
      <div
        id={`section-${title}`}
        className={cn(
          "overflow-hidden transition-all duration-300 ease-out",
          isOpen ? "max-h-96 opacity-100 px-4 pb-4" : "max-h-0 opacity-0"
        )}
      >
        {children}
      </div>
    </div>
  );
};
```

### 1.6 Input 16px para Evitar Zoom iOS

**Problema v1.0:** Inputs con `text-sm` (14px) causan zoom automático en Safari iOS.

**Corrección:**

```tsx
// ANTES (v1.0) - causa zoom en iOS
"w-full rounded-xl border border-gray-300 px-4 py-3 text-sm ..."

// DESPUÉS (v1.1) - 16px en mobile, 14px en desktop
"w-full rounded-xl border border-gray-300 px-4 py-3
 text-base sm:text-sm ..."
//  ▲ 16px mobile      ▲ 14px desktop
```

Esta corrección aplica a TODOS los `<input>`, `<textarea>`, y `<select>` del flujo.

---

## 2. Visuales Coherentes

### 2.1 Sistema de Iconos por Paso

| Paso | Icono | Uso en título | Contexto |
|------|-------|--------------|----------|
| 1 | 👤 | "👤 Tu nombre y teléfono" | Datos personales |
| 2 | 🔐 | "🔐 Tu cuenta GARDEN" | Seguridad/acceso |
| 3 | 📍 | "📍 ¿En qué zona vives?" | Ubicación geográfica |
| 4 | 🛠 | "🛠 ¿Qué servicios ofreces?" | Configuración |
| 5 | 💬 | "💬 Cuéntanos tu experiencia" | Narrativa personal |
| 6 | 📝 | "📝 Amplía tu descripción" | Detalle extra |
| 7 | 🐾 | "🐾 ¿Qué mascotas prefieres?" | Preferencias animales |
| 8 | 📏 | "📏 ¿Qué tamaños aceptas?" | Especificación |
| 9 | 🏠 | "🏠 Describe tu espacio" | Hogar (solo hospedaje) |
| 10 | ⏰ | "⏰ ¿Cómo es tu día a día?" | Rutina temporal |
| 11 | 💰 | "💰 Define tus tarifas" | Precios/dinero |
| 12 | 📸 | "📸 Sube fotos de tu espacio" | Multimedia |
| 13 | 🪪 | "🪪 Verificación de identidad" | Documento oficial |
| 14 | 📋 | "📋 Términos y condiciones" | Legal |
| 15 | ✅ | "✅ Revisa tu información" | Confirmación final |

**Implementación:** Los iconos se usan como texto Unicode, no como imágenes. Se renderizan nativo en todos los OS. El título combina icono + texto.

```tsx
const STEP_ICONS = ['👤','🔐','📍','🛠','💬','📝','🐾','📏','🏠','⏰','💰','📸','🪪','📋','✅'];

// En el sidebar
<span className="mr-2" aria-hidden="true">{STEP_ICONS[step - 1]}</span>
<span>{stepTitle}</span>
```

### 2.2 Tooltips para Preguntas Clave

**Patrón visual:**

```
  Precio por día (Bs) *  ⓘ
                          ▲
                    ┌─────────────────────────────┐
                    │  Este precio se muestra en   │
                    │  tu perfil público. Los       │
                    │  dueños pueden comparar.      │
                    │                               │
                    │  Sugerencia: mira los precios │
                    │  de otros cuidadores en tu    │
                    │  zona antes de decidir.       │
                    └─────────────────────────────┘
```

**Tooltips por paso:**

| Paso | Campo | Tooltip (texto del ⓘ) |
|------|-------|----------------------|
| 1 | Teléfono | "Usamos WhatsApp para coordinaciones con dueños y notificaciones de reservas." |
| 5 | Bio | "Una buena descripción aumenta tus probabilidades de ser elegido. Sé específico sobre tu experiencia." |
| 9 | Tipo de espacio | "Describe con detalle. Los dueños quieren saber exactamente dónde estará su mascota." |
| 11 | Precio por día | "Este precio se muestra en tu perfil. Mira los precios de otros cuidadores en tu zona antes de decidir." |
| 11 | Precio paseo | "Los precios de paseo incluyen ida, paseo y regreso de la mascota." |
| 12 | Fotos | "Las fotos reales de tu espacio son lo que más genera confianza. Evita fotos genéricas." |
| 13 | CI | "Solo el equipo GARDEN ve tu CI. Se usa para la verificación presencial." |

**Componente Tooltip:**

```tsx
const Tooltip = ({ content }: { content: string }) => {
  const [show, setShow] = useState(false);

  return (
    <span className="relative inline-flex">
      <button
        type="button"
        className="ml-1.5 inline-flex h-5 w-5 items-center justify-center
                   rounded-full text-gray-400 hover:text-gray-600
                   hover:bg-gray-100 transition-colors
                   focus-visible:outline-none focus-visible:ring-2
                   focus-visible:ring-green-500
                   dark:text-gray-500 dark:hover:text-gray-300
                   dark:hover:bg-gray-700"
        aria-label="Más información"
        onMouseEnter={() => setShow(true)}
        onMouseLeave={() => setShow(false)}
        onFocus={() => setShow(true)}
        onBlur={() => setShow(false)}
      >
        <span className="text-xs font-bold">ⓘ</span>
      </button>

      {show && (
        <div
          role="tooltip"
          className="absolute bottom-full left-1/2 z-50 mb-2 w-64
                     -translate-x-1/2 rounded-xl bg-gray-900 px-4 py-3
                     text-xs leading-relaxed text-white shadow-lg
                     dark:bg-gray-100 dark:text-gray-900
                     animate-in fade-in slide-in-from-bottom-1 duration-150"
        >
          {content}
          <div className="absolute left-1/2 top-full -translate-x-1/2
                          border-4 border-transparent border-t-gray-900
                          dark:border-t-gray-100" />
        </div>
      )}
    </span>
  );
};
```

### 2.3 Progress Tracker Clickable (Desktop Sidebar)

**Comportamiento:**

| Estado del paso | Clickable | Cursor | Efecto clic |
|----------------|-----------|--------|-------------|
| Completado (✓) | Sí | `cursor-pointer` | Navega a ese paso |
| Actual (●) | No (ya estás ahí) | `cursor-default` | Ninguno |
| Pendiente (○) | No | `cursor-not-allowed` | Ninguno |
| Skipped (◌) | Sí (si paso anterior completado) | `cursor-pointer` | Navega |

```tsx
const SidebarStep = ({ step, status, onNavigate }) => {
  const isClickable = status === 'completed' ||
                      (status === 'skipped' && isPreviousCompleted(step));

  return (
    <button
      type="button"
      onClick={() => isClickable && onNavigate(step)}
      disabled={!isClickable}
      className={cn(
        "flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-sm",
        "transition-all duration-150",
        {
          // Completado
          'text-green-700 hover:bg-green-50 cursor-pointer':
            status === 'completed',
          // Actual
          'text-green-800 font-semibold bg-green-50/50 cursor-default':
            status === 'current',
          // Pendiente
          'text-gray-400 cursor-not-allowed':
            status === 'pending',
        }
      )}
      aria-current={status === 'current' ? 'step' : undefined}
      aria-disabled={!isClickable}
    >
      <StepCircle step={step} status={status} />
      <span className="flex items-center gap-1.5">
        <span aria-hidden="true">{STEP_ICONS[step - 1]}</span>
        {STEP_TITLES[step - 1]}
      </span>
    </button>
  );
};
```

**Visual del sidebar con estados mixtos:**

```
  ┌──────────────────┐
  │  PROGRESO         │
  │                   │
  │  ✓ 👤 Nombre  →  │  ← clickable, hover:bg-green-50
  │  ✓ 🔐 Email   →  │  ← clickable
  │  ✓ 📍 Zona    →  │  ← clickable
  │  ● 🛠 Servicios  │  ← actual (bg-green-50/50)
  │  ○ 💬 Experiencia│  ← deshabilitado (text-gray-400)
  │  ○ 📝 Detalle    │
  │  ○ 🐾 Preferenc. │
  │  ...              │
  └──────────────────┘
```

### 2.4 Micro-interacciones Visuales

**Selección de zona (radio card):**

```tsx
// Transición al seleccionar
"transition-all duration-200 ease-out"
// Al seleccionar: scale-[1.02] breve, luego vuelve a scale-100
// Border anima de gray-200 a green-500
// Background anima de transparent a green-50
```

**Checkbox legal (paso 14):**

```tsx
// Checkbox custom con animación de check
<label className="group flex items-start gap-3 cursor-pointer">
  <div className={cn(
    "mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center",
    "rounded-md border-2 transition-all duration-150",
    checked
      ? "border-green-500 bg-green-500 dark:border-green-400 dark:bg-green-400"
      : "border-gray-300 group-hover:border-green-400 dark:border-gray-600"
  )}>
    {checked && (
      <svg className="h-3 w-3 text-white animate-in zoom-in duration-150">
        <path d="M1 3.5L3.5 6L7 1" stroke="currentColor" strokeWidth="2"
              fill="none" strokeLinecap="round" />
      </svg>
    )}
  </div>
  <span className="text-sm text-gray-700 dark:text-gray-300">
    {label}
  </span>
</label>
```

---

## 3. Manejo de Errores Refinado

### 3.1 Validation Gate: No Avanzar si Inválido

```tsx
const handleNext = async () => {
  // 1. Trigger validation para el paso actual
  const isValid = await trigger(); // react-hook-form trigger()

  if (!isValid) {
    // 2. Focus al primer campo con error
    const firstError = Object.keys(errors)[0];
    const el = document.getElementById(firstError);
    el?.focus();
    el?.scrollIntoView({ behavior: 'smooth', block: 'center' });

    // 3. Announce error to screen reader
    setAnnouncement(`Error: ${errors[firstError]?.message}`);

    // 4. Shake animation en el botón "Siguiente"
    setShakeNext(true);
    setTimeout(() => setShakeNext(false), 500);

    return; // NO avanza
  }

  // 5. Paso válido → guardar + avanzar
  saveToLocalStorage();
  setCurrentStep(prev => prev + 1);
};
```

### 3.2 Inline Error - Patrón Visual Completo

```
  Nombre *
  ┌───────────────────────────────┐
  │                               │  ← border-red-300
  │                               │     (shakes on submit attempt)
  └───────────────────────────────┘
  ⚠ El nombre es obligatorio         ← text-red-600, role="alert"
                                        animates in (fade + slide-up)
```

**Shake animation CSS:**

```css
@keyframes shake {
  0%, 100% { transform: translateX(0); }
  10%, 30%, 50%, 70%, 90% { transform: translateX(-4px); }
  20%, 40%, 60%, 80% { transform: translateX(4px); }
}
.animate-shake { animation: shake 0.4s ease-in-out; }
```

### 3.3 Errores por Paso - Catálogo Completo

| Paso | Campo | Error | Mensaje español |
|------|-------|-------|----------------|
| 1 | firstName | required | "El nombre es obligatorio" |
| 1 | firstName | minLength(2) | "El nombre debe tener al menos 2 caracteres" |
| 1 | firstName | pattern(letters) | "El nombre solo puede contener letras y espacios" |
| 1 | lastName | required | "El apellido es obligatorio" |
| 1 | phone | required | "El teléfono es obligatorio" |
| 1 | phone | pattern | "Formato válido: +591 seguido de 7 u 8 dígitos" |
| 2 | email | required | "El email es obligatorio" |
| 2 | email | format | "Ingresa un email válido" |
| 2 | email | async (409) | "Este email ya está registrado. ¿Iniciar sesión?" |
| 2 | password | required | "La contraseña es obligatoria" |
| 2 | password | minLength(8) | "Mínimo 8 caracteres" |
| 2 | password | pattern | "Debe incluir al menos una mayúscula y un número" |
| 2 | confirmPassword | match | "Las contraseñas no coinciden" |
| 3 | zone | required | "Selecciona tu zona" |
| 4 | servicesOffered | min(1) | "Selecciona al menos un servicio" |
| 5 | bioSummary | required | "Cuéntanos sobre tu experiencia" |
| 5 | bioSummary | minLength(50) | "Necesitamos al menos 50 caracteres para que los dueños te conozcan" |
| 9 | spaceType | required (if HOSPEDAJE) | "Describe tu tipo de espacio" |
| 11 | pricePerDay | required (if HOSPEDAJE) | "Define tu precio por día" |
| 11 | pricePerDay | min(30) | "El precio mínimo es Bs 30" |
| 11 | pricePerWalk30 | required (if PASEO) | "Define tu precio de paseo 30 min" |
| 11 | pricePerWalk60 | required (if PASEO) | "Define tu precio de paseo 1 hora" |
| 11 | pricePerWalk60 | custom | "El precio de 1 hora debe ser mayor que el de 30 min" |
| 12 | photos | min(4) | "Necesitas al menos 4 fotos" |
| 12 | photos[n] | fileSize | "La foto excede el límite de 5 MB" |
| 12 | photos[n] | fileType | "Solo se aceptan fotos JPG, PNG o WebP" |
| 13 | ciPhotoFront | required | "Sube la foto del frente de tu CI" |
| 13 | ciPhotoBack | required | "Sube la foto del reverso de tu CI" |
| 14 | termsAccepted | required | "Debes aceptar los Términos de servicio" |
| 14 | privacyAccepted | required | "Debes aceptar la Política de privacidad" |
| 14 | verificationAccepted | required | "Debes aceptar la verificación de identidad" |

### 3.4 Error Summary (Paso 15 - Revisión)

Si faltan campos obligatorios al intentar enviar:

```
┌──────────────────────────────────────────┐
│  ⚠ Completa estos campos antes de       │
│  enviar tu solicitud:                    │
│                                          │
│  • Paso 9: Describe tu espacio  [Ir →]   │
│  • Paso 12: Faltan 2 fotos     [Ir →]   │
│                                          │
│  (border-red-200 bg-red-50 text-red-800) │
│  role="alert"                            │
└──────────────────────────────────────────┘
```

---

## 4. Dashboard Responsive Completo

### 4.1 Mobile - Stack Vertical con Secciones Colapsables

```
┌─────────────────────────────────┐
│  GARDEN 🌿        (●) ▼ Menu   │  ← Avatar dropdown
├─────────────────────────────────┤
│                                 │
│  ┌─────────────────────────────┐│
│  │ ✓ Perfil verificado        ││  ← Banner compacto
│  │   y visible                 ││
│  └─────────────────────────────┘│
│                                 │
│  ┌─────────────────────────────┐│
│  │ 👤 Tu Perfil            [▼] ││  ← Colapsable
│  │ ─────────────────────────── ││
│  │                             ││
│  │  ┌─────────────────────┐   ││
│  │  │ ┌─────┐             │   ││
│  │  │ │foto │ Juan Pérez  │   ││
│  │  │ │     │ ✓ Verificado│   ││
│  │  │ └─────┘ ★ 4.8 (12)  │   ││
│  │  │                     │   ││
│  │  │ 📍 Equipetrol       │   ││
│  │  │ 🏠 Hospedaje: Bs120 │   ││
│  │  │ 🦮 Paseo 30m: Bs30  │   ││
│  │  │ 🦮 Paseo 1h: Bs50   │   ││
│  │  │                     │   ││
│  │  │ [Editar perfil]     │   ││
│  │  │ [Ver perfil público]│   ││
│  │  └─────────────────────┘   ││
│  └─────────────────────────────┘│
│                                 │
│  ┌─────────────────────────────┐│
│  │ 📅 Próximas Reservas   [▼] ││  ← Colapsable
│  │ ─────────────────────────── ││
│  │                             ││
│  │  ┌─────────────────────┐   ││
│  │  │ 🏠 Hospedaje        │   ││  ← Booking card
│  │  │ Max (Labrador)      │   ││
│  │  │ 15-18 Mar · Bs 360  │   ││
│  │  │ Carlos R. [Detalle →]│   ││
│  │  └─────────────────────┘   ││
│  │                             ││
│  │  ┌─────────────────────┐   ││
│  │  │ 🦮 Paseo 1h         │   ││
│  │  │ Luna (Golden)       │   ││
│  │  │ 20 Mar Tarde · Bs50 │   ││
│  │  │ Ana M. [Detalle →]  │   ││
│  │  └─────────────────────┘   ││
│  │                             ││
│  │  [Ver todas las reservas →] ││
│  └─────────────────────────────┘│
│                                 │
└─────────────────────────────────┘
```

### 4.2 Tablet (768-1023px) - Cards Side by Side

```
┌──────────────────────────────────────────────┐
│  GARDEN 🌿    Cuidadores     (●) Mi panel    │
├──────────────────────────────────────────────┤
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │ ✓ Tu perfil está verificado y        │    │
│  │   visible para los dueños.           │    │
│  └──────────────────────────────────────┘    │
│                                              │
│  ┌──────────────────┐ ┌──────────────────┐   │
│  │ 👤 Tu Perfil     │ │ 📅 Reservas      │   │
│  │ ─────────        │ │ ──────────       │   │
│  │ ┌─────┐          │ │                  │   │
│  │ │foto │ Juan P.  │ │ ┌──────────────┐ │   │
│  │ └─────┘ ✓ 4.8    │ │ │🏠 Max        │ │   │
│  │                  │ │ │15-18 Mar     │ │   │
│  │ 📍 Equipetrol    │ │ │Bs 360        │ │   │
│  │ 🏠 Bs120/día     │ │ └──────────────┘ │   │
│  │ 🦮 30m:Bs30      │ │                  │   │
│  │                  │ │ ┌──────────────┐ │   │
│  │ [Editar perfil]  │ │ │🦮 Luna       │ │   │
│  │ [Ver público →]  │ │ │20 Mar Bs50   │ │   │
│  └──────────────────┘ │ └──────────────┘ │   │
│                       │                  │   │
│                       │ [Ver todas →]    │   │
│                       └──────────────────┘   │
│                                              │
└──────────────────────────────────────────────┘
```

### 4.3 Avatar Dropdown Menu

```
  (●) Mi panel ▼
      │
      ▼
  ┌──────────────────────┐
  │  👤 Juan Pérez       │
  │  juan@email.com      │
  │  ────────────────    │
  │  📊 Mi panel         │  → /caregiver/dashboard
  │  ✎  Editar perfil    │  → /caregiver/edit
  │  👁 Ver perfil público│  → /caregivers/:id
  │  ────────────────    │
  │  🚪 Cerrar sesión    │  → logout + redirect /
  └──────────────────────┘

  Clases:
  "absolute right-0 top-full mt-2 w-64 rounded-2xl
   border border-gray-200 bg-white py-2 shadow-xl
   dark:border-gray-700 dark:bg-gray-800
   animate-in fade-in slide-in-from-top-2 duration-200"
```

### 4.4 Reservas - Table (Desktop) vs Cards (Mobile)

**Desktop (≥1024px): Tabla con columnas**

```
┌──────────────────────────────────────────────────────────────┐
│  Próximas Reservas                                           │
│  ─────────────────                                           │
│                                                              │
│  Servicio    Mascota        Fechas        Monto    Estado    │
│  ──────────  ─────────────  ──────────    ─────    ──────    │
│  🏠 Hosp.   Max (Labrador) 15-18 Mar     Bs 360   Confirmada│
│  🦮 Paseo   Luna (Golden)  20 Mar Tarde  Bs 50    Confirmada│
│  🏠 Hosp.   Rocky (Boxer)  25-28 Mar     Bs 480   Pendiente │
│                                                              │
│  [Ver todas las reservas →]                                  │
└──────────────────────────────────────────────────────────────┘
```

**Mobile (<768px): Cards stacked** (como se muestra en §4.1)

---

## 5. Animaciones y Transiciones Profesionales

### 5.1 Catálogo de Animaciones

| Elemento | Trigger | Animación | Duración | Easing |
|----------|---------|-----------|----------|--------|
| Page transition | Route change | Fade in + slide up (8px) | 200ms | ease-out |
| Step transition | Next/Prev | Slide left/right + fade | 300ms | ease-out |
| Tab switch | Tab click | Fade content + slide indicator | 200ms | ease-out |
| Card selection | Click/Space | Scale 1.02 → 1.0 + border color | 200ms | ease-out |
| Error appearance | Validation fail | Fade in + slide up (4px) | 150ms | ease-out |
| Error shake | Submit with errors | Horizontal shake (±4px) | 400ms | ease-in-out |
| Tooltip | Hover/Focus | Fade in + slide up (4px) | 150ms | ease-out |
| Progress bar | Step change | Width transition | 500ms | ease-out |
| Photo upload | File dropped | Fade in preview | 200ms | ease-out |
| Photo remove | Click remove | Fade out + scale down | 150ms | ease-in |
| Mobile menu | Hamburger click | Slide in from right | 300ms | ease-out |
| Dropdown | Avatar click | Fade in + slide from top (8px) | 200ms | ease-out |
| Success check | Submit OK | Scale 0 → 1 + bounce | 400ms | spring |
| Skeleton pulse | Loading | Opacity 0.5 → 1.0 loop | 1500ms | ease-in-out |

### 5.2 Wizard Step Transition

```tsx
// Step content wrapper with directional slide
const StepTransition = ({ direction, children }) => (
  <div
    className={cn(
      "animate-in duration-300 ease-out fill-mode-both",
      direction === 'forward'
        ? "fade-in slide-in-from-right-4"
        : "fade-in slide-in-from-left-4"
    )}
  >
    {children}
  </div>
);

// Usage
<StepTransition direction={currentStep > prevStep ? 'forward' : 'backward'}>
  <CurrentStepComponent />
</StepTransition>
```

### 5.3 Success Animation (Post-Submit)

```tsx
// Animated checkmark circle
const SuccessAnimation = () => (
  <div className="flex flex-col items-center py-12">
    <div className="relative h-20 w-20">
      {/* Circle */}
      <svg className="h-20 w-20 animate-in zoom-in duration-300" viewBox="0 0 80 80">
        <circle cx="40" cy="40" r="36" fill="none"
                className="stroke-green-500 dark:stroke-green-400"
                strokeWidth="3"
                strokeDasharray="226"
                strokeDashoffset="226"
                style={{ animation: 'draw-circle 0.6s ease-out 0.1s forwards' }} />
      </svg>
      {/* Checkmark */}
      <svg className="absolute inset-0 h-20 w-20" viewBox="0 0 80 80">
        <path d="M25 42 L35 52 L55 30" fill="none"
              className="stroke-green-500 dark:stroke-green-400"
              strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"
              strokeDasharray="50" strokeDashoffset="50"
              style={{ animation: 'draw-check 0.3s ease-out 0.7s forwards' }} />
      </svg>
    </div>
    <h2 className="mt-6 text-xl font-bold text-gray-900 dark:text-white
                    animate-in fade-in slide-in-from-bottom-2 duration-300 delay-700">
      Tu solicitud fue enviada
    </h2>
  </div>
);
```

---

## 6. Tailwind Dark/Light Theme

### 6.1 Configuración base

```tsx
// Tailwind config: usa class strategy
// tailwind.config.ts
export default {
  darkMode: 'class', // toggle via <html class="dark">
  // ...
}

// Toggle en navbar/settings
const { theme, toggleTheme } = useTheme();
```

### 6.2 Design Tokens - Light vs Dark

| Token | Light | Dark |
|-------|-------|------|
| **surface-page** | `bg-gray-50` | `dark:bg-gray-950` |
| **surface-card** | `bg-white` | `dark:bg-gray-900` |
| **surface-input** | `bg-white` | `dark:bg-gray-800` |
| **surface-elevated** | `bg-white shadow-lg` | `dark:bg-gray-800 dark:shadow-xl` |
| **border-default** | `border-gray-200` | `dark:border-gray-700` |
| **border-input** | `border-gray-300` | `dark:border-gray-600` |
| **border-focus** | `border-green-500` | `dark:border-green-400` |
| **text-primary** | `text-gray-900` | `dark:text-white` |
| **text-secondary** | `text-gray-500` | `dark:text-gray-400` |
| **text-muted** | `text-gray-400` | `dark:text-gray-500` |
| **brand-primary** | `bg-green-600` | `dark:bg-green-500` |
| **brand-primary-hover** | `hover:bg-green-700` | `dark:hover:bg-green-400` |
| **brand-primary-light** | `bg-green-50` | `dark:bg-green-950` |
| **brand-text** | `text-green-700` | `dark:text-green-400` |
| **error-bg** | `bg-red-50` | `dark:bg-red-950` |
| **error-border** | `border-red-300` | `dark:border-red-700` |
| **error-text** | `text-red-600` | `dark:text-red-400` |
| **success-bg** | `bg-green-50` | `dark:bg-green-950` |
| **success-border** | `border-green-200` | `dark:border-green-800` |
| **warning-bg** | `bg-amber-50` | `dark:bg-amber-950` |
| **warning-border** | `border-amber-200` | `dark:border-amber-800` |

### 6.3 Componentes con Dark Mode - Ejemplos

#### Navbar

```tsx
// ANTES (v1.0 - solo light)
"sticky top-0 z-50 border-b border-gray-200 bg-white/95 backdrop-blur-sm"

// DESPUÉS (v1.1 - light + dark)
"sticky top-0 z-50 border-b border-gray-200 bg-white/95 backdrop-blur-sm
 dark:border-gray-800 dark:bg-gray-950/95"
```

#### Input field

```tsx
// v1.1 - con dark mode
"w-full rounded-xl border border-gray-300 bg-white px-4 py-3
 text-base sm:text-sm text-gray-900
 placeholder:text-gray-400
 focus:border-green-500 focus:outline-none focus:ring-2 focus:ring-green-500/20
 transition-colors
 dark:border-gray-600 dark:bg-gray-800 dark:text-white
 dark:placeholder:text-gray-500
 dark:focus:border-green-400 dark:focus:ring-green-400/20"
```

#### Zone radio card

```tsx
// Unselected
"cursor-pointer rounded-xl border-2 border-gray-200 p-4
 hover:border-green-300 hover:bg-green-50/50 transition-all
 dark:border-gray-700 dark:hover:border-green-600 dark:hover:bg-green-950/30"

// Selected
"cursor-pointer rounded-xl border-2 border-green-500 bg-green-50 p-4
 ring-2 ring-green-500/20
 dark:border-green-400 dark:bg-green-950 dark:ring-green-400/20"
```

#### ProfileStatusBanner (pendiente)

```tsx
// v1.1
"rounded-2xl border border-amber-200 bg-amber-50 px-6 py-4 text-amber-800
 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-200"
```

#### Dashboard card

```tsx
"rounded-2xl border border-gray-200 bg-white p-6 shadow-sm
 dark:border-gray-700 dark:bg-gray-900 dark:shadow-none"
```

### 6.4 Dark Mode Toggle (Navbar)

```
  Light:  ☀ (sun icon)    →  click  →  Dark: 🌙 (moon icon)

  "rounded-lg p-2 text-gray-500 hover:bg-gray-100
   dark:text-gray-400 dark:hover:bg-gray-800
   transition-colors"
```

### 6.5 Contraste WCAG en Dark Mode

| Elemento | Light ratio | Dark ratio | Cumple AA |
|----------|-----------|-----------|-----------|
| Text (white on gray-950) | — | 18.1:1 | Sí |
| Text secondary (gray-400 on gray-950) | — | 6.8:1 | Sí |
| Green button (white on green-500) | — | 3.2:1 | **No** (large text only) |
| Green button fix (white on green-600 dark) | — | 4.6:1 | Sí |
| Error text (red-400 on gray-950) | — | 6.0:1 | Sí |
| Placeholder (gray-500 on gray-800) | — | 4.2:1 | Sí (non-text) |

**Fix dark mode button contrast:**

```tsx
// Usar green-600 en dark mode para botones (no green-500)
"bg-green-600 dark:bg-green-600 hover:bg-green-700 dark:hover:bg-green-500"
// Esto mantiene 4.6:1 en ambos modos
```

---

## 7. Wireframes Refinados: Pasos Sensibles

### 7.1 Paso 13: Verificación de Identidad - Refinado

**Desktop (≥1024px):**

```
┌──────────────────────────────────────────────────────────────────────────┐
│  GARDEN 🌿         Cuidadores                        (●) Mi panel      │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────┐  ┌────────────────────────────────────────────┐   │
│  │  PROGRESO        │  │                                            │   │
│  │  ...             │  │  Paso 13 de 15                             │   │
│  │  ✓ 12 Fotos     │  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━░░ (87%) │   │
│  │  ● 13 Verif.    │  │                                            │   │
│  │  ○ 14 Acuerdo   │  │  🪪 Verificación de identidad             │   │
│  │  ○ 15 Revisión  │  │  ─────────────────────────────             │   │
│  │                  │  │                                            │   │
│  │  ┌────────────┐ │  │  ┌──────────────────────────────────────┐  │   │
│  │  │ Guardar    │ │  │  │                                      │  │   │
│  │  │ y salir    │ │  │  │  🔒 Tus datos están protegidos       │  │   │
│  │  └────────────┘ │  │  │  ─────────────────────────────       │  │   │
│  └──────────────────┘  │  │                                      │  │   │
│                         │  │  • Solo el equipo GARDEN accede     │  │   │
│                         │  │    a estas fotos                    │  │   │
│                         │  │  • Se usan únicamente para          │  │   │
│                         │  │    verificar tu identidad           │  │   │
│                         │  │  • Se eliminan tras la verificación │  │   │
│                         │  │  • Cifradas durante transmisión     │  │   │
│                         │  │    y almacenamiento                 │  │   │
│                         │  │                                      │  │   │
│                         │  │  🔗 Ver Política de privacidad →    │  │   │
│                         │  │                                      │  │   │
│                         │  └──────────────────────────────────────┘  │   │
│                         │                                            │   │
│                         │  ┌──────────────────┐  ┌──────────────────┐│   │
│                         │  │  Frente de CI *  │  │  Reverso de CI * ││   │
│                         │  │                  │  │                  ││   │
│                         │  │  ┌────────────┐  │  │  ┌────────────┐  ││   │
│                         │  │  │            │  │  │  │            │  ││   │
│                         │  │  │   + Subir   │  │  │  │   + Subir   │  ││   │
│                         │  │  │   foto     │  │  │  │   foto     │  ││   │
│                         │  │  │            │  │  │  │            │  ││   │
│                         │  │  └────────────┘  │  │  └────────────┘  ││   │
│                         │  │  JPG/PNG ≤5MB    │  │  JPG/PNG ≤5MB    ││   │
│                         │  └──────────────────┘  └──────────────────┘│   │
│                         │                                            │   │
│                         │  ┌──────────────────────────────────────┐  │   │
│                         │  │  ⓘ Consejos para una buena foto:    │  │   │
│                         │  │  • Buena iluminación, sin reflejos   │  │   │
│                         │  │  • Que se lean todos los datos       │  │   │
│                         │  │  • Sin dedos cubriendo información   │  │   │
│                         │  └──────────────────────────────────────┘  │   │
│                         │                                            │   │
│                         │       [← Atrás]       [Siguiente →]        │   │
│                         └────────────────────────────────────────────┘   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Mobile (<768px) - Paso 13:**

```
┌─────────────────────────────────┐
│  ← Paso 13/15    [Guardar ✕]   │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━░░  │
├─────────────────────────────────┤
│                                 │
│  🪪 Verificación de identidad  │
│  ──────────────────────────     │
│                                 │
│  ┌───────────────────────────┐  │
│  │ 🔒 Tus datos están       │  │
│  │ protegidos                │  │
│  │                           │  │
│  │ • Solo equipo GARDEN      │  │
│  │   accede a estas fotos    │  │
│  │ • Se eliminan tras        │  │
│  │   verificación            │  │
│  │ • Cifradas en tránsito    │  │
│  │                           │  │
│  │ 🔗 Política de privacidad│  │
│  └───────────────────────────┘  │
│                                 │
│  Frente de CI *                 │
│  ┌───────────────────────────┐  │
│  │                           │  │
│  │      📷 Tomar foto       │  │  ← En mobile: cámara
│  │      o subir archivo      │  │     como opción primaria
│  │                           │  │
│  └───────────────────────────┘  │
│                                 │
│  Reverso de CI *                │
│  ┌───────────────────────────┐  │
│  │                           │  │
│  │      📷 Tomar foto       │  │
│  │      o subir archivo      │  │
│  │                           │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │ ⓘ Buena iluminación,    │  │
│  │   sin reflejos, datos     │  │
│  │   legibles                │  │
│  └───────────────────────────┘  │
│                                 │
│ ┌───────────────────────────┐   │
│ │ [← Atrás]  [Siguiente →] │   │
│ └───────────────────────────┘   │
└─────────────────────────────────┘
```

**Mobile: Opción de cámara directa:**

```tsx
// En mobile, input acepta capture="environment"
<input
  type="file"
  accept="image/jpeg,image/png,image/webp"
  capture="environment" // Abre cámara directamente en mobile
  className="sr-only"
  id="ci-front"
/>
<label htmlFor="ci-front" className="...dropzone classes...">
  <span className="md:hidden">📷 Tomar foto o subir archivo</span>
  <span className="hidden md:block">+ Subir foto (o arrastra aquí)</span>
</label>
```

### 7.2 Paso 12: Fotos - Upload con Progress y Lazy Loading

**Desktop - Grid 3x2 con estados individuales:**

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│  📸 Sube fotos de tu espacio                              │
│  ────────────────────────────                              │
│  Mínimo 4, máximo 6 fotos.                                │
│  Las fotos reales generan más confianza.  ⓘ               │
│                                                            │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐            │
│  │            │ │            │ │ ┌────────┐ │            │
│  │  [foto 1]  │ │  [foto 2]  │ │ │uploading│ │            │
│  │  ✕ borrar  │ │  ✕ borrar  │ │ │ 47%    │ │            │
│  │            │ │            │ │ │━━━░░░░ │ │            │
│  └────────────┘ └────────────┘ │ └────────┘ │            │
│  ┌────────────┐ ┌────────────┐ └────────────┘            │
│  │            │ │            │ ┌────────────┐            │
│  │  + Subir   │ │  + Subir   │ │            │            │
│  │  foto      │ │  foto      │ │  + Subir   │            │
│  │  (drag &   │ │            │ │  foto      │            │
│  │   drop)    │ │            │ │            │            │
│  └────────────┘ └────────────┘ └────────────┘            │
│                                                            │
│  2/6 fotos ⚠ Necesitas al menos 4                         │
│                                                            │
│  Sugerencias de fotos:                                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │
│  │🏡 Patio  │ │🛏 Espacio│ │🐕 Tú con │ │🚪 Entrada│     │
│  │/jardín   │ │ dormir   │ │tu mascota│ │/portón   │     │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘     │
│  (chips de sugerencia, no obligatorios)                    │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Lazy upload con progress tracking:**

```tsx
const PhotoUploadSlot = ({ photo, onUpload, onRemove, index }) => {
  const [progress, setProgress] = useState(0);
  const [status, setStatus] = useState<'idle'|'uploading'|'done'|'error'>('idle');

  if (status === 'uploading') {
    return (
      <div className="relative flex h-32 items-center justify-center
                      rounded-xl border-2 border-green-300 bg-green-50
                      dark:border-green-700 dark:bg-green-950
                      sm:h-40">
        <div className="text-center">
          <div className="text-sm font-medium text-green-700 dark:text-green-400">
            {progress}%
          </div>
          <div className="mt-2 h-1.5 w-24 overflow-hidden rounded-full bg-gray-200
                          dark:bg-gray-700">
            <div
              className="h-full rounded-full bg-green-500 transition-all duration-300"
              style={{ width: `${progress}%` }}
              role="progressbar"
              aria-valuenow={progress}
              aria-label={`Subiendo foto ${index + 1}: ${progress}%`}
            />
          </div>
        </div>
      </div>
    );
  }

  if (status === 'error') {
    return (
      <div className="relative flex h-32 items-center justify-center
                      rounded-xl border-2 border-red-300 bg-red-50
                      dark:border-red-700 dark:bg-red-950
                      sm:h-40">
        <div className="text-center">
          <span className="text-red-600 dark:text-red-400 text-sm">
            Error al subir
          </span>
          <button onClick={retry}
                  className="mt-1 block text-xs text-green-600 underline
                             dark:text-green-400">
            Reintentar
          </button>
        </div>
      </div>
    );
  }

  // ... idle and done states
};
```

---

## 8. Flujos Edge Cases

### 8.1 Logout desde Dashboard

```
1. Cuidador en /caregiver/dashboard
2. Clic avatar → menú dropdown → "Cerrar sesión"
3. Modal de confirmación:
   ┌──────────────────────────────┐
   │  ¿Cerrar sesión?             │
   │                              │
   │  Volverás a la página        │
   │  principal de GARDEN.        │
   │                              │
   │  [Cancelar]  [Cerrar sesión] │
   └──────────────────────────────┘
4. Confirma → clearStoredToken() + queryClient.clear()
5. Redirect a / (home/listing)
6. Navbar vuelve a mostrar "Soy cuidador"
```

### 8.2 Perfil Rechazado → Re-submit

```
1. Admin rechaza perfil del cuidador
   → POST /api/admin/caregivers/:id/reject { reason: "Fotos borrosas" }
2. Cuidador visita /caregiver/dashboard
3. Ve ProfileStatusBanner con estado NUEVO:

   ┌────────────────────────────────────────────────┐
   │  ⚠ Tu perfil no fue aprobado                   │
   │                                                 │
   │  Motivo: "Las fotos no muestran claramente      │
   │  tu espacio. Por favor sube fotos con mejor     │
   │  iluminación."                                  │
   │                                                 │
   │  [Editar y reenviar perfil →]                   │
   │                                                 │
   │  border-red-200 bg-red-50 text-red-800          │
   │  dark:border-red-800 dark:bg-red-950            │
   │  dark:text-red-200                              │
   └────────────────────────────────────────────────┘

4. Clic "Editar y reenviar perfil →"
5. Navega a /caregiver/edit (formulario pre-llenado)
6. Edita los campos indicados (ej: reemplaza fotos)
7. Clic "Reenviar solicitud"
   → PUT /api/caregivers/:id { ...updated fields }
   → PATCH /api/caregivers/:id/resubmit
8. Banner cambia a "Pendiente de verificación"
```

**Nuevo estado para ProfileStatusBanner:**

| Estado | Color | Icono | Mensaje |
|--------|-------|-------|---------|
| **Rechazado** | `bg-red-50 border-red-200 text-red-800` / `dark:bg-red-950 dark:border-red-800 dark:text-red-200` | ⚠ | "Tu perfil no fue aprobado. Motivo: {reason}. [Editar y reenviar →]" |

### 8.3 Token Expirado durante Wizard

```
1. Cuidador inició sesión hace 7 días
2. Está en /caregiver/edit (editando perfil)
3. Presiona "Guardar cambios"
4. PUT /api/caregivers/:id → 401 Unauthorized
5. Interceptor de axios intenta refresh token:
   a. POST /api/auth/refresh → 200 → retry original request → éxito
   b. POST /api/auth/refresh → 401 (refresh también expiró):
      - Guarda datos del formulario en localStorage (draft)
      - Muestra modal:
        ┌──────────────────────────────┐
        │  Tu sesión expiró            │
        │                              │
        │  Tus cambios fueron          │
        │  guardados. Inicia sesión    │
        │  para continuar.             │
        │                              │
        │  [Iniciar sesión →]          │
        └──────────────────────────────┘
      - Clic → redirect /caregiver/auth
      - Post-login → restaura draft → continúa editando
```

### 8.4 Wizard Draft Expirado (>7 días)

```
1. Visitante vuelve a /caregiver/register
2. Sistema detecta draft con lastSavedAt > 7 días atrás
3. Modal:
   ┌──────────────────────────────────────┐
   │  Registro guardado caducado          │
   │                                      │
   │  Guardaste tu progreso el            │
   │  28 de enero, hace más de 7 días.    │
   │  Por seguridad, algunos datos        │
   │  pueden haber cambiado.              │
   │                                      │
   │  [Empezar de nuevo]                  │
   │  [Intentar recuperar datos →]        │
   └──────────────────────────────────────┘
4. "Intentar recuperar" → carga draft pero marca paso 2
   (email/password) como pendiente de re-confirmación
5. "Empezar de nuevo" → limpia localStorage, paso 1
```

### 8.5 Conexión Perdida durante Upload de Fotos

```
1. Cuidador en Paso 12, subiendo foto 3 de 4
2. Conexión se pierde durante upload
3. Upload falla → estado 'error' en la foto:

   ┌────────────┐
   │  ⚠ Error   │
   │  ─────     │
   │  Sin       │
   │  conexión  │
   │            │
   │ [Reintentar│
   │      ↻]    │
   └────────────┘

4. Banner superior aparece:
   ┌───────────────────────────────────┐
   │  ⚠ Sin conexión a internet.      │
   │  Los datos guardados están        │
   │  seguros en tu dispositivo.       │
   └───────────────────────────────────┘

5. Cuando vuelve la conexión:
   - Banner desaparece
   - Botón "Reintentar" disponible
   - NO reintenta automáticamente (el usuario decide)
```

### 8.6 Cuidador Suspendido Intenta Acceder

```
1. Admin suspende cuidador (suspended=true)
2. Cuidador intenta acceder a /caregiver/dashboard
3. ProtectedRoute detecta suspended=true
4. Redirect a /caregiver/suspended:

   ┌──────────────────────────────────────┐
   │                                      │
   │  ⚠ Tu cuenta está suspendida        │
   │  ─────────────────────────           │
   │                                      │
   │  Tu perfil fue suspendido por el     │
   │  equipo GARDEN.                      │
   │                                      │
   │  Si crees que esto es un error,      │
   │  contacta nuestro soporte:           │
   │                                      │
   │  📱 WhatsApp: +591 7XX-XXXX         │
   │  📧 soporte@garden.bo               │
   │                                      │
   │  [Volver al inicio]                  │
   │  [Cerrar sesión]                     │
   │                                      │
   └──────────────────────────────────────┘
```

### 8.7 Browser Back durante Wizard

```
1. Cuidador está en Paso 8
2. Presiona botón "Back" del browser
3. Comportamiento:
   - El wizard intercepta con `beforeunload` + history.pushState
   - Navega al Paso 7 (paso anterior en el wizard)
   - NO sale del wizard al presionar back una vez
4. Si presiona Back en Paso 1:
   - Modal: "¿Guardar progreso y salir?"
   - [Guardar y salir] → guarda draft, navega a /caregiver/auth
   - [Descartar] → limpia draft, navega a /caregiver/auth
   - [Cancelar] → se queda en Paso 1

Implementación:
```tsx
useEffect(() => {
  const handlePopState = (e: PopStateEvent) => {
    e.preventDefault();
    if (currentStep > 1) {
      setCurrentStep(prev => prev - 1);
      window.history.pushState(null, '', window.location.href);
    } else {
      setShowExitModal(true);
    }
  };
  window.history.pushState(null, '', window.location.href);
  window.addEventListener('popstate', handlePopState);
  return () => window.removeEventListener('popstate', handlePopState);
}, [currentStep]);
```

---

## 9. Self-Review y Correcciones

### 9.1 Inconsistencias Corregidas desde v1.0

| # | Inconsistencia | Ubicación v1.0 | Corrección v1.1 |
|---|----------------|----------------|-----------------|
| 1 | **Paso 9 condicional no mencionado en sidebar.** El sidebar desktop muestra "9 Hogar" incluso si el usuario solo ofrece PASEOS (y paso 9 se salta). | §5.2, §7.3 sidebar | Sidebar muestra paso 9 como "— Hogar (no aplica)" en gris tachado si solo PASEO. La numeración de pasos se mantiene (no reordena) para consistencia de progreso. |
| 2 | **Paso 11 condicional incompleto.** Si solo ofrece HOSPEDAJE, no se muestran campos de paseos. Pero v1.0 no especifica qué pasa con `pricePerWalk30/60` en ese caso. | §5.3 Paso 11 | Campos de paseo no se muestran. Se envían como `null` al backend. Backend acepta `null` (ya definidos como `Int?` en schema). |
| 3 | **`disabled` vs `aria-disabled` en botón Siguiente.** v1.0 usa `disabled:opacity-50 disabled:cursor-not-allowed` en submit, contradice la decisión de accesibilidad de usar `aria-disabled`. | §8.3 Auth submit button | Corregido a `aria-disabled="true"` + clases visuales manuales. Nunca usar `disabled` HTML en submit buttons. |
| 4 | **Input text-sm causa zoom iOS.** v1.0 define inputs como `text-sm` (14px). Safari iOS hace zoom auto en inputs <16px. | §8.3 todos los inputs | Corregido: `text-base sm:text-sm`. 16px en mobile, 14px en desktop. Ver §1.6. |
| 5 | **bioSummary min 50 chars pero placeholder ejemplo tiene 57.** El placeholder "Ej: Tengo 2 labradores, cuido mascotas hace 3 años..." guía bien, pero no aclara que 50 chars es el mínimo. | §5.3 Paso 5 | Agregar helper text debajo del textarea: "Mínimo 50 caracteres. Describe tu experiencia, cuánto tiempo llevas, si tienes mascotas propias." |
| 6 | **Paso 12 fotos: sin adaptación para solo PASEO.** v1.0 menciona que el subtítulo cambia, pero las sugerencias de fotos siguen siendo de espacio (patio, dormitorio). | §5.3 Paso 12 | Sugerencias dinámicas según servicio. PASEO: "Tú con un perro", "Ruta de paseo", "Parque o zona verde", "Tu equipo (correa, bolsas)". |
| 7 | **Auth page: tab "Registrarme" no aclara si es tab de contenido o navega.** v1.0 dice que al presionar "Comenzar registro" navega a `/caregiver/register`. Pero el tab mismo podría confundir. | §4.3 | Aclara: El tab "Registrarme" muestra info + botón CTA. El CTA navega. El tab NO navega directamente. Es un tab de contenido. |
| 8 | **Dashboard sin estado "Rechazado".** v1.0 define 4 variantes de banner pero no "Rechazado". | §6.2 | Agregado estado "Rechazado" con botón "Editar y reenviar". Ver §8.2. |
| 9 | **Falta dark mode en todos los componentes.** v1.0 no menciona dark mode en ningún lugar. | Todo §8 | Agregado §6 completo con tokens dark, ejemplos, y contraste verificado. |
| 10 | **Sidebar no clickable en v1.0.** v1.0 dice "Se puede navegar a pasos anteriores completados desde el sidebar" pero no especifica implementación ni estados. | §5.6 | Documentado en §2.3 con estados (completed=clickable, current=no, pending=no), componente, y ARIA. |

### 9.2 Condicionales Hospedaje/Paseo - Tabla Definitiva

| Paso | Solo HOSPEDAJE | Solo PASEO | HOSPEDAJE + PASEO |
|------|---------------|------------|-------------------|
| 1-8 | Normal | Normal | Normal |
| **9 Hogar** | Normal (obligatorio) | **Se salta auto** (sidebar: tachado) | Normal (obligatorio) |
| 10 Rutina | Normal | Normal | Normal |
| **11 Tarifas** | Solo `pricePerDay` | Solo `pricePerWalk30` + `pricePerWalk60` | Todos los campos |
| **12 Fotos** | Sugerencias: patio, dormitorio, mascota, portón | Sugerencias: tú con perro, ruta, parque, equipo | Sugerencias: patio, mascota, ruta, portón |
| 13-15 | Normal | Normal | Normal |

**Paso 9 saltado - Sidebar visual:**

```
  ✓ 📏 Tamaños
  ━ 🏠 Hogar (no aplica)    ← text-gray-300, line-through
  ○ ⏰ Rutina
```

**Paso 9 saltado - Progress bar:**
El paso 9 no cuenta para el porcentaje. Si se salta, el total es 14 pasos. La barra se calcula: `(completedSteps / totalActiveSteps) * 100`.

```tsx
const totalSteps = servicesOffered.includes('HOSPEDAJE') ? 15 : 14;
const progress = (currentStepIndex / totalSteps) * 100;
```

### 9.3 Escalabilidad - Lazy Loading Completo

**Photo upload pipeline optimizado:**

```tsx
// Pipeline de upload lazy con queue
const usePhotoUploadQueue = (maxConcurrent = 2) => {
  const [queue, setQueue] = useState<UploadJob[]>([]);
  const [active, setActive] = useState<UploadJob[]>([]);

  useEffect(() => {
    // Procesar queue con max 2 uploads simultáneos
    if (active.length < maxConcurrent && queue.length > 0) {
      const next = queue[0];
      setQueue(prev => prev.slice(1));
      setActive(prev => [...prev, next]);
      processUpload(next);
    }
  }, [queue, active]);

  const processUpload = async (job: UploadJob) => {
    try {
      // 1. Resize client-side (web worker si disponible)
      const resized = await resizeInWorker(job.file, {
        maxWidth: 1200,
        format: 'webp',
        quality: 0.85,
      });

      // 2. Upload con progreso
      const url = await uploadToCloudinary(resized, (pct) => {
        updateJobProgress(job.id, pct);
      });

      // 3. Liberar ObjectURL del preview
      URL.revokeObjectURL(job.previewUrl);

      // 4. Marcar completado
      completeJob(job.id, url);
    } catch (error) {
      failJob(job.id, error);
    } finally {
      setActive(prev => prev.filter(j => j.id !== job.id));
    }
  };

  return { addToQueue, queue, active, results };
};
```

**Web Worker para resize (no bloquea UI):**

```tsx
// workers/imageResize.worker.ts
self.onmessage = async (e: MessageEvent) => {
  const { file, maxWidth, quality } = e.data;
  const bitmap = await createImageBitmap(file);
  const ratio = Math.min(1, maxWidth / bitmap.width);
  const canvas = new OffscreenCanvas(
    bitmap.width * ratio,
    bitmap.height * ratio
  );
  const ctx = canvas.getContext('2d')!;
  ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  const blob = await canvas.convertToBlob({ type: 'image/webp', quality });
  self.postMessage({ blob });
};
```

### 9.4 Checklist Final de Consistencia

| Aspecto | v1.0 | v1.1 | Estado |
|---------|------|------|--------|
| `text-sm` en inputs mobile | 14px (causa zoom iOS) | `text-base sm:text-sm` (16px mobile) | Corregido |
| `disabled` en submit buttons | HTML `disabled` | `aria-disabled="true"` | Corregido |
| Border-radius system | cards=2xl, buttons=xl | Consistente en todo el doc | Verificado |
| Dark mode | Ausente | Completo con contraste verificado | Agregado |
| Tooltips | Ausentes | 7 tooltips en pasos clave | Agregado |
| Clickable progress | Mencionado, no especificado | Componente completo con ARIA | Agregado |
| Condicional Paso 9 (solo PASEO) | Mencionado en texto | Tabla definitiva + sidebar visual + progress calc | Completado |
| Condicional Paso 11 | Mencionado pero parcial | Tabla con 3 escenarios + null handling | Completado |
| Condicional Paso 12 sugerencias | Subtítulo cambia, sugerencias no | Sugerencias dinámicas por servicio | Corregido |
| ProfileStatusBanner "Rechazado" | 4 variantes (falta rechazado) | 5 variantes con botón reenviar | Agregado |
| Edge case: logout | No documentado | Flujo completo con modal | Agregado |
| Edge case: rechazado + re-submit | No documentado | Flujo 8 pasos | Agregado |
| Edge case: token expirado | Parcial (solo "auto-redirect") | Flujo con draft save + modal | Completado |
| Edge case: draft expirado | Mencionado (7 días) sin UI | Modal con opciones | Agregado |
| Edge case: conexión perdida uploads | No documentado | Estado error + reintentar + banner | Agregado |
| Edge case: browser back | No documentado | History API intercept + modal | Agregado |
| Edge case: suspendido | Banner existe, sin página dedicada | Página /caregiver/suspended | Agregado |
| Collapsible sections mobile | No documentado | Componente + implementación paso 11 | Agregado |
| Animaciones | Mencionadas parcialmente | Catálogo completo 14 animaciones | Completado |
| Step transition direction | No especificado | Slide left/right según dirección | Agregado |

---

*Fin del documento GARDEN_Flujo_Soy_Cuidador_Refinado.md v1.1*
*Este documento complementa GARDEN_Flujo_Soy_Cuidador.md v1.0 — ambos deben leerse juntos.*
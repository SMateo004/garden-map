# GARDEN - Formulario de Registro/Edicion de Perfil de Cuidador

## React 18 + Tailwind CSS + Cloudinary | Dark/Light Theme

**Version:** 1.0
**Fecha:** 06 de Febrero, 2026
**Schema:** Prisma `CaregiverProfile` con enum `Zone`, `ServiceType`, `spaceType` libre
**Scope:** Formulario unico (registro + edicion), responsive mobile-first, dark mode ready

---

## Tabla de Contenidos

1. [Wireframe del Formulario](#1-wireframe-del-formulario)
2. [Estructura de Componentes React](#2-estructura-de-componentes-react)
3. [Clases Tailwind por Seccion](#3-clases-tailwind-por-seccion)
4. [Estados y Flujos](#4-estados-y-flujos)

---

## 1. Wireframe del Formulario

Formulario en pagina unica con scroll (no multi-step). Razon: el cuidador completa todo de una vez, puede ver su progreso, y el boton "Guardar" esta siempre visible como meta. Las secciones se separan con dividers y headers claros.

### 1.1 Mobile (< 768px) — Vista Completa

```
┌──────────────────────────────────┐
│ [←]   Mi perfil de cuidador     │
├──────────────────────────────────┤
│                                  │
│  ┌──────────────────────────────┐│
│  │  ⏳ Pendiente de verificacion││
│  │                              ││
│  │  Tu perfil sera revisado     ││
│  │  manualmente por el equipo   ││
│  │  GARDEN en 24-48 horas.      ││
│  │                              ││
│  │  Incluye entrevista personal ││
│  │  y visita a tu espacio.      ││
│  └──────────────────────────────┘│
│                                  │
│  ── FOTOS DE TU ESPACIO ─────── │
│                                  │
│  Muestra donde estaran las      │
│  mascotas. Fotos reales, no     │
│  stock. Minimo 4, maximo 6.     │
│                                  │
│  ┌──────┐  ┌──────┐  ┌──────┐  │
│  │      │  │      │  │      │  │
│  │  +   │  │  +   │  │  +   │  │
│  │      │  │      │  │      │  │
│  └──────┘  └──────┘  └──────┘  │
│  ┌──────┐  ┌──────┐  ┌──────┐  │
│  │      │  │      │  │      │  │
│  │  +   │  │  +   │  │  +   │  │
│  │      │  │      │  │      │  │
│  └──────┘  └──────┘  └──────┘  │
│                                  │
│  📷 0/4 minimo  ·  0/6 maximo   │
│                                  │
│  Sugerencias:                    │
│  1. Tu patio o espacio exterior  │
│  2. Donde dormira la mascota    │
│  3. Tu con tu propia mascota    │
│  4. Ruta de paseo (si ofreces)  │
│                                  │
│  ── SOBRE TI ────────────────── │
│                                  │
│  Descripcion *                   │
│  ┌──────────────────────────────┐│
│  │ Describe tu espacio, tu      ││
│  │ experiencia con mascotas y   ││
│  │ por que deberian confiar     ││
│  │ en ti...                     ││
│  │                              ││
│  │                              ││
│  │                     0/500    ││
│  └──────────────────────────────┘│
│                                  │
│  Tipo de espacio *               │
│  ┌──────────────────────────────┐│
│  │ Ej: Casa con patio cercado  ││
│  │ de 50m²                      ││
│  └──────────────────────────────┘│
│  Describe tu espacio como       │
│  quieras: tamano, patio,        │
│  jardin, departamento, etc.     │
│                                  │
│  ── UBICACION ───────────────── │
│                                  │
│  Zona *                          │
│  ┌──────────────────────────────┐│
│  │ Selecciona tu zona         ▾││
│  ├──────────────────────────────┤│
│  │ ○ Equipetrol                 ││
│  │ ○ Urbari                     ││
│  │ ○ Norte                      ││
│  │ ○ Las Palmas                 ││
│  │ ○ Centro / Av. San Martin   ││
│  │ ○ Otros                      ││
│  └──────────────────────────────┘│
│                                  │
│  ── SERVICIOS Y PRECIOS ─────── │
│                                  │
│  Que servicios ofreces? *        │
│                                  │
│  ┌──────────────────────────────┐│
│  │ ☐  🏠 Hospedaje              ││
│  │     Tu mascota se queda en   ││
│  │     mi espacio               ││
│  └──────────────────────────────┘│
│  ┌──────────────────────────────┐│
│  │ ☐  🦮 Paseos                  ││
│  │     Paseo por tu zona        ││
│  └──────────────────────────────┘│
│                                  │
│  ╌╌ (aparece si Hospedaje) ╌╌╌  │
│                                  │
│  Precio hospedaje *              │
│  ┌────────────────────┐          │
│  │ Bs         [     ] │ / dia   │
│  └────────────────────┘          │
│  Rango sugerido: Bs 60 - 200    │
│                                  │
│  ╌╌ (aparece si Paseos) ╌╌╌╌╌╌  │
│                                  │
│  Precio paseo 30 min *           │
│  ┌────────────────────┐          │
│  │ Bs         [     ] │ /30min  │
│  └────────────────────┘          │
│                                  │
│  Precio paseo 1 hora *           │
│  ┌────────────────────┐          │
│  │ Bs         [     ] │ /1h     │
│  └────────────────────┘          │
│  Rango sugerido: Bs 20 - 100    │
│                                  │
│  ── ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ──  │
│                                  │
│  ┌──────────────────────────────┐│
│  │ Requisitos para guardar:     ││
│  │                              ││
│  │ ✓ Minimo 4 fotos             ││
│  │ ✗ Descripcion (min 50 chars) ││
│  │ ✗ Tipo de espacio            ││
│  │ ✓ Zona seleccionada          ││
│  │ ✗ Al menos 1 servicio        ││
│  │ ✗ Precios de cada servicio   ││
│  └──────────────────────────────┘│
│                                  │
│ ┌──────────────────────────────┐ │
│ │                              │ │
│ │   [  Guardar perfil  ]       │ │  ← disabled hasta cumplir todo
│ │                              │ │
│ │   Tu perfil sera revisado    │ │
│ │   en 24-48 horas             │ │
│ │                              │ │
│ └──────────────────────────────┘ │
│                                  │
└──────────────────────────────────┘
```

### 1.2 Desktop (>= 1024px) — Vista Completa

```
┌────────────────────────────────────────────────────────────────────────────┐
│  [🌿 GARDEN]         Cuidadores    Como funciona    [Maria L. ▾]          │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ← Volver                                                                 │
│                                                                            │
│  ┌────────────────────────────────────────────────┬───────────────────────┐│
│  │                                                │                       ││
│  │  Mi perfil de cuidador                         │  ┌─── SIDEBAR ──────┐││
│  │  ────────────────────                          │  │                   │││
│  │                                                │  │  Requisitos       │││
│  │  ┌──────────────────────────────────────────┐  │  │  ────────────     │││
│  │  │  ⏳ Tu perfil sera revisado manualmente  │  │  │                   │││
│  │  │  por el equipo GARDEN en 24-48 horas.    │  │  │  ◻ 4+ fotos      │││
│  │  │  Incluye entrevista y visita.            │  │  │  ◻ Descripcion   │││
│  │  └──────────────────────────────────────────┘  │  │  ◻ Tipo espacio  │││
│  │                                                │  │  ◻ Zona          │││
│  │  ── FOTOS DE TU ESPACIO ────────────────────── │  │  ◻ 1+ servicio   │││
│  │                                                │  │  ◻ Precios       │││
│  │  Muestra donde estaran las mascotas.           │  │                   │││
│  │  Fotos reales. Minimo 4, maximo 6.             │  │  ────────────     │││
│  │                                                │  │                   │││
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐  │  │  [  Guardar   ]  │││
│  │  │        │ │        │ │        │ │        │  │  │  perfil           │││
│  │  │   +    │ │   +    │ │   +    │ │   +    │  │  │                   │││
│  │  │ Foto 1 │ │ Foto 2 │ │ Foto 3 │ │ Foto 4 │  │  │  (disabled)      │││
│  │  │        │ │        │ │        │ │        │  │  │                   │││
│  │  └────────┘ └────────┘ └────────┘ └────────┘  │  │  ────────────     │││
│  │  ┌────────┐ ┌────────┐                         │  │                   │││
│  │  │        │ │        │                         │  │  Tu perfil sera   │││
│  │  │   +    │ │   +    │  📷 0/4 min · 0/6 max  │  │  revisado en      │││
│  │  │ Foto 5 │ │ Foto 6 │                         │  │  24-48 horas      │││
│  │  │        │ │        │                         │  │                   │││
│  │  └────────┘ └────────┘                         │  └───────────────────┘││
│  │                                                │                       ││
│  │  Sugerencias: patio, dormitorio mascota,       │                       ││
│  │  tu con tu mascota, ruta de paseo              │                       ││
│  │                                                │                       ││
│  │  ── SOBRE TI ──────────────────────────────── │                       ││
│  │                                                │                       ││
│  │  Descripcion *                                 │                       ││
│  │  ┌──────────────────────────────────────────┐  │                       ││
│  │  │ Describe tu espacio, tu experiencia con  │  │                       ││
│  │  │ mascotas y por que deberian confiar      │  │                       ││
│  │  │ en ti...                                 │  │                       ││
│  │  │                                          │  │                       ││
│  │  │                                          │  │                       ││
│  │  │                                 0/500    │  │                       ││
│  │  └──────────────────────────────────────────┘  │                       ││
│  │                                                │                       ││
│  │  Tipo de espacio *                             │                       ││
│  │  ┌──────────────────────────────────────────┐  │                       ││
│  │  │ Ej: Casa con patio cercado de 50m²       │  │                       ││
│  │  └──────────────────────────────────────────┘  │                       ││
│  │  Texto libre: "depto en piso 5 con balcon",   │                       ││
│  │  "casa con jardin y piscina", etc.             │                       ││
│  │                                                │                       ││
│  │  ── UBICACION ────────────────────────────── │                        ││
│  │                                                │                       ││
│  │  Zona *                                        │                       ││
│  │  ┌──────────────────────────────────────────┐  │                       ││
│  │  │ Selecciona tu zona                     ▾ │  │                       ││
│  │  └──────────────────────────────────────────┘  │                       ││
│  │                                                │                       ││
│  │  ── SERVICIOS Y PRECIOS ────────────────────  │                       ││
│  │                                                │                       ││
│  │  ┌─────────────────────┐ ┌──────────────────┐ │                       ││
│  │  │ ☐  🏠 Hospedaje      │ │ ☐  🦮 Paseos     │ │                       ││
│  │  │  Se queda en mi     │ │  Paseo por la    │ │                       ││
│  │  │  espacio             │ │  zona            │ │                       ││
│  │  └─────────────────────┘ └──────────────────┘ │                       ││
│  │                                                │                       ││
│  │  ╌╌ Precios (se muestran al activar) ╌╌╌╌╌╌  │                       ││
│  │                                                │                       ││
│  │  ┌───────────────────────────────┐             │                       ││
│  │  │ 🏠 Hospedaje                  │             │                       ││
│  │  │   Bs [      ] / dia          │             │                       ││
│  │  │   Sugerido: Bs 60 - 200       │             │                       ││
│  │  └───────────────────────────────┘             │                       ││
│  │                                                │                       ││
│  │  ┌───────────────────────────────┐             │                       ││
│  │  │ 🦮 Paseos                      │             │                       ││
│  │  │   30 min  Bs [      ]         │             │                       ││
│  │  │   1 hora  Bs [      ]         │             │                       ││
│  │  │   Sugerido: Bs 20 - 100       │             │                       ││
│  │  └───────────────────────────────┘             │                       ││
│  │                                                │                       ││
│  └────────────────────────────────────────────────┴───────────────────────┘│
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 Fotos: Estados de Upload (Detalle)

```
SLOT VACIO:
┌────────────────┐
│                │
│   ┌────────┐   │
│   │  📷 +  │   │  border-dashed, border-2
│   └────────┘   │  border-gray-300 dark:border-gray-600
│                │  hover:border-garden-400
│   Agregar      │  cursor-pointer
│                │
└────────────────┘

DRAG OVER:
┌────────────────┐
│████████████████│
│████████████████│  border-garden-500
│████ Soltar ████│  bg-garden-50 dark:bg-garden-950
│████  aqui  ████│  scale-[1.02] transition
│████████████████│
│████████████████│
└────────────────┘

SUBIENDO (con progreso):
┌────────────────┐
│░░░░░░░░░░░░░░░░│
│░ Preview de  ░░│  img con opacity-60
│░ la foto     ░░│
│░             ░░│
│░  ┌────────┐ ░░│  circulo SVG progress
│░  │  67%   │ ░░│  stroke-dasharray animado
│░  └────────┘ ░░│
│░░░░░░░░░░░░░░░░│
└────────────────┘

SUBIDA EXITOSA:
┌────────────────┐
│░░░░░░░░░░░░░░░░│
│░ Foto clara  ░░│  img sin opacity
│░ y nitida    ░░│
│░         [✕] ░░│  boton eliminar (hover)
│░             ░░│
│░░░░░░░░░░░░░░░░│
│ Principal      │  badge si es la primera
│ ═══════ ▲▼     │  controles reordenar
└────────────────┘

ERROR:
┌────────────────┐
│░░░░░░░░░░░░░░░░│
│░ Preview     ░░│  img con grayscale + opacity-50
│░ difusa      ░░│
│░             ░░│
│░   ⚠ Error   ░░│  icono + texto
│░  5.2MB > 5MB ░░│
│░ [Reintentar] ░░│  boton retry
│░░░░░░░░░░░░░░░░│
└────────────────┘
```

### 1.4 Seccion Precios: Aparicion Condicional

```
NINGUN SERVICIO SELECCIONADO:
┌──────────────────────┐  ┌──────────────────────┐
│ ☐  🏠 Hospedaje       │  │ ☐  🦮 Paseos          │
│  Se queda en mi      │  │  Paseo por la zona   │
│  espacio              │  │                      │
└──────────────────────┘  └──────────────────────┘

  (no se muestran campos de precio)


HOSPEDAJE ACTIVADO:
┌──────────────────────┐  ┌──────────────────────┐
│ ☑  🏠 Hospedaje       │  │ ☐  🦮 Paseos          │
│  Se queda en mi      │  │  Paseo por la zona   │
│  espacio              │  │                      │
└──────────────────────┘  └──────────────────────┘

  ┌─── slide-down, fade-in (animate) ──────────┐
  │                                              │
  │  Precio por dia *                            │
  │  ┌──────────────────┐                        │
  │  │ Bs       [     ] │ / dia                 │
  │  └──────────────────┘                        │
  │  Sugerido: Bs 60 - 200 para Santa Cruz      │
  │                                              │
  └──────────────────────────────────────────────┘


AMBOS ACTIVADOS:
┌──────────────────────┐  ┌──────────────────────┐
│ ☑  🏠 Hospedaje       │  │ ☑  🦮 Paseos          │
│  Se queda en mi      │  │  Paseo por la zona   │
│  espacio              │  │                      │
└──────────────────────┘  └──────────────────────┘

  ┌─── PRECIOS HOSPEDAJE ──────────────────────┐
  │  Precio por dia *                           │
  │  Bs [      ] / dia                         │
  │  Sugerido: Bs 60 - 200                      │
  └─────────────────────────────────────────────┘

  ┌─── PRECIOS PASEO ──────────────────────────┐
  │  Precio paseo 30 min *                      │
  │  Bs [      ] / 30 min                      │
  │                                              │
  │  Precio paseo 1 hora *                       │
  │  Bs [      ] / 1 hora                       │
  │  Sugerido: Bs 20 - 100                       │
  └──────────────────────────────────────────────┘
```

### 1.5 Banner de Verificacion: Variantes por Estado

```
NUEVO (nunca guardado):
┌──────────────────────────────────────────────────────┐
│  📝  Completa tu perfil                              │
│                                                      │
│  Llena todos los campos para enviar tu solicitud.    │
│  El equipo GARDEN revisara tu perfil en 24-48h.      │
│                                                      │
│  bg-blue-50 dark:bg-blue-950/30                      │
│  border-blue-200 dark:border-blue-800                │
│  text-blue-800 dark:text-blue-200                    │
└──────────────────────────────────────────────────────┘

GUARDADO, PENDIENTE DE VERIFICACION:
┌──────────────────────────────────────────────────────┐
│  ⏳  Pendiente de verificacion                       │
│                                                      │
│  Tu perfil fue enviado. El equipo GARDEN te          │
│  contactara en 24-48 horas para coordinar la         │
│  entrevista y visita a tu espacio.                    │
│                                                      │
│  Te notificaremos por email y WhatsApp.              │
│                                                      │
│  bg-amber-50 dark:bg-amber-950/30                    │
│  border-amber-200 dark:border-amber-800              │
│  text-amber-800 dark:text-amber-200                  │
└──────────────────────────────────────────────────────┘

VERIFICADO:
┌──────────────────────────────────────────────────────┐
│  ✓  Perfil verificado                                │
│                                                      │
│  Tu perfil es visible para clientes en GARDEN.       │
│  Puedes editar tu descripcion y precios.             │
│  Los cambios en fotos requieren re-verificacion.     │
│                                                      │
│  bg-garden-50 dark:bg-garden-950/30                  │
│  border-garden-200 dark:border-garden-800            │
│  text-garden-800 dark:text-garden-200                │
└──────────────────────────────────────────────────────┘

SUSPENDIDO:
┌──────────────────────────────────────────────────────┐
│  ⚠  Perfil suspendido                                │
│                                                      │
│  Motivo: [razon de suspension]                       │
│  Contacta a soporte para mas informacion.            │
│                                                      │
│  bg-red-50 dark:bg-red-950/30                        │
│  border-red-200 dark:border-red-800                  │
│  text-red-800 dark:text-red-200                      │
└──────────────────────────────────────────────────────┘
```

---

## 2. Estructura de Componentes React

### 2.1 Arbol de Componentes

```
CaregiverProfilePage                   ← page-level, route: /perfil/editar
│
├── ProfileStatusBanner                 ← banner contextual (nuevo/pendiente/verificado/suspendido)
│   └── props: status, suspensionReason?
│
├── ProfileForm                         ← formulario principal, maneja estado global del form
│   │
│   ├── PhotoUploadSection              ← seccion de fotos
│   │   ├── PhotoDropZone               ← area de drop general (hidden input + drag)
│   │   ├── PhotoGrid                   ← grid responsive 2x3 (mobile) / 4+2 (desktop)
│   │   │   └── PhotoSlot (x6)         ← slot individual (vacio/subiendo/listo/error)
│   │   │       ├── PhotoPreview        ← img con overlay de estado
│   │   │       ├── UploadProgress      ← circulo SVG animado (0-100%)
│   │   │       ├── PhotoActions        ← eliminar, reintentar, reordenar (▲▼)
│   │   │       └── PhotoBadge          ← "Principal" en slot 0
│   │   ├── PhotoCounter                ← "3/4 minimo · 3/6 maximo"
│   │   └── PhotoSuggestions            ← lista de fotos sugeridas
│   │
│   ├── BioSection                      ← descripcion + tipo de espacio
│   │   ├── TextareaWithCounter         ← textarea con contador 0/500 en vivo
│   │   └── SpaceTypeInput              ← input texto libre con placeholder
│   │
│   ├── ZoneSection                     ← selector de zona
│   │   └── ZoneSelect                  ← select nativo (mobile) / custom dropdown (desktop)
│   │
│   ├── ServicesSection                 ← servicios + precios condicionales
│   │   ├── ServiceCheckbox (x2)        ← checkbox card (Hospedaje, Paseos)
│   │   ├── HospedajePricing            ← precio/dia (visible si Hospedaje checked)
│   │   │   └── PriceInput              ← input numerico con "Bs" prefix
│   │   └── PaseoPricing                ← precios 30min + 1h (visible si Paseos checked)
│   │       └── PriceInput (x2)
│   │
│   ├── RequirementsChecklist           ← checklist visual de requisitos pendientes
│   │   └── RequirementItem (x6)       ← ✓/✗ + label
│   │
│   └── SubmitSection                   ← boton guardar + texto de verificacion
│       ├── SubmitButton                ← disabled hasta cumplir, con loading spinner
│       └── VerificationNote            ← "Tu perfil sera revisado en 24-48h"
│
└── UnsavedChangesGuard                 ← beforeunload + prompt si hay cambios sin guardar
```

### 2.2 Tipado de Props y Estado

```typescript
// src/types/caregiver-form.ts

import type { Zone, ServiceType } from './caregiver';

// ── Estado del perfil (determina banner y permisos de edicion) ──

export type ProfileStatus =
  | 'new'              // nunca guardado
  | 'pending'          // guardado, esperando verificacion
  | 'verified'         // verificado por admin
  | 'suspended';       // suspendido

// ── Estado del formulario ──

export interface CaregiverFormData {
  bio: string;
  spaceType: string;
  zone: Zone | null;
  servicesOffered: ServiceType[];
  pricePerDay: number | null;
  pricePerWalk30: number | null;
  pricePerWalk60: number | null;
}

export interface CaregiverFormErrors {
  bio?: string;
  spaceType?: string;
  zone?: string;
  servicesOffered?: string;
  pricePerDay?: string;
  pricePerWalk30?: string;
  pricePerWalk60?: string;
  photos?: string;
}

// ── Estado de foto individual ──

export type PhotoUploadStatus = 'idle' | 'uploading' | 'success' | 'error';

export interface PhotoSlotState {
  id: string;                         // unique key para React
  file: File | null;                  // null si viene del server (edicion)
  preview: string;                    // ObjectURL local o Cloudinary URL
  status: PhotoUploadStatus;
  progress: number;                   // 0-100
  cloudinaryUrl: string | null;
  error: string | null;
  isFromServer: boolean;              // true si ya existia (edicion)
}

// ── Requirements checklist ──

export interface RequirementStatus {
  photos: boolean;       // >= 4 exitosas
  bio: boolean;          // >= 50 chars
  spaceType: boolean;    // no vacio
  zone: boolean;         // seleccionada
  services: boolean;     // >= 1 seleccionado
  pricing: boolean;      // precios de servicios seleccionados
}

// ── Zone labels (enum → display) ──

export const ZONE_LABELS: Record<Zone, string> = {
  EQUIPETROL: 'Equipetrol',
  URBARI: 'Urbari',
  NORTE: 'Norte',
  LAS_PALMAS: 'Las Palmas',
  CENTRO_SAN_MARTIN: 'Centro / Av. San Martin',
  OTROS: 'Otros',
};
```

### 2.3 Hook Principal: `useCaregiverForm`

```typescript
// src/hooks/useCaregiverForm.ts

import { useState, useCallback, useMemo, useEffect } from 'react';
import type {
  CaregiverFormData,
  CaregiverFormErrors,
  RequirementStatus,
  ProfileStatus,
  PhotoSlotState,
} from '../types/caregiver-form';

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:3001/api';

interface UseCaregiverFormOptions {
  authToken: string;
  initialData?: CaregiverFormData;
  initialPhotos?: string[];           // Cloudinary URLs (edicion)
  profileStatus: ProfileStatus;
}

export function useCaregiverForm(options: UseCaregiverFormOptions) {
  const { authToken, initialData, initialPhotos, profileStatus } = options;

  // ── Form data ──
  const [formData, setFormData] = useState<CaregiverFormData>(
    initialData ?? {
      bio: '',
      spaceType: '',
      zone: null,
      servicesOffered: [],
      pricePerDay: null,
      pricePerWalk30: null,
      pricePerWalk60: null,
    }
  );

  const [errors, setErrors] = useState<CaregiverFormErrors>({});
  const [photos, setPhotos] = useState<PhotoSlotState[]>(() =>
    (initialPhotos ?? []).map((url, i) => ({
      id: `server-${i}`,
      file: null,
      preview: url,
      status: 'success' as const,
      progress: 100,
      cloudinaryUrl: url,
      error: null,
      isFromServer: true,
    }))
  );

  const [submitStatus, setSubmitStatus] = useState<
    'idle' | 'submitting' | 'success' | 'error'
  >('idle');
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [isDirty, setIsDirty] = useState(false);

  // ── Update field ──
  const updateField = useCallback(<K extends keyof CaregiverFormData>(
    field: K,
    value: CaregiverFormData[K]
  ) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    setErrors(prev => {
      const next = { ...prev };
      delete next[field];
      return next;
    });
    setIsDirty(true);
  }, []);

  // ── Toggle servicio ──
  const toggleService = useCallback((service: 'HOSPEDAJE' | 'PASEO') => {
    setFormData(prev => {
      const has = prev.servicesOffered.includes(service);
      const next = has
        ? prev.servicesOffered.filter(s => s !== service)
        : [...prev.servicesOffered, service];

      // Limpiar precios al deseleccionar
      const updates: Partial<CaregiverFormData> = { servicesOffered: next };
      if (service === 'HOSPEDAJE' && has) updates.pricePerDay = null;
      if (service === 'PASEO' && has) {
        updates.pricePerWalk30 = null;
        updates.pricePerWalk60 = null;
      }

      return { ...prev, ...updates };
    });
    setIsDirty(true);
  }, []);

  // ── Requirements checklist (derivado) ──
  const successPhotos = photos.filter(p => p.status === 'success');

  const requirements: RequirementStatus = useMemo(() => ({
    photos: successPhotos.length >= 4,
    bio: formData.bio.trim().length >= 50,
    spaceType: formData.spaceType.trim().length > 0,
    zone: formData.zone !== null,
    services: formData.servicesOffered.length > 0,
    pricing: (
      (!formData.servicesOffered.includes('HOSPEDAJE') ||
        (formData.pricePerDay !== null && formData.pricePerDay >= 30)) &&
      (!formData.servicesOffered.includes('PASEO') ||
        (formData.pricePerWalk30 !== null && formData.pricePerWalk30 >= 15 &&
         formData.pricePerWalk60 !== null && formData.pricePerWalk60 >= 25))
    ),
  }), [formData, successPhotos.length]);

  const canSubmit = useMemo(() =>
    Object.values(requirements).every(Boolean) &&
    !photos.some(p => p.status === 'uploading'),
  [requirements, photos]);

  // ── Validar todo ──
  const validate = useCallback((): boolean => {
    const errs: CaregiverFormErrors = {};

    if (formData.bio.trim().length < 50)
      errs.bio = 'Minimo 50 caracteres';
    if (formData.bio.length > 500)
      errs.bio = 'Maximo 500 caracteres';
    if (!formData.spaceType.trim())
      errs.spaceType = 'Describe tu espacio';
    if (!formData.zone)
      errs.zone = 'Selecciona tu zona';
    if (formData.servicesOffered.length === 0)
      errs.servicesOffered = 'Selecciona al menos un servicio';
    if (formData.servicesOffered.includes('HOSPEDAJE') &&
        (!formData.pricePerDay || formData.pricePerDay < 30))
      errs.pricePerDay = 'Precio minimo: Bs 30';
    if (formData.servicesOffered.includes('PASEO')) {
      if (!formData.pricePerWalk30 || formData.pricePerWalk30 < 15)
        errs.pricePerWalk30 = 'Precio minimo: Bs 15';
      if (!formData.pricePerWalk60 || formData.pricePerWalk60 < 25)
        errs.pricePerWalk60 = 'Precio minimo: Bs 25';
    }
    if (successPhotos.length < 4)
      errs.photos = `Necesitas ${4 - successPhotos.length} fotos mas`;

    setErrors(errs);
    return Object.keys(errs).length === 0;
  }, [formData, successPhotos.length]);

  // ── Submit ──
  const submit = useCallback(async () => {
    if (!validate()) return false;

    setSubmitStatus('submitting');
    setSubmitError(null);

    try {
      const payload = {
        ...formData,
        photos: successPhotos.map(p => p.cloudinaryUrl),
      };

      const res = await fetch(`${API_BASE}/caregivers/profile`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`,
        },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error?.message || 'Error guardando perfil');
      }

      setSubmitStatus('success');
      setIsDirty(false);
      return true;
    } catch (err) {
      setSubmitError(
        err instanceof Error ? err.message : 'Error inesperado'
      );
      setSubmitStatus('error');
      return false;
    }
  }, [formData, successPhotos, authToken, validate]);

  return {
    formData,
    errors,
    photos,
    setPhotos,
    submitStatus,
    submitError,
    isDirty,
    requirements,
    canSubmit,
    updateField,
    toggleService,
    submit,
  };
}
```

### 2.4 Responsabilidades por Componente

```
┌───────────────────────────┬─────────────────────────────────────────────────┐
│ Componente                │ Responsabilidad                                 │
├───────────────────────────┼─────────────────────────────────────────────────┤
│ CaregiverProfilePage      │ Fetch perfil existente (si edicion), provee     │
│                           │ authToken, renderiza ProfileForm + Banner       │
├───────────────────────────┼─────────────────────────────────────────────────┤
│ ProfileStatusBanner       │ Render condicional: nuevo/pendiente/verificado/ │
│                           │ suspendido. Puro presentacional, sin estado.    │
├───────────────────────────┼─────────────────────────────────────────────────┤
│ ProfileForm               │ Orquesta useCaregiverForm + usePhotoUpload.     │
│                           │ Distribuye datos a secciones hijas.             │
├───────────────────────────┼─────────────────────────────────────────────────┤
│ PhotoUploadSection        │ Maneja drag&drop global, delega upload a hook.  │
│                           │ Renderiza PhotoGrid + counter + sugerencias.    │
├───────────────────────────┼─────────────────────────────────────────────────┤
│ PhotoSlot                 │ Render condicional por status. Maneja acciones  │
│                           │ individuales: eliminar, retry, reorder. Memo.   │
├───────────────────────────┼─────────────────────────────────────────────────┤
│ TextareaWithCounter       │ Textarea controlado con contador live chars.    │
│                           │ Cambia color cerca del limite (>450: amber,     │
│                           │ 500: red). Muestra error si < 50.              │
├───────────────────────────┼─────────────────────────────────────────────────┤
│ SpaceTypeInput            │ Input texto libre. Placeholder contextual.      │
│                           │ Suggestions inline (no autocomplete).           │
├───────────────────────────┼─────────────────────────────────────────────────┤
│ ZoneSelect                │ <select> nativo en mobile (mejor UX tactil),    │
│                           │ custom dropdown con search en desktop.          │
├───────────────────────────┼─────────────────────────────────────────────────┤
│ ServiceCheckbox           │ Card clickeable con icono + titulo + subtitulo. │
│                           │ Checked: borde verde + bg-garden-50.            │
│                           │ Unchecked: borde gris + bg-white.               │
├───────────────────────────┼─────────────────────────────────────────────────┤
│ PriceInput                │ Input numerico con prefix "Bs". Valida rango    │
│                           │ on blur. Formato: solo enteros positivos.       │
├───────────────────────────┼─────────────────────────────────────────────────┤
│ RequirementsChecklist     │ Lista de 6 requisitos con iconos ✓/✗.          │
│                           │ Derivado de requirements en el hook.            │
│                           │ Sticky en sidebar desktop, inline en mobile.   │
├───────────────────────────┼─────────────────────────────────────────────────┤
│ SubmitButton              │ Boton primario. disabled + tooltip si faltan    │
│                           │ requisitos. Spinner durante submit.             │
├───────────────────────────┼─────────────────────────────────────────────────┤
│ UnsavedChangesGuard       │ Escucha beforeunload + react-router blocker.   │
│                           │ Muestra dialog si isDirty=true al navegar.      │
└───────────────────────────┴─────────────────────────────────────────────────┘
```

---

## 3. Clases Tailwind por Seccion

### 3.1 Page Container y Layout

```tsx
// ── Page wrapper ──
<div className="
  min-h-screen
  bg-gray-50 dark:bg-gray-950
  transition-colors duration-200
">

// ── Content area (desktop: 2 columnas) ──
<div className="
  max-w-4xl lg:max-w-6xl mx-auto
  px-4 sm:px-6 lg:px-8
  py-6 sm:py-8 lg:py-10
">

// ── Layout 2-col (desktop) ──
<div className="
  flex flex-col
  lg:flex-row lg:gap-8
">
  {/* Formulario principal */}
  <div className="flex-1 min-w-0">
    {/* ...sections... */}
  </div>

  {/* Sidebar con requirements (solo desktop) */}
  <aside className="
    hidden lg:block
    lg:w-72 xl:w-80
    shrink-0
  ">
    <div className="sticky top-24">
      {/* RequirementsChecklist + SubmitButton */}
    </div>
  </aside>
</div>
```

### 3.2 ProfileStatusBanner

```tsx
// ── Banner base ──
<div className={`
  rounded-xl border p-4 sm:p-5
  flex items-start gap-3
  ${variants[status]}  // colores segun estado
`}>
  <span className="text-xl shrink-0" aria-hidden="true">
    {icon}
  </span>
  <div className="min-w-0">
    <p className="font-semibold text-sm">{title}</p>
    <p className="text-sm mt-0.5 opacity-80">{description}</p>
  </div>
</div>

// ── Variantes de color ──
const variants = {
  new: `
    bg-blue-50 dark:bg-blue-950/30
    border-blue-200 dark:border-blue-800
    text-blue-800 dark:text-blue-200
  `,
  pending: `
    bg-amber-50 dark:bg-amber-950/30
    border-amber-200 dark:border-amber-800
    text-amber-800 dark:text-amber-200
  `,
  verified: `
    bg-garden-50 dark:bg-garden-950/30
    border-garden-200 dark:border-garden-800
    text-garden-800 dark:text-garden-200
  `,
  suspended: `
    bg-red-50 dark:bg-red-950/30
    border-red-200 dark:border-red-800
    text-red-800 dark:text-red-200
  `,
};
```

### 3.3 Section Header

```tsx
// ── Separador de seccion reutilizable ──
<div className="mt-8 first:mt-0">
  <div className="
    flex items-center gap-3
    mb-4
  ">
    <h2 className="
      text-base font-semibold
      text-gray-900 dark:text-gray-100
      whitespace-nowrap
    ">
      {title}
    </h2>
    <div className="
      h-px flex-1
      bg-gray-200 dark:bg-gray-800
    " />
  </div>
  {subtitle && (
    <p className="
      text-sm text-gray-500 dark:text-gray-400
      mb-4 -mt-2
    ">
      {subtitle}
    </p>
  )}
</div>
```

### 3.4 PhotoGrid y PhotoSlot

```tsx
// ── Grid de fotos ──
<div className="
  grid
  grid-cols-3 sm:grid-cols-3 lg:grid-cols-4
  gap-2 sm:gap-3
">
  {slots.map(slot => <PhotoSlot key={slot.id} ... />)}
</div>

// ── Slot vacio ──
<button className="
  aspect-square rounded-xl
  border-2 border-dashed
  border-gray-300 dark:border-gray-600
  hover:border-garden-400 dark:hover:border-garden-500
  hover:bg-garden-50/50 dark:hover:bg-garden-950/50
  flex flex-col items-center justify-center gap-1.5
  cursor-pointer
  transition-all duration-200
  text-gray-400 dark:text-gray-500
  hover:text-garden-600 dark:hover:text-garden-400
  focus-visible:outline-2 focus-visible:outline-garden-500 focus-visible:outline-offset-2
">
  <PlusIcon className="w-6 h-6 sm:w-8 sm:h-8" />
  <span className="text-[11px] sm:text-xs">Agregar</span>
</button>

// ── Slot con foto (success) ──
<div className="
  aspect-square rounded-xl overflow-hidden
  relative group
  ring-2 ring-transparent
  hover:ring-garden-300 dark:hover:ring-garden-700
  transition-all duration-200
">
  <img
    src={photo.preview}
    alt={`Foto ${index + 1} de tu espacio`}
    className="w-full h-full object-cover"
  />
  {/* Boton eliminar (visible en hover/focus) */}
  <button className="
    absolute top-1.5 right-1.5
    w-7 h-7
    bg-black/50 dark:bg-black/70
    hover:bg-red-500
    text-white rounded-full
    flex items-center justify-center
    opacity-0 group-hover:opacity-100
    focus-visible:opacity-100
    transition-opacity duration-150
  ">
    <XIcon className="w-3.5 h-3.5" />
  </button>
  {/* Badge "Principal" */}
  {index === 0 && (
    <span className="
      absolute bottom-1.5 left-1.5
      bg-garden-500 text-white
      text-[10px] font-bold uppercase tracking-wide
      px-2 py-0.5 rounded-md
    ">
      Principal
    </span>
  )}
</div>

// ── Slot subiendo ──
<div className="
  aspect-square rounded-xl overflow-hidden relative
">
  <img src={photo.preview} className="w-full h-full object-cover opacity-50" />
  <div className="
    absolute inset-0
    flex flex-col items-center justify-center
    bg-black/20 dark:bg-black/40
  ">
    <svg className="w-12 h-12" viewBox="0 0 36 36">
      {/* Circulo de fondo */}
      <circle cx="18" cy="18" r="16"
        fill="none"
        stroke="rgba(255,255,255,0.25)"
        strokeWidth="2.5"
      />
      {/* Circulo de progreso */}
      <circle cx="18" cy="18" r="16"
        fill="none"
        stroke="white"
        strokeWidth="2.5"
        strokeDasharray={`${progress} 100`}
        strokeLinecap="round"
        transform="rotate(-90 18 18)"
        className="transition-all duration-300"
      />
    </svg>
    <span className="text-white text-xs font-semibold mt-1">
      {progress}%
    </span>
  </div>
</div>

// ── Slot error ──
<div className="
  aspect-square rounded-xl overflow-hidden relative
  ring-2 ring-red-400 dark:ring-red-600
">
  <img src={photo.preview} className="w-full h-full object-cover grayscale opacity-40" />
  <div className="
    absolute inset-0
    flex flex-col items-center justify-center gap-1
    bg-red-950/30
  ">
    <ExclamationIcon className="w-5 h-5 text-red-400" />
    <span className="text-white text-[10px] text-center px-2 leading-tight">
      {photo.error}
    </span>
    <button className="
      mt-1 text-[11px] text-white font-medium
      bg-white/20 hover:bg-white/30
      px-2.5 py-1 rounded-md
      transition-colors
    ">
      Reintentar
    </button>
  </div>
</div>
```

### 3.5 TextareaWithCounter

```tsx
<div>
  <label className="
    block text-sm font-medium mb-1.5
    text-gray-700 dark:text-gray-300
  ">
    Descripcion <span className="text-red-500">*</span>
  </label>

  <div className="relative">
    <textarea
      value={bio}
      onChange={e => updateField('bio', e.target.value)}
      maxLength={500}
      rows={5}
      placeholder="Describe tu espacio, tu experiencia con mascotas y por que deberian confiar en ti..."
      className={`
        w-full rounded-xl
        border px-4 py-3
        text-sm leading-relaxed
        resize-none
        transition-colors duration-200
        placeholder:text-gray-400 dark:placeholder:text-gray-600

        ${error
          ? 'border-red-300 dark:border-red-700 focus:ring-red-500'
          : 'border-gray-300 dark:border-gray-700 focus:ring-garden-500'
        }

        bg-white dark:bg-gray-900
        text-gray-900 dark:text-gray-100

        focus:outline-none focus:ring-2 focus:ring-offset-0
      `}
    />

    {/* Contador de caracteres */}
    <span className={`
      absolute bottom-3 right-3
      text-xs font-medium tabular-nums
      ${bio.length >= 500 ? 'text-red-500 dark:text-red-400'
        : bio.length >= 450 ? 'text-amber-500 dark:text-amber-400'
        : 'text-gray-400 dark:text-gray-600'}
    `}>
      {bio.length}/500
    </span>
  </div>

  {/* Error o helper text */}
  {error ? (
    <p className="mt-1.5 text-xs text-red-500 dark:text-red-400">{error}</p>
  ) : bio.length > 0 && bio.length < 50 ? (
    <p className="mt-1.5 text-xs text-amber-500 dark:text-amber-400">
      {50 - bio.length} caracteres mas para el minimo
    </p>
  ) : null}
</div>
```

### 3.6 ServiceCheckbox

```tsx
<button
  type="button"
  onClick={() => toggleService(service)}
  className={`
    w-full sm:flex-1
    rounded-xl border-2 p-4
    text-left
    transition-all duration-200
    focus-visible:outline-2 focus-visible:outline-garden-500 focus-visible:outline-offset-2

    ${checked
      ? `border-garden-500 dark:border-garden-600
         bg-garden-50 dark:bg-garden-950/40`
      : `border-gray-200 dark:border-gray-700
         bg-white dark:bg-gray-900
         hover:border-gray-300 dark:hover:border-gray-600`
    }
  `}
  role="checkbox"
  aria-checked={checked}
>
  <div className="flex items-start gap-3">
    {/* Checkbox visual */}
    <div className={`
      mt-0.5 w-5 h-5 rounded-md border-2 shrink-0
      flex items-center justify-center
      transition-colors duration-200
      ${checked
        ? 'bg-garden-500 border-garden-500 dark:bg-garden-600 dark:border-garden-600'
        : 'border-gray-300 dark:border-gray-600'
      }
    `}>
      {checked && <CheckIcon className="w-3 h-3 text-white" />}
    </div>

    <div className="min-w-0">
      <div className="flex items-center gap-2">
        <span aria-hidden="true">{icon}</span>
        <span className="
          font-semibold text-sm
          text-gray-900 dark:text-gray-100
        ">
          {label}
        </span>
      </div>
      <p className="
        text-xs mt-0.5
        text-gray-500 dark:text-gray-400
      ">
        {description}
      </p>
    </div>
  </div>
</button>
```

### 3.7 PriceInput

```tsx
<div>
  <label className="
    block text-sm font-medium mb-1.5
    text-gray-700 dark:text-gray-300
  ">
    {label} <span className="text-red-500">*</span>
  </label>

  <div className="relative">
    {/* Prefix "Bs" */}
    <span className="
      absolute left-3 top-1/2 -translate-y-1/2
      text-sm font-semibold
      text-gray-500 dark:text-gray-400
      pointer-events-none
    ">
      Bs
    </span>

    <input
      type="number"
      inputMode="numeric"
      min={min}
      max={max}
      value={value ?? ''}
      onChange={e => onChange(e.target.value ? parseInt(e.target.value) : null)}
      placeholder={placeholder}
      className={`
        w-full rounded-xl
        border pl-10 pr-16 py-2.5
        text-sm font-medium tabular-nums
        transition-colors duration-200

        ${error
          ? 'border-red-300 dark:border-red-700 focus:ring-red-500'
          : 'border-gray-300 dark:border-gray-700 focus:ring-garden-500'
        }

        bg-white dark:bg-gray-900
        text-gray-900 dark:text-gray-100

        focus:outline-none focus:ring-2 focus:ring-offset-0

        [appearance:textfield]
        [&::-webkit-outer-spin-button]:appearance-none
        [&::-webkit-inner-spin-button]:appearance-none
      `}
    />

    {/* Suffix */}
    <span className="
      absolute right-3 top-1/2 -translate-y-1/2
      text-xs
      text-gray-400 dark:text-gray-500
      pointer-events-none
    ">
      {suffix}
    </span>
  </div>

  {/* Helper text */}
  {error ? (
    <p className="mt-1 text-xs text-red-500 dark:text-red-400">{error}</p>
  ) : (
    <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">
      Sugerido: Bs {suggestedMin} - {suggestedMax}
    </p>
  )}
</div>
```

### 3.8 RequirementsChecklist

```tsx
<div className="
  rounded-xl border
  border-gray-200 dark:border-gray-800
  bg-white dark:bg-gray-900
  p-5
  divide-y divide-gray-100 dark:divide-gray-800
">
  <h3 className="
    text-sm font-semibold mb-3
    text-gray-900 dark:text-gray-100
  ">
    Requisitos
  </h3>

  {items.map(({ label, met }) => (
    <div key={label} className="
      flex items-center gap-2.5
      py-2 first:pt-0 last:pb-0
    ">
      {met ? (
        <CheckCircleIcon className="
          w-4.5 h-4.5 shrink-0
          text-garden-500 dark:text-garden-400
        " />
      ) : (
        <CircleIcon className="
          w-4.5 h-4.5 shrink-0
          text-gray-300 dark:text-gray-600
        " />
      )}
      <span className={`
        text-sm
        ${met
          ? 'text-gray-600 dark:text-gray-400 line-through'
          : 'text-gray-900 dark:text-gray-100'
        }
      `}>
        {label}
      </span>
    </div>
  ))}
</div>
```

### 3.9 SubmitButton

```tsx
<button
  type="submit"
  disabled={!canSubmit || submitStatus === 'submitting'}
  className={`
    w-full rounded-xl
    px-6 py-3.5
    text-sm font-semibold
    transition-all duration-200
    focus-visible:outline-2 focus-visible:outline-garden-500 focus-visible:outline-offset-2

    ${canSubmit
      ? `bg-garden-500 hover:bg-garden-600 active:bg-garden-700
         dark:bg-garden-600 dark:hover:bg-garden-500
         text-white
         shadow-sm hover:shadow-md`
      : `bg-gray-200 dark:bg-gray-800
         text-gray-400 dark:text-gray-600
         cursor-not-allowed`
    }
  `}
>
  {submitStatus === 'submitting' ? (
    <span className="flex items-center justify-center gap-2">
      <svg className="animate-spin w-4 h-4" viewBox="0 0 24 24">
        <circle cx="12" cy="12" r="10" stroke="currentColor"
          strokeWidth="3" fill="none" opacity="0.25" />
        <path fill="currentColor" opacity="0.75"
          d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
      </svg>
      Guardando...
    </span>
  ) : (
    'Guardar perfil'
  )}
</button>

{/* Mensaje post-boton */}
{canSubmit && submitStatus !== 'success' && (
  <p className="
    text-center text-xs mt-2
    text-gray-400 dark:text-gray-500
  ">
    Tu perfil sera revisado manualmente en 24-48 horas
  </p>
)}
```

---

## 4. Estados y Flujos

### 4.1 Diagrama de Estados del Formulario

```
┌──────────────────────────────────────────────────────────────────────┐
│                  ESTADOS DEL FORMULARIO                               │
└──────────────────────────────────────────────────────────────────────┘

  ┌─────────┐
  │  EMPTY  │  Formulario recien abierto (registro)
  │         │  o cargado con datos (edicion)
  └────┬────┘
       │
       │ Usuario empieza a llenar
       ▼
  ┌─────────┐
  │  DIRTY  │  isDirty = true
  │         │  canSubmit = false (aun faltan requisitos)
  └────┬────┘
       │
       │ ┌──────────────────────────────────────────┐
       │ │ VALIDACION EN TIEMPO REAL:                │
       │ │                                           │
       │ │ · Bio: contador chars, min 50 warning     │
       │ │ · Photos: counter X/4 min · X/6 max      │
       │ │ · Zone: required indicator                │
       │ │ · Services: at least 1 checked            │
       │ │ · Prices: min values on blur              │
       │ │                                           │
       │ │ RequirementsChecklist se actualiza live    │
       │ │ SubmitButton se habilita cuando todo ✓    │
       │ └──────────────────────────────────────────┘
       │
       │ Todos los requisitos cumplidos
       ▼
  ┌──────────┐
  │  READY   │  canSubmit = true
  │          │  Boton verde activo
  └────┬─────┘
       │
       │ Click "Guardar perfil"
       ▼
  ┌──────────────┐
  │  SUBMITTING  │  Boton muestra spinner
  │              │  Formulario disabled
  │              │  PUT /api/caregivers/profile
  └──────┬───────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌────────┐ ┌────────┐
│SUCCESS │ │ ERROR  │
│        │ │        │
│ Toast: │ │ Toast: │
│ "Perfil│ │ "Error │
│ guardad│ │ guardan│
│ o"     │ │ do"    │
│        │ │        │
│ Banner │ │ Boton  │
│ cambia │ │ activo │
│ a      │ │ para   │
│ "pendi │ │ re-    │
│ ente"  │ │ intentar
└────────┘ └────────┘
```

### 4.2 Diagrama de Upload de Fotos

```
┌──────────────────────────────────────────────────────────────────────┐
│                  FLUJO DE UPLOAD POR FOTO                             │
└──────────────────────────────────────────────────────────────────────┘

  USUARIO
    │
    ├── Click en slot vacio → abre file picker
    │   o
    ├── Drag & drop sobre slot/zona general
    │
    ▼
  ┌────────────────────┐
  │  VALIDAR CLIENT    │
  │  ─────────────     │
  │  Tipo: jpg/png/webp│
  │  Size: <= 5MB      │
  │  Count: <= 6 total │
  └──────┬─────────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
  [PASA]    [FALLA]
    │         │
    │         └──→ Mostrar error inline
    │              "Formato no soportado" o
    │              "Archivo muy grande (X MB)"
    │              NO crea slot
    │
    ▼
  ┌────────────────────┐
  │  CREAR SLOT        │
  │  ─────────────     │
  │  Preview local     │  URL.createObjectURL(file)
  │  Status: uploading │
  │  Progress: 0%      │
  └──────┬─────────────┘
         │
         │  XHR POST /api/uploads/photo
         │  (con progress events)
         │
         ▼
  ┌────────────────────┐
  │  SUBIENDO          │
  │  ─────────────     │     ┌─────────────────────┐
  │  Progress: 0→100%  │     │ UI durante upload:  │
  │  Preview visible   │     │                     │
  │  Overlay oscuro    │     │ ░░░░ Preview ░░░░░░ │
  │  Circulo SVG       │     │ ░░░   [67%]   ░░░░ │
  │                    │     │ ░░░░░░░░░░░░░░░░░░░ │
  └──────┬─────────────┘     └─────────────────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
  [200 OK]  [ERROR]
    │         │
    │         ├── Network: "Error de red" → [Reintentar]
    │         ├── 401: Token expirado → redirect login
    │         ├── 413: "Archivo muy grande" → [Eliminar]
    │         └── 500: "Error del servidor" → [Reintentar]
    │
    ▼
  ┌────────────────────┐
  │  EXITOSO           │     ┌─────────────────────┐
  │  ─────────────     │     │ UI exitosa:         │
  │  Status: success   │     │                     │
  │  cloudinaryUrl set │     │ ░░ Foto nitida ░░░ │
  │  Boton eliminar    │     │ ░░           [✕] ░ │
  │  (hover)           │     │ ░░░░░░░░░░░░░░░░░░ │
  │  Controles ▲▼      │     │ Principal   ▲▼     │
  │  (reordenar)       │     └─────────────────────┘
  └────────────────────┘
```

### 4.3 Flujo de Reordenamiento (Drag & Drop)

```
DESKTOP:
  1. Hover sobre foto → cursor: grab
  2. MouseDown → cursor: grabbing, foto levanta (scale 1.05, shadow-xl)
  3. Drag sobre otro slot → slot destino se outline-dashed
  4. Drop → swap posiciones, animacion slide-in
  5. Si la nueva posicion 0 → badge "Principal" se mueve

MOBILE:
  1. Botones ▲ ▼ visibles debajo de cada foto exitosa
  2. Click ▲ → mueve foto una posicion arriba
  3. Click ▼ → mueve foto una posicion abajo
  4. Posicion 0 (primera) → ▲ deshabilitado
  5. Posicion ultima → ▼ deshabilitado
  6. Badge "Principal" siempre en posicion 0

ACCESIBILIDAD:
  · aria-grabbed="true/false" en fotos arrastrables
  · aria-dropeffect="move" en slots destino
  · Botones ▲▼: aria-label="Mover foto 3 arriba" / "Mover foto 3 abajo"
  · Anuncio screen reader: "Foto movida a posicion 2 de 5"
```

### 4.4 Flujo Completo: Registro → Verificacion

```
┌──────────────────────────────────────────────────────────────────────┐
│                    REGISTRO → VERIFICACION                            │
└──────────────────────────────────────────────────────────────────────┘

  CUIDADOR                     GARDEN APP                  ADMIN
     │                             │                         │
     │  Se registra como           │                         │
     │  CAREGIVER (auth module)    │                         │
     │────────────────────────────>│                         │
     │                             │                         │
     │  Redirigido a               │                         │
     │  /perfil/editar             │                         │
     │<────────────────────────────│                         │
     │                             │                         │
     │  Banner: "Completa          │                         │
     │  tu perfil" (azul)          │                         │
     │                             │                         │
     │  Sube fotos (4-6)           │                         │
     │  Llena bio, zona,           │                         │
     │  servicios, precios         │                         │
     │────────────────────────────>│                         │
     │                             │                         │
     │  RequirementsChecklist      │                         │
     │  se va llenando ✓✓✓✓✓✓     │                         │
     │                             │                         │
     │  Click "Guardar perfil"     │                         │
     │────────────────────────────>│                         │
     │                             │ PUT /caregivers/profile │
     │                             │ verified: false          │
     │                             │                         │
     │  Banner cambia a            │                         │
     │  "Pendiente" (amber)        │                         │
     │<────────────────────────────│                         │
     │                             │                         │
     │  Toast: "Perfil guardado.   │  Notificacion admin:    │
     │  Te contactaremos en        │  nuevo cuidador         │
     │  24-48h"                    │  pendiente              │
     │                             │────────────────────────>│
     │                             │                         │
     │     ── 24-48h offline ──    │                         │
     │                             │                         │
     │                             │  Admin revisa perfil    │
     │                             │  Entrevista + visita    │
     │                             │<────────────────────────│
     │                             │                         │
     │                             │  Admin aprueba:         │
     │                             │  verified = true        │
     │                             │  verifiedAt = now()     │
     │                             │  verifiedBy = adminId   │
     │                             │<────────────────────────│
     │                             │                         │
     │  Email + WhatsApp:          │                         │
     │  "Tu perfil fue verificado" │                         │
     │<────────────────────────────│                         │
     │                             │                         │
     │  Banner cambia a            │  Perfil visible en      │
     │  "Verificado" (verde)       │  /cuidadores (listing)  │
     │                             │                         │
```

### 4.5 Modo Edicion vs Registro

```
┌────────────────────────┬──────────────────────────┬───────────────────────┐
│ Aspecto                │ Registro (nuevo)         │ Edicion (existente)   │
├────────────────────────┼──────────────────────────┼───────────────────────┤
│ URL                    │ /perfil/editar            │ /perfil/editar        │
│ Datos iniciales        │ Todo vacio               │ Fetch GET /profile    │
│ Fotos                  │ 0 slots llenos           │ Slots pre-llenados    │
│ Banner                 │ "Completa tu perfil"     │ Segun estado actual   │
│ Titulo                 │ "Mi perfil de cuidador"  │ "Mi perfil de..."     │
│ Boton texto            │ "Guardar perfil"         │ "Guardar cambios"     │
│ Nota verificacion      │ "24-48h"                 │ "Cambios en fotos     │
│                        │                          │  requieren re-verif." │
│ UnsavedChangesGuard    │ Activo si isDirty        │ Activo si isDirty     │
│ Method HTTP            │ PUT (upsert)             │ PUT (upsert)          │
│ Fotos: isFromServer    │ false (todas nuevas)     │ true (las existentes) │
│ Campos disabled        │ Ninguno                  │ Ninguno*              │
├────────────────────────┴──────────────────────────┴───────────────────────┤
│ * Si el perfil esta suspendido, todos los campos estan disabled          │
│   y el banner rojo explica el motivo.                                    │
└──────────────────────────────────────────────────────────────────────────┘
```

### 4.6 Errores y Recovery

```
┌─────────────────────────┬──────────────────────────────────────────────┐
│ Error                    │ UX                                           │
├─────────────────────────┼──────────────────────────────────────────────┤
│ Foto: formato invalido  │ NO crea slot. Toast error con nombre         │
│                         │ del archivo y formatos aceptados.            │
├─────────────────────────┼──────────────────────────────────────────────┤
│ Foto: > 5MB             │ NO crea slot. Toast: "foto_grande.jpg        │
│                         │ pesa 8.2MB (max 5MB)"                       │
├─────────────────────────┼──────────────────────────────────────────────┤
│ Foto: upload network err│ Slot se muestra con estado error.            │
│                         │ Boton "Reintentar" dentro del slot.          │
│                         │ La foto se puede eliminar tambien.           │
├─────────────────────────┼──────────────────────────────────────────────┤
│ Foto: Cloudinary error  │ Igual que network. Mismo retry flow.         │
├─────────────────────────┼──────────────────────────────────────────────┤
│ Submit: 401 Unauthorized│ Redirect a /login con return URL.            │
│                         │ Al volver, datos persisten (localStorage).   │
├─────────────────────────┼──────────────────────────────────────────────┤
│ Submit: 400 Validation  │ Errores del server se mapean a campos.       │
│                         │ Scroll al primer campo con error.            │
│                         │ focus() en el input con error.               │
├─────────────────────────┼──────────────────────────────────────────────┤
│ Submit: 500 Server Error│ Toast rojo: "Error guardando. Intenta de    │
│                         │ nuevo." Boton submit re-habilitado.          │
│                         │ Datos NO se pierden.                         │
├─────────────────────────┼──────────────────────────────────────────────┤
│ Submit: Network Error   │ Toast rojo: "Sin conexion. Verifica tu      │
│                         │ internet." Boton submit re-habilitado.       │
├─────────────────────────┼──────────────────────────────────────────────┤
│ Navegar sin guardar     │ Dialog: "Tienes cambios sin guardar.         │
│                         │ Seguro que quieres salir?" [Salir] [Quedar] │
└─────────────────────────┴──────────────────────────────────────────────┘
```

### 4.7 Toast Notifications

```tsx
// Toasts para feedback del formulario

// ── Success ──
<div className="
  flex items-center gap-3
  bg-garden-50 dark:bg-garden-950
  border border-garden-200 dark:border-garden-800
  text-garden-800 dark:text-garden-200
  rounded-xl px-4 py-3 shadow-lg
">
  <CheckCircleIcon className="w-5 h-5 shrink-0" />
  <div>
    <p className="text-sm font-semibold">Perfil guardado</p>
    <p className="text-xs opacity-80">Te contactaremos en 24-48 horas</p>
  </div>
</div>

// ── Error ──
<div className="
  flex items-center gap-3
  bg-red-50 dark:bg-red-950
  border border-red-200 dark:border-red-800
  text-red-800 dark:text-red-200
  rounded-xl px-4 py-3 shadow-lg
">
  <ExclamationCircleIcon className="w-5 h-5 shrink-0" />
  <div>
    <p className="text-sm font-semibold">Error al guardar</p>
    <p className="text-xs opacity-80">{errorMessage}</p>
  </div>
</div>

// ── Photo rejected ──
<div className="
  flex items-center gap-3
  bg-amber-50 dark:bg-amber-950
  border border-amber-200 dark:border-amber-800
  text-amber-800 dark:text-amber-200
  rounded-xl px-4 py-3 shadow-lg
">
  <ExclamationTriangleIcon className="w-5 h-5 shrink-0" />
  <div>
    <p className="text-sm font-semibold">foto_grande.jpg rechazada</p>
    <p className="text-xs opacity-80">Archivo muy grande (8.2MB). Max: 5MB</p>
  </div>
</div>
```

---

**FIN DEL DOCUMENTO**

# GARDEN - Listing de Cuidadores: Diseno Refinado

## Filtros + Grid + Tranquilidad Visual | React 18 + Tailwind CSS

**Version:** 2.0
**Fecha:** 07 de Febrero, 2026
**Schema:** Prisma enums `Zone`, `ServiceType` — `spaceType` free text — indices `[zone, verified, suspended]`
**Evoluciona:** `GARDEN_UI_UX_Perfiles_Cuidadores.md` (wireframes base) + `GARDEN_UI_UX_Refinamiento_Backend.md` (hooks)

---

## Tabla de Contenidos

1. [Wireframe Refinado](#1-wireframe-refinado)
2. [CaregiverCard — Tailwind Completo](#2-caregivercard--tailwind-completo)
3. [Filtros → Debounce → Refetch](#3-filtros--debounce--refetch)
4. [Sistema Visual de Tranquilidad](#4-sistema-visual-de-tranquilidad)

---

## 1. Wireframe Refinado

### 1.1 Desktop Completo (>= 1024px) — Con Datos Reales

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                                                                 │
│  ┌─ NAV ──────────────────────────────────────────────────────────────────────┐ │
│  │  🌿 GARDEN              Cuidadores    Como funciona    [Iniciar sesion]    │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
│  ┌─ HERO (compact) ──────────────────────────────────────────────────────────┐ │
│  │                                                                            │ │
│  │  🐾  Encuentra al cuidador perfecto                                       │ │
│  │      para tu mascota en Santa Cruz                                        │ │
│  │                                                                            │ │
│  │      Todos verificados con entrevista personal y visita domiciliaria      │ │
│  │                                                                            │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
│  ┌─ FILTROS (sticky top-16, z-30, blur backdrop) ────────────────────────────┐ │
│  │                                                                            │ │
│  │  ┌─ Chips de filtro ───────────────────────────────────────────────────┐   │ │
│  │  │                                                                     │   │ │
│  │  │  ┌──────────────────┐  ┌──────────────────┐  ┌─────────────────┐   │   │ │
│  │  │  │ 🏠 Servicio    ▾ │  │ 📍 Zona        ▾ │  │ 💰 Precio    ▾ │   │   │ │
│  │  │  │   Hospedaje      │  │   Todas          │  │   Todos        │   │   │ │
│  │  │  └──────────────────┘  └──────────────────┘  └─────────────────┘   │   │ │
│  │  │                                                                     │   │ │
│  │  │  ┌──────────────────┐                                               │   │ │
│  │  │  │ 🏡 Espacio     ▾ │  ← disabled + opacity-50 si Servicio=Paseos │   │ │
│  │  │  │   Todos          │                                               │   │ │
│  │  │  └──────────────────┘                                               │   │ │
│  │  │                                                                     │   │ │
│  │  └─────────────────────────────────────────────────────────────────────┘   │ │
│  │                                                                            │ │
│  │  ┌─ Active filters + count ─────────────────────────────────────────────┐ │ │
│  │  │                                                                       │ │ │
│  │  │  Hospedaje ✕    Equipetrol ✕    Estandar ✕      [Limpiar todo]       │ │ │
│  │  │                                                                       │ │ │
│  │  │                                         5 cuidadores encontrados 🐕   │ │ │
│  │  └───────────────────────────────────────────────────────────────────────┘ │ │
│  │                                                                            │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
│  ┌─ GRID ────────────────────────────────────────────────────────────────────┐ │
│  │                                                                            │ │
│  │  ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐      │ │
│  │  │ ┌───────────────┐ │  │ ┌───────────────┐ │  │ ┌───────────────┐ │      │ │
│  │  │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │  │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │  │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │      │ │
│  │  │ │▓ Patio 50m²   ▓│ │  │ │▓ Jardin con  ▓│ │  │ │▓ Casa Norte  ▓│ │      │ │
│  │  │ │▓ c/ cesped    ▓│ │  │ │▓ hamaca       ▓│ │  │ │▓ con patio   ▓│ │      │ │
│  │  │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │  │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │  │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │      │ │
│  │  │ │✓ Verificado   │ │  │ │✓ Verificado   │ │  │ │✓ Verificado   │ │      │ │
│  │  │ └───────────────┘ │  │ └───────────────┘ │  │ └───────────────┘ │      │ │
│  │  │                    │  │                    │  │                    │      │ │
│  │  │  Maria Lopez Vaca  │  │  Roberto Suarez M. │  │  Carla Mendez R.  │      │ │
│  │  │  ★ 4.8 (14)        │  │  ★ 4.6 (9)         │  │  ★ 5.0 (4)        │      │ │
│  │  │  📍 Equipetrol     │  │  📍 Equipetrol      │  │  📍 Norte          │      │ │
│  │  │                    │  │                    │  │                    │      │ │
│  │  │  🏠 Hospedaje      │  │  🏠 Hosp. 🦮 Paseo │  │  🏠 Hospedaje      │      │ │
│  │  │                    │  │                    │  │                    │      │ │
│  │  │  Bs 120/dia        │  │  Bs 150/dia        │  │  Bs 90/dia         │      │ │
│  │  │                    │  │  Bs 35/paseo        │  │                    │      │ │
│  │  │                    │  │                    │  │                    │      │ │
│  │  │  [    Ver perfil ] │  │  [    Ver perfil ] │  │  [    Ver perfil ] │      │ │
│  │  └───────────────────┘  └───────────────────┘  └───────────────────┘      │ │
│  │                                                                            │ │
│  │  ┌───────────────────┐  ┌───────────────────┐                             │ │
│  │  │       ...          │  │       ...          │                             │ │
│  │  └───────────────────┘  └───────────────────┘                             │ │
│  │                                                                            │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
│  ┌─ PAGINATION ──────────────────────────────────────────────────────────────┐ │
│  │                                                                            │ │
│  │         ←  Anterior     1   [2]   3   4     Siguiente  →                  │ │
│  │                                                                            │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
│  ┌─ TRUST FOOTER ────────────────────────────────────────────────────────────┐ │
│  │                                                                            │ │
│  │    🛡 Verificacion     📸 Fotos reales     🐾 Resenas reales              │ │
│  │    personal             de cada espacio      de clientes                    │ │
│  │                                                                            │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Mobile Completo (< 768px)

```
┌──────────────────────────────┐
│ [☰]   🌿 GARDEN     [Login] │
├──────────────────────────────┤
│                              │
│  🐾 Encuentra tu cuidador   │
│     ideal en Santa Cruz     │
│                              │
│  Todos verificados           │
│  personalmente               │
│                              │
│ ┌────────────────────────┐   │
│ │ 🔍 Filtros             │   │
│ │ ┌──────┐┌──────┐┌────┐│   │   ← chips horizontales scrollables
│ │ │🏠Hosp││📍Zona││💰$ ││   │
│ │ └──────┘└──────┘└────┘│   │
│ │      ← scroll →       │   │
│ └────────────────────────┘   │
│                              │
│  Hospedaje ✕  Equipetrol ✕   │   ← active filter pills
│                              │
│  5 cuidadores 🐕             │
│                              │
│ ┌────────────────────────┐   │
│ │ ┌────────────────────┐ │   │
│ │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │   │
│ │ │▓                   ▓│ │   │
│ │ │▓  Patio cercado    ▓│ │   │
│ │ │▓  50m², cesped,    ▓│ │   │
│ │ │▓  2 labradores     ▓│ │   │
│ │ │▓                   ▓│ │   │
│ │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │   │
│ │ │  ✓ Verificado       │ │   │
│ │ └────────────────────┘ │   │
│ │                        │   │
│ │  Maria Lopez Vaca      │   │
│ │  ★ 4.8 (14 resenas)   │   │
│ │  📍 Equipetrol         │   │
│ │                        │   │
│ │  🏠 Hospedaje          │   │
│ │  Bs 120/dia            │   │
│ │                        │   │
│ │  [    Ver perfil     ] │   │
│ └────────────────────────┘   │
│                              │
│ ┌────────────────────────┐   │
│ │ ┌────────────────────┐ │   │
│ │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │   │
│ │ │▓ Jardin con hamaca ▓│ │   │
│ │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │   │
│ │ │  ✓ Verificado       │ │   │
│ │ └────────────────────┘ │   │
│ │                        │   │
│ │  Roberto Suarez M.     │   │
│ │  ★ 4.6 (9 resenas)    │   │
│ │  📍 Equipetrol         │   │
│ │                        │   │
│ │  🏠 Hosp. 🦮 Paseo    │   │
│ │  Bs 150/dia            │   │
│ │  Bs 35/paseo 30m       │   │
│ │                        │   │
│ │  [    Ver perfil     ] │   │
│ └────────────────────────┘   │
│                              │
│       ← 1 [2] 3 →           │
│                              │
│  ┌────────────────────────┐  │
│  │ 🛡 Verificados         │  │
│  │ 📸 Fotos reales        │  │
│  │ 🐾 Resenas reales      │  │
│  └────────────────────────┘  │
│                              │
└──────────────────────────────┘
```

### 1.3 Dropdown de Filtro — Interaccion Detallada

```
SERVICIO (radio — seleccion unica):
┌──────────────────────┐
│ 🏠 Servicio        ▾ │  ← button trigger
└──────────┬───────────┘
           │ click
           ▼
┌───────────────────────────────┐
│                               │   shadow-xl, rounded-xl
│  ○  Todos                     │   border border-gray-200
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─── │   dark:border-gray-700
│  ●  🏠 Hospedaje              │   dark:bg-gray-900
│     Tu mascota se queda       │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─── │
│  ○  🦮 Paseos                  │
│     Paseo por la zona         │
│                               │
└───────────────────────────────┘

ZONA (checkbox — seleccion multiple):
┌──────────────────────┐
│ 📍 Zona            ▾ │
└──────────┬───────────┘
           ▼
┌───────────────────────────────┐
│                               │
│  ☑  Equipetrol                │   ← checked, garden-500
│  ☐  Urbari                    │
│  ☐  Norte                     │
│  ☐  Las Palmas                │
│  ☐  Centro / Av. San Martin  │
│  ☐  Otros                     │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─── │
│  [Limpiar]        [Aplicar]   │
│                               │
└───────────────────────────────┘

PRECIO (radio — contextual segun servicio):
┌──────────────────────┐
│ 💰 Precio          ▾ │
└──────────┬───────────┘
           ▼
┌───────────────────────────────┐  Si Servicio = Hospedaje:
│                               │
│  ○  Todos los precios         │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─── │
│  ○  Economico                 │
│     Bs 60 - 100 / dia        │  ← helper text con rango
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─── │
│  ●  Estandar                  │
│     Bs 100 - 140 / dia       │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─── │
│  ○  Premium                   │
│     Bs 140+ / dia             │
│                               │
└───────────────────────────────┘

┌───────────────────────────────┐  Si Servicio = Paseos:
│                               │
│  ○  Todos los precios         │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─── │
│  ○  Economico                 │
│     Bs 20 - 30 / paseo       │  ← rangos cambian!
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─── │
│  ○  Estandar                  │
│     Bs 30 - 50 / paseo       │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─── │
│  ○  Premium                   │
│     Bs 50+ / paseo            │
│                               │
└───────────────────────────────┘

ESPACIO (radio — disabled si solo Paseos):
┌──────────────────────┐
│ 🏡 Espacio  ▾  🚫    │  ← opacity-50, cursor-not-allowed
└──────────────────────┘
  tooltip: "No aplica para paseos"

┌──────────────────────┐          Si Hospedaje o Todos:
│ 🏡 Espacio         ▾ │
└──────────┬───────────┘
           ▼
┌───────────────────────────────┐
│                               │
│  ○  Todos                     │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─── │
│  ○  🏠 Casa con patio        │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─── │
│  ○  🏠 Casa sin patio        │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─── │
│  ○  🏢 Departamento           │
│                               │
└───────────────────────────────┘
```

### 1.4 Mobile Filter Bottom Sheet

```
┌──────────────────────────────┐
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░│  ← overlay bg-black/40
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░│    click fuera = cerrar
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
├──────────────────────────────┤
│          ─────               │  ← drag handle
│                              │
│  Filtros             [Reset] │
│  ────────────────────        │
│                              │
│  Servicio                    │
│  ┌────────┐ ┌────────┐      │
│  │🏠 Hosp.│ │🦮Paseos│      │   ← chips toggle
│  └────────┘ └────────┘      │
│                              │
│  Zona                        │
│  ┌──────────┐ ┌──────────┐  │
│  │Equipetrol│ │  Urbari  │  │
│  └──────────┘ └──────────┘  │
│  ┌──────────┐ ┌──────────┐  │
│  │  Norte   │ │Las Palmas│  │
│  └──────────┘ └──────────┘  │
│  ┌──────────┐ ┌──────────┐  │
│  │  Centro  │ │  Otros   │  │
│  └──────────┘ └──────────┘  │
│                              │
│  Precio                      │
│  ┌─────────────────────────┐ │
│  │ ○ Economico  Bs 60-100 │ │
│  │ ● Estandar   Bs 100-140│ │
│  │ ○ Premium    Bs 140+   │ │
│  └─────────────────────────┘ │
│                              │
│  Espacio                     │
│  ┌─────────────────────────┐ │
│  │ ○ Casa con patio        │ │
│  │ ○ Casa sin patio        │ │
│  │ ○ Departamento           │ │
│  └─────────────────────────┘ │
│                              │
│ ┌──────────────────────────┐ │
│ │  Mostrar 5 resultados 🐕 │ │  ← actualiza en tiempo real
│ └──────────────────────────┘ │
└──────────────────────────────┘
```

---

## 2. CaregiverCard — Tailwind Completo

### 2.1 Componente con Todos los Estados

```tsx
// src/components/caregivers/CaregiverCard.tsx

import { memo } from 'react';
import { Link } from 'react-router-dom';
import type { CaregiverListItem, Zone } from '../../types/caregiver';
import { VerifiedBadge } from '../ui/VerifiedBadge';
import { StarRating } from '../ui/StarRating';
import { CloudinaryImage } from '../ui/CloudinaryImage';

const ZONE_LABELS: Record<Zone, string> = {
  EQUIPETROL: 'Equipetrol',
  URBARI: 'Urbari',
  NORTE: 'Norte',
  LAS_PALMAS: 'Las Palmas',
  CENTRO_SAN_MARTIN: 'Centro',
  OTROS: 'Otros',
};

const SERVICE_CONFIG = {
  HOSPEDAJE: { icon: '🏠', label: 'Hospedaje', short: 'Hosp.' },
  PASEO:     { icon: '🦮', label: 'Paseos',    short: 'Paseo' },
} as const;

interface CaregiverCardProps {
  caregiver: CaregiverListItem;
}

export const CaregiverCard = memo(function CaregiverCard({
  caregiver: c,
}: CaregiverCardProps) {
  const mainPhotoUrl = c.photos?.[0] ?? null;

  return (
    <article
      className="
        group relative
        bg-white dark:bg-gray-900
        rounded-2xl
        border border-gray-200 dark:border-gray-800
        shadow-sm
        hover:shadow-lg hover:shadow-garden-500/5
        dark:hover:shadow-garden-400/5
        hover:-translate-y-0.5
        transition-all duration-300 ease-out
        overflow-hidden
        flex flex-col
        focus-within:ring-2 focus-within:ring-garden-500 focus-within:ring-offset-2
        dark:focus-within:ring-offset-gray-950
      "
      aria-label={`Perfil de ${c.firstName} ${c.lastName}, cuidador verificado en ${ZONE_LABELS[c.zone]}`}
    >
      {/* ── Foto principal ── */}
      <div className="relative aspect-[16/9] overflow-hidden bg-gray-100 dark:bg-gray-800">
        {mainPhotoUrl ? (
          <CloudinaryImage
            src={mainPhotoUrl}
            alt={`Espacio real de ${c.firstName} ${c.lastName} para cuidado de mascotas`}
            width={400}
            height={225}
            className="
              w-full h-full object-cover
              group-hover:scale-[1.03]
              transition-transform duration-500 ease-out
            "
            loading="lazy"
            decoding="async"
          />
        ) : (
          <div className="
            w-full h-full
            flex items-center justify-center
            text-gray-300 dark:text-gray-600
          ">
            <svg className="w-12 h-12" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1}
                d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
              />
            </svg>
          </div>
        )}

        {/* Badge verificado (sobre la foto) */}
        {c.verified && <VerifiedBadge variant="compact" />}

        {/* Gradient sutil bottom para legibilidad */}
        <div className="
          absolute inset-x-0 bottom-0 h-12
          bg-gradient-to-t from-black/10 to-transparent
          pointer-events-none
        " />
      </div>

      {/* ── Contenido ── */}
      <div className="flex-1 p-4 sm:p-5 flex flex-col gap-3">

        {/* Nombre + Rating */}
        <div>
          <h3
            className="
              text-base font-semibold leading-tight
              text-gray-900 dark:text-gray-100
              group-hover:text-garden-700 dark:group-hover:text-garden-400
              transition-colors duration-200
            "
            data-testid="caregiver-name"
          >
            {c.firstName} {c.lastName}
          </h3>

          <div className="flex items-center gap-2 mt-1.5">
            <StarRating rating={c.rating} size="sm" />
            <span className="
              text-xs text-gray-500 dark:text-gray-400
              tabular-nums
            ">
              {c.rating.toFixed(1)} ({c.reviewCount})
            </span>
          </div>
        </div>

        {/* Zona */}
        <div
          className="flex items-center gap-1.5"
          data-testid="caregiver-zone"
        >
          <svg className="w-3.5 h-3.5 text-gray-400 dark:text-gray-500 shrink-0"
            fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
              d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
              d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          <span className="text-sm text-gray-600 dark:text-gray-400">
            {ZONE_LABELS[c.zone]}
          </span>
        </div>

        {/* Servicios (chips) */}
        <div className="flex flex-wrap gap-1.5" data-testid="caregiver-services">
          {c.servicesOffered.map(service => (
            <span
              key={service}
              className="
                inline-flex items-center gap-1
                text-xs font-medium
                px-2 py-0.5
                rounded-full
                bg-garden-50 dark:bg-garden-950/40
                text-garden-700 dark:text-garden-300
                border border-garden-200 dark:border-garden-800
              "
              data-testid={`service-chip-${service}`}
            >
              <span aria-hidden="true">{SERVICE_CONFIG[service].icon}</span>
              {SERVICE_CONFIG[service].label}
            </span>
          ))}
        </div>

        {/* Spacer */}
        <div className="flex-1" />

        {/* Precios */}
        <div
          className="space-y-0.5"
          data-testid="caregiver-price"
        >
          {c.pricePerDay !== null && (
            <p className="text-sm font-semibold text-gray-900 dark:text-gray-100">
              Bs {c.pricePerDay}
              <span className="font-normal text-gray-500 dark:text-gray-400">/dia</span>
            </p>
          )}
          {c.pricePerWalk30 !== null && (
            <p className="text-xs text-gray-500 dark:text-gray-400">
              Bs {c.pricePerWalk30}/paseo 30m
              {c.pricePerWalk60 !== null && (
                <span> · Bs {c.pricePerWalk60}/1h</span>
              )}
            </p>
          )}
        </div>

        {/* CTA */}
        <Link
          to={`/cuidadores/${c.id}`}
          className="
            block w-full text-center
            px-4 py-2.5
            text-sm font-semibold
            rounded-xl
            bg-garden-500 dark:bg-garden-600
            hover:bg-garden-600 dark:hover:bg-garden-500
            active:bg-garden-700
            text-white
            shadow-sm hover:shadow-md
            transition-all duration-200
            focus-visible:outline-2 focus-visible:outline-garden-500 focus-visible:outline-offset-2
          "
        >
          Ver perfil
        </Link>
      </div>
    </article>
  );
});
```

### 2.2 Grid Responsive

```tsx
// src/components/caregivers/CaregiverGrid.tsx

import type { CaregiverListItem } from '../../types/caregiver';
import { CaregiverCard } from './CaregiverCard';

interface CaregiverGridProps {
  caregivers: CaregiverListItem[];
}

export function CaregiverGrid({ caregivers }: CaregiverGridProps) {
  return (
    <div
      className="
        grid
        grid-cols-1
        sm:grid-cols-2
        lg:grid-cols-3
        gap-4 sm:gap-5 lg:gap-6
      "
      data-testid="caregiver-grid"
    >
      {caregivers.map(c => (
        <CaregiverCard key={c.id} caregiver={c} />
      ))}
    </div>
  );
}
```

### 2.3 Skeleton (Loading)

```tsx
// src/components/caregivers/CaregiverCardSkeleton.tsx

export function CaregiverCardSkeleton() {
  return (
    <div className="
      bg-white dark:bg-gray-900
      rounded-2xl
      border border-gray-200 dark:border-gray-800
      overflow-hidden
      animate-pulse
    ">
      {/* Foto placeholder */}
      <div className="aspect-[16/9] bg-gray-200 dark:bg-gray-800" />

      {/* Content */}
      <div className="p-4 sm:p-5 space-y-3">
        {/* Nombre */}
        <div className="h-5 bg-gray-200 dark:bg-gray-800 rounded-lg w-3/4" />
        {/* Rating */}
        <div className="h-3.5 bg-gray-200 dark:bg-gray-800 rounded w-1/2" />
        {/* Zona */}
        <div className="h-3.5 bg-gray-200 dark:bg-gray-800 rounded w-1/3" />
        {/* Chips */}
        <div className="flex gap-1.5">
          <div className="h-5 bg-gray-200 dark:bg-gray-800 rounded-full w-20" />
          <div className="h-5 bg-gray-200 dark:bg-gray-800 rounded-full w-16" />
        </div>
        {/* Precio */}
        <div className="h-4 bg-gray-200 dark:bg-gray-800 rounded w-2/5" />
        {/* Button */}
        <div className="h-10 bg-gray-200 dark:bg-gray-800 rounded-xl" />
      </div>
    </div>
  );
}

export function CaregiverGridSkeleton({ count = 6 }: { count?: number }) {
  return (
    <div className="
      grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3
      gap-4 sm:gap-5 lg:gap-6
    ">
      {Array.from({ length: count }, (_, i) => (
        <CaregiverCardSkeleton key={i} />
      ))}
    </div>
  );
}
```

### 2.4 Card Visual Breakdown

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     CARD: JERARQUIA VISUAL                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─ 1. FOTO (decision en 1 segundo) ──────────────────────────────┐    │
│  │                                                                 │    │
│  │  aspect-[16/9]        ← foto del ESPACIO (no del cuidador)    │    │
│  │  object-cover         ← llena sin distorsion                  │    │
│  │  group-hover:scale-1.03 ← zoom sutil al hover (500ms ease)   │    │
│  │  loading="lazy"       ← solo carga cuando entra en viewport  │    │
│  │                                                                 │    │
│  │  Badge: position absolute, bottom-2 left-2                     │    │
│  │         bg-trust-badge/90, backdrop-blur-sm                     │    │
│  │         "✓ Verificado"                                          │    │
│  │                                                                 │    │
│  │  Gradient: from-black/10 bottom                                 │    │
│  │           → separa badge de foto clara                          │    │
│  │                                                                 │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ┌─ 2. IDENTIDAD (quien es) ──────────────────────────────────────┐    │
│  │                                                                 │    │
│  │  Nombre: text-base font-semibold → mas grande que v1            │    │
│  │          group-hover cambia a garden-700 (sutileza)             │    │
│  │                                                                 │    │
│  │  Rating: ★ iconos + numero + (#resenas)                         │    │
│  │          text-xs, text-trust-star, tabular-nums                 │    │
│  │                                                                 │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ┌─ 3. CONTEXTO (donde, que) ─────────────────────────────────────┐    │
│  │                                                                 │    │
│  │  Zona: icono MapPin SVG + texto                                 │    │
│  │        text-sm, text-gray-600 dark:text-gray-400                │    │
│  │                                                                 │    │
│  │  Servicios: chips rounded-full                                   │    │
│  │             bg-garden-50 dark:bg-garden-950/40                  │    │
│  │             border-garden-200 dark:border-garden-800            │    │
│  │             icon + label                                         │    │
│  │                                                                 │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ┌─ 4. DECISION (cuanto, accion) ─────────────────────────────────┐    │
│  │                                                                 │    │
│  │  Precio: "Bs 120" font-semibold + "/dia" font-normal            │    │
│  │          Paseo como texto secundario mas pequeno                │    │
│  │                                                                 │    │
│  │  CTA: "Ver perfil"                                               │    │
│  │       bg-garden-500, rounded-xl, full-width                     │    │
│  │       hover:shadow-md, active:bg-garden-700                     │    │
│  │       Enlace <a> (no boton) → SEO + accesibilidad              │    │
│  │                                                                 │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  HOVER EFFECT (todo el card):                                           │
│  · shadow-sm → shadow-lg shadow-garden-500/5                           │
│  · translate-y → -0.5 (sube 2px)                                       │
│  · foto scale → 1.03 (zoom sutil)                                      │
│  · nombre color → garden-700                                            │
│  · duration-300 ease-out                                                │
│  · DARK: shadow-garden-400/5 (brillo sutil en dark)                    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Filtros → Debounce → Refetch

### 3.1 Arquitectura Dual: Client-Side (MVP) → Server-Side (Escala)

```
┌──────────────────────────────────────────────────────────────────────────┐
│            MODO 1: CLIENT-SIDE (MVP, < 200 cuidadores)                   │
│            FEATURES.CLIENT_SIDE_FILTERING = true                         │
└──────────────────────────────────────────────────────────────────────────┘

  Usuario cambia filtro
       │
       ▼
  ┌──────────────┐
  │  onChange()   │  Instantaneo (0ms)
  │  setFilters() │  No hay fetch
  │  useMemo()    │  Filtrado en memoria
  │  re-render    │  Resultado visual inmediato
  └──────────────┘
       │
       ▼
  Grid actualizado ← ~16ms (un frame)


┌──────────────────────────────────────────────────────────────────────────┐
│            MODO 2: SERVER-SIDE (Escala, > 200 cuidadores)                │
│            FEATURES.CLIENT_SIDE_FILTERING = false                        │
└──────────────────────────────────────────────────────────────────────────┘

  Usuario cambia filtro
       │
       ▼
  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
  │  onChange()   │────>│  debounce    │────>│  fetch()      │
  │  setFilters() │     │  300ms       │     │  GET /api/    │
  │  (UI update   │     │              │     │  caregivers?  │
  │   inmediato)  │     │  Cancela     │     │  service=...  │
  │              │     │  anterior si │     │  &zone=...    │
  │              │     │  usuario     │     │  &page=1      │
  │              │     │  sigue       │     │  &limit=12    │
  │              │     │  cambiando   │     │               │
  └──────────────┘     └──────────────┘     └──────┬───────┘
                                                    │
                                              ┌─────▼─────┐
                                              │  200 OK    │
                                              │  12 items  │
                                              │  total: 45 │
                                              │  pages: 4  │
                                              └─────┬─────┘
                                                    │
                                                    ▼
                                           Grid actualizado
```

### 3.2 Hook Unificado con Feature Flag

```typescript
// src/hooks/useCaregivers.ts (v2 — dual mode)

import { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import { FEATURES } from '../config/features';
import type {
  CaregiverListItem,
  CaregiverFilters,
  CaregiverListResponse,
  PriceRange,
} from '../types/caregiver';

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:3001/api';
const ITEMS_PER_PAGE = 12;
const DEBOUNCE_MS = 300;

const PRICE_RANGES = {
  hospedaje: {
    economico: [60, 100],
    estandar:  [100, 140],
    premium:   [140, Infinity],
  },
  paseo: {
    economico: [20, 30],
    estandar:  [30, 50],
    premium:   [50, Infinity],
  },
} as const;

const INITIAL_FILTERS: CaregiverFilters = {
  service: null,
  zones: [],
  priceRange: null,
  spaceType: null,
};

export function useCaregivers() {
  const [allCaregivers, setAllCaregivers] = useState<CaregiverListItem[]>([]);
  const [serverResults, setServerResults] = useState<CaregiverListItem[]>([]);
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle');
  const [error, setError] = useState<string | null>(null);
  const [filters, setFilters] = useState<CaregiverFilters>(INITIAL_FILTERS);
  const [currentPage, setCurrentPage] = useState(1);
  const [serverTotal, setServerTotal] = useState(0);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>();
  const abortRef = useRef<AbortController>();

  // ── MODO CLIENT-SIDE: fetch all una vez ──
  useEffect(() => {
    if (!FEATURES.CLIENT_SIDE_FILTERING) return;

    const controller = new AbortController();
    abortRef.current = controller;

    (async () => {
      setStatus('loading');
      try {
        const res = await fetch(
          `${API_BASE}/caregivers?limit=200&verified=true`,
          { signal: controller.signal, headers: { Accept: 'application/json' } }
        );
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const json: CaregiverListResponse = await res.json();
        setAllCaregivers(json.data.caregivers);
        setStatus('success');
      } catch (err) {
        if (err instanceof Error && err.name === 'AbortError') return;
        setError(err instanceof Error ? err.message : 'Error de conexion');
        setStatus('error');
      }
    })();

    return () => controller.abort();
  }, []);

  // ── MODO SERVER-SIDE: fetch con filtros + debounce ──
  useEffect(() => {
    if (FEATURES.CLIENT_SIDE_FILTERING) return;

    // Debounce: esperar 300ms despues del ultimo cambio de filtro
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      abortRef.current?.abort();
      const controller = new AbortController();
      abortRef.current = controller;

      (async () => {
        setStatus('loading');
        try {
          const params = new URLSearchParams();
          params.set('verified', 'true');
          params.set('page', String(currentPage));
          params.set('limit', String(ITEMS_PER_PAGE));

          if (filters.service && filters.service !== 'AMBOS') {
            params.set('service', filters.service);
          }
          if (filters.zones.length > 0) {
            filters.zones.forEach(z => params.append('zone', z));
          }
          if (filters.priceRange) {
            const ctx = filters.service === 'PASEO' ? 'paseo' : 'hospedaje';
            const [min, max] = PRICE_RANGES[ctx][filters.priceRange];
            params.set('priceMin', String(min));
            if (max !== Infinity) params.set('priceMax', String(max));
          }
          if (filters.spaceType && filters.service !== 'PASEO') {
            params.set('spaceType', filters.spaceType);
          }

          const res = await fetch(
            `${API_BASE}/caregivers?${params}`,
            { signal: controller.signal, headers: { Accept: 'application/json' } }
          );
          if (!res.ok) throw new Error(`HTTP ${res.status}`);
          const json: CaregiverListResponse = await res.json();
          setServerResults(json.data.caregivers);
          setServerTotal(json.data.pagination.total);
          setStatus('success');
        } catch (err) {
          if (err instanceof Error && err.name === 'AbortError') return;
          setError(err instanceof Error ? err.message : 'Error de conexion');
          setStatus('error');
        }
      })();
    }, DEBOUNCE_MS);

    return () => {
      clearTimeout(debounceRef.current);
      abortRef.current?.abort();
    };
  }, [filters, currentPage]);

  // ── FILTRADO CLIENT-SIDE (solo modo 1) ──
  const clientFiltered = useMemo(() => {
    if (!FEATURES.CLIENT_SIDE_FILTERING) return [];
    let result = allCaregivers;

    if (filters.service && filters.service !== 'AMBOS') {
      result = result.filter(c =>
        c.servicesOffered.includes(filters.service as 'HOSPEDAJE' | 'PASEO')
      );
    }
    if (filters.zones.length > 0) {
      result = result.filter(c => filters.zones.includes(c.zone));
    }
    if (filters.priceRange) {
      const ctx = filters.service === 'PASEO' ? 'paseo' : 'hospedaje';
      const [min, max] = PRICE_RANGES[ctx][filters.priceRange];
      result = result.filter(c => {
        const price = ctx === 'hospedaje' ? c.pricePerDay : c.pricePerWalk30;
        return price !== null && price >= min && price < max;
      });
    }
    if (filters.spaceType && filters.service !== 'PASEO') {
      result = result.filter(c => c.spaceType === filters.spaceType);
    }
    return result;
  }, [allCaregivers, filters]);

  // ── RESULTADOS UNIFICADOS ──
  const filtered = FEATURES.CLIENT_SIDE_FILTERING ? clientFiltered : serverResults;
  const total = FEATURES.CLIENT_SIDE_FILTERING ? clientFiltered.length : serverTotal;
  const totalPages = Math.max(1, Math.ceil(total / ITEMS_PER_PAGE));

  // Reset pagina al cambiar filtros
  useEffect(() => { setCurrentPage(1); }, [filters]);

  const page = useMemo(() => {
    if (!FEATURES.CLIENT_SIDE_FILTERING) return filtered; // ya paginado por server
    const start = (currentPage - 1) * ITEMS_PER_PAGE;
    return filtered.slice(start, start + ITEMS_PER_PAGE);
  }, [filtered, currentPage]);

  // ── ACCIONES ──
  const updateFilter = useCallback(
    <K extends keyof CaregiverFilters>(key: K, value: CaregiverFilters[K]) => {
      setFilters(prev => ({ ...prev, [key]: value }));
    }, []
  );

  const clearFilters = useCallback(() => setFilters(INITIAL_FILTERS), []);

  const hasActiveFilters = useMemo(() =>
    filters.service !== null ||
    filters.zones.length > 0 ||
    filters.priceRange !== null ||
    filters.spaceType !== null,
  [filters]);

  const goToPage = useCallback((p: number) => {
    setCurrentPage(Math.max(1, Math.min(p, totalPages)));
    document.getElementById('caregiver-grid')?.scrollIntoView({
      behavior: 'smooth', block: 'start',
    });
  }, [totalPages]);

  const retry = useCallback(() => {
    setStatus('idle');
    setError(null);
    setAllCaregivers([]);
    setServerResults([]);
  }, []);

  return {
    caregivers: page,
    filteredCount: total,
    status,
    error,
    filters,
    hasActiveFilters,
    pagination: { currentPage, totalPages, total },
    updateFilter,
    clearFilters,
    goToPage,
    retry,
  };
}
```

### 3.3 Diagrama de Timing: Debounce en Accion

```
ESCENARIO: Usuario cambia 3 filtros rapido (< 300ms entre cada uno)

  t=0ms      t=100ms     t=200ms     t=500ms     t=800ms
    │           │           │           │           │
    ▼           ▼           ▼           │           │
  Servicio=   Zona=       Precio=      │           │
  Hospedaje   Equipetrol  Estandar     │           │
    │           │           │           │           │
    │ timer     │ cancel    │ cancel    │           │
    │ start     │ + restart │ + restart │           │
    │ (300ms)   │ (300ms)   │ (300ms)   │           │
    │           │           │           │           │
    │           │           │     ┌─────▼─────┐     │
    │           │           │     │  fetch()   │     │
    │           │           │     │  GET /api  │     │
    │           │           │     │  ?service= │     │
    │           │           │     │  HOSPEDAJE │     │
    │           │           │     │  &zone=    │     │
    │           │           │     │  EQUIPETROL│     │
    │           │           │     │  &priceMin │     │
    │           │           │     │  =100      │     │
    │           │           │     │  &priceMax │     │
    │           │           │     │  =140      │     │
    │           │           │     └─────┬─────┘     │
    │           │           │           │           │
    │           │           │           │     ┌─────▼─────┐
    │           │           │           │     │  200 OK    │
    │           │           │           │     │  3 items   │
    │           │           │           │     └─────┬─────┘
    │           │           │           │           │
    │           │           │           │           ▼
    │           │           │           │     Grid renderiza
    │           │           │           │     3 cards

RESULTADO:
  · 1 fetch en vez de 3 (ahorro 66%)
  · UI responsive: filtros se marcan inmediatamente
  · Grid muestra skeleton durante los 300ms + RTT del fetch
  · Si el usuario sigue cambiando, el fetch pendiente se cancela (AbortController)
```

### 3.4 Filter Chip: Active Pill con Dismiss

```tsx
// src/components/filters/ActiveFilterPill.tsx

interface ActiveFilterPillProps {
  label: string;
  onRemove: () => void;
}

export function ActiveFilterPill({ label, onRemove }: ActiveFilterPillProps) {
  return (
    <span className="
      inline-flex items-center gap-1
      text-xs font-medium
      px-2.5 py-1
      rounded-full
      bg-garden-100 dark:bg-garden-900/40
      text-garden-800 dark:text-garden-200
      border border-garden-200 dark:border-garden-800
      animate-in fade-in slide-in-from-left-1 duration-200
    ">
      {label}
      <button
        onClick={onRemove}
        className="
          ml-0.5
          w-4 h-4
          rounded-full
          flex items-center justify-center
          hover:bg-garden-200 dark:hover:bg-garden-800
          transition-colors
          focus-visible:outline-2 focus-visible:outline-garden-500
        "
        aria-label={`Quitar filtro: ${label}`}
      >
        <svg className="w-2.5 h-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3}
            d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </span>
  );
}
```

### 3.5 Filter Bar Completo (Desktop)

```tsx
// src/components/filters/FilterBar.tsx

import type { CaregiverFilters, Zone, PriceRange } from '../../types/caregiver';
import { FilterDropdown } from './FilterDropdown';
import { ActiveFilterPill } from './ActiveFilterPill';

const ZONE_OPTIONS: { value: Zone; label: string }[] = [
  { value: 'EQUIPETROL', label: 'Equipetrol' },
  { value: 'URBARI', label: 'Urbari' },
  { value: 'NORTE', label: 'Norte' },
  { value: 'LAS_PALMAS', label: 'Las Palmas' },
  { value: 'CENTRO_SAN_MARTIN', label: 'Centro / Av. San Martin' },
  { value: 'OTROS', label: 'Otros' },
];

interface FilterBarProps {
  filters: CaregiverFilters;
  onUpdate: <K extends keyof CaregiverFilters>(key: K, value: CaregiverFilters[K]) => void;
  onClear: () => void;
  hasActive: boolean;
  resultCount: number;
}

export function FilterBar({ filters, onUpdate, onClear, hasActive, resultCount }: FilterBarProps) {
  const isPaseoOnly = filters.service === 'PASEO';

  // Rangos de precio contextuales
  const priceLabels = isPaseoOnly
    ? { economico: 'Bs 20-30/paseo', estandar: 'Bs 30-50/paseo', premium: 'Bs 50+/paseo' }
    : { economico: 'Bs 60-100/dia', estandar: 'Bs 100-140/dia', premium: 'Bs 140+/dia' };

  return (
    <div className="
      sticky top-16 z-30
      bg-white/80 dark:bg-gray-950/80
      backdrop-blur-lg
      border-b border-gray-200 dark:border-gray-800
    ">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
        {/* Row 1: Dropdowns */}
        <div className="flex flex-wrap gap-2">
          <FilterDropdown
            icon="🏠"
            label="Servicio"
            type="radio"
            value={filters.service}
            options={[
              { value: null, label: 'Todos' },
              { value: 'HOSPEDAJE', label: '🏠 Hospedaje', description: 'Tu mascota se queda' },
              { value: 'PASEO', label: '🦮 Paseos', description: 'Paseo por la zona' },
            ]}
            onChange={v => onUpdate('service', v)}
          />

          <FilterDropdown
            icon="📍"
            label="Zona"
            type="checkbox"
            value={filters.zones}
            options={ZONE_OPTIONS.map(z => ({ value: z.value, label: z.label }))}
            onChange={v => onUpdate('zones', v as Zone[])}
          />

          <FilterDropdown
            icon="💰"
            label="Precio"
            type="radio"
            value={filters.priceRange}
            options={[
              { value: null, label: 'Todos los precios' },
              { value: 'economico', label: 'Economico', description: priceLabels.economico },
              { value: 'estandar', label: 'Estandar', description: priceLabels.estandar },
              { value: 'premium', label: 'Premium', description: priceLabels.premium },
            ]}
            onChange={v => onUpdate('priceRange', v as PriceRange | null)}
          />

          <FilterDropdown
            icon="🏡"
            label="Espacio"
            type="radio"
            value={filters.spaceType}
            disabled={isPaseoOnly}
            disabledTooltip="No aplica para paseos"
            options={[
              { value: null, label: 'Todos' },
              { value: 'casa_patio', label: '🏠 Casa con patio' },
              { value: 'casa_sin_patio', label: '🏠 Casa sin patio' },
              { value: 'departamento', label: '🏢 Departamento' },
            ]}
            onChange={v => onUpdate('spaceType', v)}
          />
        </div>

        {/* Row 2: Active pills + count */}
        {hasActive && (
          <div className="
            flex flex-wrap items-center gap-2
            mt-3 pt-3
            border-t border-gray-100 dark:border-gray-800
          ">
            {filters.service && (
              <ActiveFilterPill
                label={filters.service === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseos'}
                onRemove={() => onUpdate('service', null)}
              />
            )}
            {filters.zones.map(z => (
              <ActiveFilterPill
                key={z}
                label={ZONE_OPTIONS.find(o => o.value === z)!.label}
                onRemove={() => onUpdate('zones', filters.zones.filter(x => x !== z))}
              />
            ))}
            {filters.priceRange && (
              <ActiveFilterPill
                label={filters.priceRange.charAt(0).toUpperCase() + filters.priceRange.slice(1)}
                onRemove={() => onUpdate('priceRange', null)}
              />
            )}
            {filters.spaceType && (
              <ActiveFilterPill
                label={filters.spaceType.replace('_', ' ')}
                onRemove={() => onUpdate('spaceType', null)}
              />
            )}

            <button
              onClick={onClear}
              className="
                text-xs font-medium
                text-garden-600 dark:text-garden-400
                hover:text-garden-800 dark:hover:text-garden-300
                underline underline-offset-2
                transition-colors
              "
            >
              Limpiar todo
            </button>

            <span className="ml-auto flex items-center gap-1.5">
              <span
                className="
                  text-sm font-medium tabular-nums
                  text-gray-700 dark:text-gray-300
                "
                role="status"
                aria-live="polite"
                aria-atomic="true"
                data-testid="result-count"
              >
                {resultCount} cuidador{resultCount !== 1 ? 'es' : ''}
              </span>
              <span className="text-base" aria-hidden="true">🐕</span>
            </span>
          </div>
        )}
      </div>
    </div>
  );
}
```

---

## 4. Sistema Visual de Tranquilidad

### 4.1 Paleta de Colores: Trust & Calm

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    PALETA GARDEN: CONFIANZA + CALMA                       │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  PRIMARIO (Garden Green) — accion, confianza, naturaleza                │
│  ─────────────────────────────────────────────────────                   │
│  50:  #f0fdf4   backgrounds sutiles, hover states                       │
│  100: #dcfce7   selected chips, active pill bg                          │
│  200: #bbf7d0   borders de elementos activos                            │
│  500: #22c55e   botones primarios, badge verificado                     │
│  600: #16a34a   hover en botones, links                                 │
│  700: #15803d   active/pressed, texto resaltado                         │
│  900: #14532d   texto primario dark (sobre bg claro)                    │
│  950: #052e16   backgrounds dark mode (sutil)                           │
│                                                                          │
│  TRUST (colores semanticos)                                              │
│  ─────────────────────────                                               │
│  badge:    #16a34a (garden-600) — "verificado", seguro                  │
│  star:     #f59e0b (amber-500)  — rating, valoracion                    │
│  warning:  #ef4444 (red-500)    — errores, suspendido                   │
│  info:     #3b82f6 (blue-500)   — informativo, nuevo                    │
│  pending:  #f59e0b (amber-500)  — pendiente, en proceso                 │
│                                                                          │
│  NEUTRAL (grises)                                                        │
│  ───────────────                                                         │
│  Light: gray-50 (bg) → gray-900 (texto)                                │
│  Dark:  gray-950 (bg) → gray-100 (texto)                               │
│  Borders: gray-200 (light) / gray-800 (dark)                            │
│                                                                          │
│  TIPOGRAFIA                                                              │
│  ──────────                                                              │
│  font-sans: Inter, system-ui, sans-serif                                │
│  font-semibold: titulos, nombres, precios                               │
│  font-medium: labels, chips, botones                                    │
│  Base size: 14px (text-sm) para densidad confortable                    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Iconografia de Tranquilidad

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    ICONOS GARDEN: CONFIANZA + CALIDEZ                     │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  EMOJIS NATIVOS (MVP — sin dependencia de icon library):                │
│  ─────────────────────────────────────────────────                       │
│  🐾  Mascota generico (hero, counter, footer)                           │
│  🐕  Perro (counter "5 cuidadores 🐕")                                 │
│  🏠  Hospedaje (service chip)                                            │
│  🦮  Paseos (service chip) — perro guia, implica movimiento            │
│  🏡  Espacio/casa (filtro espacio)                                       │
│  📍  Ubicacion (zona en card)                                            │
│  💰  Precio (filtro)                                                     │
│  🛡  Verificacion (trust footer)                                         │
│  📸  Fotos reales (trust footer)                                         │
│  🌿  Logo GARDEN (naturaleza, organico)                                 │
│                                                                          │
│  SVG CUSTOM (heroicons/outline — 24x24, strokeWidth=1.5):              │
│  ─────────────────────────────────────────────────────                   │
│  MapPinIcon      → zona en card (mas preciso que emoji)                 │
│  CheckBadgeIcon  → badge verificado (icono + texto)                     │
│  StarIcon (solid)→ rating (relleno amber)                               │
│  PhotoIcon       → placeholder sin foto                                 │
│  FunnelIcon      → boton filtros mobile                                 │
│  XMarkIcon       → dismiss pills, cerrar dropdowns                     │
│  ChevronDownIcon → dropdown trigger                                     │
│                                                                          │
│  USO POR CONTEXTO:                                                       │
│  ─────────────────                                                       │
│  Emojis: para contenido visible al usuario (chips, badges, decorativo)  │
│  SVGs: para controles interactivos (botones, navigation, forms)         │
│  Nunca mezclar emoji + SVG en el mismo contexto (ej: un chip usa        │
│  emoji, un boton usa SVG, no al reves)                                   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### 4.3 Micro-Interacciones de Confianza

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    MICRO-INTERACCIONES                                    │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. CARD HOVER (desktop):                                                │
│  ────────────────────────                                                │
│  · Eleva suavemente (-translate-y-0.5, shadow-lg)                       │
│  · Foto hace zoom sutil (scale-1.03, 500ms ease-out)                   │
│  · Nombre cambia a garden-700                                            │
│  · Sombra con tinte verde (shadow-garden-500/5)                         │
│  → Efecto: "esta card te invita a explorar"                             │
│                                                                          │
│  2. BADGE VERIFICADO:                                                    │
│  ─────────────────────                                                   │
│  · Siempre visible (no hover-dependent)                                  │
│  · bg verde semi-transparente + backdrop-blur                            │
│  · Icono ✓ solido + texto "Verificado"                                  │
│  · No brilla, no parpadea — estabilidad = confianza                     │
│  → Efecto: "esto ya fue validado, puedes confiar"                       │
│                                                                          │
│  3. FILTER PILL APPEAR:                                                  │
│  ─────────────────────                                                   │
│  · Fade-in + slide-in-from-left (200ms)                                  │
│  · Los pills activos se acumulan suavemente                              │
│  · ✕ aparece para remover con hover-bg sutil                            │
│  → Efecto: "tu seleccion queda clara y reversible"                      │
│                                                                          │
│  4. RESULT COUNTER:                                                      │
│  ─────────────────                                                       │
│  · aria-live="polite" (screen readers se enteran)                        │
│  · tabular-nums (numeros no saltan al cambiar)                           │
│  · 🐕 emoji al lado (toque de calidez)                                  │
│  · Transicion suave al cambiar numero (opacity flash)                    │
│  → Efecto: "feedback inmediato sin agobiar"                              │
│                                                                          │
│  5. SKELETON LOADING:                                                    │
│  ───────────────────                                                     │
│  · Misma estructura que el card real (foto + content)                    │
│  · animate-pulse (no spinner — menos ansiedad)                           │
│  · Mantiene aspect-ratio → 0 CLS cuando cargan datos                    │
│  → Efecto: "algo viene, y tendra esta forma"                            │
│                                                                          │
│  6. EMPTY STATE:                                                         │
│  ───────────────                                                         │
│  · Icono grande de busqueda (no triste, neutro)                          │
│  · Texto empático: "No encontramos..." (no "Error")                    │
│  · CTA: "Limpiar filtros" (accion clara de salida)                      │
│  → Efecto: "no es un error tuyo, ajusta y sigue"                        │
│                                                                          │
│  7. TRUST FOOTER:                                                        │
│  ───────────────                                                         │
│  · 3 columnas con icono + titulo + subtitulo                             │
│  · 🛡 Verificacion personal                                             │
│  · 📸 Fotos reales de cada espacio                                      │
│  · 🐾 Resenas reales de clientes                                        │
│  · Separado del grid, bg-gray-50 dark:bg-gray-900                       │
│  · Visible despues de scroll completo                                    │
│  → Efecto: "refuerzo de confianza al final del browse"                  │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### 4.4 Trust Footer Component

```tsx
// src/components/ui/TrustFooter.tsx

const TRUST_ITEMS = [
  {
    icon: '🛡',
    title: 'Verificacion personal',
    description: 'Entrevista + visita a cada cuidador',
  },
  {
    icon: '📸',
    title: 'Fotos reales',
    description: 'De cada espacio, no stock ni IA',
  },
  {
    icon: '🐾',
    title: 'Resenas reales',
    description: 'De clientes que usaron el servicio',
  },
];

export function TrustFooter() {
  return (
    <section
      className="
        mt-12
        py-8 sm:py-10
        bg-gray-50 dark:bg-gray-900/50
        border-t border-gray-200 dark:border-gray-800
      "
      aria-label="Garantias de confianza GARDEN"
    >
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="
          grid
          grid-cols-1 sm:grid-cols-3
          gap-6 sm:gap-8
          text-center
        ">
          {TRUST_ITEMS.map(item => (
            <div key={item.title} className="flex flex-col items-center gap-2">
              <span className="text-3xl" aria-hidden="true">
                {item.icon}
              </span>
              <h3 className="
                text-sm font-semibold
                text-gray-900 dark:text-gray-100
              ">
                {item.title}
              </h3>
              <p className="
                text-xs
                text-gray-500 dark:text-gray-400
                max-w-[200px]
              ">
                {item.description}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
```

### 4.5 CloudinaryImage: Wrapper con Lazy Load + srcSet

```tsx
// src/components/ui/CloudinaryImage.tsx

interface CloudinaryImageProps {
  src: string;                   // URL base de Cloudinary
  alt: string;
  width: number;
  height: number;
  className?: string;
  loading?: 'lazy' | 'eager';
  decoding?: 'async' | 'auto';
  sizes?: string;
}

function getTransformedUrl(base: string, w: number, h: number): string {
  return base.replace(
    '/upload/',
    `/upload/c_fill,w_${w},h_${h},q_auto,f_auto/`
  );
}

function getSrcSet(base: string, aspectRatio: number): string {
  const widths = [320, 400, 640, 800];
  return widths
    .map(w => {
      const h = Math.round(w / aspectRatio);
      return `${getTransformedUrl(base, w, h)} ${w}w`;
    })
    .join(', ');
}

export function CloudinaryImage({
  src,
  alt,
  width,
  height,
  className = '',
  loading = 'lazy',
  decoding = 'async',
  sizes = '(max-width: 639px) 100vw, (max-width: 1023px) 50vw, 33vw',
}: CloudinaryImageProps) {
  const aspectRatio = width / height;

  return (
    <img
      src={getTransformedUrl(src, width, height)}
      srcSet={getSrcSet(src, aspectRatio)}
      sizes={sizes}
      alt={alt}
      width={width}
      height={height}
      loading={loading}
      decoding={decoding}
      className={className}
    />
  );
}
```

### 4.6 Tailwind Config Completo

```typescript
// tailwind.config.ts

import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        garden: {
          50:  '#f0fdf4',
          100: '#dcfce7',
          200: '#bbf7d0',
          300: '#86efac',
          400: '#4ade80',
          500: '#22c55e',
          600: '#16a34a',
          700: '#15803d',
          800: '#166534',
          900: '#14532d',
          950: '#052e16',
        },
        trust: {
          badge:   '#16a34a',
          star:    '#f59e0b',
          warning: '#ef4444',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
      },
      aspectRatio: {
        card: '16 / 9',
        photo: '4 / 3',
      },
      boxShadow: {
        'card-hover': '0 10px 25px -5px rgba(34, 197, 94, 0.05), 0 8px 10px -6px rgba(34, 197, 94, 0.03)',
      },
      animation: {
        'skeleton': 'pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'in': 'fadeSlideIn 200ms ease-out',
      },
      keyframes: {
        fadeSlideIn: {
          '0%': { opacity: '0', transform: 'translateX(-4px)' },
          '100%': { opacity: '1', transform: 'translateX(0)' },
        },
      },
    },
  },
  plugins: [],
};

export default config;
```

---

**FIN DEL DOCUMENTO**

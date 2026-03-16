# GARDEN - UI/UX Design: Perfiles de Cuidadores Verificados

## Web Responsive (React 18 + Tailwind CSS + Cloudinary)

**Version:** 1.0
**Fecha:** 06 de Febrero, 2026
**Scope:** Funcionalidad #1 del MVP - Listing + Detalle de Cuidadores
**Target:** Web responsive (mobile-first, 360px-1440px+)

---

## Tabla de Contenidos

1. [Wireframe General](#1-wireframe-general)
2. [Flujos de Usuario](#2-flujos-de-usuario)
3. [Estilos Tailwind](#3-estilos-tailwind)
4. [Escalabilidad Visual (V2)](#4-escalabilidad-visual-v2)
5. [Self-Review](#5-self-review)

---

## 1. Wireframe General

### 1.1 Página de Listing: `/cuidadores`

Esta es la página principal donde el cliente busca cuidadores. El diseño sigue el principio del MVP: **encontrar un cuidador relevante en menos de 2 minutos**.

#### 1.1.1 Layout Desktop (>= 1024px)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  [GARDEN logo]          Cuidadores    Cómo funciona    [Iniciar sesión]    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Encuentra al cuidador perfecto para tu mascota                            │
│  ─────────────────────────────────────────────────                          │
│                                                                             │
│  ┌─── FILTROS (sticky top on scroll) ──────────────────────────────────┐   │
│  │                                                                      │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌────────────┐  │   │
│  │  │ 🏠 Servicio ▾│ │ 📍 Zona    ▾│ │ 💰 Precio  ▾│ │ 🏡 Espacio▾│  │   │
│  │  │              │ │              │ │              │ │            │  │   │
│  │  │ ○ Hospedaje  │ │ □ Equipetrol │ │ ○ Económico  │ │ ○ Casa c/  │  │   │
│  │  │ ○ Paseos     │ │ □ Urbarí     │ │   Bs 60-100  │ │   patio    │  │   │
│  │  │ ○ Ambos      │ │ □ Norte      │ │ ○ Estándar   │ │ ○ Casa s/  │  │   │
│  │  │              │ │ □ Las Palmas │ │   Bs 100-140 │ │   patio    │  │   │
│  │  │              │ │ □ Centro     │ │ ○ Premium    │ │ ○ Depto    │  │   │
│  │  │              │ │ □ Otros      │ │   Bs 140+    │ │            │  │   │
│  │  └──────────────┘ └──────────────┘ └──────────────┘ └────────────┘  │   │
│  │                                                                      │   │
│  │  [Limpiar filtros]                      12 cuidadores disponibles    │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─── GRID: 3 columnas (lg) / 2 columnas (md) ────────────────────────┐   │
│  │                                                                      │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │   │
│  │  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │     │   │
│  │  │ │             │ │  │ │             │ │  │ │             │ │     │   │
│  │  │ │  FOTO       │ │  │ │  FOTO       │ │  │ │  FOTO       │ │     │   │
│  │  │ │  PRINCIPAL  │ │  │ │  PRINCIPAL  │ │  │ │  PRINCIPAL  │ │     │   │
│  │  │ │  (16:9)     │ │  │ │  (16:9)     │ │  │ │  (16:9)     │ │     │   │
│  │  │ │             │ │  │ │             │ │  │ │             │ │     │   │
│  │  │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │     │   │
│  │  │                  │  │                  │  │                  │     │   │
│  │  │ ✓ Verificado     │  │ ✓ Verificado     │  │ ✓ Verificado     │     │   │
│  │  │                  │  │                  │  │                  │     │   │
│  │  │ María López      │  │ Carlos Pérez     │  │ Ana Gómez        │     │   │
│  │  │ ★ 4.8 (12)       │  │ ★ 4.5 (8)        │  │ ★ 5.0 (3)        │     │   │
│  │  │ 📍 Equipetrol    │  │ 📍 Norte          │  │ 📍 Urbarí         │     │   │
│  │  │                  │  │                  │  │                  │     │   │
│  │  │ 🏠 Hospedaje     │  │ 🦮 Paseos         │  │ 🏠🦮 Ambos        │     │   │
│  │  │ 🦮 Paseos        │  │                  │  │                  │     │   │
│  │  │                  │  │                  │  │                  │     │   │
│  │  │ Bs 120/día       │  │ Bs 30/paseo      │  │ Bs 140/día       │     │   │
│  │  │ Bs 40/paseo 30m  │  │ Bs 50/paseo 1h   │  │ Bs 45/paseo 30m  │     │   │
│  │  │                  │  │                  │  │                  │     │   │
│  │  │ [  Ver perfil  ] │  │ [  Ver perfil  ] │  │ [  Ver perfil  ] │     │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘     │   │
│  │                                                                      │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │   │
│  │  │     ...          │  │     ...          │  │     ...          │     │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘     │   │
│  │                                                                      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─── PAGINACIÓN ──────────────────────────────────────────────────────┐   │
│  │           ← Anterior    1  [2]  3  4    Siguiente →                  │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 1.1.2 Layout Mobile (< 768px)

```
┌───────────────────────────┐
│ [☰]  GARDEN      [Login] │
├───────────────────────────┤
│                           │
│ Encuentra tu cuidador     │
│ ideal                     │
│                           │
│ ┌───────────────────────┐ │
│ │ 🔍 Filtros (3 activos)│ │
│ │         [Abrir ▾]     │ │
│ └───────────────────────┘ │
│                           │
│  12 cuidadores            │
│                           │
│ ┌───────────────────────┐ │
│ │ ┌───────────────────┐ │ │
│ │ │                   │ │ │
│ │ │   FOTO PRINCIPAL  │ │ │
│ │ │   (16:9, full w)  │ │ │
│ │ │                   │ │ │
│ │ └───────────────────┘ │ │
│ │                       │ │
│ │ ✓ Verificado por      │ │
│ │   GARDEN              │ │
│ │                       │ │
│ │ María López           │ │
│ │ ★ 4.8 (12 reseñas)   │ │
│ │ 📍 Equipetrol         │ │
│ │                       │ │
│ │ 🏠 Hospedaje          │ │
│ │   Bs 120/día          │ │
│ │ 🦮 Paseos             │ │
│ │   30m Bs 40 · 1h Bs 60│ │
│ │                       │ │
│ │ [    Ver perfil     ] │ │
│ └───────────────────────┘ │
│                           │
│ ┌───────────────────────┐ │
│ │       ...             │ │
│ └───────────────────────┘ │
│                           │
│     ← 1 [2] 3 4 →        │
│                           │
└───────────────────────────┘
```

#### 1.1.3 Filtros Mobile (Bottom Sheet)

Cuando el usuario toca "Filtros", se abre un bottom sheet deslizable:

```
┌───────────────────────────┐
│ ░░░░░░░░░░░░░░░░░░░░░░░░░│  ← Fondo oscurecido (overlay)
│ ░░░░░░░░░░░░░░░░░░░░░░░░░│
├───────────────────────────┤
│         ─────             │  ← Handle para drag
│                           │
│  Filtros        [Limpiar] │
│  ─────────────────────    │
│                           │
│  Tipo de servicio         │
│  ┌─────────┐ ┌─────────┐ │
│  │🏠Hosp.  │ │🦮Paseos │ │
│  └─────────┘ └─────────┘ │
│  ┌───────────────────┐    │
│  │  🏠🦮 Ambos       │    │
│  └───────────────────┘    │
│                           │
│  Zona                     │
│  ┌──────────┐ ┌─────────┐│
│  │Equipetrol│ │ Urbarí  ││
│  └──────────┘ └─────────┘│
│  ┌──────────┐ ┌─────────┐│
│  │  Norte   │ │Las Palm.││
│  └──────────┘ └─────────┘│
│  ┌──────────┐ ┌─────────┐│
│  │  Centro  │ │  Otros  ││
│  └──────────┘ └─────────┘│
│                           │
│  Precio                   │
│  ┌───────────────────┐    │
│  │ Económico Bs60-100│    │
│  └───────────────────┘    │
│  ┌───────────────────┐    │
│  │ Estándar Bs100-140│    │
│  └───────────────────┘    │
│  ┌───────────────────┐    │
│  │ Premium  Bs140+   │    │
│  └───────────────────┘    │
│                           │
│  Tipo de espacio          │
│  (solo para hospedaje)    │
│  ┌──────────┐ ┌─────────┐│
│  │Casa c/   │ │Casa s/  ││
│  │patio     │ │patio    ││
│  └──────────┘ └─────────┘│
│  ┌───────────────────┐    │
│  │  Departamento     │    │
│  └───────────────────┘    │
│                           │
│ ┌───────────────────────┐ │
│ │  Mostrar 8 resultados │ │
│ └───────────────────────┘ │
└───────────────────────────┘
```

**Notas de interacción:**
- Los filtros se aplican **client-side** (toda la data ya cargada, sin roundtrips al backend para MVP con <200 cuidadores)
- El filtro "Tipo de espacio" se deshabilita visualmente (opacity-50 + tooltip) si el servicio seleccionado es solo "Paseos"
- Los chips de zona permiten selección multiple (checkbox behavior)
- El contador "Mostrar X resultados" se actualiza en tiempo real conforme cambian filtros
- En desktop los filtros son dropdowns inline; en mobile es bottom sheet para no consumir viewport

---

### 1.2 Página de Detalle: `/cuidadores/:id`

El perfil individual del cuidador. Aqui el cliente decide si confía o descarta.

#### 1.2.1 Layout Desktop (>= 1024px)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  [GARDEN logo]          Cuidadores    Cómo funciona    [Mi cuenta ▾]       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ← Volver a cuidadores                                                    │
│                                                                             │
│  ┌────────────────────────────────────────┬─────────────────────────────┐   │
│  │                                        │                             │   │
│  │  ┌─── GALERÍA DE FOTOS ─────────────┐ │  ┌─── SIDEBAR (sticky) ──┐ │   │
│  │  │                                   │ │  │                        │ │   │
│  │  │  ┌───────────────────────────┐    │ │  │  Bs 120/día            │ │   │
│  │  │  │                           │    │ │  │  Bs 40/paseo 30min     │ │   │
│  │  │  │                           │    │ │  │  Bs 60/paseo 1h        │ │   │
│  │  │  │     FOTO PRINCIPAL        │    │ │  │                        │ │   │
│  │  │  │     (4:3 ratio)           │    │ │  │  ────────────────────  │ │   │
│  │  │  │     800x600 optimized     │    │ │  │                        │ │   │
│  │  │  │                           │    │ │  │  Selecciona servicio:  │ │   │
│  │  │  │     ◀  1/6  ▶             │    │ │  │  ┌──────────────────┐  │ │   │
│  │  │  │                           │    │ │  │  │ 🏠 Hospedaje     │  │ │   │
│  │  │  └───────────────────────────┘    │ │  │  └──────────────────┘  │ │   │
│  │  │                                   │ │  │  ┌──────────────────┐  │ │   │
│  │  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐│ │  │  │ 🦮 Paseos        │  │ │   │
│  │  │  │thm 2│ │thm 3│ │thm 4│ │thm 5││ │  │  └──────────────────┘  │ │   │
│  │  │  │     │ │     │ │     │ │     ││ │  │                        │ │   │
│  │  │  └─────┘ └─────┘ └─────┘ └─────┘│ │  │  [  Reservar ahora  ] │ │   │
│  │  │                                   │ │  │                        │ │   │
│  │  └───────────────────────────────────┘ │  │  ────────────────────  │ │   │
│  │                                        │  │                        │ │   │
│  │  ┌─── INFO PRINCIPAL ───────────────┐ │  │  ★ 4.8 · 12 reseñas   │ │   │
│  │  │                                   │ │  │  📍 Equipetrol         │ │   │
│  │  │  María López                      │ │  │  🏡 Casa con patio    │ │   │
│  │  │  ┌────────────────────────┐       │ │  │                        │ │   │
│  │  │  │ ✓ Verificado por GARDEN│       │ │  │  Servicios:            │ │   │
│  │  │  └────────────────────────┘       │ │  │  ✓ Hospedaje           │ │   │
│  │  │                                   │ │  │  ✓ Paseos              │ │   │
│  │  │  "Casa con patio cercado de 50m², │ │  │                        │ │   │
│  │  │   tengo 2 labradores, vivo sola,  │ │  └────────────────────────┘ │   │
│  │  │   trabajo desde casa. Recibo      │ │                             │   │
│  │  │   perros de todos los tamaños.    │ │                             │   │
│  │  │   Tengo experiencia cuidando..."  │ │                             │   │
│  │  │                                   │ │                             │   │
│  │  │  ── Detalles ──────────────────── │ │                             │   │
│  │  │  📍 Zona: Equipetrol              │ │                             │   │
│  │  │  🏡 Espacio: Casa con patio       │ │                             │   │
│  │  │  🏠 Hospedaje: Bs 120/día         │ │                             │   │
│  │  │  🦮 Paseo 30min: Bs 40            │ │                             │   │
│  │  │  🦮 Paseo 1h: Bs 60              │ │                             │   │
│  │  │                                   │ │                             │   │
│  │  └───────────────────────────────────┘ │                             │   │
│  │                                        │                             │   │
│  │  ┌─── RESEÑAS ─────────────────────┐  │                             │   │
│  │  │                                   │ │                             │   │
│  │  │  ★ 4.8 promedio · 12 reseñas     │ │                             │   │
│  │  │  ────────────────────────────     │ │                             │   │
│  │  │                                   │ │                             │   │
│  │  │  ┌───────────────────────────┐   │ │                             │   │
│  │  │  │ Carlos R.        ★★★★★   │   │ │                             │   │
│  │  │  │ Hospedaje · Feb 2026      │   │ │                             │   │
│  │  │  │                           │   │ │                             │   │
│  │  │  │ "Excelente cuidadora, mi  │   │ │                             │   │
│  │  │  │  perro volvió feliz..."   │   │ │                             │   │
│  │  │  └───────────────────────────┘   │ │                             │   │
│  │  │                                   │ │                             │   │
│  │  │  ┌───────────────────────────┐   │ │                             │   │
│  │  │  │ Ana M.           ★★★★☆   │   │ │                             │   │
│  │  │  │ Paseo 1h · Ene 2026       │   │ │                             │   │
│  │  │  │                           │   │ │                             │   │
│  │  │  │ "Carlos fue puntual y     │   │ │                             │   │
│  │  │  │  envió fotos del paseo."  │   │ │                             │   │
│  │  │  │                           │   │ │                             │   │
│  │  │  │  > Respuesta de María:    │   │ │                             │   │
│  │  │  │  > "Gracias Ana, fue un   │   │ │                             │   │
│  │  │  │  >  placer pasear a Loki."│   │ │                             │   │
│  │  │  └───────────────────────────┘   │ │                             │   │
│  │  │                                   │ │                             │   │
│  │  │  [  Ver todas las reseñas (12) ]  │ │                             │   │
│  │  │                                   │ │                             │   │
│  │  └───────────────────────────────────┘ │                             │   │
│  │                                        │                             │   │
│  └────────────────────────────────────────┴─────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 1.2.2 Layout Mobile (< 768px)

```
┌───────────────────────────┐
│ [←]   María López  [···] │
├───────────────────────────┤
│                           │
│ ┌───────────────────────┐ │
│ │                       │ │
│ │    FOTO PRINCIPAL     │ │
│ │    (full width)       │ │
│ │    swipeable carousel │ │
│ │                       │ │
│ │    ◉ ○ ○ ○ ○ ○       │ │  ← dot indicators
│ └───────────────────────┘ │
│                           │
│  María López              │
│  ┌────────────────────┐   │
│  │ ✓ Verificado por   │   │
│  │   GARDEN            │   │
│  └────────────────────┘   │
│                           │
│  ★ 4.8 · 12 reseñas      │
│  📍 Equipetrol            │
│  🏡 Casa con patio        │
│                           │
│ ─────────────────────     │
│                           │
│  Sobre mí                 │
│                           │
│  "Casa con patio cercado  │
│   de 50m², tengo 2        │
│   labradores, vivo sola,  │
│   trabajo desde casa..."  │
│                           │
│  [Leer más]               │
│                           │
│ ─────────────────────     │
│                           │
│  Servicios y precios      │
│                           │
│  ┌───────────────────────┐│
│  │ 🏠 Hospedaje          ││
│  │    Bs 120/día          ││
│  │ 🦮 Paseo 30min        ││
│  │    Bs 40               ││
│  │ 🦮 Paseo 1h           ││
│  │    Bs 60               ││
│  └───────────────────────┘│
│                           │
│ ─────────────────────     │
│                           │
│  Reseñas (12)             │
│                           │
│  ┌───────────────────────┐│
│  │ Carlos R.    ★★★★★    ││
│  │ Hospedaje · Feb 2026  ││
│  │ "Excelente cuidadora  ││
│  │  mi perro volvió..."  ││
│  └───────────────────────┘│
│                           │
│  ┌───────────────────────┐│
│  │ Ana M.       ★★★★☆   ││
│  │ Paseo · Ene 2026      ││
│  │ "Carlos fue puntual   ││
│  │  y envió fotos..."    ││
│  └───────────────────────┘│
│                           │
│  [Ver todas las reseñas]  │
│                           │
│ ┌───────────────────────┐ │
│ │                       │ │
│ │   [ Reservar ahora ]  │ │  ← Sticky bottom CTA
│ │                       │ │
│ └───────────────────────┘ │
└───────────────────────────┘
```

#### 1.2.3 Galeria de Fotos - Comportamiento

**Fotos reales, no stock.** El MVP depende de esto. Cada cuidador tiene 4-6 fotos verificadas por el equipo GARDEN:

| # | Foto sugerida | Por que importa |
|---|---------------|-----------------|
| 1 | Casa/patio exterior | Cliente ve el espacio real |
| 2 | Area donde duerme la mascota | Tranquilidad sobre comodidad |
| 3 | Cuidador con su propia mascota | Humaniza, genera empatia |
| 4 | Patio/jardin (hospedaje) o ruta de paseo | Demuestra espacio/conocimiento |
| 5 | Interior de la casa (opcional) | Contexto adicional |
| 6 | Cuidador de frente, sonriendo | Confianza cara a cara |

**Desktop:** Galeria con foto principal grande + thumbnails debajo. Click en thumbnail cambia la principal. Flechas para navegar.

**Mobile:** Carrusel horizontal full-width con swipe nativo. Dot indicators abajo. Tap para ver foto en fullscreen (lightbox con pinch-to-zoom).

**Cloudinary transforms por contexto:**

```
Listing card (thumbnail):     c_fill,w_400,h_225,q_auto,f_auto
Detalle principal (desktop):  c_fill,w_800,h_600,q_auto,f_auto
Detalle principal (mobile):   c_fill,w_640,h_480,q_auto,f_auto
Thumbnail galeria:            c_fill,w_120,h_90,q_auto,f_auto
Lightbox fullscreen:          c_limit,w_1200,q_auto,f_auto
```

---

### 1.3 CaregiverCard - Componente de Listing

El card del cuidador es el componente mas importante del listing. Debe permitir **descarte rapido**: el cliente mira y en 2-3 segundos decide si abre el perfil o sigue scrolleando.

**Jerarquia visual del card (de arriba a abajo):**

```
┌─────────────────────────────┐
│ ┌─────────────────────────┐ │
│ │                         │ │  1. FOTO: primera impresion
│ │    FOTO PRINCIPAL       │ │     (espacio real, no cara)
│ │    aspect-ratio: 16/9   │ │
│ │                         │ │
│ │  ┌──────────────────┐   │ │  2. BADGE: genera confianza
│ │  │✓ Verificado      │   │ │     (superpuesto sobre foto,
│ │  └──────────────────┘   │ │      esquina inferior izq.)
│ └─────────────────────────┘ │
│                              │
│  María López                 │  3. NOMBRE: identidad
│  ★ 4.8 (12)  📍 Equipetrol  │  4. RATING + ZONA: decision rapida
│                              │
│  ┌────────┐ ┌────────┐      │  5. SERVICIOS: chips visuales
│  │🏠 Hosp.│ │🦮 Paseo│      │
│  └────────┘ └────────┘      │
│                              │
│  Bs 120/día · Bs 40/paseo   │  6. PRECIO: decide si esta en rango
│                              │
│  ┌────────────────────────┐  │  7. CTA: accion clara
│  │     Ver perfil         │  │
│  └────────────────────────┘  │
└─────────────────────────────┘
```

**Datos que se muestran vs. datos que NO:**

| Se muestra en card | NO se muestra en card |
|--------------------|-----------------------|
| Foto principal | Bio/descripcion |
| Badge verificado | Tipo de espacio |
| Nombre | Fotos adicionales |
| Rating + # resenas | Resenas individuales |
| Zona | Calendario disponibilidad |
| Servicios ofrecidos (chips) | Precio paseo 1h (solo 30min) |
| Precio principal | |

Razon: el card es para **filtrar visualmente**, no para leer. Los detalles van en la pagina de perfil.

---

### 1.4 Componente Badge "Verificado por GARDEN"

Dos variantes segun contexto:

**Variante compact (en card del listing):**
```
┌─────────────────────┐
│ ✓ Verificado        │   Sobre foto, semi-transparente
└─────────────────────┘
```

**Variante full (en pagina de detalle):**
```
┌───────────────────────────────┐
│ ✓ Verificado por GARDEN       │
│   Entrevista personal + visita│
└───────────────────────────────┘
```

El badge es **no-removable** por el cuidador. Solo el admin lo otorga (US-1.3).

---

## 2. Flujos de Usuario

### 2.1 Registro de Cuidador (US-1.2)

Formulario multi-step para no abrumar. El cuidador completa su perfil, pero no es visible hasta aprobacion admin.

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  CUIDADOR                                                            │
│    │                                                                 │
│    ▼                                                                 │
│  ┌────────────────┐                                                  │
│  │ PASO 1:        │                                                  │
│  │ Datos basicos  │                                                  │
│  │ ─────────────  │                                                  │
│  │ • Nombre       │                                                  │
│  │ • Apellido     │                                                  │
│  │ • Email        │                                                  │
│  │ • Password     │                                                  │
│  │ • Telefono     │                                                  │
│  │   (+591...)    │                                                  │
│  │                │                                                  │
│  │ [Siguiente →]  │                                                  │
│  └───────┬────────┘                                                  │
│          │                                                           │
│          ▼                                                           │
│  ┌────────────────┐                                                  │
│  │ PASO 2:        │                                                  │
│  │ Tu perfil      │                                                  │
│  │ ─────────────  │                                                  │
│  │ • Bio/descr.   │  "Casa con patio cercado de 50m², tengo 2       │
│  │   (textarea)   │   labradores, vivo sola..."                      │
│  │                │                                                  │
│  │ • Zona         │  ┌──────────────────────┐                        │
│  │   (select)     │  │ Equipetrol         ▾ │                        │
│  │                │  └──────────────────────┘                        │
│  │                │                                                  │
│  │ • Espacio      │  ○ Casa con patio                                │
│  │   (radio)      │  ○ Casa sin patio                                │
│  │                │  ○ Departamento                                  │
│  │                │                                                  │
│  │ [← Atrás] [Siguiente →]                                          │
│  └───────┬────────┘                                                  │
│          │                                                           │
│          ▼                                                           │
│  ┌────────────────┐                                                  │
│  │ PASO 3:        │                                                  │
│  │ Servicios      │                                                  │
│  │ ─────────────  │                                                  │
│  │                │                                                  │
│  │ ¿Que servicios │                                                  │
│  │  ofreces?      │                                                  │
│  │                │                                                  │
│  │ ☑ Hospedaje    │  → Muestra campos de precio:                     │
│  │   Bs [120]/dia │    input numerico, placeholder "ej: 120"         │
│  │                │                                                  │
│  │ ☑ Paseos       │  → Muestra campos de precio:                     │
│  │   30m Bs [40]  │    dos inputs: 30min y 1h                        │
│  │   1h  Bs [60]  │                                                  │
│  │                │                                                  │
│  │ [← Atrás] [Siguiente →]                                          │
│  └───────┬────────┘                                                  │
│          │                                                           │
│          ▼                                                           │
│  ┌────────────────┐                                                  │
│  │ PASO 4:        │                                                  │
│  │ Fotos (4-6)    │                                                  │
│  │ ─────────────  │                                                  │
│  │                │                                                  │
│  │ ┌────┐ ┌────┐ │                                                   │
│  │ │ +  │ │ +  │ │  Drag & drop o click para subir                   │
│  │ │Foto│ │Foto│ │  Validacion: min 4, max 6                         │
│  │ │ 1  │ │ 2  │ │  Formatos: JPG, PNG, WebP                        │
│  │ └────┘ └────┘ │  Max: 5MB por foto                                │
│  │ ┌────┐ ┌────┐ │                                                   │
│  │ │ +  │ │ +  │ │  Primera foto = foto principal del listing        │
│  │ │Foto│ │Foto│ │  El cuidador puede reordenar con drag             │
│  │ │ 3  │ │ 4  │ │                                                   │
│  │ └────┘ └────┘ │                                                   │
│  │                │                                                  │
│  │ La primera foto sera tu                                           │
│  │ foto principal en el listing.                                     │
│  │                │                                                  │
│  │ [← Atrás] [Enviar solicitud]                                     │
│  └───────┬────────┘                                                  │
│          │                                                           │
│          ▼                                                           │
│  ┌────────────────────────────────────────────┐                      │
│  │                                            │                      │
│  │  ✓ Solicitud enviada                       │                      │
│  │                                            │                      │
│  │  Tu perfil esta en revision.               │                      │
│  │  El equipo GARDEN te contactara en         │                      │
│  │  24-48h para coordinar la entrevista       │                      │
│  │  y visita a tu espacio.                    │                      │
│  │                                            │                      │
│  │  Te notificaremos por email y WhatsApp     │                      │
│  │  al +591 7XX-XXXXX                         │                      │
│  │                                            │                      │
│  │  [Ir al inicio]                            │                      │
│  │                                            │                      │
│  └────────────────────────────────────────────┘                      │
│                                                                      │
│  ───────── PROCESO OFFLINE ──────────                                │
│                                                                      │
│  ┌────────────────────────────────────────────┐                      │
│  │ ADMIN (fuera de la app):                   │                      │
│  │                                            │                      │
│  │ 1. Entrevista 1h (presencial o videocall)  │                      │
│  │ 2. Visita domiciliaria 30-45min            │                      │
│  │ 3. Sube fotos verificadas (si necesario)   │                      │
│  │ 4. Decision: Aprobar / Rechazar            │                      │
│  └──────────────────┬─────────────────────────┘                      │
│                     │                                                │
│          ┌──────────┴──────────┐                                     │
│          ▼                    ▼                                      │
│  ┌──────────────┐    ┌──────────────┐                                │
│  │  APROBADO    │    │  RECHAZADO   │                                │
│  │              │    │              │                                │
│  │ • Badge      │    │ • Email con  │                                │
│  │   "Verificado│    │   motivo     │                                │
│  │   por GARDEN"│    │              │                                │
│  │ • Perfil     │    │ • Puede      │                                │
│  │   visible en │    │   re-aplicar │                                │
│  │   listings   │    │   en 30 dias │                                │
│  │ • WhatsApp + │    │              │                                │
│  │   email de   │    │              │                                │
│  │   bienvenida │    │              │                                │
│  └──────────────┘    └──────────────┘                                │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

#### 2.1.1 Wireframe Paso 2 (Mobile)

```
┌───────────────────────────┐
│ [←]  Paso 2 de 4          │
│       ●●◉○                │  ← progress dots
├───────────────────────────┤
│                           │
│  Tu perfil                │
│                           │
│  Sobre ti *               │
│  ┌───────────────────────┐│
│  │ Describe tu espacio,  ││
│  │ tu experiencia con    ││
│  │ mascotas y por que    ││
│  │ te gustaria ser       ││
│  │ cuidador GARDEN...    ││
│  │                       ││
│  │                       ││
│  │              120/500  ││
│  └───────────────────────┘│
│                           │
│  Zona *                   │
│  ┌───────────────────────┐│
│  │ Selecciona tu zona  ▾ ││
│  └───────────────────────┘│
│                           │
│  Tipo de espacio *        │
│                           │
│  ┌───────────────────────┐│
│  │ ○ Casa con patio      ││
│  ├───────────────────────┤│
│  │ ○ Casa sin patio      ││
│  ├───────────────────────┤│
│  │ ○ Departamento        ││
│  └───────────────────────┘│
│                           │
│ ┌───────────────────────┐ │
│ │   [← Atrás]  [Sig. →] │ │
│ └───────────────────────┘ │
└───────────────────────────┘
```

---

### 2.2 Verificacion Admin (US-1.3)

Panel exclusivo para rol ADMIN. No es publico.

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  ADMIN accede a /admin/cuidadores/pendientes                         │
│    │                                                                 │
│    ▼                                                                 │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ Panel Admin > Cuidadores Pendientes (3)                        │  │
│  │                                                                │  │
│  │ ┌──────────────────────────────────────────────────────────┐   │  │
│  │ │ Foto │ María López    │ Equipetrol │ 4 Feb │ [Revisar]  │   │  │
│  │ ├──────┤────────────────┤────────────┤───────┤────────────│   │  │
│  │ │ Foto │ Carlos Pérez   │ Norte      │ 3 Feb │ [Revisar]  │   │  │
│  │ ├──────┤────────────────┤────────────┤───────┤────────────│   │  │
│  │ │ Foto │ Ana Gómez      │ Urbarí     │ 2 Feb │ [Revisar]  │   │  │
│  │ └──────────────────────────────────────────────────────────┘   │  │
│  └────────────────────────────────────────────────────────────────┘  │
│    │                                                                 │
│    │ Admin hace click en [Revisar]                                   │
│    ▼                                                                 │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ Revision: María López                                          │  │
│  │                                                                │  │
│  │ ┌─── Datos ────────────────────────────────────────────────┐   │  │
│  │ │ Email: maria@email.com                                    │   │  │
│  │ │ Telefono: +591 76543210                                   │   │  │
│  │ │ Zona: Equipetrol                                          │   │  │
│  │ │ Espacio: Casa con patio                                   │   │  │
│  │ │ Servicios: Hospedaje (Bs 120/dia), Paseos (30m: Bs 40,   │   │  │
│  │ │            1h: Bs 60)                                     │   │  │
│  │ │ Solicitud: 4 Feb 2026                                     │   │  │
│  │ └──────────────────────────────────────────────────────────┘   │  │
│  │                                                                │  │
│  │ ┌─── Bio ──────────────────────────────────────────────────┐   │  │
│  │ │ "Casa con patio cercado de 50m², tengo 2 labradores..."  │   │  │
│  │ └──────────────────────────────────────────────────────────┘   │  │
│  │                                                                │  │
│  │ ┌─── Fotos (6) ───────────────────────────────────────────┐   │  │
│  │ │ [Foto1] [Foto2] [Foto3] [Foto4] [Foto5] [Foto6]         │   │  │
│  │ │ (click para ampliar)                                      │   │  │
│  │ └──────────────────────────────────────────────────────────┘   │  │
│  │                                                                │  │
│  │ ┌─── Notas internas (solo admin) ─────────────────────────┐   │  │
│  │ │ ┌────────────────────────────────────────────────────┐   │   │  │
│  │ │ │ Entrevista OK. Visita 05/02. Patio amplio,        │   │   │  │
│  │ │ │ perros bien cuidados. Conoce rutas de paseo       │   │   │  │
│  │ │ │ por Equipetrol.                                    │   │   │  │
│  │ │ └────────────────────────────────────────────────────┘   │   │  │
│  │ └──────────────────────────────────────────────────────────┘   │  │
│  │                                                                │  │
│  │  ┌──────────────────┐    ┌──────────────────┐                  │  │
│  │  │  ✓ Aprobar       │    │  ✗ Rechazar      │                  │  │
│  │  │  (verde)         │    │  (rojo)          │                  │  │
│  │  └──────────────────┘    └──────────────────┘                  │  │
│  │                                                                │  │
│  └────────────────────────────────────────────────────────────────┘  │
│    │                                                                 │
│    │ Al aprobar:                                                     │
│    │  1. CaregiverProfile.verified = true                            │
│    │  2. CaregiverProfile.approvedAt = now()                         │
│    │  3. AdminAction log creado                                      │
│    │  4. Perfil visible en /cuidadores                               │
│    │  5. WhatsApp + email al cuidador: "Bienvenido a GARDEN"         │
│    │                                                                 │
│    │ Al rechazar (requiere motivo):                                  │
│    │  1. Email al cuidador con feedback                              │
│    │  2. AdminAction log con reason                                  │
│    │  3. Perfil NO visible                                           │
│    ▼                                                                 │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

### 2.3 Visualizacion Cliente (Flujo Completo de Busqueda)

El flujo critico: cliente abre la app y encuentra un cuidador de confianza.

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  CLIENTE                                                             │
│    │                                                                 │
│    ▼                                                                 │
│  ┌────────────────┐                                                  │
│  │ Landing page / │                                                  │
│  │ Homepage       │                                                  │
│  │                │                                                  │
│  │ CTA: "Buscar   │                                                  │
│  │ cuidadores"    │                                                  │
│  └───────┬────────┘                                                  │
│          │                                                           │
│          ▼                                                           │
│  ┌────────────────┐                                                  │
│  │ /cuidadores    │                                                  │
│  │ (Listing)      │                                                  │
│  │                │                                                  │
│  │ Grid de cards  │  ← Solo cuidadores con verified=true             │
│  │ 12 por pagina  │     y suspended=false                            │
│  └───────┬────────┘                                                  │
│          │                                                           │
│          │ Cliente usa filtros para reducir opciones                  │
│          │                                                           │
│          ▼                                                           │
│  ┌─────────────────────────────────────────┐                         │
│  │  FILTRADO (client-side, inmediato)      │                         │
│  │                                         │                         │
│  │  Servicio: "Hospedaje"                  │                         │
│  │  Zona: "Equipetrol"                     │                         │
│  │  Precio: "Estandar (Bs 100-140)"        │                         │
│  │  Espacio: "Casa con patio"              │                         │
│  │                                         │                         │
│  │  → 3 cuidadores disponibles             │                         │
│  └─────────────────┬───────────────────────┘                         │
│                    │                                                  │
│                    │ Cliente evalua cards                             │
│                    │ (2-3 segundos por card)                          │
│                    │                                                  │
│          ┌─────────┴──────────┐                                      │
│          │                    │                                       │
│          ▼                    ▼                                       │
│  ┌──────────────┐    ┌──────────────┐                                │
│  │  DESCARTA    │    │  INTERESADO  │                                │
│  │              │    │              │                                │
│  │ Razon:       │    │ Click en     │                                │
│  │ • Foto no    │    │ "Ver perfil" │                                │
│  │   inspira    │    │              │                                │
│  │   confianza  │    │              │                                │
│  │ • Zona lejana│    │              │                                │
│  │ • Precio alto│    │              │                                │
│  │ • Sin paseos │    │              │                                │
│  │              │    │              │                                │
│  │ (sigue       │    └──────┬───────┘                                │
│  │  scrolleando)│           │                                        │
│  └──────────────┘           ▼                                        │
│                    ┌──────────────────┐                               │
│                    │ /cuidadores/:id  │                               │
│                    │ (Detalle)        │                               │
│                    │                  │                               │
│                    │ Ve:              │                               │
│                    │ • 4-6 fotos      │                               │
│                    │ • Bio completa   │                               │
│                    │ • Badge verif.   │                               │
│                    │ • Servicios +    │                               │
│                    │   precios        │                               │
│                    │ • Resenas        │                               │
│                    └──────┬───────────┘                               │
│                           │                                          │
│              ┌────────────┴────────────┐                             │
│              │                         │                              │
│              ▼                         ▼                              │
│     ┌──────────────┐          ┌──────────────┐                       │
│     │  DESCARTA    │          │   DECIDE     │                       │
│     │              │          │   RESERVAR   │                       │
│     │ "Depto chico,│          │              │                       │
│     │  mi perro    │          │ Click en     │                       │
│     │  necesita    │          │ "Reservar    │                       │
│     │  patio"      │          │  ahora"      │                       │
│     │              │          │              │                       │
│     │ ← Volver     │          │ → Flujo de   │                       │
│     │   al listing │          │   reserva    │                       │
│     └──────────────┘          │   (fuera de  │                       │
│                               │   este doc)  │                       │
│                               └──────────────┘                       │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

**Metricas clave de este flujo:**
- **Landing → Listing:** < 1 click
- **Listing → Perfil relevante:** < 30 segundos (con filtros)
- **Perfil → Decision (reservar/descartar):** < 60 segundos
- **Total busqueda a reserva:** < 2 minutos (objetivo MVP)

---

## 3. Estilos Tailwind

### 3.1 Design Tokens (CSS custom properties via Tailwind config)

```typescript
// tailwind.config.ts
import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        garden: {
          50:  '#f0fdf4',  // backgrounds sutiles
          100: '#dcfce7',  // hover states
          200: '#bbf7d0',
          300: '#86efac',
          400: '#4ade80',
          500: '#22c55e',  // primary (botones, badges)
          600: '#16a34a',  // primary hover
          700: '#15803d',  // primary active
          800: '#166534',
          900: '#14532d',
          950: '#052e16',  // textos dark
        },
        trust: {
          badge:   '#16a34a',  // verde verificado
          star:    '#f59e0b',  // amarillo estrellas
          warning: '#ef4444',  // rojo errores
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
      },
      aspectRatio: {
        'card': '16 / 9',
        'photo': '4 / 3',
      },
      animation: {
        'skeleton': 'pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite',
      },
    },
  },
  plugins: [],
};

export default config;
```

---

### 3.2 Componentes Clave

#### 3.2.1 Badge "Verificado por GARDEN"

```tsx
// Variante compact (sobre foto en listing card)
interface VerifiedBadgeProps {
  variant: 'compact' | 'full';
}

export function VerifiedBadge({ variant }: VerifiedBadgeProps) {
  if (variant === 'compact') {
    return (
      <span
        className="
          absolute bottom-2 left-2
          inline-flex items-center gap-1
          bg-trust-badge/90 backdrop-blur-sm
          text-white text-xs font-semibold
          px-2.5 py-1 rounded-full
          shadow-sm
        "
        role="status"
        aria-label="Cuidador verificado por GARDEN"
      >
        <svg {/* check icon */} className="w-3.5 h-3.5" aria-hidden="true" />
        Verificado
      </span>
    );
  }

  // Variante full (pagina de detalle)
  return (
    <div
      className="
        inline-flex items-center gap-2
        bg-garden-50 border border-garden-200
        text-garden-800 text-sm font-medium
        px-3 py-1.5 rounded-lg
      "
      role="status"
      aria-label="Cuidador verificado por GARDEN mediante entrevista personal y visita domiciliaria"
    >
      <svg {/* shield-check icon */} className="w-5 h-5 text-trust-badge" aria-hidden="true" />
      <div>
        <span className="font-semibold">Verificado por GARDEN</span>
        <span className="block text-xs text-garden-600">
          Entrevista personal + visita
        </span>
      </div>
    </div>
  );
}
```

#### 3.2.2 CaregiverCard (Listing)

```tsx
import { memo } from 'react';

interface CaregiverCardProps {
  id: string;
  firstName: string;
  lastName: string;
  profilePicture: string;  // Cloudinary URL
  zone: string;
  rating: number;
  reviewCount: number;
  servicesOffered: ('HOSPEDAJE' | 'PASEO')[];
  pricePerDay: number | null;
  pricePerWalk30: number | null;
  pricePerWalk60: number | null;
  verified: boolean;
}

export const CaregiverCard = memo(function CaregiverCard(props: CaregiverCardProps) {
  const {
    id, firstName, lastName, profilePicture, zone,
    rating, reviewCount, servicesOffered,
    pricePerDay, pricePerWalk30, verified,
  } = props;

  // Cloudinary responsive transform
  const thumbUrl = profilePicture.replace(
    '/upload/',
    '/upload/c_fill,w_400,h_225,q_auto,f_auto/'
  );

  return (
    <article
      className="
        group
        bg-white rounded-xl
        border border-gray-200
        shadow-sm hover:shadow-md
        transition-shadow duration-200
        overflow-hidden
        flex flex-col
      "
      aria-label={`Perfil de ${firstName} ${lastName}, cuidador en ${zone}`}
    >
      {/* Foto principal */}
      <div className="relative aspect-card overflow-hidden">
        <img
          src={thumbUrl}
          alt={`Espacio de ${firstName} para cuidado de mascotas`}
          className="
            w-full h-full object-cover
            group-hover:scale-105
            transition-transform duration-300
          "
          loading="lazy"
          decoding="async"
          width={400}
          height={225}
        />
        {verified && <VerifiedBadge variant="compact" />}
      </div>

      {/* Contenido */}
      <div className="p-4 flex flex-col flex-1 gap-2">
        {/* Nombre */}
        <h3 className="text-lg font-semibold text-gray-900 leading-tight">
          {firstName} {lastName}
        </h3>

        {/* Rating + Zona */}
        <div className="flex items-center gap-3 text-sm text-gray-600">
          <span className="inline-flex items-center gap-1" aria-label={`${rating} de 5 estrellas, ${reviewCount} reseñas`}>
            <svg {/* star */} className="w-4 h-4 text-trust-star" aria-hidden="true" />
            <span className="font-medium text-gray-900">{rating.toFixed(1)}</span>
            <span>({reviewCount})</span>
          </span>
          <span className="inline-flex items-center gap-1">
            <svg {/* map-pin */} className="w-4 h-4" aria-hidden="true" />
            {zone}
          </span>
        </div>

        {/* Servicios (chips) */}
        <div className="flex flex-wrap gap-1.5" role="list" aria-label="Servicios ofrecidos">
          {servicesOffered.includes('HOSPEDAJE') && (
            <span role="listitem" className="
              inline-flex items-center gap-1
              bg-blue-50 text-blue-700
              text-xs font-medium
              px-2 py-0.5 rounded-full
            ">
              Hospedaje
            </span>
          )}
          {servicesOffered.includes('PASEO') && (
            <span role="listitem" className="
              inline-flex items-center gap-1
              bg-amber-50 text-amber-700
              text-xs font-medium
              px-2 py-0.5 rounded-full
            ">
              Paseos
            </span>
          )}
        </div>

        {/* Precios */}
        <div className="mt-auto pt-2 text-sm text-gray-700">
          {pricePerDay && (
            <span className="font-semibold text-gray-900">
              Bs {pricePerDay}/dia
            </span>
          )}
          {pricePerDay && pricePerWalk30 && (
            <span className="mx-1.5 text-gray-300">·</span>
          )}
          {pricePerWalk30 && (
            <span>Bs {pricePerWalk30}/paseo</span>
          )}
        </div>

        {/* CTA */}
        <a
          href={`/cuidadores/${id}`}
          className="
            mt-2 block w-full text-center
            bg-garden-500 hover:bg-garden-600
            active:bg-garden-700
            text-white font-medium
            py-2.5 rounded-lg
            transition-colors duration-150
            focus-visible:outline-2 focus-visible:outline-offset-2
            focus-visible:outline-garden-500
          "
        >
          Ver perfil
        </a>
      </div>
    </article>
  );
});
```

#### 3.2.3 Grid de Listing (Responsive)

```tsx
export function CaregiverGrid({ caregivers }: { caregivers: CaregiverCardProps[] }) {
  return (
    <section
      aria-label="Lista de cuidadores verificados"
      className="
        grid
        grid-cols-1
        sm:grid-cols-2
        lg:grid-cols-3
        gap-4 sm:gap-6
      "
    >
      {caregivers.map((c) => (
        <CaregiverCard key={c.id} {...c} />
      ))}
    </section>
  );
}
```

#### 3.2.4 Barra de Filtros (Desktop)

```tsx
export function FilterBar() {
  return (
    <div
      className="
        sticky top-0 z-20
        bg-white/95 backdrop-blur-sm
        border-b border-gray-200
        py-4
      "
      role="search"
      aria-label="Filtros de busqueda de cuidadores"
    >
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-wrap items-center gap-3">
          {/* Cada filtro es un dropdown con Headless UI Listbox o Popover */}
          <FilterDropdown
            label="Servicio"
            icon={HomeIcon}
            options={[
              { value: 'HOSPEDAJE', label: 'Hospedaje' },
              { value: 'PASEO', label: 'Paseos' },
              { value: 'AMBOS', label: 'Ambos' },
            ]}
          />
          <FilterDropdown
            label="Zona"
            icon={MapPinIcon}
            multiple  // permite seleccion multiple
            options={ZONES}
          />
          <FilterDropdown
            label="Precio"
            icon={CurrencyIcon}
            options={PRICE_RANGES}
          />
          <FilterDropdown
            label="Espacio"
            icon={BuildingIcon}
            options={SPACE_TYPES}
            disabled={selectedService === 'PASEO'}
          />

          {/* Limpiar */}
          {hasActiveFilters && (
            <button
              onClick={clearFilters}
              className="
                text-sm text-gray-500 hover:text-gray-700
                underline underline-offset-2
              "
            >
              Limpiar filtros
            </button>
          )}

          {/* Contador */}
          <span className="ml-auto text-sm text-gray-500" aria-live="polite">
            {filteredCount} cuidadores disponibles
          </span>
        </div>
      </div>
    </div>
  );
}
```

#### 3.2.5 Chip de Filtro Individual

```tsx
// Chip activo (filtro seleccionado)
<span className="
  inline-flex items-center gap-1.5
  bg-garden-100 text-garden-800
  border border-garden-300
  text-sm font-medium
  px-3 py-1.5 rounded-full
  cursor-pointer
  hover:bg-garden-200
  transition-colors
">
  Equipetrol
  <button aria-label="Quitar filtro Equipetrol" className="hover:text-garden-900">
    <XMarkIcon className="w-3.5 h-3.5" />
  </button>
</span>

// Chip inactivo (opcion no seleccionada)
<span className="
  inline-flex items-center gap-1.5
  bg-gray-100 text-gray-700
  border border-gray-200
  text-sm font-medium
  px-3 py-1.5 rounded-full
  cursor-pointer
  hover:bg-gray-200
  transition-colors
">
  Norte
</span>
```

#### 3.2.6 Carrusel de Fotos (Mobile - Detalle)

```tsx
export function PhotoCarousel({ photos, caregiverName }: {
  photos: string[];
  caregiverName: string;
}) {
  return (
    <div
      className="relative"
      role="region"
      aria-label={`Galeria de fotos de ${caregiverName}`}
      aria-roledescription="carrusel"
    >
      {/* Scroll container */}
      <div className="
        flex overflow-x-auto
        snap-x snap-mandatory
        scrollbar-hide
        -mx-4 sm:mx-0
      ">
        {photos.map((photo, idx) => (
          <div
            key={idx}
            className="
              snap-center shrink-0
              w-full
            "
            role="group"
            aria-roledescription="slide"
            aria-label={`Foto ${idx + 1} de ${photos.length}`}
          >
            <img
              src={photo.replace(
                '/upload/',
                '/upload/c_fill,w_640,h_480,q_auto,f_auto/'
              )}
              alt={`Espacio de ${caregiverName}, foto ${idx + 1}`}
              className="w-full aspect-photo object-cover"
              loading={idx === 0 ? 'eager' : 'lazy'}
              decoding="async"
            />
          </div>
        ))}
      </div>

      {/* Dot indicators */}
      <div
        className="
          absolute bottom-3 left-1/2 -translate-x-1/2
          flex items-center gap-1.5
        "
        role="tablist"
        aria-label="Indicadores de foto"
      >
        {photos.map((_, idx) => (
          <button
            key={idx}
            role="tab"
            aria-selected={idx === currentIndex}
            aria-label={`Ir a foto ${idx + 1}`}
            className={`
              w-2 h-2 rounded-full transition-all
              ${idx === currentIndex
                ? 'bg-white w-4 shadow-sm'
                : 'bg-white/60'
              }
            `}
          />
        ))}
      </div>
    </div>
  );
}
```

#### 3.2.7 Galeria de Fotos (Desktop - Detalle)

```tsx
export function PhotoGallery({ photos, caregiverName }: {
  photos: string[];
  caregiverName: string;
}) {
  const [activeIndex, setActiveIndex] = useState(0);

  return (
    <div aria-label={`Galeria de fotos de ${caregiverName}`}>
      {/* Foto principal */}
      <div className="
        relative rounded-xl overflow-hidden
        aspect-photo bg-gray-100
      ">
        <img
          src={photos[activeIndex].replace(
            '/upload/',
            '/upload/c_fill,w_800,h_600,q_auto,f_auto/'
          )}
          alt={`Espacio de ${caregiverName}, foto ${activeIndex + 1}`}
          className="w-full h-full object-cover"
          loading="eager"
        />

        {/* Flechas de navegacion */}
        <button
          onClick={() => setActiveIndex(prev => Math.max(0, prev - 1))}
          disabled={activeIndex === 0}
          className="
            absolute left-2 top-1/2 -translate-y-1/2
            bg-white/90 hover:bg-white
            rounded-full p-2 shadow-md
            disabled:opacity-0
            transition-opacity
          "
          aria-label="Foto anterior"
        >
          <ChevronLeftIcon className="w-5 h-5" />
        </button>
        <button
          onClick={() => setActiveIndex(prev => Math.min(photos.length - 1, prev + 1))}
          disabled={activeIndex === photos.length - 1}
          className="
            absolute right-2 top-1/2 -translate-y-1/2
            bg-white/90 hover:bg-white
            rounded-full p-2 shadow-md
            disabled:opacity-0
            transition-opacity
          "
          aria-label="Foto siguiente"
        >
          <ChevronRightIcon className="w-5 h-5" />
        </button>

        {/* Contador */}
        <span className="
          absolute bottom-2 right-2
          bg-black/50 text-white text-xs
          px-2 py-1 rounded-md
        ">
          {activeIndex + 1} / {photos.length}
        </span>
      </div>

      {/* Thumbnails */}
      <div className="flex gap-2 mt-3 overflow-x-auto scrollbar-hide">
        {photos.map((photo, idx) => (
          <button
            key={idx}
            onClick={() => setActiveIndex(idx)}
            className={`
              shrink-0 w-20 h-16 rounded-lg overflow-hidden
              border-2 transition-all
              ${idx === activeIndex
                ? 'border-garden-500 ring-1 ring-garden-500'
                : 'border-transparent opacity-70 hover:opacity-100'
              }
            `}
            aria-label={`Ver foto ${idx + 1}`}
            aria-pressed={idx === activeIndex}
          >
            <img
              src={photo.replace(
                '/upload/',
                '/upload/c_fill,w_120,h_90,q_auto,f_auto/'
              )}
              alt=""
              className="w-full h-full object-cover"
              loading="lazy"
              decoding="async"
            />
          </button>
        ))}
      </div>
    </div>
  );
}
```

#### 3.2.8 Seccion de Resenas

```tsx
export function ReviewCard({ review }: { review: Review }) {
  return (
    <article
      className="
        border-b border-gray-100 last:border-0
        py-4 first:pt-0
      "
      aria-label={`Reseña de ${review.clientName}`}
    >
      <div className="flex items-start gap-3">
        {/* Avatar */}
        <div className="
          w-10 h-10 rounded-full bg-garden-100
          flex items-center justify-center
          text-garden-700 font-semibold text-sm
          shrink-0
        ">
          {review.clientName.charAt(0)}
        </div>

        <div className="flex-1 min-w-0">
          {/* Header */}
          <div className="flex items-center justify-between gap-2">
            <span className="font-medium text-gray-900 text-sm">
              {review.clientName}
            </span>
            <StarRating rating={review.rating} size="sm" />
          </div>

          {/* Meta: tipo servicio + fecha */}
          <div className="flex items-center gap-2 mt-0.5">
            <span className={`
              text-xs px-1.5 py-0.5 rounded
              ${review.serviceType === 'HOSPEDAJE'
                ? 'bg-blue-50 text-blue-600'
                : 'bg-amber-50 text-amber-600'
              }
            `}>
              {review.serviceType === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseo'}
            </span>
            <time className="text-xs text-gray-400" dateTime={review.createdAt}>
              {formatRelativeDate(review.createdAt)}
            </time>
          </div>

          {/* Comentario */}
          <p className="mt-2 text-sm text-gray-700 leading-relaxed">
            {review.comment}
          </p>

          {/* Respuesta del cuidador */}
          {review.caregiverResponse && (
            <div className="
              mt-3 ml-3 pl-3
              border-l-2 border-garden-200
              text-sm text-gray-600
            ">
              <span className="font-medium text-gray-800 block text-xs mb-1">
                Respuesta del cuidador
              </span>
              {review.caregiverResponse}
            </div>
          )}
        </div>
      </div>
    </article>
  );
}
```

#### 3.2.9 Skeleton Loader (Loading State)

```tsx
export function CaregiverCardSkeleton() {
  return (
    <div
      className="bg-white rounded-xl border border-gray-200 overflow-hidden"
      aria-hidden="true"
    >
      {/* Foto skeleton */}
      <div className="aspect-card bg-gray-200 animate-skeleton" />

      <div className="p-4 space-y-3">
        {/* Nombre */}
        <div className="h-5 bg-gray-200 rounded w-2/3 animate-skeleton" />
        {/* Rating + zona */}
        <div className="h-4 bg-gray-200 rounded w-1/2 animate-skeleton" />
        {/* Chips */}
        <div className="flex gap-2">
          <div className="h-5 bg-gray-200 rounded-full w-20 animate-skeleton" />
          <div className="h-5 bg-gray-200 rounded-full w-16 animate-skeleton" />
        </div>
        {/* Precio */}
        <div className="h-4 bg-gray-200 rounded w-1/3 animate-skeleton" />
        {/* Boton */}
        <div className="h-10 bg-gray-200 rounded-lg animate-skeleton" />
      </div>
    </div>
  );
}

export function CaregiverGridSkeleton({ count = 6 }: { count?: number }) {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
      {Array.from({ length: count }).map((_, i) => (
        <CaregiverCardSkeleton key={i} />
      ))}
    </div>
  );
}
```

#### 3.2.10 Empty State (Sin Resultados)

```tsx
export function NoResultsState({ onClearFilters }: { onClearFilters: () => void }) {
  return (
    <div className="
      text-center py-16 px-4
    ">
      <div className="
        w-16 h-16 mx-auto mb-4
        bg-gray-100 rounded-full
        flex items-center justify-center
      ">
        <MagnifyingGlassIcon className="w-8 h-8 text-gray-400" />
      </div>
      <h3 className="text-lg font-semibold text-gray-900 mb-2">
        No encontramos cuidadores
      </h3>
      <p className="text-sm text-gray-500 max-w-sm mx-auto mb-6">
        Intenta con otros filtros o amplia tu busqueda a mas zonas.
      </p>
      <button
        onClick={onClearFilters}
        className="
          text-garden-600 hover:text-garden-700
          font-medium text-sm
          underline underline-offset-2
        "
      >
        Limpiar todos los filtros
      </button>
    </div>
  );
}
```

#### 3.2.11 Sidebar Sticky (Desktop - Pagina Detalle)

```tsx
export function BookingSidebar({ caregiver }: { caregiver: CaregiverDetail }) {
  return (
    <aside className="
      sticky top-24
      bg-white rounded-xl
      border border-gray-200
      shadow-sm
      p-6
      space-y-4
    ">
      {/* Precios */}
      <div className="space-y-1">
        {caregiver.pricePerDay && (
          <div className="flex items-baseline gap-1">
            <span className="text-2xl font-bold text-gray-900">
              Bs {caregiver.pricePerDay}
            </span>
            <span className="text-gray-500">/dia</span>
          </div>
        )}
        {caregiver.pricePerWalk30 && (
          <p className="text-sm text-gray-600">
            Paseo 30min: Bs {caregiver.pricePerWalk30}
            {caregiver.pricePerWalk60 && ` · 1h: Bs ${caregiver.pricePerWalk60}`}
          </p>
        )}
      </div>

      <hr className="border-gray-100" />

      {/* Selector servicio */}
      <fieldset>
        <legend className="text-sm font-medium text-gray-700 mb-2">
          Selecciona servicio
        </legend>
        <div className="space-y-2">
          {caregiver.servicesOffered.includes('HOSPEDAJE') && (
            <label className="
              flex items-center gap-3 p-3
              border border-gray-200 rounded-lg
              cursor-pointer
              has-[:checked]:border-garden-500
              has-[:checked]:bg-garden-50
              transition-colors
            ">
              <input type="radio" name="service" value="HOSPEDAJE"
                className="text-garden-500 focus:ring-garden-500" />
              <span className="text-sm font-medium">Hospedaje</span>
            </label>
          )}
          {caregiver.servicesOffered.includes('PASEO') && (
            <label className="
              flex items-center gap-3 p-3
              border border-gray-200 rounded-lg
              cursor-pointer
              has-[:checked]:border-garden-500
              has-[:checked]:bg-garden-50
              transition-colors
            ">
              <input type="radio" name="service" value="PASEO"
                className="text-garden-500 focus:ring-garden-500" />
              <span className="text-sm font-medium">Paseos</span>
            </label>
          )}
        </div>
      </fieldset>

      {/* CTA */}
      <a
        href={`/reservar/${caregiver.id}`}
        className="
          block w-full text-center
          bg-garden-500 hover:bg-garden-600
          active:bg-garden-700
          text-white font-semibold
          py-3 rounded-lg
          transition-colors
          focus-visible:outline-2 focus-visible:outline-offset-2
          focus-visible:outline-garden-500
        "
      >
        Reservar ahora
      </a>

      <hr className="border-gray-100" />

      {/* Info rapida */}
      <dl className="space-y-2 text-sm">
        <div className="flex items-center gap-2">
          <dt className="sr-only">Rating</dt>
          <dd className="inline-flex items-center gap-1">
            <StarIcon className="w-4 h-4 text-trust-star" />
            <span className="font-medium">{caregiver.rating.toFixed(1)}</span>
            <span className="text-gray-500">· {caregiver.reviewCount} resenas</span>
          </dd>
        </div>
        <div className="flex items-center gap-2 text-gray-600">
          <MapPinIcon className="w-4 h-4 shrink-0" />
          <span>{caregiver.zone}</span>
        </div>
        {caregiver.spaceType && (
          <div className="flex items-center gap-2 text-gray-600">
            <HomeIcon className="w-4 h-4 shrink-0" />
            <span>{formatSpaceType(caregiver.spaceType)}</span>
          </div>
        )}
      </dl>
    </aside>
  );
}
```

#### 3.2.12 CTA Sticky Bottom (Mobile - Pagina Detalle)

```tsx
export function MobileBookingBar({ pricePerDay, caregiverId }: {
  pricePerDay: number | null;
  caregiverId: string;
}) {
  return (
    <div className="
      fixed bottom-0 inset-x-0
      bg-white border-t border-gray-200
      p-4 pb-safe
      z-30
      md:hidden
    ">
      <div className="flex items-center justify-between gap-4">
        {pricePerDay && (
          <div>
            <span className="text-lg font-bold">Bs {pricePerDay}</span>
            <span className="text-gray-500 text-sm">/dia</span>
          </div>
        )}
        <a
          href={`/reservar/${caregiverId}`}
          className="
            flex-1 text-center
            bg-garden-500 hover:bg-garden-600
            text-white font-semibold
            py-3 rounded-lg
          "
        >
          Reservar ahora
        </a>
      </div>
    </div>
  );
}
```

---

### 3.3 Performance Patterns

#### 3.3.1 Lazy Loading de Imagenes

Todas las imagenes del listing usan `loading="lazy"` nativo. La primera foto del carrusel en detalle usa `loading="eager"` (LCP).

```tsx
// Componente wrapper para imagenes de Cloudinary con fallback
export function CloudinaryImage({
  src,
  alt,
  width,
  height,
  transform,
  priority = false,
  className,
}: CloudinaryImageProps) {
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState(false);

  const optimizedSrc = src.replace(
    '/upload/',
    `/upload/${transform}/`
  );

  // Generar srcset para responsive
  const srcSet = [400, 640, 800, 1200]
    .map(w => {
      const t = transform.replace(/w_\d+/, `w_${w}`);
      return `${src.replace('/upload/', `/upload/${t}/`)} ${w}w`;
    })
    .join(', ');

  return (
    <div className={`relative overflow-hidden ${className}`}>
      {/* Placeholder blur */}
      {!loaded && !error && (
        <div className="absolute inset-0 bg-gray-200 animate-skeleton" />
      )}

      {/* Error fallback */}
      {error ? (
        <div className="
          absolute inset-0 bg-gray-100
          flex items-center justify-center
        ">
          <PhotoIcon className="w-8 h-8 text-gray-300" />
        </div>
      ) : (
        <img
          src={optimizedSrc}
          srcSet={srcSet}
          sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
          alt={alt}
          width={width}
          height={height}
          loading={priority ? 'eager' : 'lazy'}
          decoding="async"
          onLoad={() => setLoaded(true)}
          onError={() => setError(true)}
          className={`
            w-full h-full object-cover
            transition-opacity duration-300
            ${loaded ? 'opacity-100' : 'opacity-0'}
          `}
        />
      )}
    </div>
  );
}
```

#### 3.3.2 Virtualizacion del Grid (100+ perfiles)

Para el MVP con <200 cuidadores, el filtrado client-side es viable. Pero si el listing crece, el grid necesita virtualizacion:

```tsx
// Para MVP: renderizar todo (< 200 items)
// Si count > 50 visible, usar react-window:

import { FixedSizeGrid } from 'react-window';

// Solo activar virtualizacion si hay mas de 50 items visibles
const VIRTUALIZATION_THRESHOLD = 50;

export function CaregiverListing({ caregivers }: { caregivers: CaregiverCardProps[] }) {
  if (caregivers.length <= VIRTUALIZATION_THRESHOLD) {
    return <CaregiverGrid caregivers={caregivers} />;
  }

  // Virtualized grid para 100+ items
  return (
    <FixedSizeGrid
      columnCount={columns}       // responsive: 1/2/3
      columnWidth={cardWidth}
      rowCount={Math.ceil(caregivers.length / columns)}
      rowHeight={380}             // altura estimada del card
      height={windowHeight}
      width={containerWidth}
    >
      {({ columnIndex, rowIndex, style }) => {
        const idx = rowIndex * columns + columnIndex;
        if (idx >= caregivers.length) return null;
        return (
          <div style={style} className="p-3">
            <CaregiverCard {...caregivers[idx]} />
          </div>
        );
      }}
    </FixedSizeGrid>
  );
}
```

---

### 3.4 Accesibilidad (ARIA)

#### 3.4.1 Checklist de Accesibilidad Implementada

| Elemento | ARIA / Patron | Implementacion |
|----------|---------------|----------------|
| **Listing grid** | `role="region"` + `aria-label` | Section semantica con label descriptivo |
| **Card** | `<article>` + `aria-label` | Tag semantico con nombre del cuidador |
| **Badge** | `role="status"` + `aria-label` | Descripcion completa del estado |
| **Rating** | `aria-label` con valor numerico | "4.8 de 5 estrellas, 12 resenas" |
| **Carrusel mobile** | `aria-roledescription="carrusel"` | Con slides y controles accesibles |
| **Dot indicators** | `role="tablist"` + `role="tab"` | `aria-selected` en dot activo |
| **Filtros** | `role="search"` + `aria-label` | Grupo con label "Filtros de busqueda" |
| **Contador resultados** | `aria-live="polite"` | Anuncia cambios en # de resultados |
| **Empty state** | Semantico con heading | `<h3>` dentro de contenedor centrado |
| **Foto** | `alt` descriptivo | "Espacio de Maria para cuidado de mascotas" |
| **Skeleton** | `aria-hidden="true"` | Oculto de screen readers |
| **Focus** | `focus-visible:outline` | Outline visible solo con teclado |
| **Botones** | `aria-label` en icon-only buttons | "Foto anterior", "Quitar filtro Equipetrol" |

#### 3.4.2 Keyboard Navigation

```
Tab order en listing:
  1. Filtro Servicio → 2. Filtro Zona → 3. Filtro Precio → 4. Filtro Espacio
  5. Limpiar filtros (si visible) → 6. Primer card → 7. Segundo card → ...

Tab order en detalle:
  1. Boton "Volver" → 2. Galeria (flechas con arrow keys)
  3. Thumbnails → 4. Selector servicio → 5. "Reservar ahora"
  6. Resenas
```

---

## 4. Escalabilidad Visual (V2)

### 4.1 Mejoras Planificadas

| Feature V2 | Complejidad | Impacto en UI | Dependencia |
|------------|-------------|---------------|-------------|
| **Infinite scroll** | Media | Reemplaza paginacion por scroll infinito con `IntersectionObserver` | react-window o tanstack-virtual |
| **Zoom en fotos** | Baja | Lightbox fullscreen con pinch-to-zoom en mobile, click-zoom en desktop | react-medium-image-zoom o similar |
| **Mapa interactivo** | Alta | Vista alternativa: mapa con pins de cuidadores por zona (Mapbox/Google Maps) | Coordenadas GPS en schema |
| **Comparar cuidadores** | Media | Checkbox en cards + bottom bar "Comparar (2)" + tabla side-by-side | Nuevo componente CompareView |
| **Filtros avanzados** | Baja | Chips adicionales: "Acepta gatos", "Tiene otras mascotas", experiencia | Campos nuevos en CaregiverProfile |
| **Galeria con video** | Media | Slot de video corto (15-30s) del cuidador mostrando su espacio | Cloudinary video transforms |
| **Animaciones de transicion** | Baja | Shared element transition de card a detalle (View Transitions API) | Browser support |
| **Favoritos** | Baja | Icono corazon en card, lista "Mis favoritos" en perfil cliente | Tabla Favorite en schema |
| **Ordenar por** | Baja | Dropdown "Ordenar: Precio bajo-alto, Rating, Distancia" | Client-side sort |

### 4.2 Infinite Scroll (Detalle Tecnico V2)

```tsx
// V2: Reemplazar paginacion por infinite scroll
import { useInfiniteQuery } from '@tanstack/react-query';
import { useInView } from 'react-intersection-observer';

export function CaregiverInfiniteList() {
  const { ref: sentinelRef, inView } = useInView({ threshold: 0 });

  const {
    data,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
  } = useInfiniteQuery({
    queryKey: ['caregivers', filters],
    queryFn: ({ pageParam = 1 }) =>
      fetchCaregivers({ ...filters, page: pageParam, limit: 12 }),
    getNextPageParam: (lastPage) =>
      lastPage.pagination.page < lastPage.pagination.pages
        ? lastPage.pagination.page + 1
        : undefined,
  });

  useEffect(() => {
    if (inView && hasNextPage) {
      fetchNextPage();
    }
  }, [inView, hasNextPage]);

  const caregivers = data?.pages.flatMap(p => p.caregivers) ?? [];

  return (
    <>
      <CaregiverGrid caregivers={caregivers} />

      {/* Sentinel element para trigger */}
      <div ref={sentinelRef} className="h-1" />

      {isFetchingNextPage && (
        <div className="py-8">
          <CaregiverGridSkeleton count={3} />
        </div>
      )}
    </>
  );
}
```

### 4.3 Lightbox con Zoom (Detalle Tecnico V2)

```tsx
// V2: Fullscreen photo viewer con zoom
export function PhotoLightbox({ photos, initialIndex, onClose }: {
  photos: string[];
  initialIndex: number;
  onClose: () => void;
}) {
  return (
    <div
      className="
        fixed inset-0 z-50
        bg-black/95
        flex items-center justify-center
      "
      role="dialog"
      aria-modal="true"
      aria-label="Visor de fotos"
    >
      {/* Header */}
      <div className="absolute top-0 inset-x-0 flex justify-between items-center p-4 z-10">
        <span className="text-white/70 text-sm">
          {currentIndex + 1} / {photos.length}
        </span>
        <button
          onClick={onClose}
          className="text-white/70 hover:text-white p-2"
          aria-label="Cerrar visor"
        >
          <XMarkIcon className="w-6 h-6" />
        </button>
      </div>

      {/* Imagen con zoom */}
      <img
        src={photos[currentIndex].replace(
          '/upload/',
          '/upload/c_limit,w_1200,q_auto,f_auto/'
        )}
        alt=""
        className="
          max-w-full max-h-[85vh]
          object-contain
          select-none
          touch-pinch-zoom
        "
        style={{
          transform: `scale(${zoom})`,
          transition: 'transform 0.2s ease-out',
        }}
        draggable={false}
      />

      {/* Navegacion */}
      {/* ... flechas izq/der ... */}
    </div>
  );
}
```

### 4.4 Preparacion del Schema para V2

Campos que podrian agregarse a `CaregiverProfile` sin romper el MVP actual:

```prisma
model CaregiverProfile {
  // ... campos MVP existentes ...

  // V2: Filtros avanzados
  acceptsCats      Boolean?    // Acepta gatos
  hasOtherPets     Boolean?    // Tiene otras mascotas
  otherPetsInfo    String?     // "2 labradores, 1 gato"
  maxPetsAtOnce    Int?        // Maximo mascotas simultaneas
  experienceYears  Int?        // Anos de experiencia

  // V2: Ubicacion precisa
  latitude         Float?
  longitude        Float?

  // V2: Video
  introVideoUrl    String?

  // V2: Extras
  extraServices    String[]    // ["bano", "entrenamiento_basico", "medicinas"]
}
```

Estos campos son todos `nullable` para no afectar registros MVP existentes. El frontend los ignora si son null y los muestra cuando tienen valor.

---

## 5. Self-Review

### 5.1 Alineacion con Documentacion Tecnica v1.0

| Requirement (Doc Tecnica) | Status | Notas |
|---------------------------|--------|-------|
| Schema `CaregiverProfile` (sec. 5.1) | **Alineado** | Todos los campos del schema se reflejan en la UI: bio, zone, spaceType, photos[], servicesOffered, pricePerDay, pricePerWalk30, pricePerWalk60, verified, rating, reviewCount |
| Schema `User` (sec. 5.1) | **Alineado** | firstName, lastName, profilePicture usados en cards |
| Schema `Review` (sec. 5.1) | **Alineado** | rating, comment, serviceType, caregiverResponse, client relation, createdAt |
| GET /api/caregivers (sec. 4.2.2) | **Alineado** | Query params: service, zone, priceRange, spaceType, page, limit. Response structure matches card data |
| GET /api/caregivers/:id (sec. 4.2.2) | **Alineado** | Detalle incluye: photos[], bio, availability, reviews, todos los precios |
| US-1.2 Registro cuidador (sec. 2.2) | **Alineado** | Formulario multi-step cubre: descripcion, zona, servicios, 4-6 fotos. Estado: "Pendiente verificacion" |
| US-1.3 Verificacion admin (sec. 2.2) | **Alineado** | Panel admin con lista pendientes, boton Aprobar/Rechazar + notas internas + notificacion |
| US-2.1 Lista verificados (sec. 2.2) | **Alineado** | Solo verified=true + suspended=false, card con foto/nombre/zona/rating/precio, badge "Verificado", paginacion 12/pagina |
| US-2.2 Filtro servicio (sec. 2.2) | **Alineado** | Checkbox: Hospedaje/Paseos/Ambos, resultados sin reload, contador |
| US-2.3 Filtro zona (sec. 2.2) | **Alineado** | Dropdown con las 6 zonas especificas, seleccion multiple |
| US-2.4 Filtro precio (sec. 2.2) | **Alineado** | 3 rangos: Economico/Estandar/Premium con montos en Bs |
| US-2.5 Filtro espacio (sec. 2.2) | **Alineado** | 3 opciones, deshabilitado cuando servicio=Paseos |
| US-2.6 Perfil detallado (sec. 2.2) | **Alineado** | Galeria 4+ fotos, descripcion, servicios+precios, resenas+rating, boton Reservar |
| Paginacion 12/pagina (sec. 4.2.2) | **Alineado** | Paginacion clasica en MVP, infinite scroll planificado V2 |

### 5.2 Alineacion con MVP PDF

| Requirement (MVP) | Status | Notas |
|--------------------|--------|-------|
| **Fotos REALES, no stock** | **Alineado** | Alt text dice "Espacio de [nombre]...", guia de 6 fotos con proposito especifico (patio, area dormir, etc.). No se usan placeholders genericos |
| **Badge "Verificado por GARDEN"** | **Alineado** | Dos variantes (compact sobre foto, full en detalle). Incluye sub-texto "Entrevista personal + visita" |
| **Zona visible** | **Alineado** | MapPin icon + nombre de zona en card y detalle |
| **Descripcion especifica** (no "me encantan los animales") | **Alineado** | Textarea con placeholder guia: "Describe tu espacio, tu experiencia..." + limite 500 chars. El counter visible guia al cuidador |
| **Servicios checkboxes** | **Alineado** | Paso 3 del registro con checkboxes Hospedaje/Paseos + campos de precio condicionales |
| **Descarte rapido** por espacio/necesidades | **Alineado** | Card muestra solo datos clave para descarte en 2-3s. Filtro espacio permite pre-filtrar. Tipo de servicio visible con chips color-coded |
| **Proceso operativo ALTO** (entrevista + visita) | **Alineado** | Flujo muestra paso offline post-solicitud. Pantalla de confirmacion aclara "24-48h para coordinar entrevista y visita" |
| **4 filtros unicamente** | **Alineado** | Exactamente 4: Servicio, Zona, Precio, Espacio. No se agregan filtros extras en MVP |
| **Filtro espacio solo para hospedaje** | **Alineado** | Filtro se deshabilita (opacity-50) cuando servicio=Paseos |
| **Precios en Bs (Bolivianos)** | **Alineado** | Todos los precios con prefijo "Bs", rangos de precio del MVP respetados |
| **Subida 4-6 fotos** | **Alineado** | Grid de upload con min 4, max 6. Validacion de formato y tamano |
| **Paseos incluidos en MVP** | **Alineado** | Cards muestran servicios con chips diferenciados. Precios de paseo 30min y 1h visibles. Resenas taggeadas por tipo de servicio |

### 5.3 Errores Detectados y Corregidos

#### Error 1: Filtro de precio no diferenciaba hospedaje vs paseos
- **Detectado:** El MVP PDF define rangos diferentes para hospedaje (Bs 60-100, 100-140, 140+) y paseos (Bs 20-30, 30-50, 50+). Un unico dropdown "Precio" no cubria ambos.
- **Correccion:** El dropdown de precio muestra rangos contextuales segun el servicio seleccionado. Si servicio="Hospedaje", muestra rangos de hospedaje. Si servicio="Paseos", muestra rangos de paseo. Si "Ambos" o sin seleccion, muestra rangos de hospedaje como default (ticket mas alto, mas relevante para conversion).

#### Error 2: Card mostraba demasiada informacion
- **Detectado:** Borrador inicial incluia bio truncada y tipo de espacio en el card. Esto contradecia el principio de "descarte rapido en 2-3 segundos" del MVP.
- **Correccion:** Card simplificado a: foto + badge + nombre + rating + zona + chips servicio + precio. Bio y espacio solo en pagina de detalle.

#### Error 3: Falta de precio paseo 1h en detalle
- **Detectado:** El schema tiene `pricePerWalk60` pero el sidebar de detalle solo mostraba precio 30min.
- **Correccion:** Sidebar ahora muestra ambos: "Paseo 30min: Bs 40 · 1h: Bs 60".

#### Error 4: Lightbox no planificado para fotos
- **Detectado:** En mobile, tap en foto no tenia comportamiento definido. El MVP enfatiza "Ve EXACTAMENTE donde estara su perro" - las fotos necesitan verse en detalle.
- **Correccion:** Tap en foto de carrusel mobile abre lightbox fullscreen con pinch-to-zoom. Planificado como V2 feature pero con placeholder UX definido.

#### Error 5: Filtro espacio no se deshabilitaba
- **Detectado:** El MVP dice explicitamente "solo relevante para hospedaje" y "deshabilitado para Paseos".
- **Correccion:** Implementado `disabled` prop en FilterDropdown cuando servicio="PASEO", con opacity-50 y tooltip "Solo aplica para hospedaje".

### 5.4 Flexibilidad para Cambios de Schema

El diseno esta preparado para absorber cambios sin refactoreo mayor:

| Cambio posible | Impacto en UI | Adaptacion |
|----------------|---------------|------------|
| Agregar campo `acceptsCats` | Minimo | Nuevo chip en card (V2), nuevo filtro |
| Cambiar zonas disponibles | Ninguno | Zonas vienen de constante `ZONES`, un solo punto de cambio |
| Modificar rangos de precio | Ninguno | Rangos vienen de constante `PRICE_RANGES` |
| Agregar campo `introVideoUrl` | Bajo | Slot en galeria para reproducir video |
| Cambiar rating de Float a Int | Ninguno | `.toFixed(1)` sigue funcionando |
| Renombrar `spaceType` valores | Bajo | `formatSpaceType()` centraliza el mapeo |
| Agregar mas fotos (>6) | Ninguno | Galeria ya soporta array de largo variable |
| Nuevos tipos de servicio | Medio | Agregar chip color-coded y filtro, pero estructura esta |

### 5.5 Performance Checklist

| Metrica | Target | Implementacion |
|---------|--------|----------------|
| **LCP (Largest Contentful Paint)** | < 2.5s | Primera foto del listing con `loading="eager"`, Cloudinary f_auto (WebP/AVIF) |
| **FID (First Input Delay)** | < 100ms | Filtros client-side (sin network), React.memo en cards |
| **CLS (Cumulative Layout Shift)** | < 0.1 | `aspect-ratio` en containers de imagen, skeleton con dimensiones fijas |
| **Bundle size** | < 150KB gzipped | Solo Headless UI para dropdowns, sin UI library pesada |
| **Imagenes** | < 50KB por thumb | Cloudinary `q_auto,f_auto` con width limits |
| **Grid render 100+ items** | < 16ms/frame | Virtualizacion con react-window si >50 items visibles |

---

## Apendice: Resumen de Componentes React

```
src/
├── components/
│   ├── caregivers/
│   │   ├── CaregiverCard.tsx          # Card individual del listing
│   │   ├── CaregiverCardSkeleton.tsx  # Loading placeholder
│   │   ├── CaregiverGrid.tsx          # Grid responsive (1/2/3 cols)
│   │   ├── CaregiverGridSkeleton.tsx  # Grid de skeletons
│   │   ├── BookingSidebar.tsx         # Sidebar sticky desktop (detalle)
│   │   ├── MobileBookingBar.tsx       # CTA sticky bottom mobile
│   │   ├── PhotoGallery.tsx           # Galeria desktop (thumb + principal)
│   │   ├── PhotoCarousel.tsx          # Carrusel mobile (swipe)
│   │   ├── ReviewCard.tsx             # Resena individual
│   │   ├── ReviewList.tsx             # Lista de resenas con "ver mas"
│   │   └── VerifiedBadge.tsx          # Badge compact/full
│   ├── filters/
│   │   ├── FilterBar.tsx              # Barra de filtros desktop (sticky)
│   │   ├── FilterBottomSheet.tsx      # Bottom sheet mobile
│   │   ├── FilterDropdown.tsx         # Dropdown individual (Headless UI)
│   │   └── FilterChip.tsx             # Chip activo/inactivo
│   ├── ui/
│   │   ├── CloudinaryImage.tsx        # Wrapper con srcSet + lazy load
│   │   ├── StarRating.tsx             # Estrellas (1-5)
│   │   ├── NoResultsState.tsx         # Empty state
│   │   └── Pagination.tsx             # Paginacion clasica
│   └── registration/
│       ├── CaregiverRegistrationForm.tsx  # Multi-step form wrapper
│       ├── StepBasicInfo.tsx              # Paso 1: datos basicos
│       ├── StepProfile.tsx                # Paso 2: bio, zona, espacio
│       ├── StepServices.tsx               # Paso 3: servicios + precios
│       ├── StepPhotos.tsx                 # Paso 4: upload fotos
│       └── StepConfirmation.tsx           # Pantalla exito post-envio
├── pages/
│   ├── CaregiverListingPage.tsx       # /cuidadores
│   └── CaregiverDetailPage.tsx        # /cuidadores/:id
└── hooks/
    ├── useCaregiverFilters.ts         # Estado de filtros + logica client-side
    ├── useCloudinaryUpload.ts         # Upload a Cloudinary (drag & drop)
    └── useIntersectionObserver.ts     # Para lazy loading / infinite scroll V2
```

---

**FIN DEL DOCUMENTO DE DISENO UI/UX**

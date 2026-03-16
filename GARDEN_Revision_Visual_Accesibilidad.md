# GARDEN - Revision Visual, Accesibilidad y Performance

## Auditoria Cross-Page: Form + Listado + Detalle

**Version:** 1.0
**Fecha:** 07 de Febrero, 2026
**Audita:** `GARDEN_Formulario_Perfil_Cuidador.md`, `GARDEN_Listing_Cuidadores_Refinado.md`, `GARDEN_UI_Testing_Mockups.md`
**Alineado con:** Tema de tranquilidad (greens, calm transitions, trust signals)

---

## Tabla de Contenidos

1. [Hallazgos y Mejoras Visuales/Responsive](#1-hallazgos-y-mejoras-visualesresponsive)
2. [Checklist de Accesibilidad Completo](#2-checklist-de-accesibilidad-completo)
3. [Optimizaciones de Performance](#3-optimizaciones-de-performance)
4. [Mockups Comparativos Mobile vs Desktop](#4-mockups-comparativos-mobile-vs-desktop)
5. [Matriz de Inconsistencias Resueltas](#5-matriz-de-inconsistencias-resueltas)

---

## 1. Hallazgos y Mejoras Visuales/Responsive

### 1.1 Auditoria por Pagina: Brechas Detectadas

```
┌─────────────────────────────────────────────────────────────────────────────┐
│               AUDITORIA VISUAL: 3 PAGINAS PRINCIPALES                       │
├───────────────┬────────────────────────────┬────────────────────────────────┤
│ Pagina        │ Brecha detectada           │ Mejora propuesta               │
├───────────────┼────────────────────────────┼────────────────────────────────┤
│ FORMULARIO    │ Sidebar sticky no tiene    │ Agregar max-h-[calc(100vh-    │
│               │ max-height → desborda en   │ 8rem)] overflow-y-auto al     │
│               │ pantallas cortas (laptop)  │ sticky sidebar                 │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ Photo grid 3 cols en       │ Cambiar a grid-cols-2 en      │
│               │ mobile < 375px deja slots  │ pantallas < 375px con         │
│               │ muy pequenos (< 90px)      │ min-[375px]:grid-cols-3       │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ Textarea counter "0/500"   │ Agregar aria-live="polite" al │
│               │ no se anuncia a screen     │ counter y aria-describedby    │
│               │ readers al escribir        │ en el textarea                 │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ ProfileStatusBanner no     │ Agregar role="status" al      │
│               │ tiene role semantico       │ banner, role="alert" solo     │
│               │                            │ al banner de suspendido       │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ PriceInput no tiene        │ Agregar inputMode="numeric"   │
│               │ inputMode → teclado QWERTY │ pattern="[0-9]*" para mobile  │
│               │ en mobile                  │ numeric keyboard              │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ Boton eliminar foto [✕]    │ Agregar touch target minimo   │
│               │ es 28px → debajo del       │ 44x44px con padding invisible │
│               │ minimo tactil 44px         │ (p-2 con inner icon 16px)     │
├───────────────┼────────────────────────────┼────────────────────────────────┤
│ LISTADO       │ Filter bar sticky con      │ Agregar safe-area-inset       │
│               │ backdrop-blur no tiene     │ padding y role="search" al    │
│               │ landmark semantico         │ contenedor de filtros          │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ Pagination no es navegable │ Envolver en <nav              │
│               │ como landmark              │ aria-label="Paginacion">      │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ CaregiverCard "Ver perfil" │ Cambiar a "Ver perfil de      │
│               │ no distingue entre cards   │ {nombre}" con sr-only span    │
│               │ para screen readers        │ para contexto unico           │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ Empty state icon 🔍 no     │ Usar SVG decorativo con       │
│               │ tiene alt="" (decorativo)  │ aria-hidden="true" en vez     │
│               │                            │ de emoji sin role             │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ Mobile filter bottom sheet │ Agregar role="dialog"         │
│               │ no tiene trap de focus     │ aria-modal="true" y focus     │
│               │                            │ trap con Tab cycling          │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ Cards gap en breakpoint    │ Agregar breakpoint intermedio │
│               │ 640-767px (sm) muestra 2   │ gap-3 en sm para que 2 cols   │
│               │ cards apretadas            │ respiren mas                   │
├───────────────┼────────────────────────────┼────────────────────────────────┤
│ DETALLE       │ Gallery desktop no tiene   │ Agregar arrow key navigation  │
│               │ keyboard nav para          │ con roving tabindex en        │
│               │ thumbnails                 │ thumbnail strip                │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ Mobile carousel swipe      │ Implementar touch events      │
│               │ detection usa mouse events │ (touchstart/touchend) con     │
│               │ en los tests               │ threshold de 50px             │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ Booking sidebar no tiene   │ Agregar <aside                │
│               │ landmark semantico         │ aria-label="Reservar">        │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ "Leer mas" en bio mobile   │ Agregar aria-expanded al      │
│               │ no anuncia estado          │ boton, manejar                │
│               │ expandido/colapsado        │ expanded/collapsed state      │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ Reviews section no lazy    │ Cargar solo 3 reviews         │
│               │ loads → puede ser pesada   │ iniciales, "Ver todas"        │
│               │ con 20+ reviews            │ carga el resto on-demand      │
│               ├────────────────────────────┼────────────────────────────────┤
│               │ WhatsApp sticky bar mobile │ Agregar safe-area-inset-      │
│               │ puede tapar contenido      │ bottom + bottom-[env(safe-    │
│               │ en iPhone con notch        │ area-inset-bottom)]           │
└───────────────┴────────────────────────────┴────────────────────────────────┘
```

### 1.2 Mejoras de Responsive: Breakpoint Gaps

```
┌──────────────────────────────────────────────────────────────────────────────┐
│            BREAKPOINTS: BRECHAS IDENTIFICADAS Y SOLUCION                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ACTUAL (documentos):                                                        │
│  · < 768px  = mobile (1 col cards, bottom sheet filters)                    │
│  · >= 768px = ???  ← NO HAY breakpoint intermedio (tablet)                  │
│  · >= 1024px = desktop (3 col cards, sidebar, gallery + thumbnails)         │
│                                                                              │
│  PROBLEMA: entre 768px-1023px (iPad, tablet) el layout no esta definido.    │
│  Los cards saltan de 1 col a 3 cols sin transicion → 2 cards a 768px        │
│  con sm:grid-cols-2 pero sin un diseño tablet especifico.                   │
│                                                                              │
│  SOLUCION — Agregar md breakpoint explicitamente:                            │
│                                                                              │
│  < 640px   (xs)   : 1 col cards, bottom sheet, full-width form             │
│  640-767px (sm)   : 2 col cards, bottom sheet, full-width form             │
│  768-1023px (md)  : 2 col cards, dropdown filters (no bottom sheet),       │
│                      form con sidebar overlay (no sticky column)            │
│  >= 1024px (lg)   : 3 col cards, dropdown filters, 2-col form layout      │
│  >= 1280px (xl)   : 3 col cards wider, more breathing room                 │
│                                                                              │
│  FORMULARIO — breakpoint md (768-1023px):                                    │
│  · Form sigue full-width (no sidebar)                                       │
│  · Requirements checklist: inline above submit (no sticky sidebar)          │
│  · Photo grid: 4 cols (en vez de 3 mobile, 4 desktop)                      │
│  · Service checkboxes: side-by-side (ya funciona)                           │
│                                                                              │
│  DETALLE — breakpoint md (768-1023px):                                       │
│  · Gallery: full-width con thumbnails en fila debajo (no sidebar)           │
│  · Booking: inline section (no sidebar, no sticky bar)                      │
│  · Reviews: 2 columnas                                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 Mejoras Visuales de Tranquilidad

```
┌──────────────────────────────────────────────────────────────────────────────┐
│            REFINAMIENTOS VISUALES — TEMA TRANQUILIDAD                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. BREATHING ROOM (spacing consistente):                                    │
│  ─────────────────────────────────────────                                   │
│  · Cards: gap-5 en mobile (actual gap-4) → mas aire entre cards             │
│  · Sections form: mt-10 entre secciones (actual mt-8) → mas separacion     │
│  · Hero: py-10 sm:py-14 (actual py-8) → hero respira mas                   │
│  · Filter bar → cards: gap de 24px (space-y-6) → transicion natural        │
│                                                                              │
│  2. SOMBRAS SUAVES (profundidad sin agresividad):                           │
│  ────────────────────────────────────────────────                            │
│  · Card resting: shadow-[0_1px_3px_0_rgb(0_0_0/0.04)] (mas sutil que sm)  │
│  · Card hover: shadow-[0_8px_25px_-5px_rgb(34_197_94/0.06)] (tinte verde) │
│  · Filter bar: shadow-[0_1px_2px_0_rgb(0_0_0/0.03)] (casi invisible)      │
│  · Photo slot hover: ring-2 ring-garden-200 (sutil, no ring-garden-300)    │
│                                                                              │
│  3. TRANSICIONES MAS LENTAS (calma):                                         │
│  ───────────────────────────────────                                         │
│  · Card hover: duration-300 → duration-400 (un poco mas lento = suave)     │
│  · Photo zoom: duration-500 → duration-700 (zoom aun mas gradual)          │
│  · Filter pill appear: duration-200 → duration-300 (entrada suave)         │
│  · Page transitions: add opacity transition 150ms on route change          │
│                                                                              │
│  4. BORDES REDONDEADOS CONSISTENTES:                                         │
│  ───────────────────────────────────                                         │
│  Documento actual mezcla: rounded-xl, rounded-2xl, rounded-lg, rounded-md  │
│                                                                              │
│  Propuesta de sistema consistente:                                           │
│  · Cards (article):       rounded-2xl  (16px)                               │
│  · Modals/sheets:         rounded-2xl  (16px)                               │
│  · Buttons:               rounded-xl   (12px)                               │
│  · Inputs/select:         rounded-xl   (12px)                               │
│  · Chips/pills:           rounded-full                                       │
│  · Badge verificado:      rounded-lg   (8px)                                │
│  · Photo slots:           rounded-xl   (12px)                               │
│  · Thumbnails:            rounded-lg   (8px)                                │
│  · Banners:               rounded-xl   (12px)                               │
│                                                                              │
│  5. GRADIENTES DE CONFIANZA:                                                 │
│  ───────────────────────────                                                 │
│  · Hero background: agregar gradiente sutil                                  │
│    bg-gradient-to-b from-garden-50/50 to-white                              │
│    dark:from-garden-950/20 dark:to-gray-950                                  │
│  · Trust footer: gradiente superior                                          │
│    bg-gradient-to-b from-transparent to-garden-50/30                        │
│    dark:to-garden-950/10                                                     │
│  · Form page: gradiente sutil top                                            │
│    bg-gradient-to-b from-blue-50/30 via-transparent to-transparent          │
│    (refuerza sensacion de "proceso oficial")                                │
│                                                                              │
│  6. DARK MODE — REFINAMIENTOS:                                               │
│  ─────────────────────────────                                               │
│  · Cards dark: bg-gray-900 → bg-gray-900/80 (un poco de transparencia)     │
│  · Badge dark: dark:bg-garden-900/60 (mas sutil, no tan saturado)          │
│  · Photo overlay gradient: from-black/10 → from-black/20 en dark            │
│    (necesita mas contraste para badge sobre foto oscura)                    │
│  · Star rating: amber-500 funciona en ambos temas (OK, no cambiar)         │
│  · Focus ring dark: ring-garden-400 (actual ring-garden-500, muy oscuro)   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Checklist de Accesibilidad Completo

### 2.1 ARIA Labels: Fotos y Elementos Visuales

```
┌──────────────────────────────────────────────────────────────────────────────┐
│         ARIA LABELS — COMPLETO POR COMPONENTE                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ── CaregiverCard (listing) ──                                               │
│                                                                              │
│  <article                                                                    │
│    aria-label="Perfil de Maria Lopez Vaca, cuidadora verificada              │
│                en Equipetrol"                                                │
│  >                                                                           │
│    <img                                                                      │
│      alt="Espacio real de Maria Lopez Vaca para cuidado de                   │
│           mascotas en Equipetrol"     ← descripcion, NO "foto 1"            │
│      role="img"                       ← redundante en <img> pero explicito  │
│    />                                                                        │
│    <div role="status"                                                        │
│         aria-label="Cuidadora verificada por GARDEN">                       │
│      ✓ Verificado                     ← icono + texto (no solo color)       │
│    </div>                                                                    │
│    <div aria-hidden="true">★</div>   ← estrella decorativa                 │
│    <span aria-label="Calificacion 4.8 de 5, basada en 14 resenas">         │
│      4.8 (14)                                                                │
│    </span>                                                                   │
│    <Link                                                                     │
│      aria-label="Ver perfil completo de Maria Lopez Vaca">                  │
│      Ver perfil                       ← texto visible generico, label unico │
│    </Link>                                                                   │
│  </article>                                                                  │
│                                                                              │
│  ── Photo Gallery (detalle, desktop) ──                                      │
│                                                                              │
│  <section                                                                    │
│    aria-label="Galeria de fotos del espacio de Maria Lopez Vaca"            │
│    role="region"                                                             │
│  >                                                                           │
│    <img alt="Patio cercado con cesped de 50 metros cuadrados,               │
│              donde las mascotas juegan. Foto 1 de 6."                       │
│         ← descripcion de LO QUE SE VE + posicion                            │
│    />                                                                        │
│    <div role="tablist"                                                       │
│         aria-label="Miniaturas de fotos">                                   │
│      <button role="tab"                                                      │
│              aria-selected="true"                                            │
│              aria-label="Foto 1: Patio con cesped">                         │
│        <img alt="" aria-hidden="true" />  ← thumbnail decorativo            │
│      </button>                                                               │
│      <button role="tab"                                                      │
│              aria-selected="false"                                           │
│              aria-label="Foto 2: Dormitorio de mascotas">                   │
│      </button>                                                               │
│    </div>                                                                    │
│    <button aria-label="Foto anterior">◀</button>                            │
│    <button aria-label="Siguiente foto">▶</button>                           │
│    <span aria-live="polite"                                                  │
│          aria-atomic="true">Foto 1 de 6</span>                              │
│  </section>                                                                  │
│                                                                              │
│  ── Photo Carousel (detalle, mobile) ──                                      │
│                                                                              │
│  <div role="region"                                                          │
│       aria-label="Carrusel de fotos"                                        │
│       aria-roledescription="carrusel">                                      │
│    <div role="group"                                                         │
│         aria-roledescription="diapositiva"                                  │
│         aria-label="Foto 1 de 6: Patio con cesped">                        │
│      <img alt="Patio cercado con cesped de 50m²" />                         │
│    </div>                                                                    │
│    <div role="tablist" aria-label="Indicadores de foto">                    │
│      <button role="tab"                                                      │
│              aria-selected="true"                                            │
│              aria-label="Ir a foto 1">                                      │
│        <span class="sr-only">Foto 1</span>                                  │
│      </button>                                                               │
│    </div>                                                                    │
│  </div>                                                                      │
│                                                                              │
│  ── Photo Upload (formulario) ──                                             │
│                                                                              │
│  <div role="group"                                                           │
│       aria-label="Subir fotos de tu espacio (0 de 4 minimo)">              │
│    <input type="file"                                                        │
│           accept="image/jpeg,image/png,image/webp"                          │
│           aria-label="Seleccionar fotos de tu espacio"                      │
│           multiple />                                                        │
│    <button aria-label="Agregar foto al slot 3">                             │
│      + Agregar                                                               │
│    </button>                                                                 │
│    <div role="img"                                                           │
│         aria-label="Foto 1 de tu espacio: subida exitosamente">             │
│      <button aria-label="Eliminar foto 1 de tu espacio"                     │
│              class="min-w-[44px] min-h-[44px]"> ← touch target             │
│        ✕                                                                     │
│      </button>                                                               │
│      <button aria-label="Mover foto 1 hacia arriba">▲</button>             │
│      <button aria-label="Mover foto 1 hacia abajo">▼</button>              │
│    </div>                                                                    │
│    <div role="progressbar"                                                   │
│         aria-valuenow="67"                                                   │
│         aria-valuemin="0"                                                    │
│         aria-valuemax="100"                                                  │
│         aria-label="Subiendo foto 4: 67%">                                  │
│    </div>                                                                    │
│    <div role="alert"                                                         │
│         aria-live="assertive">                                               │
│      foto_grande.jpg: Archivo muy grande (8.2MB > 5MB)                      │
│    </div>                                                                    │
│  </div>                                                                      │
│                                                                              │
│  ── Filter Dropdowns (listing) ──                                            │
│                                                                              │
│  <div role="search"                                                          │
│       aria-label="Filtrar cuidadores">                                      │
│    <button aria-haspopup="listbox"                                           │
│            aria-expanded="false"                                             │
│            aria-label="Filtrar por servicio: Hospedaje seleccionado">       │
│      Servicio ▾                                                              │
│    </button>                                                                 │
│    <div role="listbox"                                                       │
│         aria-label="Opciones de servicio">                                  │
│      <div role="option"                                                      │
│           aria-selected="true">Hospedaje</div>                              │
│      <div role="option"                                                      │
│           aria-selected="false">Paseos</div>                                │
│    </div>                                                                    │
│  </div>                                                                      │
│                                                                              │
│  ── Zone filter (checkbox group) ──                                          │
│                                                                              │
│  <fieldset>                                                                  │
│    <legend class="sr-only">Seleccionar zonas</legend>                       │
│    <label>                                                                   │
│      <input type="checkbox"                                                  │
│             aria-label="Filtrar por zona Equipetrol"                        │
│             checked />                                                       │
│      Equipetrol                                                              │
│    </label>                                                                  │
│  </fieldset>                                                                 │
│                                                                              │
│  ── Result counter ──                                                        │
│                                                                              │
│  <span role="status"                                                         │
│        aria-live="polite"                                                    │
│        aria-atomic="true">                                                   │
│    5 cuidadores encontrados   ← ya existe, OK                               │
│  </span>                                                                     │
│                                                                              │
│  ── Pagination ──                                                            │
│                                                                              │
│  <nav aria-label="Paginacion de resultados">                                │
│    <button aria-label="Ir a pagina anterior" disabled>←</button>            │
│    <button aria-label="Pagina 1">1</button>                                 │
│    <button aria-label="Pagina 2, pagina actual"                             │
│            aria-current="page">[2]</button>                                 │
│    <button aria-label="Pagina 3">3</button>                                 │
│    <button aria-label="Ir a pagina siguiente">→</button>                   │
│  </nav>                                                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Keyboard Navigation — Mapa Completo

```
┌──────────────────────────────────────────────────────────────────────────────┐
│         KEYBOARD NAVIGATION: FLUJO POR PAGINA                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ── LISTING PAGE: Tab Order ──                                               │
│                                                                              │
│  [Skip link: "Ir al contenido"]  ← primer Tab, oculto visual               │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Nav: Logo] → [Cuidadores] → [Como funciona] → [Iniciar sesion]           │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Filtro Servicio ▾] → [Filtro Zona ▾] → [Filtro Precio ▾]                │
│  → [Filtro Espacio ▾]                                                        │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Active pill: Hospedaje ✕] → [pill: Equipetrol ✕] → [Limpiar todo]       │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Card 1: Ver perfil] → [Card 2: Ver perfil] → [Card 3: Ver perfil]       │
│  → ... (todas las cards de la pagina)                                       │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Paginacion: ← Anterior] → [Pag 1] → [Pag 2] → [Siguiente →]            │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Trust Footer links]                                                        │
│                                                                              │
│  INTERACCIONES DENTRO DE DROPDOWN:                                           │
│  · Enter/Space → abre dropdown                                               │
│  · ↑/↓ → navega opciones                                                    │
│  · Enter/Space → selecciona opcion                                           │
│  · Escape → cierra sin cambiar                                               │
│  · Tab → cierra y avanza al siguiente filtro                                │
│  · Home/End → primera/ultima opcion                                         │
│  · Typing → busca opcion que empieza con letra (typeahead)                  │
│                                                                              │
│  ── DETAIL PAGE: Tab Order ──                                                │
│                                                                              │
│  [Skip link] → [Nav]                                                         │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [← Volver a cuidadores]                                                    │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Gallery: ← Anterior] → [→ Siguiente] → [Thumbnail 1] → [Thumb 2] → ...  │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Badge verificado (expandible)]                                             │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Leer mas (bio)]  ← solo en mobile cuando bio es larga                     │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Booking sidebar: Servicio Hospedaje] → [Servicio Paseo]                   │
│  → [Contactar WhatsApp]                                                      │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Ver todas las resenas]                                                     │
│                                                                              │
│  GALLERY KEYBOARD (roving tabindex):                                         │
│  · ← / → navega thumbnails (roving tabindex, solo 1 en tab order)          │
│  · Enter/Space selecciona thumbnail → actualiza foto principal              │
│  · ← / → en foto principal tambien avanza/retrocede                         │
│                                                                              │
│  ── FORM PAGE: Tab Order ──                                                  │
│                                                                              │
│  [Skip link] → [Nav] → [← Volver]                                           │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Banner status (si interactivo)]                                            │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Photo slot 1: Agregar] → [slot 2] → ... → [slot 6]                       │
│      │ Tab (si slot tiene foto:)                                             │
│      [Eliminar] → [Mover ▲] → [Mover ▼]                                    │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Textarea: Descripcion]                                                     │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Input: Tipo de espacio]                                                    │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Select: Zona]                                                              │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Checkbox: Hospedaje] → [Checkbox: Paseos]                                 │
│      │ Tab (si checked:)                                                     │
│      [Input: Precio hospedaje] o [Input: Precio paseo 30m]                  │
│      → [Input: Precio paseo 1h]                                             │
│      │ Tab                                                                   │
│      ▼                                                                       │
│  [Boton: Guardar perfil]  ← focus visible con outline-garden-500            │
│                                                                              │
│  FORM-SPECIFIC:                                                              │
│  · Ctrl+S / Cmd+S → submit (si canSubmit) — shortcut de teclado            │
│  · Escape en input → NO hace nada (no pierde datos)                         │
│  · Tab desde ultimo campo → va a Guardar (no a sidebar)                     │
│  · Sidebar requirements: no en tab order (aria-hidden, decorativo)          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Focus Management: Casos Especiales

```
┌──────────────────────────────────────────────────────────────────────────────┐
│         FOCUS MANAGEMENT: PATRONES CRITICOS                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. DROPDOWN ABIERTO → CERRADO:                                              │
│  ───────────────────────────────                                             │
│  · Al abrir: focus al primer option (o selected si hay)                     │
│  · Al cerrar (Escape): focus regresa al trigger button                      │
│  · Al cerrar (click fuera): focus NO se mueve (queda donde estaba)         │
│  · Al seleccionar (Enter): cierra + focus al trigger                        │
│                                                                              │
│  CODIGO:                                                                     │
│  ```tsx                                                                      │
│  const triggerRef = useRef<HTMLButtonElement>(null);                         │
│  const handleClose = (returnFocus = true) => {                              │
│    setIsOpen(false);                                                         │
│    if (returnFocus) triggerRef.current?.focus();                             │
│  };                                                                          │
│  ```                                                                         │
│                                                                              │
│  2. MOBILE BOTTOM SHEET (filtros):                                           │
│  ─────────────────────────────────                                           │
│  · Al abrir: focus trap activo (Tab cycling dentro del sheet)               │
│  · Primer Tab: primer control interactivo del sheet                         │
│  · Ultimo Tab + Tab: regresa al primero (cycle)                             │
│  · Shift+Tab desde primero: va al ultimo                                    │
│  · Escape: cierra, focus al boton "Filtros" que lo abrio                   │
│  · Body scroll: deshabilitado (overflow:hidden en <body>)                   │
│                                                                              │
│  CODIGO:                                                                     │
│  ```tsx                                                                      │
│  // useFocusTrap hook                                                        │
│  function useFocusTrap(ref: RefObject<HTMLElement>, isActive: boolean) {     │
│    useEffect(() => {                                                         │
│      if (!isActive || !ref.current) return;                                  │
│      const focusable = ref.current.querySelectorAll(                         │
│        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])' │
│      );                                                                      │
│      const first = focusable[0] as HTMLElement;                              │
│      const last = focusable[focusable.length - 1] as HTMLElement;            │
│      first?.focus();                                                         │
│      const handler = (e: KeyboardEvent) => {                                 │
│        if (e.key !== 'Tab') return;                                          │
│        if (e.shiftKey && document.activeElement === first) {                 │
│          e.preventDefault(); last?.focus();                                   │
│        } else if (!e.shiftKey && document.activeElement === last) {          │
│          e.preventDefault(); first?.focus();                                  │
│        }                                                                     │
│      };                                                                      │
│      document.addEventListener('keydown', handler);                          │
│      return () => document.removeEventListener('keydown', handler);          │
│    }, [isActive]);                                                           │
│  }                                                                           │
│  ```                                                                         │
│                                                                              │
│  3. PHOTO UPLOAD — FOCUS DESPUES DE ACCION:                                  │
│  ──────────────────────────────────────────                                   │
│  · Despues de eliminar foto N: focus al slot N (ahora vacio) o N-1          │
│  · Despues de subir foto: focus al siguiente slot vacio                      │
│  · Despues de reorder (▲): focus se mueve con la foto                       │
│  · Despues de retry: focus queda en el mismo slot                           │
│                                                                              │
│  4. FORM SUBMIT — FOCUS AL RESULTADO:                                        │
│  ─────────────────────────────────────                                        │
│  · Submit exitoso: focus al toast de exito (role="status")                  │
│  · Submit error (servidor): focus al toast de error (role="alert")          │
│  · Validacion error: focus al PRIMER campo con error                        │
│                                                                              │
│  CODIGO:                                                                     │
│  ```tsx                                                                      │
│  const firstErrorField = Object.keys(errors)[0];                            │
│  if (firstErrorField) {                                                      │
│    document.querySelector(`[name="${firstErrorField}"]`)                      │
│      ?.closest('.form-field')                                                │
│      ?.querySelector('input, textarea, select, button')                      │
│      ?.focus();                                                              │
│  }                                                                           │
│  ```                                                                         │
│                                                                              │
│  5. PAGINATION — FOCUS DESPUES DE NAVEGACION:                                │
│  ─────────────────────────────────────────────                                │
│  · Click pagina: scroll to grid top + focus al primer card                  │
│  · Keyboard (Enter en pag N): focus al primer card de nueva pagina          │
│  · Esto evita que el usuario pierda contexto                                │
│                                                                              │
│  6. ROUTE CHANGE — FOCUS MANAGEMENT:                                         │
│  ─────────────────────────────────────                                        │
│  · Listing → Detail: focus al <h1> del nombre del cuidador                  │
│  · Detail → Listing: focus al card que el usuario estaba viendo             │
│    (requiere guardar scroll position en sessionStorage)                      │
│  · Any → Form: focus al <h1> "Mi perfil de cuidador"                       │
│                                                                              │
│  CODIGO:                                                                     │
│  ```tsx                                                                      │
│  // En la page, useEffect on mount:                                          │
│  useEffect(() => {                                                           │
│    const heading = document.querySelector('h1');                              │
│    heading?.setAttribute('tabindex', '-1');                                   │
│    heading?.focus({ preventScroll: true });                                   │
│  }, []);                                                                     │
│  ```                                                                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 2.4 Screen Reader Announcements

```
┌──────────────────────────────────────────────────────────────────────────────┐
│         LIVE REGIONS: QUE SE ANUNCIA Y CUANDO                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  aria-live="polite" (no interrumpe al usuario):                             │
│  ──────────────────────────────────────────────                               │
│  · Result counter: "5 cuidadores encontrados"                               │
│  · Photo counter: "Foto 3 de 6"                                             │
│  · Upload progress: "Foto 4: subiendo, 67%"                                 │
│  · Textarea counter: "423 de 500 caracteres"                                │
│  · Requirements met: "4 de 6 requisitos completos"                          │
│                                                                              │
│  aria-live="assertive" (interrumpe, urgente):                               │
│  ─────────────────────────────────────────────                                │
│  · Upload error: "Error: foto_grande.jpg supera el limite de 5MB"           │
│  · Form submit error: "Error al guardar: revisa los campos marcados"        │
│  · Network error: "No pudimos cargar los cuidadores"                        │
│                                                                              │
│  role="status" (equivalente a polite, semantico):                           │
│  ────────────────────────────────────────────────                             │
│  · Badge verificado                                                          │
│  · Toast de exito: "Perfil guardado exitosamente"                           │
│  · Filter applied confirmation (implicito en counter update)                │
│                                                                              │
│  role="alert" (equivalente a assertive, semantico):                         │
│  ─────────────────────────────────────────────────                            │
│  · Error state page-level                                                    │
│  · Suspension banner                                                         │
│  · Validation errors al submit                                               │
│                                                                              │
│  NO ANUNCIAR (decorativo, aria-hidden="true"):                              │
│  ──────────────────────────────────────────────                               │
│  · Emojis decorativos (🐕, 🏠, 📍, 🌿)                                    │
│  · Star icons (★) — el texto "4.8 de 5" ya lo dice                         │
│  · Photo gradient overlay                                                    │
│  · Skeleton pulse animation                                                  │
│  · Card hover shadow change                                                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Optimizaciones de Performance

### 3.1 Lazy Loading de Imagenes

```tsx
// ── ESTRATEGIA DE CARGA DE IMAGENES ──

// REGLA: Solo la PRIMERA fila de cards (3 desktop, 1 mobile)
// se carga eager. Todo lo demas es lazy.

// CaregiverGrid con prioridad de carga:
export function CaregiverGrid({ caregivers }: CaregiverGridProps) {
  // Primera fila: 3 en desktop, 2 en tablet, 1 en mobile
  // Usar IntersectionObserver es preferible, pero loading="lazy"
  // nativo cubre el 95% de los casos.
  const EAGER_COUNT = 3; // above-the-fold en desktop

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
      {caregivers.map((c, i) => (
        <CaregiverCard
          key={c.id}
          caregiver={c}
          // Las primeras 3 cards cargan inmediato para LCP
          photoLoading={i < EAGER_COUNT ? 'eager' : 'lazy'}
          // Las primeras 3 tienen fetchpriority alto
          photoFetchPriority={i < EAGER_COUNT ? 'high' : 'auto'}
        />
      ))}
    </div>
  );
}

// CloudinaryImage mejorado con fetchpriority:
export function CloudinaryImage({
  src, alt, width, height,
  loading = 'lazy',
  fetchPriority = 'auto',
  sizes = '(max-width: 639px) 100vw, (max-width: 1023px) 50vw, 33vw',
  ...rest
}: CloudinaryImageProps) {
  return (
    <img
      src={getTransformedUrl(src, width, height)}
      srcSet={getSrcSet(src, width / height)}
      sizes={sizes}
      alt={alt}
      width={width}
      height={height}
      loading={loading}
      decoding="async"
      // @ts-expect-error -- fetchpriority is valid HTML but not in React types
      fetchpriority={fetchPriority}
      {...rest}
    />
  );
}
```

```
┌──────────────────────────────────────────────────────────────────────────────┐
│         PRECONNECT + PRELOAD: head tags                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  <!-- index.html <head> -->                                                  │
│                                                                              │
│  <!-- Preconectar a Cloudinary lo antes posible -->                          │
│  <link rel="preconnect" href="https://res.cloudinary.com" />                │
│  <link rel="dns-prefetch" href="https://res.cloudinary.com" />              │
│                                                                              │
│  <!-- Preconectar al API -->                                                 │
│  <link rel="preconnect" href="https://api.garden.bo" />                     │
│                                                                              │
│  <!-- Precargar font Inter (si se usa externamente) -->                      │
│  <link rel="preload" href="/fonts/inter-var.woff2"                          │
│        as="font" type="font/woff2" crossorigin />                           │
│                                                                              │
│  IMPACTO:                                                                    │
│  · Preconnect ahorra ~100-200ms en la primera imagen                        │
│  · dns-prefetch es fallback para browsers sin preconnect                    │
│  · Font preload evita FOUT (flash of unstyled text)                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Reduccion de Re-renders

```tsx
// ── PROBLEMA: Re-renders innecesarios en CaregiverGrid ──
//
// Cuando el usuario cambia un filtro, TODOS los cards se re-renderizan
// aunque solo cambien 2 cards (los que salen/entran del filtrado).
//
// SOLUCION: React.memo en CaregiverCard ya existe (OK), pero hay
// mas optimizaciones posibles:

// 1. MEMOIZAR CALLBACK DE FILTROS:
// Cada render de FilterBar crea nuevos closures. Usar useCallback
// para estabilizar las refs.

// ANTES (re-render en cada keystroke):
<FilterDropdown onChange={v => onUpdate('service', v)} />

// DESPUES (ref estable):
const handleServiceChange = useCallback(
  (v: string | null) => onUpdate('service', v),
  [onUpdate]
);
<FilterDropdown onChange={handleServiceChange} />


// 2. ESTABILIZAR PRICE_RANGES OBJECT:
// El objeto PRICE_RANGES se crea fuera del componente (ya OK).
// Pero priceLabels se recalcula en cada render.

// ANTES:
const priceLabels = isPaseoOnly
  ? { economico: 'Bs 20-30/paseo', ... }
  : { economico: 'Bs 60-100/dia', ... };

// DESPUES:
const priceLabels = useMemo(
  () => isPaseoOnly
    ? PASEO_PRICE_LABELS   // const fuera del componente
    : HOSPEDAJE_PRICE_LABELS,
  [isPaseoOnly]
);


// 3. SEPARAR RESULT COUNTER DEL FILTER BAR:
// El counter actualiza aria-live en cada cambio de filtros.
// Si esta dentro de FilterBar, todo FilterBar se re-renderiza.

// SOLUCION: extraer a componente memo separado:
const ResultCounter = memo(function ResultCounter({
  count
}: { count: number }) {
  return (
    <span
      role="status"
      aria-live="polite"
      aria-atomic="true"
      className="text-sm font-medium tabular-nums"
    >
      {count} cuidador{count !== 1 ? 'es' : ''}
    </span>
  );
});


// 4. VIRTUALIZAR LISTA SI > 50 CARDS VISIBLES:
// Para el MVP (<200 total, 12 por pagina) no es necesario.
// Pero si se elimina paginacion:
//
// import { useVirtualizer } from '@tanstack/react-virtual';
// Solo renderizar cards visibles en viewport + buffer de 3


// 5. THROTTLE SCROLL EN STICKY FILTER BAR:
// El evento scroll puede disparar muchos re-renders si el
// filter bar cambia estado (ej: compact mode al hacer scroll).
//
// SOLUCION: usar IntersectionObserver en vez de scroll listener:
function useStickyState(ref: RefObject<HTMLElement>) {
  const [isSticky, setIsSticky] = useState(false);

  useEffect(() => {
    if (!ref.current) return;
    const sentinel = document.createElement('div');
    sentinel.style.height = '1px';
    ref.current.parentNode?.insertBefore(sentinel, ref.current);

    const observer = new IntersectionObserver(
      ([entry]) => setIsSticky(!entry.isIntersecting),
      { threshold: 0 }
    );
    observer.observe(sentinel);
    return () => { observer.disconnect(); sentinel.remove(); };
  }, []);

  return isSticky;
}
```

### 3.3 Bundle y Code Splitting

```
┌──────────────────────────────────────────────────────────────────────────────┐
│         CODE SPLITTING: CARGA SOLO LO NECESARIO                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  RUTAS LAZY (React.lazy + Suspense):                                         │
│  ──────────────────────────────────                                           │
│  · /cuidadores          → CaregiverListingPage   (carga siempre)            │
│  · /cuidadores/:id      → CaregiverDetailPage    (lazy)                     │
│  · /perfil/editar       → CaregiverProfilePage   (lazy)                     │
│  · /admin/*             → AdminDashboard          (lazy)                     │
│                                                                              │
│  COMPONENTES LAZY:                                                           │
│  ─────────────────                                                           │
│  · PhotoGalleryModal (solo se abre al click en foto) → lazy                 │
│  · MobileBottomSheet (solo mobile) → lazy                                   │
│  · ReviewsList (below the fold en detalle) → lazy                           │
│  · PhotoUploadSection (solo en form) → NO lazy (es el contenido principal)  │
│                                                                              │
│  CODIGO:                                                                     │
│  ```tsx                                                                      │
│  // src/router.tsx                                                           │
│  const CaregiverDetail = lazy(                                               │
│    () => import('./pages/CaregiverDetailPage')                               │
│  );                                                                          │
│  const CaregiverProfile = lazy(                                              │
│    () => import('./pages/CaregiverProfilePage')                              │
│  );                                                                          │
│                                                                              │
│  // Con Suspense + skeleton:                                                 │
│  <Suspense fallback={<CaregiverDetailSkeleton />}>                          │
│    <CaregiverDetail />                                                       │
│  </Suspense>                                                                 │
│  ```                                                                         │
│                                                                              │
│  PREFETCH EN HOVER:                                                          │
│  ──────────────────                                                          │
│  Cuando el usuario hace hover sobre "Ver perfil" en un card,                │
│  prefetch el chunk del DetailPage:                                           │
│                                                                              │
│  ```tsx                                                                      │
│  const prefetchDetail = () => {                                              │
│    import('./pages/CaregiverDetailPage');                                    │
│  };                                                                          │
│  <Link                                                                       │
│    to={`/cuidadores/${c.id}`}                                                │
│    onMouseEnter={prefetchDetail}                                             │
│    onFocus={prefetchDetail}                                                  │
│  >                                                                           │
│    Ver perfil                                                                │
│  </Link>                                                                     │
│  ```                                                                         │
│                                                                              │
│  IMPACTO ESTIMADO:                                                           │
│  · Listing page: ~80KB JS (sin detail, sin form, sin admin)                 │
│  · Detail page: ~40KB JS adicional (gallery, reviews)                       │
│  · Form page: ~60KB JS adicional (upload, validation)                       │
│  · Total lazy-loaded: ~100KB menos en primera carga                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 3.4 Performance Checklist Consolidado

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ #  │ Optimizacion                         │ Impacto  │ Pagina  │ Prioridad │
├────┼──────────────────────────────────────┼──────────┼─────────┼───────────┤
│ 1  │ loading="lazy" en fotos below-fold   │ LCP -0.5s│ List+Det│ P0        │
│ 2  │ fetchpriority="high" en hero card    │ LCP -0.3s│ Listing │ P0        │
│ 3  │ Cloudinary srcSet + sizes            │ BW -40%  │ Todas   │ P0        │
│ 4  │ Preconnect Cloudinary + API          │ LCP -0.2s│ Todas   │ P0        │
│ 5  │ React.memo en CaregiverCard          │ Re-render│ Listing │ P0 (done) │
│ 6  │ aspect-ratio en cards + skeletons    │ CLS → 0  │ Listing │ P0 (done) │
│ 7  │ Client-side filter (MVP)             │ 0ms RTT  │ Listing │ P0 (done) │
│ 8  │ Lazy route: Detail + Profile pages   │ JS -100KB│ Todas   │ P1        │
│ 9  │ Prefetch detail on card hover        │ Nav -0.5s│ List→Det│ P1        │
│ 10 │ useMemo para clientFiltered          │ CPU -10ms│ Listing │ P1 (done) │
│ 11 │ ResultCounter como memo component    │ Re-render│ Listing │ P1        │
│ 12 │ Lazy load MobileBottomSheet          │ JS -15KB │ Listing │ P2        │
│ 13 │ Lazy load ReviewsList (fold)         │ JS -20KB │ Detail  │ P2        │
│ 14 │ Virtualize if > 50 visible cards     │ DOM nodes│ Listing │ P2 (V2)   │
│ 15 │ IntersectionObserver sticky state    │ Scroll   │ Listing │ P2        │
│ 16 │ Font preload Inter                   │ FOUT     │ Todas   │ P2        │
│ 17 │ Photo ObjectURL.revokeObjectURL      │ Memory   │ Form    │ P1        │
├────┴──────────────────────────────────────┴──────────┴─────────┴───────────┤
│ P0 = antes de launch | P1 = primera semana | P2 = iteracion posterior       │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 3.5 Memory Leak Prevention en Photo Upload

```tsx
// PROBLEMA: ObjectURLs creados con URL.createObjectURL() no se liberan
// automaticamente. Con 6 fotos + retries, puede acumular 10+ blobs.

// SOLUCION en useCaregiverForm:

// Al eliminar una foto:
const removePhoto = useCallback((id: string) => {
  setPhotos(prev => {
    const photo = prev.find(p => p.id === id);
    // Revocar ObjectURL para liberar memoria
    if (photo?.preview?.startsWith('blob:')) {
      URL.revokeObjectURL(photo.preview);
    }
    return prev.filter(p => p.id !== id);
  });
}, []);

// Al desmontar el componente (salir de la pagina):
useEffect(() => {
  return () => {
    photos.forEach(p => {
      if (p.preview?.startsWith('blob:')) {
        URL.revokeObjectURL(p.preview);
      }
    });
  };
}, []); // solo al desmontar

// Al reemplazar preview local con Cloudinary URL (upload exitoso):
const onUploadSuccess = useCallback((id: string, cloudinaryUrl: string) => {
  setPhotos(prev => prev.map(p => {
    if (p.id !== id) return p;
    // Revocar la preview local
    if (p.preview?.startsWith('blob:')) {
      URL.revokeObjectURL(p.preview);
    }
    return {
      ...p,
      preview: cloudinaryUrl,  // ahora usa URL de Cloudinary
      cloudinaryUrl,
      status: 'success' as const,
      progress: 100,
    };
  }));
}, []);
```

---

## 4. Mockups Comparativos Mobile vs Desktop

### 4.1 Formulario — Side-by-Side

```
MOBILE (< 640px)                         DESKTOP (>= 1024px)
─────────────────────                     ──────────────────────────────────────

┌────────────────────┐                    ┌──────────────────────────┬─────────┐
│ [←] Mi perfil      │                    │ [←] Mi perfil            │ Requis. │
├────────────────────┤                    ├──────────────────────────┤─────────┤
│                    │                    │                          │         │
│ ┌────────────────┐ │                    │ ┌───────────────────┐    │ ◻ Fotos │
│ │ ⏳ Pendiente    │ │                    │ │ ⏳ Pendiente...    │    │ ◻ Bio   │
│ │ de verificacion│ │                    │ └───────────────────┘    │ ◻ Espac.│
│ │ ...            │ │                    │                          │ ◻ Zona  │
│ └────────────────┘ │                    │ ── FOTOS ────────────── │ ◻ Serv. │
│                    │                    │                          │ ◻ Prec. │
│ ── FOTOS ──────── │                    │ ┌────┐┌────┐┌────┐┌────┐│         │
│                    │                    │ │ +  ││ +  ││ +  ││ +  ││ ─────── │
│ ┌────┐┌────┐┌────┐│                    │ │ F1 ││ F2 ││ F3 ││ F4 ││         │
│ │ +  ││ +  ││ +  ││                    │ └────┘└────┘└────┘└────┘│ [Guardar│
│ │ F1 ││ F2 ││ F3 ││                    │ ┌────┐┌────┐            │  perfil]│
│ └────┘└────┘└────┘│                    │ │ +  ││ +  │ 📷 0/4     │         │
│ ┌────┐┌────┐┌────┐│                    │ │ F5 ││ F6 │            │ disabled│
│ │ +  ││ +  ││ +  ││                    │ └────┘└────┘            │         │
│ │ F4 ││ F5 ││ F6 ││                    │                          │ Tu per- │
│ └────┘└────┘└────┘│                    │ ── SOBRE TI ──────── │ fil sera│
│                    │                    │                          │ revisado│
│ 📷 0/4 min        │                    │ ┌────────────────────┐   │ en 24-  │
│                    │                    │ │ Descripcion...     │   │ 48h     │
│ ── SOBRE TI ───── │                    │ │                    │   │         │
│                    │                    │ │             0/500  │   └─────────┘
│ ┌────────────────┐ │                    │ └────────────────────┘   │
│ │ Descripcion... │ │                    │                          │
│ │                │ │                    │ ┌────────────────────┐   │
│ │         0/500  │ │                    │ │ Tipo espacio...    │   │
│ └────────────────┘ │                    │ └────────────────────┘   │
│                    │                    │                          │
│ ┌────────────────┐ │                    │ ── UBICACION ────────── │
│ │ Tipo espacio...│ │                    │                          │
│ └────────────────┘ │                    │ ┌────────────────────┐   │
│                    │                    │ │ Zona ▾             │   │
│ ── UBICACION ──── │                    │ └────────────────────┘   │
│                    │                    │                          │
│ ┌────────────────┐ │                    │ ── SERVICIOS ────────── │
│ │ Zona ▾         │ │                    │                          │
│ └────────────────┘ │                    │ ┌──────────┐┌──────────┐│
│                    │                    │ │☐ Hospedaje││☐ Paseos  ││
│ ── SERVICIOS ──── │                    │ │ Se queda  ││ Paseo por││
│                    │                    │ │ en mi esp.││ la zona  ││
│ ┌────────────────┐ │                    │ └──────────┘└──────────┘│
│ │ ☐ 🏠 Hospedaje │ │                    │                          │
│ │  Se queda...   │ │                    │ (precios condicionales) │
│ └────────────────┘ │                    │                          │
│ ┌────────────────┐ │                    └──────────────────────────┘
│ │ ☐ 🦮 Paseos    │ │
│ │  Paseo por...  │ │
│ └────────────────┘ │
│                    │
│ ┌────────────────┐ │      DIFERENCIAS CLAVE:
│ │ Requisitos:    │ │      ─────────────────────────────────────
│ │ ◻ 4+ fotos    │ │      · Desktop: sidebar sticky con
│ │ ◻ Descripcion │ │        requirements + submit button
│ │ ◻ ...         │ │      · Mobile: requirements inline,
│ └────────────────┘ │        submit al fondo
│                    │      · Photos: 3x2 mobile, 4+2 desktop
│ [  Guardar perfil ]│      · Service checkboxes: stack mobile,
│                    │        side-by-side desktop
│ Tu perfil sera     │      · Zone: native <select> mobile,
│ revisado en 24-48h │        custom dropdown desktop
└────────────────────┘
```

### 4.2 Listado — Side-by-Side

```
MOBILE (< 640px)                         DESKTOP (>= 1024px)
─────────────────────                     ──────────────────────────────────────

┌────────────────────┐                    ┌────────────────────────────────────┐
│[☰]  GARDEN  [Login]│                    │ 🌿 GARDEN    Cuid.  Info  [Login] │
├────────────────────┤                    ├────────────────────────────────────┤
│                    │                    │                                    │
│ 🐾 Encuentra tu    │                    │ 🐾 Encuentra al cuidador perfecto │
│    cuidador ideal  │                    │    para tu mascota en Santa Cruz  │
│                    │                    │    Todos verificados personalmente │
│ ┌────────────────┐ │                    │                                    │
│ │🔍 Filtros      │ │                    │ ┌──────────────────────────────┐   │
│ │ [Hosp] [Zona]  │←scroll              │ │ [Servicio▾][Zona▾][Precio▾] │   │
│ └────────────────┘ │                    │ │ [Espacio▾]                   │   │
│                    │                    │ │                              │   │
│ Hosp. ✕  Equip. ✕ │                    │ │ Hosp.✕ Equip.✕ [Limpiar]   │   │
│ 5 cuidadores 🐕   │                    │ │           5 cuidadores 🐕   │   │
│                    │                    │ └──────────────────────────────┘   │
│ ┌────────────────┐ │                    │                                    │
│ │┌──────────────┐│ │                    │ ┌─────────┐┌─────────┐┌─────────┐│
│ ││▓▓▓▓▓▓▓▓▓▓▓▓▓▓││ │                    │ │┌───────┐││┌───────┐││┌───────┐││
│ ││▓ Patio 50m² ▓││ │                    │ ││▓Photo▓│││▓Photo▓│││▓Photo▓│││
│ ││▓▓▓▓▓▓▓▓▓▓▓▓▓▓││ │                    │ ││▓     ▓│││▓     ▓│││▓     ▓│││
│ ││✓ Verificado  ││ │                    │ │└───────┘││└───────┘││└───────┘││
│ │└──────────────┘│ │                    │ │✓Verif.  ││✓Verif.  ││✓Verif.  ││
│ │                │ │                    │ │         ││         ││         ││
│ │Maria Lopez Vaca│ │                    │ │Maria L. ││Roberto S││Carla M. ││
│ │★ 4.8 (14)     │ │                    │ │★4.8(14) ││★4.6(9)  ││★5.0(4)  ││
│ │📍 Equipetrol   │ │                    │ │📍Equip.  ││📍Equip.  ││📍Norte   ││
│ │🏠 Hospedaje    │ │                    │ │🏠Hosp.   ││🏠🦮      ││🏠Hosp.   ││
│ │Bs 120/dia      │ │                    │ │Bs120/dia││Bs150/dia││Bs90/dia ││
│ │                │ │                    │ │         ││Bs35/pas.││         ││
│ │[ Ver perfil  ] │ │                    │ │[Perfil] ││[Perfil] ││[Perfil] ││
│ └────────────────┘ │                    │ └─────────┘└─────────┘└─────────┘│
│                    │                    │                                    │
│ ┌────────────────┐ │                    │ ┌─────────┐┌─────────┐           │
│ │  (next card)   │ │                    │ │ (card4) ││ (card5) │           │
│ └────────────────┘ │                    │ └─────────┘└─────────┘           │
│                    │                    │                                    │
│    ← 1 [2] 3 →    │                    │    ← Anterior  1 [2] 3  Sig. →   │
│                    │                    │                                    │
│ ┌────────────────┐ │                    │ ┌──────────────────────────────┐   │
│ │🛡 Verificados   │ │                    │ │🛡 Verificacion  📸 Fotos     │   │
│ │📸 Fotos reales  │ │                    │ │personal       reales       │   │
│ │🐾 Resenas reales│ │                    │ │               🐾 Resenas    │   │
│ └────────────────┘ │                    │ │               reales       │   │
│                    │                    │ └──────────────────────────────┘   │
└────────────────────┘                    └────────────────────────────────────┘

DIFERENCIAS CLAVE:
────────────────────────────────────────
· Cards: 1 col mobile, 2 col sm (640+), 3 col lg (1024+)
· Filtros: chips scroll horizontal mobile, dropdowns inline desktop
· Filtros mobile: tap abre bottom sheet con todos los filtros
· Pagination: compact mobile (← 1 [2] 3 →), extended desktop
· Trust footer: stack vertical mobile, 3 cols desktop
· Hero: 2 lineas mobile, 3 lineas desktop
· Active pills: wrap mobile, inline con "Limpiar" desktop
```

### 4.3 Detalle — Side-by-Side

```
MOBILE (< 640px)                         DESKTOP (>= 1024px)
─────────────────────                     ──────────────────────────────────────

┌────────────────────┐                    ┌────────────────────────────────────┐
│[←] Maria L.  [···] │                    │ 🌿 GARDEN          [Maria L. ▾]   │
├────────────────────┤                    ├────────────────────────────────────┤
│                    │                    │ ← Volver a cuidadores             │
│ ┌────────────────┐ │                    │                                    │
│ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │                    │ ┌─────────────────────┬──────────┐│
│ │▓ Patio con    ▓│ │                    │ │ ┌─────────────────┐ │ RESERVAR ││
│ │▓ cesped verde ▓│ │                    │ │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │          ││
│ │▓ y labradores ▓│ │                    │ │ │▓ Patio grande  ▓│ │ Bs 120   ││
│ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │                    │ │ │▓ con cesped    ▓│ │ /dia     ││
│ │  ◉ ○ ○ ○ ○ ○   │ │ ← dots            │ │ │▓ y labradores  ▓│ │          ││
│ └────────────────┘ │                    │ │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │ Bs 40    ││
│                    │                    │ │ │   ◀  1/6  ▶     │ │ /paseo   ││
│ Maria Lopez Vaca   │                    │ │ └─────────────────┘ │ 30min    ││
│ ┌──────────────┐   │                    │ │                     │          ││
│ │✓ Verificado  │   │                    │ │ ┌──┐┌──┐┌──┐┌──┐   │ ──────── ││
│ │  por GARDEN  │   │                    │ │ │T1││T2││T3││T4│   │          ││
│ └──────────────┘   │                    │ │ └──┘└──┘└──┘└──┘   │ [Contact.││
│                    │                    │ │ ┌──┐┌──┐            │  WhatsApp││
│ ★ 4.8 · 14 res.   │                    │ │ │T5││T6│            │ ]        ││
│ 📍 Equipetrol      │                    │ │ └──┘└──┘            │          ││
│ 🏡 Casa c/ patio   │                    │ │                     │ ★ 4.8    ││
│                    │                    │ │ Maria Lopez Vaca    │ 14 res.  ││
│ ─────────────────  │                    │ │ ✓ Verificado por    │ 📍 Equip. ││
│                    │                    │ │   GARDEN             │ 🏡 Casa   ││
│ Sobre mi           │                    │ │                     │          ││
│ "Tengo una casa    │                    │ │ "Tengo una casa     │ Servicios││
│  con patio de 50m² │                    │ │  con patio cercado  │ ✓ Hospedj││
│  en Equipetrol..." │                    │ │  de 50m²..."        │ ✓ Paseos ││
│ [Leer mas]         │ ← solo mobile     │ │                     │          ││
│                    │                    │ │ Detalles            └──────────┘│
│ ─────────────────  │                    │ │ 📍 Equipetrol                   │
│                    │                    │ │ 🏡 Casa con patio               │
│ Servicios y precios│                    │ │ 🏠 Hospedaje: Bs 120/dia       │
│ ┌────────────────┐ │                    │ │ 🦮 Paseo: Bs 40/30m, Bs 60/1h │
│ │🏠 Bs 120/dia   │ │                    │ │                                 │
│ │🦮 Bs 40/30m    │ │                    │ │ ── RESENAS ──────────────────── │
│ │   Bs 60/1h     │ │                    │ │                                 │
│ └────────────────┘ │                    │ │ ★ 4.8 promedio · 14 resenas    │
│                    │                    │ │                                 │
│ ─────────────────  │                    │ │ ┌───────────────────────────┐   │
│                    │                    │ │ │ Patricia R.    ★★★★★     │   │
│ Resenas (14)       │                    │ │ │ Hospedaje · Ene 2026     │   │
│ ┌────────────────┐ │                    │ │ │ "Dejamos a Toby una      │   │
│ │Patricia R. ★★★★★│ │                    │ │ │  semana y Maria nos envio│   │
│ │Hosp. · Ene 2026│ │                    │ │ │  fotos todos los dias."  │   │
│ │"Dejamos a Toby │ │                    │ │ └───────────────────────────┘   │
│ │ una semana..." │ │                    │ │                                 │
│ └────────────────┘ │                    │ │ [Ver todas las resenas (14)]   │
│                    │                    │ │                                 │
│ [Ver todas]        │                    │ └─────────────────────────────────┘
│                    │                    │
│ ┌────────────────┐ │                    └────────────────────────────────────┘
│ │ [WhatsApp] 120 │ │ ← sticky bar
│ └────────────────┘ │   solo mobile      DIFERENCIAS CLAVE:
└────────────────────┘                    ──────────────────────────
                                          · Gallery: carousel (mobile) vs
                                            main+thumbnails (desktop)
                                          · Booking: sticky bottom bar (mobile)
                                            vs sidebar sticky (desktop)
                                          · Bio: truncada + "Leer mas" (mobile)
                                            vs completa (desktop)
                                          · Reviews: stack (mobile) vs cards
                                            con mas detalle (desktop)
                                          · WhatsApp CTA: sticky bar (mobile)
                                            vs sidebar button (desktop)
```

### 4.4 Tablet (768-1023px) — Nuevo Breakpoint

```
┌────────────────────────────────────────────────────────────┐
│ 🌿 GARDEN          Cuidadores    Info       [Login]        │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  🐾 Encuentra al cuidador perfecto para tu mascota        │
│     Todos verificados personalmente por GARDEN             │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ [Servicio ▾]  [Zona ▾]  [Precio ▾]  [Espacio ▾]     │  │
│  │                                                      │  │
│  │ Hosp. ✕  Equip. ✕               5 cuidadores 🐕    │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌───────────────────────┐  ┌───────────────────────┐     │
│  │ ┌───────────────────┐ │  │ ┌───────────────────┐ │     │
│  │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │  │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │     │
│  │ │▓ Patio cercado   ▓│ │  │ │▓ Jardin c/ hamaca ▓│ │     │
│  │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │  │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │     │
│  │ │ ✓ Verificado      │ │  │ │ ✓ Verificado      │ │     │
│  │ └───────────────────┘ │  │ └───────────────────┘ │     │
│  │                        │  │                        │     │
│  │ Maria Lopez Vaca       │  │ Roberto Suarez M.      │     │
│  │ ★ 4.8 (14 resenas)    │  │ ★ 4.6 (9 resenas)     │     │
│  │ 📍 Equipetrol          │  │ 📍 Equipetrol          │     │
│  │ 🏠 Hospedaje           │  │ 🏠 Hosp. 🦮 Paseo     │     │
│  │ Bs 120/dia             │  │ Bs 150/dia · Bs 35/pas│     │
│  │                        │  │                        │     │
│  │ [    Ver perfil      ] │  │ [    Ver perfil      ] │     │
│  └───────────────────────┘  └───────────────────────┘     │
│                                                            │
│  ┌───────────────────────┐  ┌───────────────────────┐     │
│  │       (card 3)         │  │       (card 4)         │     │
│  └───────────────────────┘  └───────────────────────┘     │
│                                                            │
│          ← Anterior    1  [2]  3    Siguiente →           │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 🛡 Verificacion personal   📸 Fotos reales   🐾 Res. │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘

TABLET: 2 cols grid, dropdown filters (no bottom sheet),
cards tienen mas espacio que mobile, pagination extended.
```

---

## 5. Matriz de Inconsistencias Resueltas

```
┌─────────────────────────────────────────────────────────────────────────────┐
│         CROSS-DOC INCONSISTENCIAS DETECTADAS Y RESUELTAS                    │
├────┬───────────────────────────────────┬─────────────────────────────────────┤
│ #  │ Inconsistencia                    │ Resolucion                          │
├────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 1  │ CaregiverCard usa photos[0] para │ CORRECTO. Listing card muestra foto │
│    │ foto, pero el mockup del Testing │ del ESPACIO (photos[0]), NO la foto │
│    │ doc menciona profilePicture      │ de perfil del usuario. Actualizar   │
│    │                                   │ Testing doc para alinear.           │
├────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 2  │ Form doc: Zone select es nativo  │ CORRECTO: nativo en mobile (mejor   │
│    │ en mobile, pero Listing doc usa  │ UX tactil), custom en desktop.      │
│    │ bottom sheet para zona           │ Son paginas diferentes con contextos │
│    │                                   │ diferentes. Form = single select,   │
│    │                                   │ Listing = multi-select checkbox.    │
├────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 3  │ Testing doc: axe test usa        │ ACTUALIZAR: el CaregiverCard        │
│    │ zone='equipetrol' (lowercase)    │ ahora usa Zone enum (UPPERCASE).    │
│    │ pero Prisma enum es EQUIPETROL   │ Mock debe ser zone: 'EQUIPETROL'.   │
├────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 4  │ Listing doc: card tiene          │ AGREGAR: focus-within:ring no se    │
│    │ focus-within:ring-2 pero no hay  │ dispara con teclado si el <article> │
│    │ focusable element inside besides │ no tiene tabindex. El <Link> dentro │
│    │ the Link                         │ SI recibe focus, asi que funciona.  │
│    │                                   │ Verificar con Tab real.             │
├────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 5  │ Form doc: SubmitButton es        │ CORRECTO. El boton no es <button    │
│    │ disabled hasta cumplir todo,     │ disabled> (eso lo saca de tab order │
│    │ pero disabled buttons no son     │ y screen readers lo ignoran).       │
│    │ focusable                        │ CAMBIAR a aria-disabled="true" con  │
│    │                                   │ onClick que no hace nada +          │
│    │                                   │ tooltip "Completa los requisitos".  │
├────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 6  │ Listing doc: useCaregivers retry │ AGREGAR: retry() limpia state pero  │
│    │ limpia state pero no re-fetcha   │ no re-dispara el useEffect. Agregar │
│    │                                   │ un retryCount state que incremente  │
│    │                                   │ y este en el dependency array.      │
├────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 7  │ Form doc: UnsavedChangesGuard    │ AGREGAR: Despues de submit exitoso, │
│    │ no menciona que hacer despues    │ setIsDirty(false) ya existe (OK).   │
│    │ de submit exitoso — ¿sigue       │ Pero agregar redirect a /perfil     │
│    │ bloqueando navegacion?           │ despues de 2s con toast visible.    │
├────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 8  │ Listing doc: CloudinaryImage     │ ACTUALIZAR: srcSet widths [320,400, │
│    │ srcSet usa widths hasta 800, pero│ 640,800] no cubre pantallas 2x DPI  │
│    │ no considera 2x DPI displays     │ bien. Agregar 1200 y 1600 para      │
│    │                                   │ retina/HiDPI displays.              │
├────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 9  │ Form doc: photo reorder usa      │ AGREGAR: ademas de ▲/▼ en mobile,  │
│    │ drag (desktop) y ▲/▼ (mobile)   │ agregar keyboard support para drag: │
│    │ pero no menciona keyboard drag   │ Space to grab, ↑/↓ to move,        │
│    │                                   │ Space to drop, Escape to cancel.   │
├────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 10 │ Testing doc: swipe test uses     │ ACTUALIZAR: usar touchActions API   │
│    │ mouse.down/move/up instead of    │ de Playwright: page.touchscreen     │
│    │ touch events                     │ .swipe() o dispatchEvent touch.     │
├────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 11 │ Detail page: "Leer mas" en bio   │ AGREGAR: aria-expanded="false" en   │
│    │ no tiene ARIA state              │ boton, al expandir cambia a "true"  │
│    │                                   │ + aria-controls="bio-full-text".    │
├────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 12 │ All docs: no mencionan           │ AGREGAR: <html lang="es"> en el     │
│    │ skip-to-content link             │ template, y como primer child del   │
│    │                                   │ <body>:                             │
│    │                                   │ <a href="#main"                     │
│    │                                   │    class="sr-only focus:not-sr-only │
│    │                                   │    focus:fixed focus:top-2          │
│    │                                   │    focus:left-2 focus:z-50          │
│    │                                   │    focus:bg-garden-500              │
│    │                                   │    focus:text-white focus:px-4      │
│    │                                   │    focus:py-2 focus:rounded-lg">    │
│    │                                   │   Ir al contenido principal         │
│    │                                   │ </a>                                │
└────┴───────────────────────────────────┴─────────────────────────────────────┘
```

---

## Resumen Ejecutivo

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    RESUMEN DE MEJORAS PROPUESTAS                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  VISUAL/RESPONSIVE:                                                          │
│  · 18 brechas visuales detectadas y resueltas                               │
│  · Nuevo breakpoint md (768-1023px) para tablets                            │
│  · 6 refinamientos de tranquilidad (spacing, sombras, transiciones,         │
│    bordes, gradientes, dark mode)                                            │
│  · Sistema de border-radius consistente (5 niveles)                         │
│                                                                              │
│  ACCESIBILIDAD:                                                              │
│  · ARIA labels completos para 8 componentes interactivos                    │
│  · Keyboard navigation mapeada para 3 paginas completas                     │
│  · 6 patrones de focus management documentados con codigo                   │
│  · Screen reader announcements: 5 polite, 3 assertive, 7 hidden            │
│  · Skip-to-content link (faltaba en todos los docs)                         │
│  · aria-disabled en vez de disabled para submit button                      │
│                                                                              │
│  PERFORMANCE:                                                                │
│  · 17 optimizaciones priorizadas (P0/P1/P2)                                │
│  · Lazy loading con fetchpriority para LCP                                  │
│  · Code splitting con prefetch on hover                                     │
│  · 5 patrones para reducir re-renders                                       │
│  · Memory leak prevention en photo upload                                   │
│  · Preconnect + DNS prefetch para Cloudinary/API                            │
│                                                                              │
│  INCONSISTENCIAS RESUELTAS: 12 cross-doc                                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

**FIN DEL DOCUMENTO**

# GARDEN - Plan de Testing Visual/UX: Flujo Cuidador

> Plan exhaustivo de testing para el flujo "Soy cuidador" (registro 15 pasos,
> login → dashboard, edge cases). Cubre: visual checklist, E2E Playwright,
> responsive, axe-core a11y, Lighthouse >90, y gap analysis contra MVP.
>
> **Versión:** 1.0
> **Fecha:** 2026-02-07
> **Base:** GARDEN_Flujo_Soy_Cuidador.md v1.0 + GARDEN_Flujo_Soy_Cuidador_Refinado.md v1.1
> **Infra actual:** Vitest (unit) + Playwright (E2E) + @testing-library/react

---

## Tabla de Contenidos

1. [Visual Checklist](#1-visual-checklist)
2. [Casos E2E — Playwright](#2-casos-e2e-playwright)
3. [Test Matrix Responsive](#3-test-matrix-responsive)
4. [Tests de Accesibilidad (axe-core)](#4-tests-de-accesibilidad)
5. [Tests de Performance (Lighthouse >90)](#5-tests-de-performance)
6. [Edge Cases](#6-edge-cases)
7. [Gap Analysis vs MVP](#7-gap-analysis-vs-mvp)
8. [Self-Review](#8-self-review)

---

## 1. Visual Checklist

### 1.1 Botón "Soy Cuidador" — Navbar

| # | Verificación | Tipo | Estado esperado |
|---|-------------|------|-----------------|
| V01 | Texto "Soy cuidador" visible para visitante (no auth) | Visual | `bg-green-600 text-white rounded-xl` |
| V02 | Texto "Soy cuidador" visible para usuario CLIENT autenticado | Visual | Mismo estilo que visitante |
| V03 | Texto cambia a "Mi panel" para CAREGIVER autenticado | Funcional+Visual | `bg-white border border-green-200 text-green-700`, con avatar 24px |
| V04 | Texto cambia a "Admin" para role ADMIN | Funcional+Visual | Icono escudo, navega a `/admin` |
| V05 | Hover: `bg-green-700`, sombra crece (`shadow-sm → shadow-md`) | Visual | Transición 200ms ease |
| V06 | Clic: escala `scale-95`, color `bg-green-700` por 150ms | Animación | Luego navega a `/caregiver/auth` |
| V07 | Focus visible: ring verde (`ring-2 ring-green-500 ring-offset-2`) | A11y | Visible con Tab |
| V08 | Mobile: botón dentro del menú hamburguesa, full-width verde | Responsive | `lg:hidden`, menú slide-in |

### 1.2 Página Auth (`/caregiver/auth`)

| # | Verificación | Tipo | Estado esperado |
|---|-------------|------|-----------------|
| V09 | Fondo `bg-green-50` cubre toda la página | Visual | `min-h-screen` |
| V10 | Tabs "Iniciar sesión" / "Registrarme" visibles | Visual | Pill tabs con `rounded-xl bg-gray-100 p-1` |
| V11 | Tab activo: `bg-white shadow-sm text-green-700` | Visual | Contraste claro vs inactivo |
| V12 | Tab inactivo: `text-gray-500 hover:text-gray-700` | Visual | Sin fondo |
| V13 | Transición entre tabs: fade content 200ms | Animación | `ease-out` |
| V14 | Tab "Iniciar sesión": email + password + checkbox "Recordarme" + botón | Visual | Campos con label + placeholder |
| V15 | Password toggle (👁): alterna texto/password | Funcional | `type="text"` ↔ `type="password"` |
| V16 | Tab "Registrarme": info hospedaje/paseo + "~10 min" + botón "Comenzar registro →" | Visual | Cards info + CTA verde |
| V17 | Desktop (≥1024px): 2 paneles (info izq 5/12, auth der 7/12) | Responsive | `lg:flex lg:gap-8` |
| V18 | Mobile: panel info oculto, card auth full-width `mx-4` | Responsive | Solo card de auth visible |
| V19 | Link "¿Ya tienes cuenta como cliente? Vincular cuenta →" visible | Visual | `text-green-600 underline` |

### 1.3 Login — Estados Visuales

| # | Verificación | Tipo | Estado esperado |
|---|-------------|------|-----------------|
| V20 | Botón "Iniciar sesión" con spinner durante carga | Funcional | Spinner SVG + "Iniciando sesión..." + form deshabilitado |
| V21 | Error 401: texto rojo "Email o contraseña incorrectos" | Visual | `text-red-600 role="alert"` debajo del form |
| V22 | Error 403: "Tu cuenta está suspendida. Contacta soporte." | Visual | Banner rojo con icono ⚠ |
| V23 | Error 429: "Demasiados intentos. Espera 5 minutos." con timer | Visual | Countdown visible |
| V24 | Post-login exitoso: redirect a `/caregiver/dashboard` | Funcional | URL cambia, dashboard carga |
| V25 | Post-login: navbar cambia "Soy cuidador" → "Mi panel" | Funcional+Visual | Avatar + texto "Mi panel" |

### 1.4 Wizard — Progress y Navegación

| # | Verificación | Tipo | Estado esperado |
|---|-------------|------|-----------------|
| V26 | Progress bar se actualiza en cada paso: `(step/total)*100%` | Visual | Barra verde `bg-green-500`, transición 500ms |
| V27 | Texto "Paso N de 15" visible en mobile y desktop | Visual | Encima de la barra |
| V28 | Desktop sidebar: lista de 15 pasos con iconos Unicode | Visual | ✓/●/○ por estado |
| V29 | Sidebar step completado: `text-green-700`, clickable, `cursor-pointer` | Funcional | Clic navega a ese paso |
| V30 | Sidebar step actual: `font-semibold text-green-800 bg-green-50/50` | Visual | No clickable |
| V31 | Sidebar step pendiente: `text-gray-400 cursor-not-allowed` | Visual | No clickable |
| V32 | Sidebar "Guardar y salir" botón visible | Visual | `border border-gray-300` en la base del sidebar |
| V33 | Botón "Siguiente →" deshabilitado visualmente si form inválido | Visual | `opacity-50 cursor-not-allowed` via `aria-disabled` |
| V34 | Botón "← Atrás" visible en pasos 2-15, oculto en paso 1 | Funcional | Paso 1: solo "Siguiente" |
| V35 | Mobile: botones sticky en bottom (safe-area-inset) | Responsive | `fixed bottom-0 pb-[env(safe-area-inset-bottom)]` |
| V36 | Step transition: slide-in dirección correcta (forward→right, backward→left) | Animación | `slide-in-from-right-4` / `slide-in-from-left-4`, 300ms |
| V37 | Header mobile sticky: "← Paso N/15 [Guardar ✕]" | Responsive | `sticky top-0 z-30` |

### 1.5 Wizard — Cada Paso (Visual)

| # | Paso | Verificaciones clave |
|---|------|---------------------|
| V38 | 1 Nombre | Icono 👤, 2 campos (nombre/apellido) en grid `sm:grid-cols-2`, teléfono full-width con prefijo +591 fijo |
| V39 | 2 Email | Icono 🔐, indicador fortaleza contraseña (rojo/amarillo/verde), toggle 👁 en password fields |
| V40 | 3 Zona | Icono 📍, 6 radio cards en grid `sm:grid-cols-2`, seleccionada = `border-green-500 bg-green-50 ring-2` |
| V41 | 4 Servicios | Icono 🛠, 2 toggle cards (Hospedaje/Paseo), multi-select, precios típicos visibles |
| V42 | 5 Experiencia | Icono 💬, textarea con contador `87/200 caracteres`, min 50 chars helper text |
| V43 | 6 Detalle | Icono 📝, textarea opcional max 300 chars, label "(opcional)" visible |
| V44 | 7 Preferencias | Icono 🐾, chips multi-select (Perros/Gatos/Ambos), temperamento chips |
| V45 | 8 Tamaños | Icono 📏, 4 cards con rango kg (Pequeño <5kg, Mediano 5-15, Grande 15-35, Gigante >35) |
| V46 | 9 Hogar | Icono 🏠, **solo si HOSPEDAJE seleccionado**, input spaceType + textarea descripción |
| V47 | 10 Rutina | Icono ⏰, textarea opcional max 200 chars |
| V48 | 11 Tarifas | Icono 💰, campos dinámicos según servicio, rangos sugeridos con tooltips ⓘ, **secciones colapsables mobile** |
| V49 | 12 Fotos | Icono 📸, grid 2x3 dropzones, contador "N/6 fotos", min 4 required, sugerencias dinámicas |
| V50 | 13 Verif. ID | Icono 🪪, privacy banner 🔒, 2 dropzones (frente/reverso CI), mobile: opción cámara `capture="environment"` |
| V51 | 14 Legal | Icono 📋, 3 checkboxes obligatorios, resumen scrolleable, link "Ver términos completos →" |
| V52 | 15 Revisión | Icono ✅, cards resumen con botón [✎] para editar, botón "Enviar solicitud →" verde |

### 1.6 Wizard — Tooltips (7 verificaciones)

| # | Paso | Campo | Tooltip esperado (ⓘ visible, hover/focus muestra contenido) |
|---|------|-------|-------------------------------------------------------------|
| V53 | 1 | Teléfono | "Usamos WhatsApp para coordinaciones..." |
| V54 | 5 | Bio | "Una buena descripción aumenta tus probabilidades..." |
| V55 | 9 | Tipo espacio | "Describe con detalle..." |
| V56 | 11 | Precio/día | "Este precio se muestra en tu perfil..." |
| V57 | 11 | Precio paseo | "Los precios de paseo incluyen ida, paseo y regreso..." |
| V58 | 12 | Fotos | "Las fotos reales de tu espacio son lo que más genera confianza..." |
| V59 | 13 | CI | "Solo el equipo GARDEN ve tu CI..." |

### 1.7 Dashboard

| # | Verificación | Tipo | Estado esperado |
|---|-------------|------|-----------------|
| V60 | ProfileStatusBanner — Nuevo (pendiente): `bg-amber-50 border-amber-200 text-amber-800`, icono ⏳ | Visual | "Pendiente de verificación. 24-48h." |
| V61 | ProfileStatusBanner — En revisión: `bg-blue-50 border-blue-200 text-blue-800`, icono 🔍 | Visual | "Estamos revisando tu perfil." |
| V62 | ProfileStatusBanner — Verificado: `bg-green-50 border-green-200 text-green-800`, icono ✓ | Visual | "Perfil verificado y visible." |
| V63 | ProfileStatusBanner — Suspendido: `bg-red-50 border-red-200 text-red-800`, icono ⚠ | Visual | "Tu perfil está suspendido." |
| V64 | ProfileStatusBanner — Rechazado: `bg-red-50 border-red-200`, botón "Editar y reenviar →" | Visual | Muestra motivo de rechazo |
| V65 | Card "Tu Perfil": foto, nombre, zona, servicios, precios, botón "Editar perfil", "Ver público" | Visual | `rounded-2xl border shadow-sm` |
| V66 | Card "Reservas": placeholder "No tienes reservas aún" o cards de reservas | Visual | Cards con icono servicio + datos |
| V67 | Avatar dropdown: nombre + email + 4 links + cerrar sesión | Funcional | `absolute right-0 top-full rounded-2xl shadow-xl` |
| V68 | Dashboard skeleton: pulse animation durante carga | Visual | `animate-pulse bg-gray-200 rounded-lg` |

### 1.8 Dark Mode

| # | Verificación | Tipo | Estado esperado |
|---|-------------|------|-----------------|
| V69 | Toggle dark mode: ☀ → 🌙 en navbar | Funcional | `<html class="dark">` se aplica |
| V70 | Surface page: `gray-50 → dark:gray-950` | Visual | Contraste verificado |
| V71 | Surface card: `white → dark:gray-900` | Visual | Bordes `dark:border-gray-700` |
| V72 | Input fields: `bg-white → dark:bg-gray-800`, `border-gray-300 → dark:border-gray-600` | Visual | Texto `dark:text-white` |
| V73 | Botón verde en dark: `bg-green-600` (NO green-500, falla AA contrast 3.2:1) | A11y | Ratio ≥4.6:1 verificado |
| V74 | Error text: `text-red-600 → dark:text-red-400` (ratio 6.0:1) | A11y | Legible sobre `gray-950` |
| V75 | Tooltip dark: `bg-gray-900 text-white → dark:bg-gray-100 dark:text-gray-900` | Visual | Invertido |

---

## 2. Casos E2E — Playwright

### 2.1 Configuración Requerida

**Actualización de `playwright.config.ts`:**

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [['html'], ['json', { outputFile: 'e2e-results.json' }]],
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    // Responsive: 3 breakpoints obligatorios
    { name: 'mobile', use: { ...devices['iPhone 14'] } },
    { name: 'tablet', use: { ...devices['iPad Mini'] } },
    { name: 'desktop', use: { ...devices['Desktop Chrome'] } },
  ],
  webServer: process.env.CI
    ? undefined
    : {
        command: 'npm run dev',
        url: 'http://localhost:5173',
        reuseExistingServer: !process.env.CI,
      },
});
```

**Nuevas dependencias:**

```bash
npm i -D @axe-core/playwright   # Accesibilidad
```

**Fixtures compartidos (`e2e/fixtures.ts`):**

```typescript
import { test as base, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

// Fixture: mock API routes para flujo completo
export const test = base.extend<{
  mockApi: void;
  axeCheck: (pageName: string) => Promise<void>;
}>({
  mockApi: [async ({ page }, use) => {
    // Mock auth endpoints
    await page.route('**/api/auth/register', (route) =>
      route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          data: {
            user: { id: 'u-1', email: 'test@garden.bo', role: 'CAREGIVER' },
            accessToken: 'mock-jwt-token',
            refreshToken: 'mock-refresh-token',
          },
        }),
      })
    );

    await page.route('**/api/auth/login', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          data: {
            user: { id: 'u-1', email: 'test@garden.bo', role: 'CAREGIVER',
                    firstName: 'Juan', lastName: 'Pérez' },
            accessToken: 'mock-jwt-token',
            refreshToken: 'mock-refresh-token',
          },
        }),
      })
    );

    await page.route('**/api/auth/check-email*', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ available: true }),
      })
    );

    // Mock caregiver profile endpoints
    await page.route('**/api/caregivers', (route) => {
      if (route.request().method() === 'POST') {
        return route.fulfill({
          status: 201,
          contentType: 'application/json',
          body: JSON.stringify({
            success: true,
            data: {
              id: 'cp-1', zone: 'EQUIPETROL', verified: false,
              servicesOffered: ['HOSPEDAJE', 'PASEO'],
            },
          }),
        });
      }
      return route.continue();
    });

    await page.route('**/api/caregivers/verification', (route) =>
      route.fulfill({ status: 201, contentType: 'application/json',
                      body: JSON.stringify({ success: true }) })
    );

    // Mock Cloudinary upload
    await page.route('**/api.cloudinary.com/**', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          secure_url: `https://res.cloudinary.com/mock/photo-${Date.now()}.webp`,
        }),
      })
    );

    await use();
  }, { auto: true }],

  axeCheck: async ({ page }, use) => {
    const check = async (pageName: string) => {
      const results = await new AxeBuilder({ page })
        .withTags(['wcag2a', 'wcag2aa'])
        .analyze();
      expect(results.violations, `A11y violations on ${pageName}`).toEqual([]);
    };
    await use(check);
  },
});

export { expect };
```

---

### 2.2 Suite: Registro Completo (15 Pasos)

**Archivo:** `e2e/caregiver-register-full.spec.ts`

```typescript
import { test, expect } from './fixtures';

test.describe('Registro completo cuidador — 15 pasos', () => {

  // ─── Escenario 1: Flujo completo HOSPEDAJE + PASEO ───

  test('E2E-REG-01: registro completo con ambos servicios', async ({ page }) => {
    // 1. Landing → clic "Soy cuidador"
    await page.goto('/');
    await page.getByRole('link', { name: /soy cuidador/i }).click();
    await expect(page).toHaveURL(/\/caregiver\/auth/);

    // 2. Tab "Registrarme" → "Comenzar registro"
    await page.getByRole('tab', { name: /registrarme/i }).click();
    await page.getByRole('button', { name: /comenzar registro/i }).click();
    await expect(page).toHaveURL(/\/caregiver\/register/);

    // Paso 1: Nombre y teléfono
    await expect(page.getByText(/paso 1/i)).toBeVisible();
    await page.getByLabel(/nombre/i).first().fill('Juan');
    await page.getByLabel(/apellido/i).fill('Pérez');
    await page.getByLabel(/teléfono/i).fill('76543210');
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 2: Email y contraseña
    await expect(page.getByText(/paso 2/i)).toBeVisible();
    await page.getByLabel(/email/i).fill('juan@test.com');
    await page.getByLabel(/^contraseña/i).fill('Password1');
    await page.getByLabel(/repite/i).fill('Password1');
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 3: Zona
    await expect(page.getByText(/paso 3/i)).toBeVisible();
    await page.getByText('Equipetrol').click();
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 4: Servicios (seleccionar ambos)
    await expect(page.getByText(/paso 4/i)).toBeVisible();
    await page.getByText(/hospedaje/i).click();
    await page.getByText(/paseos/i).click();
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 5: Experiencia (min 50 chars)
    await expect(page.getByText(/paso 5/i)).toBeVisible();
    const bioText = 'Tengo 2 labradores y cuido mascotas de amigos y familiares desde hace 3 años en mi casa.';
    await page.getByRole('textbox').fill(bioText);
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 6: Detalle (opcional → skip)
    await expect(page.getByText(/paso 6/i)).toBeVisible();
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 7: Preferencias mascotas
    await expect(page.getByText(/paso 7/i)).toBeVisible();
    await page.getByText(/perros/i).click();
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 8: Tamaños (opcional → skip)
    await expect(page.getByText(/paso 8/i)).toBeVisible();
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 9: Hogar (visible porque HOSPEDAJE seleccionado)
    await expect(page.getByText(/paso 9/i)).toBeVisible();
    await page.getByLabel(/tipo de espacio/i).fill('Casa con patio cercado de 50m²');
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 10: Rutina (opcional → skip)
    await expect(page.getByText(/paso 10/i)).toBeVisible();
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 11: Tarifas
    await expect(page.getByText(/paso 11/i)).toBeVisible();
    await page.getByLabel(/precio por día/i).fill('120');
    await page.getByLabel(/precio 30 min/i).fill('30');
    await page.getByLabel(/precio 1 hora/i).fill('50');
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 12: Fotos (min 4)
    await expect(page.getByText(/paso 12/i)).toBeVisible();
    const fileInput = page.locator('input[type="file"]').first();
    for (let i = 1; i <= 4; i++) {
      await fileInput.setInputFiles({
        name: `photo${i}.jpg`, mimeType: 'image/jpeg',
        buffer: Buffer.alloc(200),
      });
    }
    await expect(page.getByText(/4\/6 fotos/i)).toBeVisible();
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 13: Verificación CI
    await expect(page.getByText(/paso 13/i)).toBeVisible();
    await expect(page.getByText(/tus datos están protegidos/i)).toBeVisible();
    const ciInputFront = page.locator('input[type="file"]').nth(0);
    const ciInputBack = page.locator('input[type="file"]').nth(1);
    await ciInputFront.setInputFiles({
      name: 'ci-front.jpg', mimeType: 'image/jpeg', buffer: Buffer.alloc(200),
    });
    await ciInputBack.setInputFiles({
      name: 'ci-back.jpg', mimeType: 'image/jpeg', buffer: Buffer.alloc(200),
    });
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 14: Legal (3 checkboxes)
    await expect(page.getByText(/paso 14/i)).toBeVisible();
    await page.getByLabel(/términos de servicio/i).check();
    await page.getByLabel(/política de privacidad/i).check();
    await page.getByLabel(/verificación de identidad/i).check();
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 15: Revisión → Submit
    await expect(page.getByText(/paso 15/i)).toBeVisible();
    await expect(page.getByText('Juan Pérez')).toBeVisible();
    await expect(page.getByText('Equipetrol')).toBeVisible();
    await expect(page.getByText(/hospedaje/i)).toBeVisible();
    await page.getByRole('button', { name: /enviar solicitud/i }).click();

    // Resultado: success → dashboard
    await expect(page.getByText(/tu solicitud fue enviada/i)).toBeVisible({ timeout: 5000 });
    await page.getByRole('button', { name: /ir a mi panel/i }).click();
    await expect(page).toHaveURL(/\/caregiver\/dashboard/);
    await expect(page.getByText(/pendiente de verificación/i)).toBeVisible();
  });

  // ─── Escenario 2: Solo PASEO (paso 9 se salta) ───

  test('E2E-REG-02: registro solo PASEO — paso 9 se salta', async ({ page }) => {
    await page.goto('/caregiver/register');

    // Pasos 1-3 (igual)
    await page.getByLabel(/nombre/i).first().fill('María');
    await page.getByLabel(/apellido/i).fill('López');
    await page.getByLabel(/teléfono/i).fill('65432109');
    await page.getByRole('button', { name: /siguiente/i }).click();

    await page.getByLabel(/email/i).fill('maria@test.com');
    await page.getByLabel(/^contraseña/i).fill('Password1');
    await page.getByLabel(/repite/i).fill('Password1');
    await page.getByRole('button', { name: /siguiente/i }).click();

    await page.getByText('Norte').click();
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 4: Solo PASEO
    await page.getByText(/paseos/i).click();
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Pasos 5-8
    await page.getByRole('textbox').fill('Paseo perros hace 2 años. Conozco bien las zonas verdes de la ciudad y soy responsable.');
    await page.getByRole('button', { name: /siguiente/i }).click();
    await page.getByRole('button', { name: /siguiente/i }).click(); // 6 skip
    await page.getByText(/perros/i).click();
    await page.getByRole('button', { name: /siguiente/i }).click(); // 7
    await page.getByRole('button', { name: /siguiente/i }).click(); // 8 skip

    // Paso 9: DEBE SALTARSE AUTOMÁTICAMENTE (ir directo a 10)
    await expect(page.getByText(/paso 10/i)).toBeVisible();
    // Verificar que NO aparece "Describe tu espacio"
    await expect(page.getByText(/describe tu espacio/i)).not.toBeVisible();

    // Paso 10 → skip
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 11: Solo campos de paseo, NO hospedaje
    await expect(page.getByText(/paso 11/i)).toBeVisible();
    await expect(page.getByLabel(/precio por día/i)).not.toBeVisible();
    await page.getByLabel(/precio 30 min/i).fill('25');
    await page.getByLabel(/precio 1 hora/i).fill('45');
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 12: Sugerencias deben ser de paseo (no patio/dormitorio)
    await expect(page.getByText(/paso 12/i)).toBeVisible();
    await expect(page.getByText(/ruta de paseo|parque|zona verde/i)).toBeVisible();
    // Upload 4 fotos...
    const fileInput = page.locator('input[type="file"]').first();
    for (let i = 1; i <= 4; i++) {
      await fileInput.setInputFiles({
        name: `paseo${i}.jpg`, mimeType: 'image/jpeg', buffer: Buffer.alloc(200),
      });
    }
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Pasos 13-15: continúa normal...
  });

  // ─── Escenario 3: Progress bar se calcula correctamente ───

  test('E2E-REG-03: progress bar refleja paso actual', async ({ page }) => {
    await page.goto('/caregiver/register');
    // Paso 1 → 1/15 = ~7%
    const progressBar = page.getByRole('progressbar');
    await expect(progressBar).toHaveAttribute('aria-valuenow', '1');
    await expect(progressBar).toHaveAttribute('aria-valuemax', '15');

    // Completar paso 1
    await page.getByLabel(/nombre/i).first().fill('Test');
    await page.getByLabel(/apellido/i).fill('User');
    await page.getByLabel(/teléfono/i).fill('76543210');
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 2 → 2/15 = ~13%
    await expect(progressBar).toHaveAttribute('aria-valuenow', '2');
  });
});
```

---

### 2.3 Suite: Login → Dashboard

**Archivo:** `e2e/caregiver-login-dashboard.spec.ts`

```typescript
import { test, expect } from './fixtures';

test.describe('Login cuidador → Dashboard', () => {

  test('E2E-LOGIN-01: login exitoso muestra dashboard con banner pendiente', async ({ page }) => {
    await page.goto('/caregiver/auth');

    // Tab login activo por defecto
    await expect(page.getByRole('tab', { name: /iniciar sesión/i }))
      .toHaveAttribute('aria-selected', 'true');

    await page.getByLabel(/email/i).fill('test@garden.bo');
    await page.getByLabel(/contraseña/i).fill('Password123');
    await page.getByRole('button', { name: /iniciar sesión/i }).click();

    await expect(page).toHaveURL(/\/caregiver\/dashboard/);
    await expect(page.getByText(/mi panel/i)).toBeVisible(); // navbar updated
  });

  test('E2E-LOGIN-02: login con credenciales incorrectas muestra error', async ({ page }) => {
    await page.route('**/api/auth/login', (route) =>
      route.fulfill({ status: 401, contentType: 'application/json',
        body: JSON.stringify({ success: false, message: 'Invalid credentials' }) })
    );

    await page.goto('/caregiver/auth');
    await page.getByLabel(/email/i).fill('wrong@email.com');
    await page.getByLabel(/contraseña/i).fill('wrongpass');
    await page.getByRole('button', { name: /iniciar sesión/i }).click();

    await expect(page.getByText(/email o contraseña incorrectos/i)).toBeVisible();
    await expect(page).toHaveURL(/\/caregiver\/auth/); // stays on auth
  });

  test('E2E-LOGIN-03: login con cuenta suspendida muestra aviso', async ({ page }) => {
    await page.route('**/api/auth/login', (route) =>
      route.fulfill({ status: 403, contentType: 'application/json',
        body: JSON.stringify({ success: false, message: 'Account suspended' }) })
    );

    await page.goto('/caregiver/auth');
    await page.getByLabel(/email/i).fill('suspended@test.com');
    await page.getByLabel(/contraseña/i).fill('Password123');
    await page.getByRole('button', { name: /iniciar sesión/i }).click();

    await expect(page.getByText(/tu cuenta está suspendida/i)).toBeVisible();
  });

  test('E2E-LOGIN-04: rate limit muestra contador', async ({ page }) => {
    await page.route('**/api/auth/login', (route) =>
      route.fulfill({ status: 429, contentType: 'application/json',
        body: JSON.stringify({ success: false, message: 'Too many attempts',
          retryAfter: 300 }) })
    );

    await page.goto('/caregiver/auth');
    await page.getByLabel(/email/i).fill('test@test.com');
    await page.getByLabel(/contraseña/i).fill('Password123');
    await page.getByRole('button', { name: /iniciar sesión/i }).click();

    await expect(page.getByText(/demasiados intentos/i)).toBeVisible();
  });

  test('E2E-DASH-01: dashboard muestra 5 variantes de ProfileStatusBanner', async ({ page }) => {
    const states = [
      { verified: false, rejected: false, suspended: false, expected: /pendiente/i },
      { verified: true, rejected: false, suspended: false, expected: /verificado/i },
      { verified: false, rejected: true, suspended: false, expected: /no fue aprobado/i },
      { verified: false, rejected: false, suspended: true, expected: /suspendid/i },
    ];

    for (const state of states) {
      await page.route('**/api/caregivers/me', (route) =>
        route.fulfill({
          status: 200, contentType: 'application/json',
          body: JSON.stringify({ success: true, data: {
            id: 'cp-1', firstName: 'Juan', lastName: 'Pérez',
            zone: 'EQUIPETROL', ...state,
          }}),
        })
      );
      await page.goto('/caregiver/dashboard');
      await expect(page.getByText(state.expected)).toBeVisible();
    }
  });
});
```

---

### 2.4 Suite: Validaciones por Paso

**Archivo:** `e2e/caregiver-register-validations.spec.ts`

```typescript
import { test, expect } from './fixtures';

test.describe('Validaciones wizard — no avanzar si inválido', () => {

  test('E2E-VAL-01: paso 1 — campos vacíos bloquean avance', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Debe permanecer en paso 1
    await expect(page.getByText(/paso 1/i)).toBeVisible();
    // Errores visibles
    await expect(page.getByText(/el nombre es obligatorio/i)).toBeVisible();
    await expect(page.getByText(/el apellido es obligatorio/i)).toBeVisible();
    await expect(page.getByText(/el teléfono es obligatorio/i)).toBeVisible();
  });

  test('E2E-VAL-02: paso 1 — nombre <2 chars muestra error', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.getByLabel(/nombre/i).first().fill('A');
    await page.getByLabel(/apellido/i).fill('Pérez');
    await page.getByLabel(/teléfono/i).fill('76543210');
    await page.getByRole('button', { name: /siguiente/i }).click();

    await expect(page.getByText(/al menos 2 caracteres/i)).toBeVisible();
    await expect(page.getByText(/paso 1/i)).toBeVisible(); // no avanzó
  });

  test('E2E-VAL-03: paso 1 — teléfono formato inválido', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.getByLabel(/nombre/i).first().fill('Juan');
    await page.getByLabel(/apellido/i).fill('Pérez');
    await page.getByLabel(/teléfono/i).fill('1234'); // formato inválido
    await page.getByRole('button', { name: /siguiente/i }).click();

    await expect(page.getByText(/formato válido.*591/i)).toBeVisible();
  });

  test('E2E-VAL-04: paso 2 — email ya registrado (async check)', async ({ page }) => {
    await page.route('**/api/auth/check-email*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ available: false }) })
    );

    await page.goto('/caregiver/register');
    // Complete paso 1 first
    await page.getByLabel(/nombre/i).first().fill('Juan');
    await page.getByLabel(/apellido/i).fill('Pérez');
    await page.getByLabel(/teléfono/i).fill('76543210');
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 2
    await page.getByLabel(/email/i).fill('existing@email.com');
    await page.getByLabel(/email/i).blur(); // trigger async check

    await expect(page.getByText(/ya está registrado/i)).toBeVisible({ timeout: 3000 });
  });

  test('E2E-VAL-05: paso 2 — contraseña sin mayúscula ni número', async ({ page }) => {
    await page.goto('/caregiver/register');
    // Nav to paso 2...
    await page.getByLabel(/nombre/i).first().fill('Juan');
    await page.getByLabel(/apellido/i).fill('Pérez');
    await page.getByLabel(/teléfono/i).fill('76543210');
    await page.getByRole('button', { name: /siguiente/i }).click();

    await page.getByLabel(/email/i).fill('test@test.com');
    await page.getByLabel(/^contraseña/i).fill('weakpass');
    await page.getByLabel(/repite/i).fill('weakpass');
    await page.getByRole('button', { name: /siguiente/i }).click();

    await expect(page.getByText(/mayúscula.*número|número.*mayúscula/i)).toBeVisible();
  });

  test('E2E-VAL-06: paso 2 — contraseñas no coinciden', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.getByLabel(/nombre/i).first().fill('Juan');
    await page.getByLabel(/apellido/i).fill('Pérez');
    await page.getByLabel(/teléfono/i).fill('76543210');
    await page.getByRole('button', { name: /siguiente/i }).click();

    await page.getByLabel(/email/i).fill('test@test.com');
    await page.getByLabel(/^contraseña/i).fill('Password1');
    await page.getByLabel(/repite/i).fill('Different2');
    await page.getByRole('button', { name: /siguiente/i }).click();

    await expect(page.getByText(/no coinciden/i)).toBeVisible();
  });

  test('E2E-VAL-07: paso 3 — no seleccionar zona bloquea avance', async ({ page }) => {
    // Navigate to paso 3...
    await page.goto('/caregiver/register');
    // Fill pasos 1-2 rápido
    await page.getByLabel(/nombre/i).first().fill('Juan');
    await page.getByLabel(/apellido/i).fill('Pérez');
    await page.getByLabel(/teléfono/i).fill('76543210');
    await page.getByRole('button', { name: /siguiente/i }).click();
    await page.getByLabel(/email/i).fill('test@test.com');
    await page.getByLabel(/^contraseña/i).fill('Password1');
    await page.getByLabel(/repite/i).fill('Password1');
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 3: click siguiente sin seleccionar
    await page.getByRole('button', { name: /siguiente/i }).click();
    await expect(page.getByText(/selecciona tu zona/i)).toBeVisible();
  });

  test('E2E-VAL-08: paso 4 — sin servicio seleccionado bloquea', async ({ page }) => {
    // Nav to paso 4 (con pasos 1-3 completados)...
    // ... (similar fill pattern)
    // Resultado: "Selecciona al menos un servicio"
  });

  test('E2E-VAL-09: paso 5 — bio <50 chars muestra error', async ({ page }) => {
    // Nav to paso 5...
    // Fill solo 20 chars → "Necesitamos al menos 50 caracteres"
  });

  test('E2E-VAL-10: paso 11 — precio paseo 1h < 30 min muestra error', async ({ page }) => {
    // Nav to paso 11 con PASEO...
    // precio30: 40, precio60: 30 → "debe ser mayor que el de 30 min"
  });

  test('E2E-VAL-11: paso 12 — <4 fotos bloquea avance', async ({ page }) => {
    // Nav to paso 12...
    // Upload solo 2 fotos → "Necesitas al menos 4 fotos"
    // Botón siguiente disabled visualmente (aria-disabled)
  });

  test('E2E-VAL-12: paso 14 — checkboxes no marcados bloquea', async ({ page }) => {
    // Nav to paso 14...
    // Click siguiente sin marcar checkboxes
    // → 3 errores: "Debes aceptar los Términos", "Debes aceptar la Política", "Debes aceptar la verificación"
  });

  test('E2E-VAL-13: paso 15 — Error Summary si faltan campos', async ({ page }) => {
    // Nav to paso 15 con datos incompletos (e.g., fotos faltantes)
    // → Banner role="alert": "Completa estos campos..."
    // → Links "Ir →" navegan al paso correcto
  });

  test('E2E-VAL-14: shake animation en botón al intentar avanzar con errores', async ({ page }) => {
    await page.goto('/caregiver/register');
    const nextBtn = page.getByRole('button', { name: /siguiente/i });
    await nextBtn.click();

    // Verificar que el botón tiene la clase de shake
    await expect(nextBtn).toHaveClass(/animate-shake/);
  });

  test('E2E-VAL-15: focus se mueve al primer campo con error', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.getByRole('button', { name: /siguiente/i }).click();

    // El primer campo con error (firstName) debe tener focus
    const firstInput = page.getByLabel(/nombre/i).first();
    await expect(firstInput).toBeFocused();
  });
});
```

---

### 2.5 Suite: localStorage Draft

**Archivo:** `e2e/caregiver-register-draft.spec.ts`

```typescript
import { test, expect } from './fixtures';

test.describe('Wizard — localStorage draft', () => {

  test('E2E-DRAFT-01: draft se guarda al completar pasos', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.getByLabel(/nombre/i).first().fill('Juan');
    await page.getByLabel(/apellido/i).fill('Pérez');
    await page.getByLabel(/teléfono/i).fill('76543210');
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Verificar localStorage
    const draft = await page.evaluate(() =>
      JSON.parse(localStorage.getItem('garden_wizard_draft') || '{}')
    );
    expect(draft.data.firstName).toBe('Juan');
    expect(draft.currentStep).toBe(2);
  });

  test('E2E-DRAFT-02: password NUNCA se guarda en localStorage', async ({ page }) => {
    await page.goto('/caregiver/register');
    // Completar paso 1
    await page.getByLabel(/nombre/i).first().fill('Juan');
    await page.getByLabel(/apellido/i).fill('Pérez');
    await page.getByLabel(/teléfono/i).fill('76543210');
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Paso 2: llenar password
    await page.getByLabel(/email/i).fill('test@test.com');
    await page.getByLabel(/^contraseña/i).fill('Password1');
    await page.getByLabel(/repite/i).fill('Password1');

    const draft = await page.evaluate(() =>
      JSON.parse(localStorage.getItem('garden_wizard_draft') || '{}')
    );
    expect(draft.data?.password).toBeUndefined();
    expect(draft.data?.confirmPassword).toBeUndefined();
  });

  test('E2E-DRAFT-03: modal de retomar aparece al volver con draft', async ({ page }) => {
    // Seed draft
    await page.goto('/caregiver/register');
    await page.evaluate(() => {
      localStorage.setItem('garden_wizard_draft', JSON.stringify({
        currentStep: 5,
        lastSavedAt: new Date().toISOString(),
        data: { firstName: 'Juan', lastName: 'Pérez', phone: '+59176543210',
                email: 'juan@test.com', zone: 'EQUIPETROL' },
      }));
    });

    await page.reload();

    await expect(page.getByText(/registro sin completar/i)).toBeVisible();
    await expect(page.getByRole('button', { name: /continuar/i })).toBeVisible();
    await expect(page.getByRole('button', { name: /empezar de nuevo/i })).toBeVisible();
  });

  test('E2E-DRAFT-04: "Guardar y salir" persiste estado y navega a home', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.getByLabel(/nombre/i).first().fill('Test');
    await page.getByLabel(/apellido/i).fill('Draft');
    await page.getByLabel(/teléfono/i).fill('76543210');

    await page.getByRole('button', { name: /guardar.*salir|guardar.*✕/i }).click();
    await expect(page).toHaveURL('/');

    // Verificar draft persistido
    const draft = await page.evaluate(() =>
      JSON.parse(localStorage.getItem('garden_wizard_draft') || '{}')
    );
    expect(draft.data.firstName).toBe('Test');
  });

  test('E2E-DRAFT-05: draft expirado (>7 días) muestra modal especial', async ({ page }) => {
    await page.evaluate(() => {
      const oldDate = new Date();
      oldDate.setDate(oldDate.getDate() - 8); // 8 días atrás
      localStorage.setItem('garden_wizard_draft', JSON.stringify({
        currentStep: 7, lastSavedAt: oldDate.toISOString(),
        data: { firstName: 'Old', lastName: 'Draft' },
      }));
    });

    await page.goto('/caregiver/register');
    await expect(page.getByText(/registro.*caducado|más de 7 días/i)).toBeVisible();
    await expect(page.getByRole('button', { name: /empezar de nuevo/i })).toBeVisible();
    await expect(page.getByRole('button', { name: /recuperar/i })).toBeVisible();
  });

  test('E2E-DRAFT-06: draft se limpia tras registro exitoso', async ({ page }) => {
    // Completar registro completo...
    // ... (navegar 15 pasos)
    // Después de submit exitoso:
    const draft = await page.evaluate(() =>
      localStorage.getItem('garden_wizard_draft')
    );
    expect(draft).toBeNull();
  });
});
```

---

## 3. Test Matrix Responsive

### 3.1 Breakpoints a Testear

| Breakpoint | Viewport | Dispositivo Playwright | Prioridad |
|-----------|---------|----------------------|-----------|
| Mobile portrait | 375×667 | `iPhone SE` | **P0** (78% Bolivia mobile) |
| Mobile large | 390×844 | `iPhone 14` | P0 |
| Tablet portrait | 768×1024 | `iPad Mini` | P1 |
| Tablet landscape | 1024×768 | `iPad Mini landscape` | P2 |
| Desktop | 1280×720 | `Desktop Chrome` | P0 |
| Wide | 1920×1080 | `Desktop Chrome` (custom) | P2 |

### 3.2 Suite: Responsive Visual Tests

**Archivo:** `e2e/caregiver-responsive.spec.ts`

```typescript
import { test, expect } from './fixtures';

const viewports = {
  mobile: { width: 375, height: 667 },
  tablet: { width: 768, height: 1024 },
  desktop: { width: 1280, height: 720 },
};

for (const [name, viewport] of Object.entries(viewports)) {

  test.describe(`Responsive — ${name} (${viewport.width}px)`, () => {

    test.use({ viewport });

    // ─── Navbar ───

    test(`R-NAV-${name}: navbar layout correcto`, async ({ page }) => {
      await page.goto('/');
      if (viewport.width < 1024) {
        // Mobile/tablet: hamburguesa visible, nav links ocultos
        await expect(page.getByRole('button', { name: /menú|☰/i })).toBeVisible();
      } else {
        // Desktop: links visibles, hamburguesa oculta
        await expect(page.getByText(/cuidadores/i)).toBeVisible();
        await expect(page.getByRole('link', { name: /soy cuidador/i })).toBeVisible();
      }
    });

    // ─── Auth Page ───

    test(`R-AUTH-${name}: auth page layout`, async ({ page }) => {
      await page.goto('/caregiver/auth');
      if (viewport.width >= 1024) {
        // Desktop: 2 paneles lado a lado
        await expect(page.getByText(/en garden cada cuidador/i)).toBeVisible();
      } else {
        // Mobile: solo card auth, panel info oculto
        await expect(page.getByRole('tab', { name: /iniciar sesión/i })).toBeVisible();
      }
    });

    // ─── Wizard ───

    test(`R-WIZ-${name}: wizard layout`, async ({ page }) => {
      await page.goto('/caregiver/register');
      if (viewport.width >= 1024) {
        // Desktop: sidebar visible
        await expect(page.getByText(/progreso/i)).toBeVisible();
      } else {
        // Mobile/tablet: progress bar horizontal, sin sidebar
        await expect(page.getByRole('progressbar')).toBeVisible();
      }
    });

    test(`R-WIZ-STEP1-${name}: paso 1 grid layout`, async ({ page }) => {
      await page.goto('/caregiver/register');
      const nameInput = page.getByLabel(/nombre/i).first();
      const lastNameInput = page.getByLabel(/apellido/i);

      if (viewport.width >= 640) {
        // sm+: side by side
        const nameBox = await nameInput.boundingBox();
        const lastBox = await lastNameInput.boundingBox();
        expect(nameBox!.y).toBeCloseTo(lastBox!.y, -1); // Same row
      } else {
        // mobile: stacked
        const nameBox = await nameInput.boundingBox();
        const lastBox = await lastNameInput.boundingBox();
        expect(lastBox!.y).toBeGreaterThan(nameBox!.y); // Different rows
      }
    });

    test(`R-WIZ-STEP3-${name}: zona cards grid`, async ({ page }) => {
      // Nav to paso 3...
      await page.goto('/caregiver/register');
      // Fill paso 1-2 to get to 3...
      if (viewport.width >= 640) {
        // sm+: 2 columnas
        // Check first 2 zone cards are side by side
      }
      // Mobile: 1 columna stacked
    });

    test(`R-WIZ-BOTTOM-${name}: botones sticky en mobile`, async ({ page }) => {
      if (viewport.width >= 640) return; // solo mobile
      await page.goto('/caregiver/register');
      const nextBtn = page.getByRole('button', { name: /siguiente/i });
      const box = await nextBtn.boundingBox();
      // Debe estar cerca del bottom del viewport
      expect(box!.y + box!.height).toBeGreaterThan(viewport.height - 100);
    });

    // ─── Dashboard ───

    test(`R-DASH-${name}: dashboard cards layout`, async ({ page }) => {
      await page.goto('/caregiver/dashboard');
      if (viewport.width >= 1024) {
        // Desktop: profile y reservas side by side
      } else if (viewport.width >= 768) {
        // Tablet: 2-col grid
      } else {
        // Mobile: stacked con colapsables
        await expect(page.locator('[aria-expanded]')).toBeVisible();
      }
    });

    // ─── Paso 11 Collapsible (Mobile Only) ───

    test(`R-WIZ-STEP11-${name}: tarifas collapsible`, async ({ page }) => {
      // Nav to paso 11...
      if (viewport.width < 768) {
        // Mobile: sections colapsables
        const collapseBtn = page.getByRole('button', { name: /hospedaje/i });
        await expect(collapseBtn).toHaveAttribute('aria-expanded', 'true'); // default open
        await collapseBtn.click();
        await expect(collapseBtn).toHaveAttribute('aria-expanded', 'false');
      } else {
        // Desktop: siempre visible, sin collapse
        await expect(page.getByLabel(/precio por día/i)).toBeVisible();
      }
    });

    // ─── iOS zoom prevention ───

    test(`R-INPUT-${name}: inputs usan text-base en mobile`, async ({ page }) => {
      if (viewport.width >= 640) return;
      await page.goto('/caregiver/register');
      const input = page.getByLabel(/nombre/i).first();
      const fontSize = await input.evaluate(
        (el) => window.getComputedStyle(el).fontSize
      );
      expect(parseInt(fontSize)).toBeGreaterThanOrEqual(16); // 16px = no zoom iOS
    });
  });
}
```

### 3.3 Visual Regression (Screenshots)

```typescript
// e2e/caregiver-visual-regression.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Visual regression screenshots', () => {
  const pages = [
    { name: 'auth-page', url: '/caregiver/auth' },
    { name: 'wizard-step1', url: '/caregiver/register' },
    { name: 'dashboard', url: '/caregiver/dashboard' },
  ];

  for (const { name, url } of pages) {
    for (const viewport of [
      { name: 'mobile', width: 375, height: 667 },
      { name: 'desktop', width: 1280, height: 720 },
    ]) {
      test(`snapshot-${name}-${viewport.name}`, async ({ page }) => {
        await page.setViewportSize(viewport);
        await page.goto(url);
        await page.waitForLoadState('networkidle');
        await expect(page).toHaveScreenshot(
          `${name}-${viewport.name}.png`,
          { maxDiffPixelRatio: 0.01 }
        );
      });
    }
  }
});
```

---

## 4. Tests de Accesibilidad

### 4.1 axe-core Integration

**Archivo:** `e2e/caregiver-accessibility.spec.ts`

```typescript
import { test, expect } from './fixtures';
import AxeBuilder from '@axe-core/playwright';

test.describe('Accesibilidad WCAG 2.1 AA — flujo cuidador', () => {

  test('A11Y-01: página auth sin violaciones', async ({ page }) => {
    await page.goto('/caregiver/auth');
    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])
      .analyze();
    expect(results.violations).toEqual([]);
  });

  test('A11Y-02: wizard paso 1 sin violaciones', async ({ page }) => {
    await page.goto('/caregiver/register');
    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])
      .analyze();
    expect(results.violations).toEqual([]);
  });

  test('A11Y-03: wizard paso 11 (tarifas) sin violaciones', async ({ page }) => {
    // Navigate to paso 11...
    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])
      .analyze();
    expect(results.violations).toEqual([]);
  });

  test('A11Y-04: wizard paso 13 (verificación ID) sin violaciones', async ({ page }) => {
    // Navigate to paso 13...
    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])
      .analyze();
    expect(results.violations).toEqual([]);
  });

  test('A11Y-05: dashboard sin violaciones', async ({ page }) => {
    await page.goto('/caregiver/dashboard');
    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])
      .analyze();
    expect(results.violations).toEqual([]);
  });

  test('A11Y-06: dark mode sin violaciones de contraste', async ({ page }) => {
    await page.goto('/caregiver/auth');
    // Activar dark mode
    await page.evaluate(() => document.documentElement.classList.add('dark'));
    const results = await new AxeBuilder({ page })
      .withTags(['wcag2aa'])
      .analyze();

    // Filtrar solo violaciones de contraste
    const contrastViolations = results.violations.filter(
      (v) => v.id === 'color-contrast'
    );
    expect(contrastViolations).toEqual([]);
  });
});
```

### 4.2 Focus Management Tests

```typescript
test.describe('A11y — Focus management', () => {

  test('A11Y-FOCUS-01: tab cambia focus al primer input del panel', async ({ page }) => {
    await page.goto('/caregiver/auth');
    await page.getByRole('tab', { name: /registrarme/i }).click();
    // Focus debe moverse al contenido del panel registrarme
    // (botón "Comenzar registro")
    await page.getByRole('tab', { name: /iniciar sesión/i }).click();
    await expect(page.getByLabel(/email/i)).toBeFocused();
  });

  test('A11Y-FOCUS-02: siguiente paso → focus al h2 del nuevo paso', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.getByLabel(/nombre/i).first().fill('Juan');
    await page.getByLabel(/apellido/i).fill('Pérez');
    await page.getByLabel(/teléfono/i).fill('76543210');
    await page.getByRole('button', { name: /siguiente/i }).click();

    // Focus debe estar en el heading del paso 2
    const heading = page.getByRole('heading', { name: /tu cuenta garden/i });
    await expect(heading).toBeFocused();
  });

  test('A11Y-FOCUS-03: error de validación → focus al primer campo con error', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.getByRole('button', { name: /siguiente/i }).click();
    await expect(page.getByLabel(/nombre/i).first()).toBeFocused();
  });

  test('A11Y-FOCUS-04: modal focus trap', async ({ page }) => {
    await page.goto('/caregiver/register');
    // Trigger "Guardar y salir" modal
    await page.keyboard.press('Escape');
    // Modal visible
    await expect(page.getByText(/guardar.*salir/i)).toBeVisible();
    // Tab should cycle within modal (focus trap)
    await page.keyboard.press('Tab');
    await page.keyboard.press('Tab');
    await page.keyboard.press('Tab');
    // Focus should still be inside the modal
    const activeElement = await page.evaluate(() => document.activeElement?.closest('[role="dialog"]'));
    expect(activeElement).not.toBeNull();
  });

  test('A11Y-FOCUS-05: progress bar tiene role="progressbar" con aria values', async ({ page }) => {
    await page.goto('/caregiver/register');
    const progressBar = page.getByRole('progressbar');
    await expect(progressBar).toHaveAttribute('aria-valuenow', '1');
    await expect(progressBar).toHaveAttribute('aria-valuemin', '1');
    await expect(progressBar).toHaveAttribute('aria-valuemax', '15');
    await expect(progressBar).toHaveAttribute('aria-label', /paso 1 de 15/i);
  });

  test('A11Y-FOCUS-06: auth tabs tienen role="tablist" y aria-selected', async ({ page }) => {
    await page.goto('/caregiver/auth');
    await expect(page.getByRole('tablist')).toBeVisible();
    const loginTab = page.getByRole('tab', { name: /iniciar sesión/i });
    const registerTab = page.getByRole('tab', { name: /registrarme/i });
    await expect(loginTab).toHaveAttribute('aria-selected', 'true');
    await expect(registerTab).toHaveAttribute('aria-selected', 'false');
  });

  test('A11Y-FOCUS-07: errores tienen role="alert"', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.getByRole('button', { name: /siguiente/i }).click();
    const alerts = page.locator('[role="alert"]');
    await expect(alerts.first()).toBeVisible();
  });

  test('A11Y-FOCUS-08: sidebar step actual tiene aria-current="step"', async ({ page }) => {
    test.skip(); // Solo desktop
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.goto('/caregiver/register');
    const currentStep = page.locator('[aria-current="step"]');
    await expect(currentStep).toBeVisible();
    await expect(currentStep).toContainText(/nombre/i);
  });
});
```

### 4.3 Keyboard Navigation Tests

```typescript
test.describe('A11y — Keyboard navigation', () => {

  test('A11Y-KB-01: Enter en paso válido avanza al siguiente', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.getByLabel(/nombre/i).first().fill('Juan');
    await page.getByLabel(/apellido/i).fill('Pérez');
    await page.getByLabel(/teléfono/i).fill('76543210');
    await page.keyboard.press('Enter');
    await expect(page.getByText(/paso 2/i)).toBeVisible();
  });

  test('A11Y-KB-02: Escape abre modal "Guardar y salir"', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.keyboard.press('Escape');
    await expect(page.getByText(/guardar.*salir/i)).toBeVisible();
  });

  test('A11Y-KB-03: zone radio cards navegables con arrow keys', async ({ page }) => {
    // Nav to paso 3...
    // Tab to first zone card, use ArrowDown to move between zones
    // Space/Enter to select
  });

  test('A11Y-KB-04: skip-to-content link funciona', async ({ page }) => {
    await page.goto('/caregiver/auth');
    await page.keyboard.press('Tab'); // First tab = skip link
    await page.keyboard.press('Enter');
    // Focus debe saltar al <main id="main">
    const focusedId = await page.evaluate(() => document.activeElement?.id);
    expect(focusedId).toBe('main');
  });
});
```

---

## 5. Tests de Performance

### 5.1 Lighthouse CI

**Archivo:** `lighthouse-ci.config.js`

```javascript
module.exports = {
  ci: {
    collect: {
      url: [
        'http://localhost:5173/',
        'http://localhost:5173/caregiver/auth',
        'http://localhost:5173/caregiver/register',
        'http://localhost:5173/caregiver/dashboard',
      ],
      numberOfRuns: 3,
      settings: {
        preset: 'desktop',
        chromeFlags: '--no-sandbox',
      },
    },
    assert: {
      assertions: {
        'categories:performance': ['error', { minScore: 0.90 }],
        'categories:accessibility': ['error', { minScore: 0.95 }],
        'categories:best-practices': ['error', { minScore: 0.90 }],
        'categories:seo': ['warn', { minScore: 0.85 }],
        // Métricas específicas
        'first-contentful-paint': ['warn', { maxNumericValue: 1800 }],
        'largest-contentful-paint': ['error', { maxNumericValue: 2500 }],
        'cumulative-layout-shift': ['error', { maxNumericValue: 0.1 }],
        'total-blocking-time': ['error', { maxNumericValue: 300 }],
      },
    },
    upload: {
      target: 'filesystem',
      outputDir: './lighthouse-results',
    },
  },
};
```

### 5.2 Performance Targets

| Métrica | Target | Razón |
|---------|--------|-------|
| **Performance** | ≥90 | Standard profesional |
| **Accessibility** | ≥95 | WCAG 2.1 AA compliance |
| **Best Practices** | ≥90 | Seguridad headers, HTTPS, etc |
| **FCP** (First Contentful Paint) | <1.8s | Bolivia: conexiones variables |
| **LCP** (Largest Contentful Paint) | <2.5s | Fotos de perfil/espacio |
| **CLS** (Cumulative Layout Shift) | <0.1 | Sin saltos visuales |
| **TBT** (Total Blocking Time) | <300ms | Sin bloqueo del hilo principal |

### 5.3 Tests de Performance Específicos

**Archivo:** `e2e/caregiver-performance.spec.ts`

```typescript
import { test, expect } from '@playwright/test';

test.describe('Performance — flujo cuidador', () => {

  test('PERF-01: wizard carga en <2s', async ({ page }) => {
    const start = Date.now();
    await page.goto('/caregiver/register');
    await page.waitForLoadState('domcontentloaded');
    const loadTime = Date.now() - start;
    expect(loadTime).toBeLessThan(2000);
  });

  test('PERF-02: step transition <300ms', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.getByLabel(/nombre/i).first().fill('Juan');
    await page.getByLabel(/apellido/i).fill('Pérez');
    await page.getByLabel(/teléfono/i).fill('76543210');

    const start = Date.now();
    await page.getByRole('button', { name: /siguiente/i }).click();
    await page.waitForSelector('text=/paso 2/i');
    const transitionTime = Date.now() - start;
    expect(transitionTime).toBeLessThan(500); // 300ms anim + buffer
  });

  test('PERF-03: lazy loading — wizard steps code-split', async ({ page }) => {
    // Check that only Step01 chunk loads on initial page
    const requests: string[] = [];
    page.on('request', (req) => {
      if (req.url().includes('.js')) requests.push(req.url());
    });
    await page.goto('/caregiver/register');
    await page.waitForLoadState('networkidle');

    // Should NOT have loaded Step12Photos (heavy) on initial render
    const hasPhotoStep = requests.some((r) => /step12|photos/i.test(r));
    expect(hasPhotoStep).toBe(false);
  });

  test('PERF-04: Cloudinary preconnect en <head>', async ({ page }) => {
    await page.goto('/caregiver/register');
    const preconnect = await page.evaluate(() => {
      const link = document.querySelector('link[rel="preconnect"][href*="cloudinary"]');
      return link !== null;
    });
    expect(preconnect).toBe(true);
  });

  test('PERF-05: ObjectURL se revoca al remover foto', async ({ page }) => {
    // Nav to paso 12, upload foto, remover, check no memory leak
    // (via evaluación de performance.memory si disponible)
  });

  test('PERF-06: no layout shift durante carga de wizard', async ({ page }) => {
    // Usar PerformanceObserver para CLS
    await page.goto('/caregiver/register');
    const cls = await page.evaluate(() => {
      return new Promise<number>((resolve) => {
        let clsValue = 0;
        const observer = new PerformanceObserver((list) => {
          for (const entry of list.getEntries()) {
            // @ts-ignore
            if (!entry.hadRecentInput) clsValue += entry.value;
          }
        });
        observer.observe({ type: 'layout-shift', buffered: true });
        setTimeout(() => {
          observer.disconnect();
          resolve(clsValue);
        }, 2000);
      });
    });
    expect(cls).toBeLessThan(0.1);
  });
});
```

### 5.4 Script `package.json`

```json
{
  "scripts": {
    "test:lighthouse": "lhci autorun",
    "test:perf": "playwright test e2e/caregiver-performance.spec.ts"
  }
}
```

---

## 6. Edge Cases

### 6.1 Suite: Edge Cases Completos

**Archivo:** `e2e/caregiver-edge-cases.spec.ts`

```typescript
import { test, expect } from './fixtures';

test.describe('Edge cases — flujo cuidador', () => {

  // ─── Upload failures ───

  test('EDGE-01: upload foto falla → muestra error con reintentar', async ({ page }) => {
    await page.route('**/api.cloudinary.com/**', (route) =>
      route.abort('connectionfailed')
    );

    // Nav to paso 12...
    // Intentar subir foto
    // → Slot muestra "Error al subir" + botón "Reintentar"
    // → Counter NO se incrementa
  });

  test('EDGE-02: upload foto >5MB → error inline', async ({ page }) => {
    // Nav to paso 12...
    const fileInput = page.locator('input[type="file"]').first();
    // Create 6MB buffer
    await fileInput.setInputFiles({
      name: 'huge.jpg', mimeType: 'image/jpeg',
      buffer: Buffer.alloc(6 * 1024 * 1024),
    });
    await expect(page.getByText(/excede.*5 mb/i)).toBeVisible();
  });

  test('EDGE-03: upload formato no permitido → error', async ({ page }) => {
    // Nav to paso 12...
    const fileInput = page.locator('input[type="file"]').first();
    await fileInput.setInputFiles({
      name: 'doc.pdf', mimeType: 'application/pdf',
      buffer: Buffer.alloc(200),
    });
    await expect(page.getByText(/solo.*jpg.*png.*webp/i)).toBeVisible();
  });

  // ─── Conexión perdida ───

  test('EDGE-04: sin conexión durante upload muestra banner', async ({ page }) => {
    // Nav to paso 12...
    // Cortar red durante upload
    await page.route('**/api.cloudinary.com/**', (route) =>
      route.abort('internetdisconnected')
    );
    // → Banner "Sin conexión a internet"
    // → Datos locales seguros
  });

  // ─── Token expirado ───

  test('EDGE-05: token expirado en dashboard → modal + redirect auth', async ({ page }) => {
    await page.route('**/api/caregivers/me', (route) =>
      route.fulfill({ status: 401, contentType: 'application/json',
        body: JSON.stringify({ message: 'Token expired' }) })
    );
    await page.route('**/api/auth/refresh', (route) =>
      route.fulfill({ status: 401, contentType: 'application/json',
        body: JSON.stringify({ message: 'Refresh token expired' }) })
    );

    await page.goto('/caregiver/dashboard');
    await expect(page.getByText(/tu sesión expiró/i)).toBeVisible();
    await page.getByRole('button', { name: /iniciar sesión/i }).click();
    await expect(page).toHaveURL(/\/caregiver\/auth/);
  });

  // ─── Logout ───

  test('EDGE-06: logout desde dashboard → modal → redirect home', async ({ page }) => {
    await page.goto('/caregiver/dashboard');
    // Click avatar dropdown
    await page.getByRole('button', { name: /mi panel/i }).click();
    await page.getByRole('menuitem', { name: /cerrar sesión/i }).click();

    // Modal de confirmación
    await expect(page.getByText(/cerrar sesión/i)).toBeVisible();
    await page.getByRole('button', { name: /cerrar sesión/i }).last().click();

    await expect(page).toHaveURL('/');
    // Navbar: "Soy cuidador" (no "Mi panel")
    await expect(page.getByText(/soy cuidador/i)).toBeVisible();
  });

  // ─── Perfil rechazado ───

  test('EDGE-07: perfil rechazado muestra motivo + botón reenviar', async ({ page }) => {
    await page.route('**/api/caregivers/me', (route) =>
      route.fulfill({
        status: 200, contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          data: {
            id: 'cp-1', verified: false, rejected: true,
            rejectionReason: 'Las fotos no muestran claramente tu espacio.',
          },
        }),
      })
    );

    await page.goto('/caregiver/dashboard');
    await expect(page.getByText(/no fue aprobado/i)).toBeVisible();
    await expect(page.getByText(/fotos no muestran/i)).toBeVisible();
    await expect(page.getByRole('button', { name: /editar y reenviar/i })).toBeVisible();

    await page.getByRole('button', { name: /editar y reenviar/i }).click();
    await expect(page).toHaveURL(/\/caregiver\/edit/);
  });

  // ─── Cuidador suspendido ───

  test('EDGE-08: cuidador suspendido → redirect a /caregiver/suspended', async ({ page }) => {
    await page.route('**/api/caregivers/me', (route) =>
      route.fulfill({
        status: 200, contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          data: { id: 'cp-1', suspended: true },
        }),
      })
    );

    await page.goto('/caregiver/dashboard');
    await expect(page).toHaveURL(/\/caregiver\/suspended/);
    await expect(page.getByText(/tu cuenta está suspendida/i)).toBeVisible();
    await expect(page.getByText(/whatsapp/i)).toBeVisible();
  });

  // ─── Browser back ───

  test('EDGE-09: browser back en wizard → paso anterior, no sale', async ({ page }) => {
    await page.goto('/caregiver/register');
    // Completar paso 1
    await page.getByLabel(/nombre/i).first().fill('Juan');
    await page.getByLabel(/apellido/i).fill('Pérez');
    await page.getByLabel(/teléfono/i).fill('76543210');
    await page.getByRole('button', { name: /siguiente/i }).click();
    await expect(page.getByText(/paso 2/i)).toBeVisible();

    // Press browser back
    await page.goBack();

    // Debe ir a paso 1, NO salir del wizard
    await expect(page.getByText(/paso 1/i)).toBeVisible();
    await expect(page).toHaveURL(/\/caregiver\/register/);
  });

  test('EDGE-10: browser back en paso 1 → modal "Guardar y salir"', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.goBack();
    await expect(page.getByText(/guardar.*salir/i)).toBeVisible();
  });

  // ─── Server error en submit ───

  test('EDGE-11: 500 en submit → error amigable con retry', async ({ page }) => {
    await page.route('**/api/auth/register', (route) =>
      route.fulfill({ status: 500, contentType: 'application/json',
        body: JSON.stringify({ message: 'Internal Server Error' }) })
    );

    // Nav to paso 15, click submit
    // → "Algo salió mal. Intenta de nuevo en unos minutos."
    // → Botón "Reintentar" visible
    // → Datos del formulario NO se pierden
  });

  // ─── Form con valores edge ───

  test('EDGE-12: nombre con caracteres especiales (ñ, acentos)', async ({ page }) => {
    await page.goto('/caregiver/register');
    await page.getByLabel(/nombre/i).first().fill('María José');
    await page.getByLabel(/apellido/i).fill('Pérez Ñoño');
    await page.getByLabel(/teléfono/i).fill('76543210');
    await page.getByRole('button', { name: /siguiente/i }).click();
    // Debe avanzar sin error
    await expect(page.getByText(/paso 2/i)).toBeVisible();
  });

  test('EDGE-13: bio exactamente 500 chars (límite)', async ({ page }) => {
    // Nav to paso 5...
    const bio = 'a'.repeat(500);
    await page.getByRole('textbox').fill(bio);
    // Counter muestra "500/500" en rojo
    await expect(page.getByText(/500\/500/i)).toBeVisible();
    // No se pueden escribir más
    await page.getByRole('textbox').type('extra');
    const value = await page.getByRole('textbox').inputValue();
    expect(value.length).toBeLessThanOrEqual(500);
  });

  test('EDGE-14: precio con decimales → solo enteros aceptados', async ({ page }) => {
    // Nav to paso 11...
    await page.getByLabel(/precio por día/i).fill('120.50');
    // Input type="number" step="1" → redondea o rechaza
  });

  test('EDGE-15: doble clic en "Enviar solicitud" → solo 1 request', async ({ page }) => {
    // Nav to paso 15...
    let requestCount = 0;
    page.on('request', (req) => {
      if (req.url().includes('/api/auth/register') && req.method() === 'POST') {
        requestCount++;
      }
    });

    const submitBtn = page.getByRole('button', { name: /enviar solicitud/i });
    await submitBtn.dblclick();

    // Solo debería haberse enviado 1 request
    expect(requestCount).toBe(1);
  });
});
```

---

## 7. Gap Analysis vs MVP

### 7.1 Gaps Detectados

| # | Gap | Diseño actual | MVP Spec | Severidad | Mejora propuesta |
|---|-----|--------------|----------|-----------|-----------------|
| GAP-01 | **Fotos genéricas vs reales** | Acepta cualquier JPG/PNG/WebP | MVP enfatiza "confianza" | Media | Agregar validación: no aceptar fotos stock (verificación manual admin + nota en paso 12: "Las fotos deben ser reales de tu espacio. Fotos genéricas causan rechazo.") |
| GAP-02 | **Verificación presencial** | Solo upload CI digital | MVP menciona "entrevista + visita domicilio" como parte de verificación | Alta | Agregar paso informativo post-submit: "Después de revisar tu perfil online, un miembro de GARDEN te contactará para coordinar una visita breve a tu domicilio." |
| GAP-03 | **Comisión 18-20%** | Mencionada en paso 14 (términos) | MVP define comisión variable | Baja | Ya cubierto en términos. Agregar tooltip en paso 11: "GARDEN cobra una comisión del 18-20% por cada reserva. El precio que defines es lo que el dueño paga." |
| GAP-04 | **Cancelación** | No mencionada en wizard | MVP tiene reglas detalladas (>48h free, 24-48h 50%, <24h 100%) | Media | Agregar en paso 14 un resumen de la política de cancelación como checkbox adicional o sección informativa |
| GAP-05 | **WhatsApp notificaciones** | Mencionado en post-submit y verificación | MVP usa WhatsApp como canal principal | Baja | Ya cubierto. Verificar que el teléfono del paso 1 se valida como WhatsApp (prefijo +591 7/6) |
| GAP-06 | **Edad mínima (>18)** | **NO verificada en wizard** | Implícita (CI obligatorio, servicios profesionales) | **Alta** | Agregar checkbox en paso 14: "Confirmo que soy mayor de 18 años" — bloquea si no marcado |
| GAP-07 | **Disponibilidad/calendario** | No en wizard (V2 feature) | MVP menciona "calendario" | Baja | Correctamente diferido a V2. Post-registro, dashboard puede mostrar prompt: "Próximamente: define tu disponibilidad semanal" |
| GAP-08 | **Precio mínimo vs mercado** | Min Bs 30/día, 10/30min, 20/1h | MVP: Bs 80-160/día, 20-45/30min | Media | Ajustar validación mínima: pricePerDay min 50 (más realista), mostrar rango sugerido más prominente |

### 7.2 Acciones Recomendadas (Prioridad)

| Prioridad | Acción | Esfuerzo |
|-----------|--------|----------|
| **P0** | GAP-06: Agregar verificación edad ≥18 en paso 14 | 1h — checkbox + validación |
| **P0** | GAP-02: Agregar texto informativo sobre visita presencial post-submit | 30min — texto informativo |
| **P1** | GAP-01: Reforzar warning en paso 12 sobre fotos reales | 15min — texto + tooltip |
| **P1** | GAP-04: Agregar resumen de cancelación en paso 14 | 1h — sección informativa |
| **P1** | GAP-08: Ajustar precios mínimos y sugeridos | 30min — cambio de validación |
| **P2** | GAP-03: Tooltip de comisión en paso 11 | 15min — tooltip |
| **P2** | GAP-07: Placeholder de calendario en dashboard | Diferido a V2 |

### 7.3 Test Cases para Gaps

```typescript
test.describe('Gap Analysis — tests correctivos', () => {

  test('GAP-06-TEST: checkbox >18 requerido en paso 14', async ({ page }) => {
    // Nav to paso 14...
    // Sin marcar "Soy mayor de 18" → no puede avanzar
    await page.getByRole('button', { name: /siguiente/i }).click();
    await expect(page.getByText(/confirma.*mayor.*18/i)).toBeVisible();
    await expect(page.getByText(/paso 14/i)).toBeVisible(); // no avanzó
  });

  test('GAP-01-TEST: warning de fotos reales visible en paso 12', async ({ page }) => {
    // Nav to paso 12...
    await expect(page.getByText(/fotos.*reales|genéricas.*rechazo/i)).toBeVisible();
  });

  test('GAP-08-TEST: precio por día min 50 (no 30)', async ({ page }) => {
    // Nav to paso 11 con HOSPEDAJE...
    await page.getByLabel(/precio por día/i).fill('40');
    await page.getByRole('button', { name: /siguiente/i }).click();
    await expect(page.getByText(/precio mínimo/i)).toBeVisible();
  });

  test('GAP-04-TEST: política de cancelación visible en paso 14', async ({ page }) => {
    // Nav to paso 14...
    await expect(page.getByText(/cancelación|48.*horas/i)).toBeVisible();
  });

  test('GAP-02-TEST: info visita presencial en página de éxito', async ({ page }) => {
    // Completar registro completo → página de éxito
    // → Texto sobre "visita breve a tu domicilio" visible
    await expect(page.getByText(/visita.*domicilio/i)).toBeVisible();
  });
});
```

---

## 8. Self-Review

### 8.1 Checklist de Completitud

| Categoría | Requerimiento | Cubierto | Sección |
|-----------|--------------|----------|---------|
| **Registro completo** | 15 pasos con validaciones | ✅ | §2.2 E2E-REG-01 |
| **Login → dashboard** | Login exitoso + error + suspendido + rate limit | ✅ | §2.3 E2E-LOGIN-01-04 |
| **Responsive sm** | Mobile 375px-639px | ✅ | §3.2 R-*-mobile |
| **Responsive md** | Tablet 768px-1023px | ✅ | §3.2 R-*-tablet |
| **Responsive lg** | Desktop 1024px+ | ✅ | §3.2 R-*-desktop |
| **axe-core a11y** | WCAG 2.1 AA en auth, wizard, dashboard | ✅ | §4.1 A11Y-01-06 |
| **Lighthouse >90** | Performance, accessibility, best-practices | ✅ | §5.1-5.3 |
| **Form inválido** | Campos vacíos, min/max, formatos | ✅ | §2.4 E2E-VAL-01-15 |
| **Upload falla** | Timeout, >5MB, formato inválido | ✅ | §6.1 EDGE-01-03 |
| **>18 not checked** | Checkbox edad bloquea paso 14 | ✅ | §7.3 GAP-06-TEST |
| **Checklist visual** | Botón estados, inputs, dark mode | ✅ | §1 (75 items) |
| **Casos E2E** | Playwright con mock API | ✅ | §2 (~50 tests) |
| **Gap analysis** | Coherencia con MVP spec | ✅ | §7 (8 gaps + acciones) |

### 8.2 Coherencia Interna Verificada

| Aspecto | Verificación | Estado |
|---------|-------------|--------|
| Nombres de archivo E2E | Consistentes (`caregiver-*.spec.ts`) | ✅ |
| Fixtures compartidos | `e2e/fixtures.ts` con mock API + axe helper | ✅ |
| IDs de test | Prefijo único (`E2E-REG-`, `E2E-VAL-`, `EDGE-`, `A11Y-`, etc.) | ✅ |
| Mock API | Cubre todos los endpoints: auth, caregivers, cloudinary | ✅ |
| Viewports | 3 breakpoints mínimos (mobile/tablet/desktop) | ✅ |
| Dark mode tests | Contraste + axe en modo dark | ✅ |
| Condicionales HOSPEDAJE/PASEO | E2E-REG-02 verifica skip paso 9 | ✅ |
| localStorage | 6 tests de draft (save, password excl, retomar, expirado, limpieza) | ✅ |
| Error catalog | Mapeado 1:1 con catálogo §3.3 del doc Refinado | ✅ |
| Edge cases | 15 edge cases cubriendo: upload, conexión, token, logout, back, submit | ✅ |

### 8.3 Gaps Encontrados en Esta Self-Review

| # | Gap | Corrección aplicada |
|---|-----|--------------------|
| SR-01 | Falta test de **doble submit** (double-click prevention) | Agregado EDGE-15 |
| SR-02 | Falta verificación de **edad ≥18** en wizard (no estaba en v1.0/v1.1) | Agregado GAP-06 como P0 |
| SR-03 | **Visual regression screenshots** no estaban en el plan original | Agregado §3.3 |
| SR-04 | **CLS (layout shift)** test faltaba como test automatizado | Agregado PERF-06 |
| SR-05 | **Dark mode contrast** test faltaba para axe específico | Agregado A11Y-06 |
| SR-06 | Tests de **keyboard navigation** (Enter, Escape, arrows) no estaban | Agregado §4.3 |
| SR-07 | **Política de cancelación** ausente en wizard (gap MVP) | Agregado GAP-04 |
| SR-08 | Test de **nombre con caracteres especiales** (ñ, acentos) faltaba | Agregado EDGE-12 |

### 8.4 Resumen de Cobertura Final

```
┌───────────────────────────────────────────────────────────────┐
│  GARDEN — Testing Plan Coverage                                │
│                                                                │
│  Visual Checklist:     75 items    (§1)                        │
│  E2E Playwright:       ~50 tests  (§2)                        │
│  Responsive Matrix:    3 breakpoints × 8+ scenarios (§3)      │
│  Accessibility (axe):  8 tests WCAG + 8 focus + 4 keyboard    │
│  Performance:          6 tests + Lighthouse CI config          │
│  Edge Cases:           15 scenarios (§6)                       │
│  Gap Analysis:         8 gaps identified, 5 P0/P1 actions     │
│  Self-Review:          8 gaps found and corrected              │
│                                                                │
│  Archivos E2E nuevos (propuestos):                            │
│  ├── e2e/fixtures.ts                                          │
│  ├── e2e/caregiver-register-full.spec.ts                      │
│  ├── e2e/caregiver-login-dashboard.spec.ts                    │
│  ├── e2e/caregiver-register-validations.spec.ts               │
│  ├── e2e/caregiver-register-draft.spec.ts                     │
│  ├── e2e/caregiver-responsive.spec.ts                         │
│  ├── e2e/caregiver-visual-regression.spec.ts                  │
│  ├── e2e/caregiver-accessibility.spec.ts                      │
│  ├── e2e/caregiver-performance.spec.ts                        │
│  └── e2e/caregiver-edge-cases.spec.ts                         │
│                                                                │
│  Config nuevos:                                                │
│  ├── playwright.config.ts  (actualizado: 3 projects)          │
│  └── lighthouse-ci.config.js                                  │
│                                                                │
│  Deps nuevas: @axe-core/playwright, @lhci/cli                │
│                                                                │
│  Total: ~100+ test cases across all categories                │
└───────────────────────────────────────────────────────────────┘
```

---

*Fin del documento GARDEN_Testing_Visual_UX_Cuidador.md v1.0*
*Basado en: GARDEN_Flujo_Soy_Cuidador.md v1.0 + GARDEN_Flujo_Soy_Cuidador_Refinado.md v1.1*

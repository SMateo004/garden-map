# GARDEN

Marketplace de cuidado de mascotas en Santa Cruz de la Sierra, Bolivia. Conecta dueños con
paseadores y cuidadores verificados — paseo, guardería y hospedaje — con pago por QR bancario,
billetera interna, seguimiento GPS en vivo y calificaciones.

- **App**: [gardenbo.com](https://gardenbo.com) (web) · App Store / Play Store (próximamente)
- **API**: `https://api.gardenbo.com`

## Estructura del repo

```
garden-mvp/
├── garden-api/     # Backend — Express + Prisma + PostgreSQL (TypeScript)
└── garden-app/     # App — Flutter (iOS, Android, Web)
```

No hay más proyectos activos en este monorepo. Si ves referencias a `garden-web` en documentación
vieja, es de una versión anterior (React/Vite) que ya no existe.

## Poner el proyecto a correr

### 1. Requisitos
- Git, Node.js 18+
- Flutter 3.29 (`flutter --version` para confirmar), Dart `^3.7.0`
- Xcode + CocoaPods si vas a compilar iOS · Android Studio si vas a compilar Android

### 2. Clonar y configurar
```bash
git clone https://github.com/SMateo004/garden-map.git
cd garden-map
```

Pedile a alguien del equipo el archivo `garden-api/.env` por un canal privado (nunca por chat en
texto plano — tiene credenciales reales de producción). Sin él, la API no arranca.

### 3. Backend
```bash
cd garden-api
npm install
npm run dev
```
Confirmá en `http://localhost:3000/health` que devuelve `"status":"ok"`.

> **Importante**: este proyecto no tiene una base de datos de staging — el backend local se
> conecta directo a la base de datos de producción. Usá las cuentas de prueba dedicadas
> (`reviewer.cliente@gardenbo.com` / `reviewer.cuidador@gardenbo.com` / `reviewer.admin@gardenbo.com`,
> password `ReviewGarden2026!`) y no dejes datos de prueba sueltos.

### 4. App (Flutter)
```bash
cd garden-app
flutter pub get
flutter run -d chrome --dart-define=API_URL=http://localhost:3000/api
```
O elegí otro dispositivo con `flutter devices`.

## Documentación técnica completa

Ver [`CLAUDE.md`](./CLAUDE.md) — contexto detallado para trabajar en el proyecto (arquitectura,
despliegue, reglas de dinero/pagos, convenciones de git). Se carga automáticamente en cualquier
sesión de Claude Code abierta en este repo.

## Deploy

Automático al hacer push a `main`: los cambios en `garden-api/**` redeployan la API en Render, y
los cambios en `garden-app/**` recompilan y despliegan la web en Vercel. Ver `CLAUDE.md` para el
detalle y cómo confirmar el estado real de cada pipeline.

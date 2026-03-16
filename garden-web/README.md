# GARDEN Web — Frontend

React + TypeScript + Tailwind. Listado de cuidadores, detalle de perfil y registro de cuidador.

## Stack

- **Vite** + React 18 + TypeScript
- **Tailwind CSS**
- **React Query** — cache de listado y detalle
- **Axios** — cliente HTTP con JWT en `Authorization`
- **React Hook Form** + **Yup** — formulario de registro
- **React Slick** — carrusel de fotos en detalle
- **react-lazy-load-image-component** — lazy load de imágenes
- **Vitest** + **Testing Library** — tests unitarios

## Scripts

```bash
npm install
npm run dev      # http://localhost:5173 (proxy /api → backend)
npm run build
npm run preview
npm run test     # watch
npm run test:run # single run
```

## Variables de entorno

- `VITE_API_URL`: base URL del API (vacío en dev usa proxy a `localhost:3000`).

## Estructura

- `src/api` — cliente axios + JWT, endpoints cuidadores
- `src/components` — ProfileCard, UploadForm, ListingPage, ProfileDetail, Badge
- `src/hooks` — useCaregivers, useCaregiverDetail (React Query)
- `src/forms` — schema Yup para registro cuidador
- `src/pages` — ListingPage, ProfileDetailPage, CaregiverRegisterPage
- `src/types` — tipos alineados con backend

## Tests

- `ProfileCard.test.tsx`: render del card, badge “Verificado por GARDEN” condicional, link al detalle.

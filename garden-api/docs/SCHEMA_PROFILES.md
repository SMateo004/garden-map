# Schema de perfiles de cuidadores (MVP)

Cambios aplicados al schema Prisma según MVP y especificación técnica.

## Enums

- **Zone**: EQUIPETROL, URBARI, NORTE, LAS_PALMAS, CENTRO_SAN_MARTIN, OTROS (zona/barrio visible).
- **ServiceType**: HOSPEDAJE, PASEO (ya existía).

## CaregiverProfile

| Campo | Tipo | Descripción |
|-------|------|-------------|
| bio | String? @db.VarChar(500) | Descripción específica, máx 500 caracteres |
| zone | Zone? | Zona/barrio (enum) |
| spaceType | String? | "Casa con patio", "Casa sin patio", "Departamento", etc. |
| photos | String[] | 4–6 URLs Cloudinary (casa/patio + cuidador con mascota) |
| servicesOffered | ServiceType[] | Hospedaje, Paseos, o ambos (checkboxes) |
| verified | Boolean | Badge "Verificado por GARDEN" (admin) |
| verifiedAt | DateTime? | Fecha de verificación |
| verifiedBy | String? | userId del admin que verificó |
| verificationNotes | String? | Notas de la verificación (entrevista/visita) |

Índices: `[zone, verified]`, `[verified]`, y los existentes con `suspended` para listados.

## Migración desde schema anterior

Si tenías `zone` como `String` y `approvedAt`:

1. Crear migración: `npx prisma migrate dev --name caregiver_zone_and_verification`
2. En PostgreSQL, la migración:
   - Crea el enum `Zone` y convierte la columna `zone` a ese tipo (puede requerir un paso intermedio para datos existentes: ej. `equipetrol` → `EQUIPETROL`).
   - Añade `verified_at`, `verified_by`, `verification_notes` y renombra/elimina `approved_at` según lo que generes.

Si la DB está vacía o en desarrollo, `prisma migrate dev` generará los cambios. Si ya hay datos en `zone` como texto (ej. `equipetrol`), conviene una migración custom que haga algo como:

```sql
-- Ejemplo conceptual: crear enum, añadir columna temporal, mapear valores, reemplazar, borrar temporal
ALTER TYPE ...
UPDATE caregiver_profiles SET zone_new = CASE zone_old ...
```

3. Regenerar cliente: `npx prisma generate`

## Frontend

- **ZONES** y **ZONE_LABELS** en `@/types/caregiver` usan los mismos valores que el backend (EQUIPETROL, etc.).
- Los filtros y el formulario de registro envían el valor del enum; la UI muestra etiquetas con **ZONE_LABELS** (ej. "Centro/Av. San Martín" para CENTRO_SAN_MARTIN).

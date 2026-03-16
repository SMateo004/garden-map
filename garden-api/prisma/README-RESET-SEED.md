# Reset de DB y seed manual

Si `npx prisma migrate reset --force` falla porque el seed intenta escribir en tablas que aún no existen, usa reset **sin** seed y luego ejecuta el seed a mano.

## 1. Schema y seed desacoplados del reset

- El **modelo User** en `schema.prisma` está definido correctamente (`id String @id @default(uuid())`, etc.).
- El **seed automático** está deshabilitado en `package.json` (no hay clave `"prisma": { "seed": "..." }`), así que `migrate reset` no ejecutará el seed.

## 2. Reset sin seed (crea la DB y aplica migraciones)

Desde la raíz del API:

```bash
cd garden-api
npx prisma migrate reset --force --skip-seed
```

Con esto se:

- Elimina la base de datos (o todas las tablas).
- Vuelve a crear la DB.
- Aplica **todas** las migraciones (incl. `users`, `caregiver_profiles`, `client_profiles`, etc.).
- **No** ejecuta el seed.

Al terminar, la DB existe y tiene todas las tablas; el backend puede arrancar y `/api/caregivers` no debería devolver 500 por columnas faltantes.

## 3. Ejecutar el seed manualmente (después del reset)

Con la DB ya creada y migrada:

```bash
cd garden-api
npx prisma db seed
```

O, si no tienes `seed` configurado en `package.json`, ejecuta el script directamente:

```bash
cd garden-api
tsx prisma/seed.ts
```

Esto crea/actualiza: 1 admin, 1 cuidador DRAFT, 1 cuidador PENDING_REVIEW (usa `User` y `CaregiverProfile`).

## 4. Si el seed falla por "tabla no existente"

- Tras un `migrate reset --force --skip-seed`, las tablas **sí** deberían existir. Si el seed dice que `users` (u otra) no existe:
  1. Comprueba que el reset terminó bien: `npx prisma migrate status`.
  2. Comprueba que usas la misma `DATABASE_URL` que el API (mismo `.env`).
- Si aun así falla (por ejemplo, otro proceso borró tablas), aplica migraciones y vuelve a lanzar el seed:

  ```bash
  npx prisma migrate deploy
  tsx prisma/seed.ts
  ```

- **Solo en último caso**, si necesitas un seed mínimo que no dependa de `users`: puedes comentar temporalmente en `prisma/seed.ts` todo el contenido de `main()` que use `prisma.user.upsert()` y `prisma.caregiverProfile.upsert()`, dejar un `console.log('Seed omitido');` y ejecutar `tsx prisma/seed.ts`. Luego descomenta y vuelve a ejecutar cuando la DB esté correcta.

## 5. Restaurar el seed automático (opcional)

Cuando todo funcione y quieras que `prisma migrate reset` vuelva a ejecutar el seed:

1. En `package.json`, añade de nuevo la sección `prisma`:

   ```json
   "prisma": {
     "seed": "tsx prisma/seed.ts"
   },
   ```

2. A partir de entonces, `npx prisma migrate reset --force` (sin `--skip-seed`) ejecutará también el seed tras aplicar las migraciones.

## Resumen rápido

```bash
cd garden-api
npx prisma migrate reset --force --skip-seed   # Crea DB y tablas, sin seed
tsx prisma/seed.ts                             # Seed manual (admin + cuidadores)
npm run dev                                    # Arranca backend; GET /api/caregivers debe devolver 200
```

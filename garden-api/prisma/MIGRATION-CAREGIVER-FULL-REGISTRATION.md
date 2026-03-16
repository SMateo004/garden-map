# Migración: Flujo completo registro cuidadores (CaregiverStatus + auditoría)

## 1. Aplicar la migración

Desde la raíz de `garden-api`:

```bash
npx prisma migrate dev --name caregiver_full_registration
```

Esto creará una nueva migración que:

- Añade el enum `CaregiverStatus` (DRAFT, PENDING_REVIEW, NEEDS_REVISION, APPROVED, REJECTED, SUSPENDED).
- Añade en `CaregiverProfile`: `status`, `bioDetail`, `spaceDescription`, `termsAccepted`, `privacyAccepted`, `verificationAccepted`, `termsAcceptedAt`, `rejectionReason`, `adminNotes`, `approvedAt`, `approvedBy`, `reviewedAt`.
- Añade índices `@@index([status])` y `@@index([userId])`.
- Mantiene los campos existentes (`verified`, `verificationStatus`, `photos`, `zone`, `servicesOffered`, etc.).

En PostgreSQL, las nuevas columnas serán `NULL` o tendrán `DEFAULT` según el schema; los enums se crean con `CREATE TYPE`.

---

## 2. Backward compatibility: rellenar `status` desde datos existentes

Tras aplicar la migración, **hay que poblar `status`** a partir de `verified` y `verificationStatus` para que el panel admin y las consultas sigan siendo coherentes.

### Opción A: Migración SQL dentro de Prisma (recomendada)

Añade un script en la propia migración. Después de `migrate dev`, edita el archivo generado en `prisma/migrations/YYYYMMDDHHMMSS_caregiver_full_registration/migration.sql` y **al final del archivo** agrega:

```sql
-- Backfill status from verified / verificationStatus
UPDATE caregiver_profiles
SET status = CASE
  WHEN verified = true THEN 'APPROVED'::"CaregiverStatus"
  WHEN "verificationStatus" = 'REJECTED' THEN 'REJECTED'::"CaregiverStatus"
  WHEN suspended = true THEN 'SUSPENDED'::"CaregiverStatus"
  ELSE 'PENDING_REVIEW'::"CaregiverStatus"
END
WHERE status = 'DRAFT'::"CaregiverStatus";
```

**Nota:** Si esta migración ya se aplicó sin el `UPDATE`, ejecuta el `UPDATE` manualmente una vez (ver opción B) o crea una migración vacía que solo contenga ese `UPDATE`.

### Opción B: Script one-off (Node/Prisma)

Si prefieres no tocar el SQL de la migración, crea un script y ejecútalo una vez después de `migrate dev`:

```bash
# En garden-api
npx ts-node scripts/backfill-caregiver-status.ts
```

Contenido sugerido de `scripts/backfill-caregiver-status.ts`:

```ts
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  const draftProfiles = await prisma.caregiverProfile.findMany({
    where: { status: 'DRAFT' },
    select: { id: true, verified: true, verificationStatus: true, suspended: true },
  });

  for (const p of draftProfiles) {
    const status =
      p.verified ? 'APPROVED' :
      p.verificationStatus === 'REJECTED' ? 'REJECTED' :
      p.suspended ? 'SUSPENDED' : 'PENDING_REVIEW';
    await prisma.caregiverProfile.update({
      where: { id: p.id },
      data: { status },
    });
  }
  console.log(`Updated status for ${draftProfiles.length} profiles.`);
}

main()
  .then(() => prisma.$disconnect())
  .catch((e) => { console.error(e); prisma.$disconnect(); process.exit(1); });
```

---

## 3. Compatibilidad en la aplicación

- **Listados públicos (cuidador “verificado”)**: seguir usando `verified == true` O, cuando migres la lógica, `status === 'APPROVED'` y `suspended === false`.
- **Panel admin**: filtrar por `status` (PENDING_REVIEW, NEEDS_REVISION, APPROVED, REJECTED, SUSPENDED). Los índices `@@index([status])` y `@@index([userId])` optimizan estas consultas.
- **Registro nuevo**: al crear el perfil con `registerCaregiver`, establecer `status: 'PENDING_REVIEW'` (y opcionalmente seguir seteando `verificationStatus: PENDING_REVIEW`, `verified: false` hasta que deprecés esos campos).
- **Migrar `verified` → `status`**: cuando un admin “aprueba”, actualizar `status = 'APPROVED'`, `verified = true`, `approvedAt = now()`, `approvedBy = adminId`, `reviewedAt = now()`. Cuando rechaza: `status = 'REJECTED'`, `rejectionReason = ...`, `adminNotes = ...`, `reviewedAt = now()`.

---

## 4. Resumen de campos nuevos

| Campo                 | Tipo           | Uso |
|-----------------------|----------------|-----|
| `status`              | CaregiverStatus| Flujo: DRAFT → PENDING_REVIEW → APPROVED / REJECTED / NEEDS_REVISION; SUSPENDED aparte. |
| `bioDetail`            | String? (300)  | Complemento de bio (wizard paso 5). |
| `spaceDescription`    | String? (500)  | Descripción del espacio (wizard paso 6). |
| `termsAccepted`       | Boolean?       | Aceptación términos. |
| `privacyAccepted`     | Boolean?       | Aceptación privacidad. |
| `verificationAccepted`| Boolean?       | Aceptación verificación. |
| `termsAcceptedAt`     | DateTime?      | Auditoría aceptaciones. |
| `rejectionReason`     | Text           | Motivo de rechazo (admin). |
| `adminNotes`          | Text           | Notas internas admin. |
| `approvedAt`          | DateTime?      | Fecha de aprobación. |
| `approvedBy`          | String?        | ID del admin que aprobó. |
| `reviewedAt`          | DateTime?      | Última revisión admin. |

Tipos estrictos: `Json` para estructuras complejas (`serviceAvailability`, `rates`, `currentPetsDetails`); `@db.Text` para textos largos (`rejectionReason`, `adminNotes`, descripciones); `@db.VarChar(n)` donde hay límite (bio, bioDetail, spaceType, spaceDescription, address, breedsWhy).

---

## 5. Sugerencias para compatibilidad con código existente

- **Si ya hay datos en producción**  
  1. Aplicar la migración (las columnas nuevas son opcionales y no rompen lecturas).  
  2. Ejecutar el backfill de `status` (opción A o B anterior).  
  3. En el código, seguir leyendo `verified` para “¿está aprobado?” hasta que migres todas las consultas a `status === 'APPROVED'`.  
  4. En `registerCaregiver`: al crear el perfil, además de `verificationStatus: PENDING_REVIEW` y `verified: false`, setear `status: 'PENDING_REVIEW'` para nuevos registros.

- **Panel admin**  
  - Listar por `status IN ('PENDING_REVIEW', 'NEEDS_REVISION')` para la cola de revisión.  
  - Al aprobar: actualizar `status = 'APPROVED'`, `verified = true`, `verifiedAt`/`approvedAt`/`approvedBy`/`reviewedAt`.  
  - Al rechazar: `status = 'REJECTED'`, `rejectionReason`, `adminNotes`, `reviewedAt`.  
  - Al pedir cambios: `status = 'NEEDS_REVISION'`, `adminNotes`, `reviewedAt`.  
  - Suspender: `status = 'SUSPENDED'`, `suspended = true`, `suspendedAt`, `suspensionReason`.

- **Borrador (progreso guardado)**  
  Si en el futuro guardas borradores en DB (no solo en `localStorage`), crea el perfil con `status: 'DRAFT'` y actualiza con cada paso; al enviar el formulario final, pasa a `status: 'PENDING_REVIEW'`.

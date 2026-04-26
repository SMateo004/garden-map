-- Add ON DELETE CASCADE to SugerenciaPrecio.caregiverId FK
ALTER TABLE "SugerenciaPrecio" DROP CONSTRAINT IF EXISTS "SugerenciaPrecio_caregiverId_fkey";
ALTER TABLE "SugerenciaPrecio" ADD CONSTRAINT "SugerenciaPrecio_caregiverId_fkey"
  FOREIGN KEY ("caregiverId") REFERENCES "caregiver_profiles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

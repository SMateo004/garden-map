-- Emergency contacts (1-3, required before offering Hospedaje/Guardería per Terms
-- & Conditions Section 17 "Contacto de emergencia obligatorio").
-- Applied to the live database via `npx prisma db push` (see project notes on migration
-- drift); this file exists for changelog/documentation consistency with the rest of
-- prisma/migrations.

-- AlterTable
ALTER TABLE "caregiver_profiles" ADD COLUMN "emergencyContacts" JSONB;

-- Añadir GUARDERIA al enum ServiceType
ALTER TYPE "ServiceType" ADD VALUE IF NOT EXISTS 'GUARDERIA';

-- Añadir columna de precio para guardería
ALTER TABLE "caregiver_profiles" ADD COLUMN IF NOT EXISTS "pricePerGuarderia" DOUBLE PRECISION;

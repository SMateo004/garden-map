-- Fix: walkerPhotos column on caregiver_profiles was NOT NULL without a default,
-- causing initCaregiverProfile to throw a 500 (null constraint violation).
-- Restore the intended DEFAULT '{}' so empty-profile creates succeed.
ALTER TABLE "caregiver_profiles"
  ALTER COLUMN "walkerPhotos" SET DEFAULT ARRAY[]::TEXT[];

-- Convert NULL animalTypes to empty array so isEmpty filter works correctly
UPDATE "caregiver_profiles"
SET "animalTypes" = ARRAY[]::"AnimalType"[]
WHERE "animalTypes" IS NULL;

-- Set default so new rows always get empty array instead of NULL
ALTER TABLE "caregiver_profiles"
ALTER COLUMN "animalTypes" SET DEFAULT ARRAY[]::"AnimalType"[];

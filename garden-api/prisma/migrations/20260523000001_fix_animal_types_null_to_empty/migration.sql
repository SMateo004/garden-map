-- Step 1: Populate animalTypes from serviceDetails.acceptedPetTypes for profiles
-- where animalTypes is NULL but serviceDetails has the data (legacy profiles)
UPDATE "caregiver_profiles"
SET "animalTypes" = ARRAY(
  SELECT value::"AnimalType"
  FROM jsonb_array_elements_text("serviceDetails"->'acceptedPetTypes') AS value
  WHERE value IN ('DOGS', 'CATS', 'PUPPIES', 'SENIORS', 'LARGE', 'SMALL', 'SPECIAL')
)
WHERE "animalTypes" IS NULL
  AND "serviceDetails" IS NOT NULL
  AND "serviceDetails"->'acceptedPetTypes' IS NOT NULL
  AND jsonb_typeof("serviceDetails"->'acceptedPetTypes') = 'array'
  AND jsonb_array_length("serviceDetails"->'acceptedPetTypes') > 0;

-- Step 2: Set remaining NULL animalTypes to empty array (no restriction configured)
UPDATE "caregiver_profiles"
SET "animalTypes" = ARRAY[]::"AnimalType"[]
WHERE "animalTypes" IS NULL;

-- Step 3: Set column default so new rows never get NULL
ALTER TABLE "caregiver_profiles"
ALTER COLUMN "animalTypes" SET DEFAULT ARRAY[]::"AnimalType"[];

-- Step 4: Populate sizesAccepted from serviceDetails.acceptedSizes for profiles
-- where sizesAccepted is NULL or empty but serviceDetails has the data
UPDATE "caregiver_profiles"
SET "sizesAccepted" = ARRAY(
  SELECT value
  FROM jsonb_array_elements_text("serviceDetails"->'acceptedSizes') AS value
  WHERE value IN ('SMALL', 'MEDIUM', 'LARGE', 'GIANT')
)
WHERE (array_length("sizesAccepted", 1) IS NULL OR array_length("sizesAccepted", 1) = 0)
  AND "serviceDetails" IS NOT NULL
  AND "serviceDetails"->'acceptedSizes' IS NOT NULL
  AND jsonb_typeof("serviceDetails"->'acceptedSizes') = 'array'
  AND jsonb_array_length("serviceDetails"->'acceptedSizes') > 0;

-- Safe backfill: animalTypes and sizesAccepted from serviceDetails.
-- Uses DO block so a bad data row never fails the deployment.
DO $$
BEGIN
  UPDATE "caregiver_profiles"
  SET "animalTypes" = ARRAY(
    SELECT value::"AnimalType"
    FROM jsonb_array_elements_text("serviceDetails"->'acceptedPetTypes') AS value
    WHERE value IN ('DOGS', 'CATS', 'PUPPIES', 'SENIORS', 'LARGE', 'SMALL', 'SPECIAL')
  )
  WHERE array_length("animalTypes", 1) IS NULL
    AND "serviceDetails" IS NOT NULL
    AND ("serviceDetails"->>'acceptedPetTypes') IS NOT NULL
    AND jsonb_typeof("serviceDetails"->'acceptedPetTypes') = 'array'
    AND jsonb_array_length("serviceDetails"->'acceptedPetTypes') > 0;

  UPDATE "caregiver_profiles"
  SET "sizesAccepted" = ARRAY(
    SELECT value
    FROM jsonb_array_elements_text("serviceDetails"->'acceptedSizes') AS value
    WHERE value IN ('SMALL', 'MEDIUM', 'LARGE', 'GIANT')
  )
  WHERE array_length("sizesAccepted", 1) IS NULL
    AND "serviceDetails" IS NOT NULL
    AND ("serviceDetails"->>'acceptedSizes') IS NOT NULL
    AND jsonb_typeof("serviceDetails"->'acceptedSizes') = 'array'
    AND jsonb_array_length("serviceDetails"->'acceptedSizes') > 0;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Migration 20260523000003 non-fatal error: %', SQLERRM;
END;
$$;

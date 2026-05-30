-- Cap existing maxPets values greater than 3 down to 3
UPDATE "CaregiverProfile"
SET "maxPets" = 3
WHERE "maxPets" IS NOT NULL AND "maxPets" > 3;

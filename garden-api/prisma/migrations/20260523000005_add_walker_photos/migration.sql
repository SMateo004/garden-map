-- Add walkerPhotos array field to CaregiverProfile for PASEO-only caregivers
ALTER TABLE "caregiver_profiles" ADD COLUMN IF NOT EXISTS "walkerPhotos" TEXT[] NOT NULL DEFAULT '{}';

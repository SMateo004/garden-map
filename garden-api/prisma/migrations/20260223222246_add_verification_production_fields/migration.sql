-- AlterTable
ALTER TABLE "identity_verification_sessions" ADD COLUMN     "documentConfidence" DOUBLE PRECISION,
ADD COLUMN     "identityScore" DOUBLE PRECISION,
ADD COLUMN     "livenessFrameUrls" JSONB,
ADD COLUMN     "livenessScore" DOUBLE PRECISION,
ADD COLUMN     "ocrData" JSONB,
ADD COLUMN     "similarityScore" DOUBLE PRECISION;

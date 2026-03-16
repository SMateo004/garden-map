-- AlterTable
ALTER TABLE "identity_verification_sessions" ADD COLUMN     "faceCroppedDocumentUrl" TEXT,
ADD COLUMN     "faceCroppedSelfieUrl" TEXT,
ADD COLUMN     "rejectionReason" TEXT;

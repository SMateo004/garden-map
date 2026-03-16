-- CreateEnum
CREATE TYPE "UserRole" AS ENUM ('CLIENT', 'CAREGIVER', 'ADMIN');

-- CreateEnum
CREATE TYPE "ServiceType" AS ENUM ('HOSPEDAJE', 'PASEO');

-- CreateEnum
CREATE TYPE "Zone" AS ENUM ('EQUIPETROL', 'URBARI', 'NORTE', 'LAS_PALMAS', 'CENTRO_SAN_MARTIN', 'OTROS');

-- CreateEnum
CREATE TYPE "BookingStatus" AS ENUM ('PENDING_PAYMENT', 'PAYMENT_PENDING_APPROVAL', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'CANCELLATION_REQUESTED');

-- CreateEnum
CREATE TYPE "RefundStatus" AS ENUM ('PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'PROCESSED');

-- CreateEnum
CREATE TYPE "TimeSlot" AS ENUM ('MANANA', 'TARDE', 'NOCHE');

-- CreateEnum
CREATE TYPE "ExperienceYears" AS ENUM ('NEVER', 'LESS1', 'ONE_TO_FIVE', 'MORE5');

-- CreateEnum
CREATE TYPE "AnimalType" AS ENUM ('DOGS', 'CATS', 'PUPPIES', 'SENIORS', 'LARGE', 'SMALL', 'SPECIAL');

-- CreateEnum
CREATE TYPE "MedicationType" AS ENUM ('ORAL', 'INJECT', 'TOPIC');

-- CreateEnum
CREATE TYPE "PetSize" AS ENUM ('SMALL', 'MEDIUM', 'LARGE', 'GIANT');

-- CreateEnum
CREATE TYPE "HomeType" AS ENUM ('HOUSE', 'APARTMENT');

-- CreateEnum
CREATE TYPE "PetsSleep" AS ENUM ('INSIDE', 'OUTSIDE');

-- CreateEnum
CREATE TYPE "ClientPetsSleep" AS ENUM ('BED', 'CRATE', 'SOFA', 'FLOOR');

-- CreateEnum
CREATE TYPE "VerificationStatus" AS ENUM ('PENDING_REVIEW', 'APPROVED', 'REJECTED');

-- CreateEnum
CREATE TYPE "CaregiverStatus" AS ENUM ('DRAFT', 'PENDING_REVIEW', 'NEEDS_REVISION', 'APPROVED', 'REJECTED', 'SUSPENDED');

-- CreateTable
CREATE TABLE "users" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "role" "UserRole" NOT NULL,
    "firstName" TEXT NOT NULL,
    "lastName" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "profilePicture" TEXT,
    "country" TEXT,
    "city" TEXT,
    "isOver18" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "dateOfBirth" DATE,
    "emailVerified" BOOLEAN NOT NULL DEFAULT false,
    "emailVerificationCode" VARCHAR(6),
    "emailVerificationExpires" TIMESTAMP(3),

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "caregiver_profiles" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" "CaregiverStatus" NOT NULL DEFAULT 'DRAFT',
    "verified" BOOLEAN NOT NULL DEFAULT false,
    "verifiedAt" TIMESTAMP(3),
    "verifiedBy" TEXT,
    "verificationNotes" TEXT,
    "verificationStatus" "VerificationStatus" NOT NULL DEFAULT 'PENDING_REVIEW',
    "rejectionReason" TEXT,
    "adminNotes" TEXT,
    "approvedAt" TIMESTAMP(3),
    "approvedBy" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "suspended" BOOLEAN NOT NULL DEFAULT false,
    "suspendedAt" TIMESTAMP(3),
    "suspensionReason" TEXT,
    "rating" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "reviewCount" INTEGER NOT NULL DEFAULT 0,
    "bio" VARCHAR(500),
    "bioDetail" VARCHAR(300),
    "zone" "Zone",
    "spaceType" TEXT[],
    "spaceDescription" VARCHAR(500),
    "photos" TEXT[],
    "profilePhoto" TEXT,
    "address" VARCHAR(500),
    "servicesOffered" "ServiceType"[],
    "serviceAvailability" JSONB,
    "pricePerDay" INTEGER,
    "pricePerWalk30" INTEGER,
    "pricePerWalk60" INTEGER,
    "rates" JSONB,
    "termsAccepted" BOOLEAN,
    "privacyAccepted" BOOLEAN,
    "verificationAccepted" BOOLEAN,
    "termsAcceptedAt" TIMESTAMP(3),
    "experienceYears" "ExperienceYears",
    "ownPets" BOOLEAN,
    "currentPetsDetails" JSONB,
    "caredOthers" BOOLEAN,
    "animalTypes" "AnimalType"[],
    "experienceDescription" TEXT,
    "whyCaregiver" TEXT,
    "whatDiffers" TEXT,
    "handleAnxious" TEXT,
    "emergencyResponse" TEXT,
    "acceptAggressive" BOOLEAN,
    "acceptMedication" "MedicationType"[],
    "acceptPuppies" BOOLEAN,
    "acceptSeniors" BOOLEAN,
    "sizesAccepted" "PetSize"[],
    "noAcceptBreeds" BOOLEAN,
    "breedsWhy" VARCHAR(500),
    "homeType" "HomeType",
    "ownHome" BOOLEAN,
    "hasYard" BOOLEAN,
    "yardFenced" BOOLEAN,
    "hasChildren" BOOLEAN,
    "hasOtherPets" BOOLEAN,
    "petsSleep" "PetsSleep",
    "clientPetsSleep" "ClientPetsSleep",
    "hoursAlone" INTEGER,
    "workFromHome" BOOLEAN,
    "maxPets" INTEGER,
    "oftenOut" BOOLEAN,
    "typicalDay" TEXT,
    "idDocument" TEXT,
    "selfie" TEXT,
    "ciAnversoUrl" TEXT,
    "ciReversoUrl" TEXT,
    "ciNumber" VARCHAR(50),
    "defaultAvailabilitySchedule" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "onboardingStatus" JSONB,
    "identityVerificationStatus" VARCHAR(20) DEFAULT 'PENDING',
    "identityVerificationToken" VARCHAR(64),
    "identityVerificationScore" DOUBLE PRECISION,
    "identityVerificationSubmittedAt" TIMESTAMP(3),
    "emailVerified" BOOLEAN NOT NULL DEFAULT false,
    "profileStatus" VARCHAR(20) DEFAULT 'INCOMPLETE',
    "availabilityComplete" BOOLEAN NOT NULL DEFAULT false,
    "caregiverProfileComplete" BOOLEAN NOT NULL DEFAULT false,
    "personalInfoComplete" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "caregiver_profiles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "availability" (
    "id" TEXT NOT NULL,
    "caregiverId" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "isAvailable" BOOLEAN NOT NULL DEFAULT true,
    "timeBlocks" JSONB,
    "overrideReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "availability_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "bookings" (
    "id" TEXT NOT NULL,
    "clientId" TEXT NOT NULL,
    "caregiverId" TEXT NOT NULL,
    "serviceType" "ServiceType" NOT NULL,
    "status" "BookingStatus" NOT NULL DEFAULT 'PENDING_PAYMENT',
    "startDate" DATE,
    "endDate" DATE,
    "totalDays" INTEGER,
    "walkDate" DATE,
    "timeSlot" "TimeSlot",
    "duration" INTEGER,
    "petId" TEXT,
    "petName" VARCHAR(200) NOT NULL,
    "petBreed" VARCHAR(100),
    "petAge" INTEGER,
    "petSize" "PetSize",
    "specialNeeds" TEXT,
    "totalAmount" DECIMAL(10,2) NOT NULL,
    "pricePerUnit" DECIMAL(10,2) NOT NULL,
    "commissionAmount" DECIMAL(10,2) NOT NULL,
    "stripeCheckoutSessionId" TEXT,
    "stripePaymentIntentId" TEXT,
    "qrId" TEXT,
    "qrImageUrl" TEXT,
    "qrExpiresAt" TIMESTAMP(3),
    "paidAt" TIMESTAMP(3),
    "cancelledAt" TIMESTAMP(3),
    "cancellationReason" TEXT,
    "refundAmount" DECIMAL(10,2),
    "refundStatus" "RefundStatus",
    "cancellationRequestedAt" TIMESTAMP(3),
    "cancellationRequestReason" TEXT,
    "adminCancellationApproved" BOOLEAN DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "bookings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "reviews" (
    "id" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "clientId" TEXT NOT NULL,
    "caregiverId" TEXT NOT NULL,
    "rating" SMALLINT NOT NULL,
    "comment" TEXT,
    "photo" TEXT,
    "serviceType" "ServiceType" NOT NULL,
    "caregiverResponse" TEXT,
    "respondedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "reviews_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "client_profiles" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "address" VARCHAR(500),
    "phone" VARCHAR(20),
    "petPhoto" TEXT,
    "isComplete" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "client_profiles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pets" (
    "id" TEXT NOT NULL,
    "clientProfileId" TEXT NOT NULL,
    "name" VARCHAR(200) NOT NULL,
    "breed" VARCHAR(100),
    "age" INTEGER,
    "size" "PetSize",
    "photoUrl" TEXT,
    "specialNeeds" TEXT,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "pets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "admin_actions" (
    "id" TEXT NOT NULL,
    "adminId" TEXT NOT NULL,
    "actionType" TEXT NOT NULL,
    "targetId" TEXT NOT NULL,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "admin_actions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "admin_notifications" (
    "id" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "caregiverId" TEXT NOT NULL,
    "bookingId" TEXT,
    "readAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "admin_notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "identity_verification_sessions" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" VARCHAR(20) NOT NULL,
    "similarity" DOUBLE PRECISION,
    "selfieUrl" TEXT,
    "ciFrontUrl" TEXT,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),
    "reviewedBy" TEXT,
    "reviewedAt" TIMESTAMP(3),

    CONSTRAINT "identity_verification_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE UNIQUE INDEX "users_phone_key" ON "users"("phone");

-- CreateIndex
CREATE INDEX "users_email_idx" ON "users"("email");

-- CreateIndex
CREATE INDEX "users_role_idx" ON "users"("role");

-- CreateIndex
CREATE INDEX "users_phone_idx" ON "users"("phone");

-- CreateIndex
CREATE UNIQUE INDEX "caregiver_profiles_userId_key" ON "caregiver_profiles"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "caregiver_profiles_identityVerificationToken_key" ON "caregiver_profiles"("identityVerificationToken");

-- CreateIndex
CREATE INDEX "caregiver_profiles_status_idx" ON "caregiver_profiles"("status");

-- CreateIndex
CREATE INDEX "caregiver_profiles_userId_idx" ON "caregiver_profiles"("userId");

-- CreateIndex
CREATE INDEX "caregiver_profiles_zone_verified_idx" ON "caregiver_profiles"("zone", "verified");

-- CreateIndex
CREATE INDEX "caregiver_profiles_verified_idx" ON "caregiver_profiles"("verified");

-- CreateIndex
CREATE INDEX "caregiver_profiles_zone_verified_suspended_idx" ON "caregiver_profiles"("zone", "verified", "suspended");

-- CreateIndex
CREATE INDEX "caregiver_profiles_verified_suspended_idx" ON "caregiver_profiles"("verified", "suspended");

-- CreateIndex
CREATE INDEX "caregiver_profiles_verificationStatus_idx" ON "caregiver_profiles"("verificationStatus");

-- CreateIndex
CREATE INDEX "caregiver_profiles_rating_idx" ON "caregiver_profiles"("rating" DESC);

-- CreateIndex
CREATE INDEX "caregiver_profiles_createdAt_idx" ON "caregiver_profiles"("createdAt" DESC);

-- CreateIndex
CREATE INDEX "caregiver_profiles_experienceYears_idx" ON "caregiver_profiles"("experienceYears");

-- CreateIndex
CREATE INDEX "caregiver_profiles_animalTypes_idx" ON "caregiver_profiles"("animalTypes");

-- CreateIndex
CREATE INDEX "availability_caregiverId_idx" ON "availability"("caregiverId");

-- CreateIndex
CREATE INDEX "availability_caregiverId_date_idx" ON "availability"("caregiverId", "date");

-- CreateIndex
CREATE INDEX "availability_date_isAvailable_idx" ON "availability"("date", "isAvailable");

-- CreateIndex
CREATE UNIQUE INDEX "availability_caregiverId_date_key" ON "availability"("caregiverId", "date");

-- CreateIndex
CREATE UNIQUE INDEX "bookings_stripeCheckoutSessionId_key" ON "bookings"("stripeCheckoutSessionId");

-- CreateIndex
CREATE UNIQUE INDEX "bookings_qrId_key" ON "bookings"("qrId");

-- CreateIndex
CREATE INDEX "bookings_clientId_status_idx" ON "bookings"("clientId", "status");

-- CreateIndex
CREATE INDEX "bookings_caregiverId_status_idx" ON "bookings"("caregiverId", "status");

-- CreateIndex
CREATE INDEX "bookings_status_idx" ON "bookings"("status");

-- CreateIndex
CREATE INDEX "bookings_status_startDate_idx" ON "bookings"("status", "startDate");

-- CreateIndex
CREATE INDEX "bookings_paidAt_idx" ON "bookings"("paidAt");

-- CreateIndex
CREATE INDEX "bookings_cancellationRequestedAt_idx" ON "bookings"("cancellationRequestedAt");

-- CreateIndex
CREATE INDEX "bookings_petId_idx" ON "bookings"("petId");

-- CreateIndex
CREATE UNIQUE INDEX "reviews_bookingId_key" ON "reviews"("bookingId");

-- CreateIndex
CREATE INDEX "reviews_caregiverId_rating_idx" ON "reviews"("caregiverId", "rating");

-- CreateIndex
CREATE UNIQUE INDEX "client_profiles_userId_key" ON "client_profiles"("userId");

-- CreateIndex
CREATE INDEX "client_profiles_userId_idx" ON "client_profiles"("userId");

-- CreateIndex
CREATE INDEX "client_profiles_isComplete_idx" ON "client_profiles"("isComplete");

-- CreateIndex
CREATE INDEX "pets_clientProfileId_idx" ON "pets"("clientProfileId");

-- CreateIndex
CREATE INDEX "admin_actions_adminId_actionType_idx" ON "admin_actions"("adminId", "actionType");

-- CreateIndex
CREATE INDEX "admin_actions_targetId_idx" ON "admin_actions"("targetId");

-- CreateIndex
CREATE INDEX "admin_notifications_type_readAt_idx" ON "admin_notifications"("type", "readAt");

-- CreateIndex
CREATE INDEX "admin_notifications_caregiverId_idx" ON "admin_notifications"("caregiverId");

-- CreateIndex
CREATE INDEX "admin_notifications_bookingId_idx" ON "admin_notifications"("bookingId");

-- CreateIndex
CREATE INDEX "identity_verification_sessions_userId_idx" ON "identity_verification_sessions"("userId");

-- CreateIndex
CREATE INDEX "identity_verification_sessions_status_idx" ON "identity_verification_sessions"("status");

-- CreateIndex
CREATE INDEX "identity_verification_sessions_expiresAt_idx" ON "identity_verification_sessions"("expiresAt");

-- AddForeignKey
ALTER TABLE "caregiver_profiles" ADD CONSTRAINT "caregiver_profiles_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "availability" ADD CONSTRAINT "availability_caregiverId_fkey" FOREIGN KEY ("caregiverId") REFERENCES "caregiver_profiles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_caregiverId_fkey" FOREIGN KEY ("caregiverId") REFERENCES "caregiver_profiles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_clientId_fkey" FOREIGN KEY ("clientId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_petId_fkey" FOREIGN KEY ("petId") REFERENCES "pets"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reviews" ADD CONSTRAINT "reviews_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "bookings"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reviews" ADD CONSTRAINT "reviews_caregiverId_fkey" FOREIGN KEY ("caregiverId") REFERENCES "caregiver_profiles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reviews" ADD CONSTRAINT "reviews_clientId_fkey" FOREIGN KEY ("clientId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "client_profiles" ADD CONSTRAINT "client_profiles_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pets" ADD CONSTRAINT "pets_clientProfileId_fkey" FOREIGN KEY ("clientProfileId") REFERENCES "client_profiles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "identity_verification_sessions" ADD CONSTRAINT "identity_verification_sessions_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

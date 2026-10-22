-- Recojo y entrega a domicilio (Guardería / Hospedaje)
ALTER TABLE "caregiver_profiles"
  ADD COLUMN "transportEnabled" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "transportPickupFee" DECIMAL(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN "transportDropoffFee" DECIMAL(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN "transportMaxKm" DECIMAL(5,1) NOT NULL DEFAULT 5;

ALTER TABLE "bookings"
  ADD COLUMN "transportAmount" DECIMAL(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN "transportTaxAmount" DECIMAL(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN "transportRefundAmount" DECIMAL(10,2) NOT NULL DEFAULT 0;

CREATE TABLE "booking_transport_legs" (
  "id" TEXT NOT NULL,
  "bookingId" TEXT NOT NULL,
  "kind" VARCHAR(10) NOT NULL,
  "fee" DECIMAL(10,2) NOT NULL,
  "tax" DECIMAL(10,2) NOT NULL DEFAULT 0,
  "time" VARCHAR(5),
  "address" VARCHAR(500),
  "addressLat" DOUBLE PRECISION NOT NULL,
  "addressLng" DOUBLE PRECISION NOT NULL,
  "addressReference" VARCHAR(300),
  "distanceKm" DECIMAL(6,2) NOT NULL,
  "status" VARCHAR(12) NOT NULL DEFAULT 'SCHEDULED',
  "enRouteAt" TIMESTAMP(3),
  "arrivedAt" TIMESTAMP(3),
  "doneAt" TIMESTAMP(3),
  "donePhoto" TEXT,
  "atBaseAt" TIMESTAMP(3),
  "cancelledAt" TIMESTAMP(3),
  "cancelledBy" VARCHAR(10),
  "cancelReason" VARCHAR(300),
  "refundedAmount" DECIMAL(10,2) NOT NULL DEFAULT 0,
  "trackingData" JSONB,
  "reminderSentAt" TIMESTAMP(3),
  "lateNoticeAt" TIMESTAMP(3),
  "adminAlertAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "booking_transport_legs_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "booking_transport_legs_bookingId_kind_key" ON "booking_transport_legs"("bookingId", "kind");
CREATE INDEX "booking_transport_legs_status_idx" ON "booking_transport_legs"("status");
ALTER TABLE "booking_transport_legs" ADD CONSTRAINT "booking_transport_legs_bookingId_fkey"
  FOREIGN KEY ("bookingId") REFERENCES "bookings"("id") ON DELETE CASCADE ON UPDATE CASCADE;

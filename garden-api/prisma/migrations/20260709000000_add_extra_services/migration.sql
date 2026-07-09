-- Servicios extra configurables por cuidador (hoy exclusivo de empresas,
-- isCompany=true, validado en el service) y su snapshot por reserva.
-- Se cobran siempre por día.
CREATE TABLE "extra_services" (
    "id" TEXT NOT NULL,
    "caregiverId" TEXT NOT NULL,
    "name" VARCHAR(100) NOT NULL,
    "pricePerDay" DECIMAL(10,2) NOT NULL,
    "appliesTo" "ServiceType"[],
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "extra_services_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "booking_extras" (
    "id" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "extraServiceId" TEXT,
    "name" VARCHAR(100) NOT NULL,
    "pricePerDay" DECIMAL(10,2) NOT NULL,
    "totalPrice" DECIMAL(10,2) NOT NULL,

    CONSTRAINT "booking_extras_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "extra_services_caregiverId_idx" ON "extra_services"("caregiverId");

CREATE INDEX "booking_extras_bookingId_idx" ON "booking_extras"("bookingId");

ALTER TABLE "extra_services" ADD CONSTRAINT "extra_services_caregiverId_fkey" FOREIGN KEY ("caregiverId") REFERENCES "caregiver_profiles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "booking_extras" ADD CONSTRAINT "booking_extras_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "bookings"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "booking_extras" ADD CONSTRAINT "booking_extras_extraServiceId_fkey" FOREIGN KEY ("extraServiceId") REFERENCES "extra_services"("id") ON DELETE SET NULL ON UPDATE CASCADE;

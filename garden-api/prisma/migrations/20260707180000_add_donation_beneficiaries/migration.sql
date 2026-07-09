-- Beneficiarios de donaciones (hogares de mascotas / refugios) + trazabilidad
-- de a quién se le transfirió cada donación. El monto (`amount`) de Donation
-- nunca se edita — solo se registra el desembolso y hacia quién.
CREATE TABLE "donation_beneficiaries" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "contactInfo" VARCHAR(300),
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "donation_beneficiaries_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "donations" ADD COLUMN     "beneficiaryId" TEXT,
ADD COLUMN     "disbursedByAdminId" TEXT;

CREATE INDEX "donations_beneficiaryId_idx" ON "donations"("beneficiaryId");

ALTER TABLE "donations" ADD CONSTRAINT "donations_beneficiaryId_fkey" FOREIGN KEY ("beneficiaryId") REFERENCES "donation_beneficiaries"("id") ON DELETE SET NULL ON UPDATE CASCADE;

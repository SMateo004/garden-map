-- Tarjeta de donador en la billetera: código único fijo de por vida (lazy,
-- se genera la primera vez que el cliente abre la tarjeta) y registro de
-- canjes en veterinarias/negocios asociados (cargados a mano por el admin).
ALTER TABLE "users" ADD COLUMN "donorCode" TEXT;

CREATE UNIQUE INDEX "users_donorCode_key" ON "users"("donorCode");

CREATE TABLE "donor_code_redemptions" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "businessName" VARCHAR(200) NOT NULL,
    "redeemedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "loggedByAdminId" TEXT,

    CONSTRAINT "donor_code_redemptions_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "donor_code_redemptions_userId_idx" ON "donor_code_redemptions"("userId");

ALTER TABLE "donor_code_redemptions" ADD CONSTRAINT "donor_code_redemptions_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

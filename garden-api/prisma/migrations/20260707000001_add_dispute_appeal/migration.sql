-- Apelaciones de disputas: cualquiera de las partes puede apelar el veredicto
-- de la IA dentro de 5 días hábiles. La apelación la revisa un admin humano
-- y su decisión es definitiva (Sección 13 de los Términos y Condiciones).
ALTER TABLE "Dispute" ADD COLUMN     "appealedBy" TEXT,
ADD COLUMN     "appealReason" TEXT,
ADD COLUMN     "appealedAt" TIMESTAMP(3),
ADD COLUMN     "appealResolution" TEXT,
ADD COLUMN     "appealVerdict" TEXT,
ADD COLUMN     "appealResolvedByAdminId" TEXT,
ADD COLUMN     "appealResolvedAt" TIMESTAMP(3);

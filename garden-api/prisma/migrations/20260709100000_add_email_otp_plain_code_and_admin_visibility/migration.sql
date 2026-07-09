-- Código de verificación de email en texto plano, guardado solo cuando el
-- setting global "otpVisibleToAdminEnabled" está activo (para pruebas).
ALTER TABLE "email_verifications" ADD COLUMN "plainCode" VARCHAR(6);

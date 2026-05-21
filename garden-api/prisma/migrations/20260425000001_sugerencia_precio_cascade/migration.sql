-- Add ON DELETE CASCADE to missing FK constraints that blocked caregiver deletion
-- All operations use DROP IF EXISTS + conditional DO blocks → fully idempotent.

-- SugerenciaPrecio → CaregiverProfile (conditional: table may not exist in all envs)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'SugerenciaPrecio'
  ) THEN
    EXECUTE 'ALTER TABLE "SugerenciaPrecio" DROP CONSTRAINT IF EXISTS "SugerenciaPrecio_caregiverId_fkey"';
    EXECUTE 'ALTER TABLE "SugerenciaPrecio" ADD CONSTRAINT "SugerenciaPrecio_caregiverId_fkey"
      FOREIGN KEY ("caregiverId") REFERENCES "caregiver_profiles"("id") ON DELETE CASCADE ON UPDATE CASCADE';
  END IF;
END $$;

-- ChatMessage → Booking / User (conditional)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'ChatMessage'
  ) THEN
    EXECUTE 'ALTER TABLE "ChatMessage" DROP CONSTRAINT IF EXISTS "ChatMessage_bookingId_fkey"';
    EXECUTE 'ALTER TABLE "ChatMessage" ADD CONSTRAINT "ChatMessage_bookingId_fkey"
      FOREIGN KEY ("bookingId") REFERENCES "bookings"("id") ON DELETE CASCADE ON UPDATE CASCADE';
    EXECUTE 'ALTER TABLE "ChatMessage" DROP CONSTRAINT IF EXISTS "ChatMessage_senderId_fkey"';
    EXECUTE 'ALTER TABLE "ChatMessage" ADD CONSTRAINT "ChatMessage_senderId_fkey"
      FOREIGN KEY ("senderId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE';
  END IF;
END $$;

-- MeetAndGreet → Booking (conditional)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'MeetAndGreet'
  ) THEN
    EXECUTE 'ALTER TABLE "MeetAndGreet" DROP CONSTRAINT IF EXISTS "MeetAndGreet_bookingId_fkey"';
    EXECUTE 'ALTER TABLE "MeetAndGreet" ADD CONSTRAINT "MeetAndGreet_bookingId_fkey"
      FOREIGN KEY ("bookingId") REFERENCES "bookings"("id") ON DELETE CASCADE ON UPDATE CASCADE';
  END IF;
END $$;

-- Dispute → Booking (conditional)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'Dispute'
  ) THEN
    EXECUTE 'ALTER TABLE "Dispute" DROP CONSTRAINT IF EXISTS "Dispute_bookingId_fkey"';
    EXECUTE 'ALTER TABLE "Dispute" ADD CONSTRAINT "Dispute_bookingId_fkey"
      FOREIGN KEY ("bookingId") REFERENCES "bookings"("id") ON DELETE CASCADE ON UPDATE CASCADE';
  END IF;
END $$;

-- wallet_transactions → users (was "WalletTransaction" in old naming — table is wallet_transactions)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'wallet_transactions'
  ) THEN
    EXECUTE 'ALTER TABLE "wallet_transactions" DROP CONSTRAINT IF EXISTS "wallet_transactions_userId_fkey"';
    EXECUTE 'ALTER TABLE "wallet_transactions" DROP CONSTRAINT IF EXISTS "WalletTransaction_userId_fkey"';
    EXECUTE 'ALTER TABLE "wallet_transactions" ADD CONSTRAINT "wallet_transactions_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE';
  END IF;
END $$;

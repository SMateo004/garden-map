-- Add ON DELETE CASCADE to missing FK constraints that blocked caregiver deletion

-- SugerenciaPrecio → CaregiverProfile
ALTER TABLE "SugerenciaPrecio" DROP CONSTRAINT IF EXISTS "SugerenciaPrecio_caregiverId_fkey";
ALTER TABLE "SugerenciaPrecio" ADD CONSTRAINT "SugerenciaPrecio_caregiverId_fkey"
  FOREIGN KEY ("caregiverId") REFERENCES "caregiver_profiles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ChatMessage → Booking
ALTER TABLE "ChatMessage" DROP CONSTRAINT IF EXISTS "ChatMessage_bookingId_fkey";
ALTER TABLE "ChatMessage" ADD CONSTRAINT "ChatMessage_bookingId_fkey"
  FOREIGN KEY ("bookingId") REFERENCES "bookings"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ChatMessage → User (sender)
ALTER TABLE "ChatMessage" DROP CONSTRAINT IF EXISTS "ChatMessage_senderId_fkey";
ALTER TABLE "ChatMessage" ADD CONSTRAINT "ChatMessage_senderId_fkey"
  FOREIGN KEY ("senderId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- MeetAndGreet → Booking
ALTER TABLE "MeetAndGreet" DROP CONSTRAINT IF EXISTS "MeetAndGreet_bookingId_fkey";
ALTER TABLE "MeetAndGreet" ADD CONSTRAINT "MeetAndGreet_bookingId_fkey"
  FOREIGN KEY ("bookingId") REFERENCES "bookings"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Dispute → Booking
ALTER TABLE "Dispute" DROP CONSTRAINT IF EXISTS "Dispute_bookingId_fkey";
ALTER TABLE "Dispute" ADD CONSTRAINT "Dispute_bookingId_fkey"
  FOREIGN KEY ("bookingId") REFERENCES "bookings"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- WalletTransaction → User
ALTER TABLE "WalletTransaction" DROP CONSTRAINT IF EXISTS "WalletTransaction_userId_fkey";
ALTER TABLE "WalletTransaction" ADD CONSTRAINT "WalletTransaction_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Add PENDING_MG status for bookings that require Meet & Greet before payment
ALTER TYPE "BookingStatus" ADD VALUE IF NOT EXISTS 'PENDING_MG' BEFORE 'PENDING_PAYMENT';

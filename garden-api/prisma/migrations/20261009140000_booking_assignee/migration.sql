ALTER TABLE "bookings" ADD COLUMN "assignedStaffMemberId" TEXT;
CREATE INDEX "bookings_assignedStaffMemberId_idx" ON "bookings"("assignedStaffMemberId");
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_assignedStaffMemberId_fkey" FOREIGN KEY ("assignedStaffMemberId") REFERENCES "caregiver_staff_members"("id") ON DELETE SET NULL ON UPDATE CASCADE;

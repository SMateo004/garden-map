import type { Booking, ServiceType } from '@prisma/client';

export interface BookingCreateResult {
  id: string;
  status: string;
  totalAmount: string;
  pricePerUnit: string;
  commissionAmount: string;
  qrId: string | null;
  qrImageUrl: string | null;
  qrExpiresAt: string | null;
  serviceType: ServiceType;
  startDate?: string | null;
  endDate?: string | null;
  totalDays?: number | null;
  walkDate?: string | null;
  timeSlot?: string | null;
  duration?: number | null;
  startTime?: string | null;
  petId?: string | null;
  petName: string;
  petBreed?: string | null;
  petAge?: number | null;
  specialNeeds?: string | null;
  caregiverId: string;
  clientId: string;
  createdAt: Date;
  cancelledAt?: string | null;
  cancellationReason?: string | null;
  refundAmount?: string | null;
  refundStatus?: string | null;
  paidAt?: string | null;
  caregiverName?: string;
  caregiverPhoto?: string | null;
  clientName?: string;
  clientEmail?: string;
  clientPhone?: string | null;
  clientPhoto?: string | null;
}

export function bookingToResponse(b: any): BookingCreateResult {
  const res: BookingCreateResult = {
    id: b.id,
    status: b.status,
    totalAmount: String(b.totalAmount),
    pricePerUnit: String(b.pricePerUnit),
    commissionAmount: String(b.commissionAmount),
    qrId: b.qrId,
    qrImageUrl: b.qrImageUrl,
    qrExpiresAt: b.qrExpiresAt?.toISOString() ?? null,
    serviceType: b.serviceType,
    startDate: b.startDate?.toISOString().slice(0, 10) ?? null,
    endDate: b.endDate?.toISOString().slice(0, 10) ?? null,
    totalDays: b.totalDays,
    walkDate: b.walkDate?.toISOString().slice(0, 10) ?? null,
    timeSlot: b.timeSlot,
    duration: b.duration,
    startTime: b.startTime,
    petId: b.petId ?? null,
    petName: b.petName,
    petBreed: b.petBreed ?? null,
    petAge: b.petAge ?? null,
    specialNeeds: b.specialNeeds ?? null,
    caregiverId: b.caregiverId,
    clientId: b.clientId,
    createdAt: b.createdAt,
    cancelledAt: b.cancelledAt?.toISOString() ?? null,
    cancellationReason: b.cancellationReason ?? null,
    refundAmount: b.refundAmount != null ? String(b.refundAmount) : null,
    refundStatus: b.refundStatus ?? null,
    paidAt: b.paidAt?.toISOString() ?? null,
  };

  if (b.caregiver) {
    res.caregiverName = `${b.caregiver.user.firstName} ${b.caregiver.user.lastName}`;
    res.caregiverPhoto = b.caregiver.profilePhoto || b.caregiver.user.profilePicture;
  }

  if (b.client) {
    res.clientName = `${b.client.firstName} ${b.client.lastName}`;
    res.clientEmail = b.client.email;
    res.clientPhone = b.client.phone;
    res.clientPhoto = b.client.profilePicture;
  }

  return res;
}

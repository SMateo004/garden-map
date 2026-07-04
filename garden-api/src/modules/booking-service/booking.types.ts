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
  caregiverPhone?: string | null;
  caregiverPhoto?: string | null;
  clientName?: string;
  clientEmail?: string;
  clientPhone?: string | null;
  clientPhoto?: string | null;
  serviceStartedAt?: string | null;
  serviceEndedAt?: string | null;
  clientMarkedEndAt?: string | null;
  serviceEvents?: any[] | null;
  gpsTrack?: any[] | null;
  gpsDistance?: number | null;
  caregiverAddress?: {
    lat: number | null;
    lng: number | null;
    street: string | null;
    number: string | null;
    apartment: string | null;
    condominio: string | null;
    reference: string | null;
    zone: string | null;
  } | null;
  clientAddress?: {
    lat: number | null;
    lng: number | null;
    street: string | null;
    number: string | null;
    apartment: string | null;
    condominio: string | null;
    reference: string | null;
    zone: string | null;
    full: string | null;
  } | null;
  ownerRated?: boolean;
  ownerRating?: number | null;
  ownerComment?: string | null;
  caregiverRating?: number | null;
  caregiverComment?: string | null;
  hasDisputePending?: boolean;
  disputeReasons?: string[];
  meetAndGreet?: any;
  walletPaymentAmount?: number;
  serviceReport?: any;
  /** Mascotas #2 y #3 de una reserva multi-mascota (petIndex 2, 3) — la
   * mascota #1 ya viene en petName/petBreed/petAge/specialNeeds arriba.
   * Antes esta info se guardaba en BookingPet pero nunca se devolvía al
   * cuidador, así que las necesidades especiales de la 2ª/3ª mascota
   * (ej. alergias, medicación) nunca le llegaban. */
  additionalPets?: Array<{
    petIndex: number;
    petName: string;
    petBreed: string | null;
    petAge: number | null;
    petSize: string | null;
    specialNeeds: string | null;
  }>;
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
    serviceStartedAt: b.serviceStartedAt?.toISOString() ?? null,
    serviceEndedAt: b.serviceEndedAt?.toISOString() ?? null,
    clientMarkedEndAt: b.clientMarkedEndAt?.toISOString() ?? null,
    serviceEvents: b.serviceEvents ?? [],
    gpsTrack: b.serviceTrackingData ?? [],
    gpsDistance: b.gpsDistance ?? null,
    ownerRated: b.ownerRated ?? false,
    ownerRating: b.ownerRating,
    ownerComment: b.ownerComment,
    caregiverRating: b.caregiverRating,
    caregiverComment: b.caregiverComment,
    hasDisputePending: !!(b.dispute && b.dispute.status !== 'RESOLVED'),
    disputeReasons: b.dispute?.clientReasons ?? [],
    meetAndGreet: b.meetAndGreet ?? null,
    walletPaymentAmount: Number(b.walletPaymentAmount ?? 0),
    serviceReport: b.serviceReport ?? null,
  };

  // petIndex 1 es la mascota principal (ya está en petName/specialNeeds
  // arriba) — solo exponemos la 2ª y 3ª aquí para no duplicar.
  if (Array.isArray(b.bookingPets)) {
    const additional = b.bookingPets
      .filter((bp: any) => bp.petIndex > 1)
      .sort((a: any, c: any) => a.petIndex - c.petIndex)
      .map((bp: any) => ({
        petIndex: bp.petIndex,
        petName: bp.petName,
        petBreed: bp.petBreed ?? null,
        petAge: bp.petAge ?? null,
        petSize: bp.petSize ?? null,
        specialNeeds: bp.specialNeeds ?? null,
      }));
    if (additional.length > 0) res.additionalPets = additional;
  }

  if (b.caregiver) {
    res.caregiverName = `${b.caregiver.user.firstName} ${b.caregiver.user.lastName}`;
    res.caregiverPhoto = b.caregiver.profilePhoto || b.caregiver.user.profilePicture;
    res.caregiverPhone = b.caregiver?.user?.phone ?? null;
  }

  if (b.client) {
    res.clientName = `${b.client.firstName} ${b.client.lastName}`;
    res.clientEmail = b.client.email;
    res.clientPhone = b.client.phone;
    res.clientPhoto = b.client.profilePicture;
  }

  if (b.caregiver && b.serviceType === 'HOSPEDAJE' &&
      ['CONFIRMED','IN_PROGRESS','COMPLETED'].includes(b.status)) {
    res.caregiverAddress = {
      lat: b.caregiver.addressLat ?? null,
      lng: b.caregiver.addressLng ?? null,
      street: b.caregiver.addressStreet ?? null,
      number: b.caregiver.addressNumber ?? null,
      apartment: b.caregiver.addressApartment ?? null,
      condominio: b.caregiver.addressCondominio ?? null,
      reference: b.caregiver.addressReference ?? null,
      zone: b.caregiver.addressZone ?? null,
    };
  }

  // Para PASEO: exponer dirección del dueño al cuidador (necesita ir a recoger la mascota)
  if (b.serviceType === 'PASEO' && ['CONFIRMED','IN_PROGRESS'].includes(b.status)) {
    const cp = b.client?.clientProfile ?? null;
    if (cp) {
      res.clientAddress = {
        lat: cp.addressLat ?? null,
        lng: cp.addressLng ?? null,
        street: cp.addressStreet ?? null,
        number: cp.addressNumber ?? null,
        apartment: cp.addressApartment ?? null,
        condominio: cp.addressCondominio ?? null,
        reference: cp.addressReference ?? null,
        zone: cp.addressZone ?? null,
        full: cp.address ?? null,
      };
    }
  }

  return res;
}

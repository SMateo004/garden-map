/** Item devuelto por GET /api/admin/payments-pending */
export interface PendingPaymentItem {
  id: string;
  clientId: string;
  caregiverId: string;
  serviceType: string;
  totalAmount: string;
  donationAmount: number;
  walletPaymentAmount: number;
  petName: string;
  startDate: string | null;
  endDate: string | null;
  walkDate: string | null;
  timeSlot: string | null;
  createdAt: string;
  clientEmail?: string;
  caregiverName?: string;
}

export interface PendingPaymentsResult {
  bookings: PendingPaymentItem[];
  total: number;
}

/** Item de listado GET /api/admin/reservations */
export interface AdminReservationItem {
  id: string;
  status: string;
  serviceType: string;
  totalAmount: string;
  petName: string;
  startDate: string | null;
  endDate: string | null;
  walkDate: string | null;
  timeSlot: string | null;
  duration: number | null;
  clientId: string;
  caregiverId: string;
  createdAt: string;
  clientEmail?: string;
  caregiverName?: string;
  donationAmount?: number;
  walletPaymentAmount?: number;
  hasActiveIncident?: boolean;
}

export interface AdminReservationsResult {
  reservations: AdminReservationItem[];
  total: number;
}

/** Item devuelto por GET /api/admin/caregivers/pending */
export interface PendingCaregiverItem {
  id: string;
  email: string;
  phone: string;
  fullName: string;
  status: string;
  createdAt: Date;
  updatedAt: Date;
  rejectionReason: string | null;
  isProfessional: boolean;
  antecedentesNeedsReview: boolean;
  lowRatingAutoSuspended: boolean;
}

export interface PendingCaregiversResult {
  caregivers: PendingCaregiverItem[];
  total: number;
  page: number;
  limit: number;
}

/** Respuesta de PATCH /api/admin/caregivers/:id/review */
export interface ReviewCaregiverResult {
  id: string;
  status: string;
  action: 'approve' | 'reject' | 'request_revision';
}

/** GET /api/admin/caregivers/:id/detail — datos completos para revisión admin (sin passwordHash). */
export interface AdminCaregiverDetailDto {
  id: string;
  userId: string;
  createdAt: string;
  updatedAt: string;

  // --- Estado y revisión ---
  status: string;
  verified: boolean;
  verifiedAt: string | null;
  verifiedBy: string | null;
  verificationNotes: string | null;
  verificationStatus: string;
  rejectionReason: string | null;
  adminNotes: string | null;
  approvedAt: string | null;
  approvedBy: string | null;
  reviewedAt: string | null;
  suspended: boolean;
  suspendedAt: string | null;
  suspensionReason: string | null;
  rating: number;
  reviewCount: number;

  // --- Datos personales (User) ---
  user: {
    id: string;
    email: string;
    role: string;
    firstName: string;
    lastName: string;
    phone: string;
    profilePicture: string | null;
    country: string | null;
    city: string | null;
    isOver18: boolean;
    createdAt: string;
    updatedAt: string;
    phoneOtp: string | null;
    phoneOtpExpiresAt: string | null;
  };
  emailOtpCode: string | null;
  emailOtpExpiresAt: string | null;

  // --- Perfil público / wizard ---
  bio: string | null;
  bioDetail: string | null;
  zone: string | null;
  spaceType: string[]; // Array de tipos de espacio
  spaceDescription: string | null;
  address: string | null;
  photos: string[]; // legacy — reemplazado por caregiverPhotos
  caregiverPhotos: string[];
  placePhotos: Record<string, string[]> | null;

  // --- Servicios y disponibilidad ---
  servicesOffered: string[];
  serviceAvailability: Record<string, unknown> | null;
  pricePerDay: number | null;
  pricePerWalk30: number | null;
  pricePerWalk60: number | null;
  pricePerGuarderia: number | null;
  guarderiaIncludeWalk: boolean;
  rates: Record<string, unknown> | null;
  extraServices: Array<{ id: string; name: string; pricePerDay: number | null; appliesTo: string[]; active: boolean }>;

  // --- Términos ---
  termsAccepted: boolean | null;
  privacyAccepted: boolean | null;
  verificationAccepted: boolean | null;
  termsAcceptedAt: string | null;

  // --- Experiencia ---
  experienceYears: number | null;
  ownPets: boolean | null;
  currentPetsDetails: unknown;
  caredOthers: boolean | null;
  animalTypes: string[];
  experienceDescription: string | null;
  whyCaregiver: string | null;
  whatDiffers: string | null;
  handleAnxious: string | null;
  emergencyResponse: string | null;
  acceptAggressive: boolean | null;
  acceptMedication: string[];
  acceptPuppies: boolean | null;
  acceptSeniors: boolean | null;
  sizesAccepted: string[];
  noAcceptBreeds: boolean | null;
  breedsWhy: string | null;

  // --- Hogar ---
  homeType: string | null;
  ownHome: boolean | null;
  hasYard: boolean | null;
  yardFenced: boolean | null;
  hasChildren: boolean | null;
  hasOtherPets: boolean | null;
  petsSleep: string | null;
  clientPetsSleep: string | null;
  hoursAlone: number | null;
  workFromHome: boolean | null;
  maxPets: number | null;
  oftenOut: boolean | null;
  typicalDay: string | null;

  // --- Documentos e imágenes (URLs) ---
  profilePhoto: string | null;
  idDocumentUrl: string | null;
  selfieUrl: string | null;
  ciAnversoUrl: string | null;
  ciReversoUrl: string | null;
  ciNumber: string | null;
  identityVerificationStatus: string;
  identityVerificationScore: number | null;
  identityVerificationSubmittedAt: string | null;
  lastIdentityVerificationSessionId?: string;
  emailVerified: boolean;
  isProfessional: boolean;
  isCompany: boolean;
  companyName: string | null;
  businessType: string | null;
  emergencyContacts: Array<{ name: string; phone: string }> | null;
  reviewChecklist: string[] | null;

  // --- Flags de completitud ---
  personalInfoComplete: boolean;
  caregiverProfileComplete: boolean;
  availabilityComplete: boolean;

  // --- Bloqueo verificación identidad ---
  verificationAttempts: number;
  verificationLockUntil: string | null;

  // --- Disponibilidad (calendario) ---
  defaultAvailabilitySchedule: Record<string, unknown> | null;
  availability: Array<{ date: string; isAvailable: boolean; timeBlocks: unknown }>;
}

import { api } from './client';

/** GET /api/admin/caregivers/:id/detail — solo ADMIN. Datos completos (incl. CI). Vista cliente usa GET /api/caregivers/:id. */
export interface AdminCaregiverDetail {
  id: string;
  userId: string;
  createdAt: string;
  updatedAt: string;
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
  };
  bio: string | null;
  bioDetail: string | null;
  zone: string | null;
  spaceType: string[] | null;
  spaceDescription: string | null;
  address: string | null;
  photos: string[];
  servicesOffered: string[];
  serviceAvailability: Record<string, unknown> | null;
  pricePerDay: number | null;
  pricePerWalk30: number | null;
  pricePerWalk60: number | null;
  rates: Record<string, unknown> | null;
  termsAccepted: boolean | null;
  privacyAccepted: boolean | null;
  verificationAccepted: boolean | null;
  termsAcceptedAt: string | null;
  experienceYears: string | null;
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
  profilePhoto: string | null;
  idDocumentUrl: string | null;
  selfieUrl: string | null;
  ciAnversoUrl: string | null;
  ciReversoUrl: string | null;
  ciNumber: string | null;
  identityVerificationStatus?: string;
  identityVerificationScore: number | null;
  lastIdentityVerificationSessionId?: string;
  emailVerified: boolean;
  reviewChecklist?: string[] | null;
  defaultAvailabilitySchedule?: Record<string, unknown> | null;
  availability?: Array<{ date: string; isAvailable: boolean; timeBlocks: unknown }>;
}

export async function getCaregiverDetail(profileId: string): Promise<AdminCaregiverDetail> {
  const res = await api.get<{ success: boolean; data: AdminCaregiverDetail }>(
    `/api/admin/caregivers/${profileId}/detail`
  );
  if (!res.data.success || !res.data.data) throw new Error('Error al cargar detalle');
  return res.data.data;
}

export interface PendingCaregiverItem {
  id: string;
  email: string;
  phone: string;
  fullName: string;
  status: string;
  createdAt: string;
  updatedAt: string;
  rejectionReason: string | null;
}

export interface PendingCaregiversResponse {
  caregivers: PendingCaregiverItem[];
  total: number;
  page: number;
  limit: number;
}

export type AdminCaregiversListParams = {
  status?: string;
  page?: number;
  limit?: number;
};

export async function getCaregiversList(params: AdminCaregiversListParams = {}): Promise<PendingCaregiversResponse> {
  const { status, page = 1, limit = 20 } = params;
  const res = await api.get<{ success: boolean; data: PendingCaregiversResponse }>(
    '/api/admin/caregivers',
    { params: { status, page, limit } }
  );
  if (!res.data.success) throw new Error('Error al cargar listado de cuidadores');
  return res.data.data;
}

export async function getPendingCaregivers(page = 1, limit = 20): Promise<PendingCaregiversResponse> {
  const res = await api.get<{ success: boolean; data: PendingCaregiversResponse }>(
    '/api/admin/caregivers/pending',
    { params: { page, limit } }
  );
  if (!res.data.success) throw new Error('Error al cargar solicitudes');
  return res.data.data;
}

export async function reviewCaregiver(
  profileId: string,
  action: 'approve' | 'reject' | 'request_revision' | 'force_submit',
  options?: { reason?: string; adminMessage?: string; checklist?: string[] }
): Promise<{ id: string; status: string; action: string }> {
  const { reason, adminMessage, checklist } = options ?? {};
  const res = await api.patch<{ success: boolean; data: { id: string; status: string; action: string } }>(
    `/api/admin/caregivers/${profileId}/review`,
    { action, reason, adminMessage, checklist }
  );
  if (!res.data.success) throw new Error((res.data as { error?: { message?: string } }).error?.message ?? 'Error');
  return res.data.data;
}

export async function verifyCaregiverEmail(profileId: string): Promise<{ emailVerified: boolean }> {
  const res = await api.patch<{ success: boolean; data: { emailVerified: boolean } }>(
    `/api/admin/caregivers/${profileId}/verify-email`
  );
  if (!res.data.success) throw new Error('Error al verificar email');
  return res.data.data;
}

export async function suspendCaregiver(profileId: string, reason: string): Promise<{ success: boolean; suspended: boolean }> {
  const res = await api.patch<{ success: boolean; data: { success: boolean; suspended: boolean } }>(
    `/api/admin/caregivers/${profileId}/suspend`,
    { reason }
  );
  if (!res.data.success) throw new Error('Error al suspender');
  return res.data.data;
}

export async function activateCaregiver(profileId: string, notes?: string): Promise<{ success: boolean; suspended: boolean }> {
  const res = await api.patch<{ success: boolean; data: { success: boolean; suspended: boolean } }>(
    `/api/admin/caregivers/${profileId}/activate`,
    { notes }
  );
  if (!res.data.success) throw new Error('Error al activar');
  return res.data.data;
}

export async function deleteCaregiver(profileId: string, payload: { reason: string; adminPassword: string }): Promise<{ success: boolean }> {
  const res = await api.delete<{ success: boolean; data: { success: boolean } }>(
    `/api/admin/caregivers/${profileId}`,
    { data: payload }
  );
  if (!res.data.success) throw new Error('Error al eliminar');
  return res.data.data;
}

// ---------------------------------------------------------------------------
// Pagos pendientes de aprobación manual (Subfase 2.3)
// ---------------------------------------------------------------------------

export interface PendingPaymentItem {
  id: string;
  clientId: string;
  caregiverId: string;
  serviceType: string;
  totalAmount: string;
  petName: string;
  startDate: string | null;
  endDate: string | null;
  walkDate: string | null;
  timeSlot: string | null;
  createdAt: string;
  clientEmail?: string;
  caregiverName?: string;
}

export interface PendingPaymentsResponse {
  bookings: PendingPaymentItem[];
  total: number;
}

export async function getPaymentsPending(): Promise<PendingPaymentsResponse> {
  const res = await api.get<{ success: boolean; data: PendingPaymentsResponse }>(
    '/api/admin/payments-pending'
  );
  if (!res.data.success) throw new Error('Error al cargar pagos pendientes');
  return res.data.data;
}

/** Rechazar pago manual; la reserva vuelve a PENDING_PAYMENT. */
export async function rejectPayment(bookingId: string): Promise<{ id: string; status: string }> {
  const res = await api.post<{ success: boolean; data: { id: string; status: string } }>(
    `/api/admin/bookings/${bookingId}/reject-payment`
  );
  if (!res.data.success) throw new Error((res.data as { error?: { message?: string } }).error?.message ?? 'Error');
  return res.data.data;
}

/** Aprobar pago manual (admin). Llama POST /api/payments/verify con { bookingId, manual: true }. */
export async function approvePaymentManual(bookingId: string): Promise<{ bookingId: string; status: string }> {
  const res = await api.post<{ success: boolean; data: { bookingId: string; status: string } }>(
    '/api/payments/verify',
    { bookingId, manual: true }
  );
  if (!res.data.success) throw new Error((res.data as { error?: { message?: string } }).error?.message ?? 'Error');
  return res.data.data;
}

// ---------------------------------------------------------------------------
// Reservas admin (listado, aprobar/rechazar cancelación)
// ---------------------------------------------------------------------------

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
  cancellationRequestedAt: string | null;
  cancellationRequestReason: string | null;
  clientEmail?: string;
  caregiverName?: string;
}

export interface AdminReservationsResponse {
  reservations: AdminReservationItem[];
  total: number;
}

export async function getAdminReservations(status?: string): Promise<AdminReservationsResponse> {
  const params = status ? { status } : {};
  const res = await api.get<{ success: boolean; data: AdminReservationsResponse }>(
    '/api/admin/reservations',
    { params }
  );
  if (!res.data.success) throw new Error('Error al cargar reservas');
  return res.data.data;
}

export async function approveCancellation(bookingId: string): Promise<{ id: string; status: string }> {
  const res = await api.post<{ success: boolean; data: { id: string; status: string } }>(
    `/api/admin/bookings/${bookingId}/approve-cancellation`
  );
  if (!res.data.success) throw new Error((res.data as { error?: { message?: string } }).error?.message ?? 'Error');
  return res.data.data;
}

export async function rejectCancellation(bookingId: string): Promise<{ id: string; status: string }> {
  const res = await api.post<{ success: boolean; data: { id: string; status: string } }>(
    `/api/admin/bookings/${bookingId}/reject-cancellation`
  );
  if (!res.data.success) throw new Error((res.data as { error?: { message?: string } }).error?.message ?? 'Error');
  return res.data.data;
}

// ---------------------------------------------------------------------------
// Verificación de identidad (Subfase 2.5)
// ---------------------------------------------------------------------------

export interface IdentityVerificationSession {
  id: string;
  userId: string;
  status: string;
  similarity: number | null;
  similarityScore?: number | null;
  livenessScore?: number | null;
  livenessStatus?: string | null;
  documentConfidence?: number | null;
  identityScore?: number | null;
  faceScore?: number | null;
  ocrScore?: number | null;
  docScore?: number | null;
  qualityScore?: number | null;
  trustScore?: number | null;
  behaviorScore?: number | null;
  ipAddress?: string | null;
  userAgent?: string | null;
  deviceFingerprint?: string | null;
  deviceDetails?: {
    os?: string;
    browser?: string;
    deviceType?: string;
    resolution?: string;
  } | null;
  locationData?: {
    country?: string;
    city?: string;
    proxyDetected?: boolean;
  } | null;
  ocrData?: {
    firstName?: string | null;
    lastName?: string | null;
    fullName?: string | null;
    documentNumber?: string | null;
    dateOfBirth?: string | null
  } | null;
  fraudFlags?: string[] | null;
  livenessFrameUrlsSigned?: (string | null)[];
  selfieUrl: string | null;
  ciFrontUrl: string | null;
  ciBackUrl?: string | null;
  faceCroppedSelfieUrl?: string | null;
  faceCroppedDocumentUrl?: string | null;
  selfieUrlSigned?: string | null;
  ciFrontUrlSigned?: string | null;
  ciBackUrlSigned?: string | null;
  faceCroppedSelfieUrlSigned?: string | null;
  faceCroppedDocumentUrlSigned?: string | null;
  createdAt: string;
  completedAt: string | null;
  reviewedBy: string | null;
  reviewedAt: string | null;
  user?: {
    firstName: string;
    lastName: string;
    email: string;
    caregiverProfile?: { identityVerificationStatus: string };
  };
}

export interface IdentityReviewItem {
  id: string;
  userId: string;
  user: { id: string; email: string; firstName: string; lastName: string };
  similarity: number | null;
  trustScore?: number | null;
  completedAt: string | null;
}

export async function getIdentityReviewsList(): Promise<IdentityReviewItem[]> {
  const res = await api.get<{ success: boolean; data: IdentityReviewItem[] }>(
    '/api/admin/identity-reviews'
  );
  if (!res.data.success) throw new Error('Error al cargar revisiones');
  return res.data.data ?? [];
}

export async function getIdentityVerificationDetail(sessionId: string): Promise<IdentityVerificationSession> {
  const res = await api.get<{ success: boolean; data: IdentityVerificationSession }>(
    `/api/admin/identity-reviews/${sessionId}`
  );
  if (!res.data.success || !res.data.data) throw new Error('Error al cargar verificación');
  return res.data.data;
}

export async function approveIdentityVerification(sessionId: string): Promise<{ success: boolean }> {
  const res = await api.post<{ success: boolean }>(`/api/admin/verifications/${sessionId}/approve`);
  return res.data;
}

export async function rejectIdentityVerification(sessionId: string): Promise<{ success: boolean }> {
  const res = await api.post<{ success: boolean }>(`/api/admin/verifications/${sessionId}/reject`);
  return res.data;
}

// ---------------------------------------------------------------------------
// Disputas (Agente de IA)
// ---------------------------------------------------------------------------

export interface AdminDisputeItem {
  id: string;
  bookingId: string;
  status: string;
  clientReasons: string[];
  caregiverResponse: string[];
  aiVerdict?: string;
  aiAnalysis?: string;
  resolution?: string;
  createdAt: string;
  clientName: string;
  caregiverName: string;
  amount: number | string;
}

export async function getAdminDisputes(status?: string): Promise<AdminDisputeItem[]> {
  const res = await api.get<{ success: boolean; data: AdminDisputeItem[] }>(
    '/api/admin/disputes',
    { params: { status } }
  );
  if (!res.data.success) throw new Error('Error al cargar disputas');
  return res.data.data ?? [];
}

// ---------------------------------------------------------------------------
// Retiros (Withdrawals)
// ---------------------------------------------------------------------------

export interface WithdrawalItem {
  id: string;
  userId: string;
  amount: number | string;
  status: 'PENDING' | 'PROCESSING' | 'COMPLETED' | 'REJECTED';
  description: string;
  createdAt: string;
  user: {
    firstName: string;
    lastName: string;
    email: string;
    caregiverProfile?: {
      bankName: string;
      bankAccount: string;
      bankHolder: string;
      bankType: string;
      balance: number;
    }
  }
}

export async function getWithdrawals(status?: string): Promise<WithdrawalItem[]> {
  const res = await api.get<{ success: boolean; data: { withdrawals: WithdrawalItem[] } }>(
    '/api/admin/withdrawals',
    { params: { status } }
  );
  if (!res.data.success) throw new Error('Error al cargar retiros');
  return res.data.data.withdrawals ?? [];
}

export async function processWithdrawal(id: string): Promise<void> {
  await api.patch(`/api/admin/withdrawals/${id}/process`);
}

export async function completeWithdrawal(id: string): Promise<void> {
  await api.patch(`/api/admin/withdrawals/${id}/complete`);
}

export async function rejectWithdrawal(id: string, reason: string): Promise<void> {
  await api.patch(`/api/admin/withdrawals/${id}/reject`, { reason });
}

// ---------------------------------------------------------------------------
// Códigos de regalo (Gift Codes)
// ---------------------------------------------------------------------------

export interface GiftCodeItem {
  id: string;
  code: string;
  amount: number;
  usedCount: number;
  maxUses: number;
  expiresAt: string | null;
  active: boolean;
  createdAt: string;
}

export async function getGiftCodes(): Promise<GiftCodeItem[]> {
  const res = await api.get<{ success: boolean; data: GiftCodeItem[] }>(
    '/api/admin/gift-codes'
  );
  if (!res.data.success) throw new Error('Error al cargar códigos');
  return res.data.data ?? [];
}

export async function createGiftCode(data: {
  code: string;
  amount: number;
  maxUses?: number;
  expiresAt?: string;
}): Promise<void> {
  await api.post('/api/admin/gift-codes', data);
}

export async function toggleGiftCode(id: string): Promise<void> {
  await api.patch(`/api/admin/gift-codes/${id}/toggle`);
}

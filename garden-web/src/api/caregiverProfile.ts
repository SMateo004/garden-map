/**
 * API perfil cuidador: my-profile (cargar wizard), PATCH (autosave), submit.
 * Requiere token CAREGIVER.
 */

import { api } from './client';

export interface MyProfileUser {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  phone: string;
  country: string | null;
  city: string | null;
}

export interface MyProfileResponse {
  id: string;
  status: string;
  onboardingStatus?: { step: number; completed: boolean[] };
  rejectionReason: string | null;
  bio: string | null;
  bioDetail: string | null;
  zone: string | null;
  spaceType: string[];
  spaceDescription: string | null;
  photos: string[];
  profilePhoto: string | null;
  address: string | null;
  servicesOffered: string[];
  experienceYears: string | null;
  pricePerDay: number | null;
  pricePerWalk30: number | null;
  pricePerWalk60: number | null;
  termsAccepted: boolean | null;
  privacyAccepted: boolean | null;
  verificationAccepted: boolean | null;
  ciNumber: string | null;
  identityVerificationStatus: 'PENDING' | 'REVIEW' | 'VERIFIED' | 'REJECTED' | null;
  profileStatus: 'INCOMPLETE' | 'SUBMITTED' | 'UNDER_REVIEW' | 'APPROVED' | null;
  approvedAt: string | null;
  identityVerificationToken: string | null;
  identityVerificationScore: number | null;
  balance: string | number | null;
  personalInfoComplete?: boolean;
  caregiverProfileComplete?: boolean;
  availabilityComplete?: boolean;
  identityVerificationSubmittedAt: string | null;
  createdAt: string;
  updatedAt: string;
  user: MyProfileUser;
}

export interface OnboardingStatus {
  step: number;
  completed: boolean[];
}

export interface PatchProfilePayload {
  bio?: string;
  bioDetail?: string;
  zone?: string;
  spaceType?: string[]; // Array de tipos de espacio
  onboardingStatus?: OnboardingStatus;
  spaceDescription?: string;
  address?: string;
  servicesOffered?: string[];
  pricePerDay?: number;
  pricePerWalk30?: number;
  pricePerWalk60?: number;
  termsAccepted?: boolean;
  privacyAccepted?: boolean;
  verificationAccepted?: boolean;
  photos?: string[];
  profilePhoto?: string | null;
  ciNumber?: string;
  [key: string]: unknown;
}

/** POST /api/upload/profile-photo — sube foto principal de perfil (multipart). Persiste en backend y devuelve URL. */
export async function uploadProfilePhoto(file: File): Promise<string> {
  const formData = new FormData();
  formData.append('profilePhoto', file);
  const res = await api.postForm('/api/upload/profile-photo', formData);
  if (!res.data.success || !res.data.data?.profilePhoto) {
    throw new Error('Error al subir foto de perfil');
  }
  return res.data.data.profilePhoto;
}

/** GET /api/caregiver/my-profile */
export async function getMyProfile(): Promise<MyProfileResponse | null> {
  const res = await api.get<{ success: boolean; data?: MyProfileResponse }>('/api/caregiver/my-profile');
  if (!res.data.success || res.status === 404) return null;
  return res.data.data ?? null;
}

/** PATCH /api/caregiver/profile */
export async function patchProfile(payload: PatchProfilePayload): Promise<{ profileId: string; status: string; updatedAt: string }> {
  const res = await api.patch<{ success: boolean; data: { profileId: string; status: string; updatedAt: string } }>(
    '/api/caregiver/profile',
    payload
  );
  if (!res.data.success) throw new Error((res.data as { error?: { message?: string } }).error?.message ?? 'Error al guardar');
  return res.data.data;
}

/** PATCH /api/caregiver/user-info — updates firstName, lastName, phone, email */
export async function patchUserInfo(payload: {
  firstName?: string;
  lastName?: string;
  phone?: string;
  email?: string;
}): Promise<{ updated: boolean; emailChanged?: boolean }> {
  const res = await api.patch<{ success: boolean; data: { updated: boolean; emailChanged?: boolean } }>(
    '/api/caregiver/user-info',
    payload
  );
  if (!res.data.success) throw new Error((res.data as any).error?.message ?? 'Error al actualizar');
  return res.data.data;
}

/** POST /api/caregiver/submit */
export async function submitProfile(): Promise<{ success: true; message: string }> {
  const res = await api.post<{ success: boolean; message?: string }>('/api/caregiver/submit');
  if (!res.data.success) throw new Error((res.data as { error?: { message?: string } }).error?.message ?? 'Error al enviar');
  return { success: true, message: res.data.message ?? 'Solicitud enviada.' };
}

/** POST /api/caregiver/send-verify-email */
export async function sendVerifyEmail(): Promise<{ success: boolean; message: string }> {
  const res = await api.post<{ success: boolean; message: string }>('/api/caregiver/send-verify-email');
  return res.data;
}

/** POST /api/caregiver/verify-email */
export async function verifyEmailCode(code: string): Promise<{ success: boolean; message: string }> {
  const res = await api.post<{ success: boolean; data?: { success: boolean; message: string }; message?: string }>('/api/caregiver/verify-email', { code });
  const data = (res.data as { data?: { success: boolean; message: string } }).data;
  return data ?? (res.data as { success: boolean; message: string });
}

export interface NotificationItem {
  id: string;
  title: string;
  message: string;
  type: string;
  read: boolean;
  readAt: string | null;
  createdAt: string;
}

/** GET /api/caregiver/notifications */
export async function getNotifications(): Promise<NotificationItem[]> {
  const res = await api.get<{ success: boolean; data: NotificationItem[] }>('/api/caregiver/notifications');
  if (!res.data.success || !res.data.data) return [];
  return res.data.data;
}

/** PATCH /api/caregiver/notifications/:id/read */
export async function markNotificationRead(notificationId: string): Promise<void> {
  await api.patch(`/api/caregiver/notifications/${notificationId}/read`);
}

/** Slot with enable/time-range config */
export interface TimeSlotConfig {
  enabled: boolean;
  start?: string;
  end?: string;
}

/** Time blocks: morning / afternoon / night */
export interface TimeBlocks {
  morning?: TimeSlotConfig | null;
  afternoon?: TimeSlotConfig | null;
  night?: TimeSlotConfig | null;
}

/** Default weekly schedule */
export interface DefaultSchedule {
  hospedajeDefault?: boolean;
  paseoTimeBlocks?: TimeBlocks;
}

/** Per-day override */
export interface DayOverride {
  isAvailable?: boolean;
  timeBlocks?: TimeBlocks;
  reason?: string;
}

export interface MyAvailabilityResponse {
  defaultSchedule: DefaultSchedule | null;
  dates: Record<
    string,
    { isAvailable: boolean; timeBlocks: Record<string, unknown> | null; reason?: string | null }
  >;
}

/** GET /api/caregiver/availability?from=YYYY-MM-DD&to=YYYY-MM-DD (o start/end) */
export async function getMyAvailability(from?: string, to?: string): Promise<MyAvailabilityResponse> {
  const params: Record<string, string> = {};
  if (from) params.from = from;
  if (to) params.to = to;
  const res = await api.get<{ success: boolean; data: MyAvailabilityResponse }>(
    '/api/caregiver/availability',
    { params }
  );
  if (!res.data.success) throw new Error('Error al cargar disponibilidad');
  return res.data.data;
}

export interface PatchAvailabilityPayload {
  defaultSchedule?: DefaultSchedule;
  overrides?: Record<string, DayOverride>;
}

/** PATCH /api/caregiver/availability */
export async function patchAvailability(payload: PatchAvailabilityPayload): Promise<void> {
  const res = await api.patch<{ success: boolean }>('/api/caregiver/availability', payload);
  if (!res.data.success) throw new Error('Error al guardar disponibilidad');
}

/** GET /api/caregiver/bookings — reservas asignadas al cuidador logueado. */
export interface CaregiverBookingItem {
  id: string;
  status: string;
  serviceType: string;
  totalAmount: string;
  commissionAmount: string;
  petName: string;
  startDate?: string | null;
  endDate?: string | null;
  walkDate?: string | null;
  timeSlot?: string | null;
  duration?: number | null;
  startTime?: string | null;
  clientId: string;
  caregiverId: string;
  createdAt: string;
  cancellationRequestedAt?: string | null;
  cancellationRequestReason?: string | null;
  serviceStartedAt?: string | null;
  serviceEndedAt?: string | null;
  serviceStartPhoto?: string | null;
  serviceEndPhoto?: string | null;
  payoutStatus?: string | null;
}

export async function getCaregiverBookings(): Promise<CaregiverBookingItem[]> {
  const res = await api.get<{ success: boolean; data: CaregiverBookingItem[] }>('/api/caregiver/bookings');
  if (!res.data.success) throw new Error('Error al cargar reservas');
  return res.data.data ?? [];
}

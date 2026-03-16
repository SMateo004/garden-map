import { api } from './client';
import type { ServiceType, TimeSlot } from '@/types/caregiver';

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: { code: string; message: string };
}

export interface CreateBookingBodyHospedaje {
  serviceType: 'HOSPEDAJE';
  caregiverId: string;
  petId: string;
  startDate: string; // YYYY-MM-DD
  endDate: string; // YYYY-MM-DD
  totalDays: number;
}

export interface CreateBookingBodyPaseo {
  serviceType: 'PASEO';
  caregiverId: string;
  petId: string;
  walkDate: string; // YYYY-MM-DD
  timeSlot: TimeSlot;
  startTime?: string; // HH:mm
  duration: number; // 30, 60, 90, etc.
}

export type CreateBookingBody = CreateBookingBodyHospedaje | CreateBookingBodyPaseo;

export interface BookingResult {
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
  createdAt: string;
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
}

export interface InitPaymentBody {
  method: 'qr' | 'manual';
}

export interface InitPaymentResult {
  qrId?: string;
  qrImageUrl?: string;
  qrExpiresAt?: string;
  status: string;
}

export interface CancelBookingBody {
  cancellationReason?: string;
}

export interface ExtendBookingBody {
  newEndDate: string; // YYYY-MM-DD
}

export interface ChangeDatesBookingBody {
  newStartDate: string; // YYYY-MM-DD
  newEndDate: string; // YYYY-MM-DD
}

export interface VerifyPaymentBody {
  qrId: string;
}

export function createBooking(body: CreateBookingBody): Promise<ApiResponse<BookingResult>> {
  return api.post('/api/bookings', body).then((r) => r.data);
}

export function cancelBooking(bookingId: string, body: CancelBookingBody): Promise<ApiResponse<BookingResult>> {
  return api.post(`/api/bookings/${bookingId}/cancel`, body).then((r) => r.data);
}

export function extendBooking(bookingId: string, body: ExtendBookingBody): Promise<ApiResponse<BookingResult>> {
  return api.post(`/api/bookings/${bookingId}/extend`, body).then((r) => r.data);
}

export function changeDatesBooking(
  bookingId: string,
  body: ChangeDatesBookingBody
): Promise<ApiResponse<BookingResult>> {
  return api.post(`/api/bookings/${bookingId}/change-dates`, body).then((r) => r.data);
}

export function verifyPaymentByQr(body: VerifyPaymentBody): Promise<ApiResponse<{ bookingId: string; status: string }>> {
  return api.post('/api/payments/verify', body).then((r) => r.data);
}

export function getMyBookings(): Promise<ApiResponse<BookingResult[]>> {
  return api.get('/api/bookings/my').then((r) => r.data);
}

export function getBookingById(bookingId: string): Promise<ApiResponse<BookingResult>> {
  return api.get(`/api/bookings/${bookingId}`).then((r) => r.data);
}

/** GET /api/bookings/:id/confirm — datos para página de confirmación (mismo payload que getBookingById). */
export function getBookingConfirm(bookingId: string): Promise<ApiResponse<BookingResult>> {
  return api.get(`/api/bookings/${bookingId}/confirm`).then((r) => r.data);
}

/** POST /api/bookings/:id/payment — iniciar pago (QR o manual). Devuelve QR o status PAYMENT_PENDING_APPROVAL. */
export function initPayment(
  bookingId: string,
  body: InitPaymentBody
): Promise<ApiResponse<InitPaymentResult>> {
  return api.post(`/api/bookings/${bookingId}/payment`, body).then((r) => r.data);
}

export interface CancellationRequestBody {
  reason: string;
}

/** POST /api/bookings/:id/cancellation-request — cuidador solicita cancelación. */
export function requestCancellationByCaregiver(
  bookingId: string,
  body: CancellationRequestBody
): Promise<ApiResponse<BookingResult>> {
  return api.post(`/api/bookings/${bookingId}/cancellation-request`, body).then((r) => r.data);
}

/** POST /api/bookings/:id/accept — cuidador acepta reserva pagada. */
export function acceptBooking(bookingId: string): Promise<ApiResponse<BookingResult>> {
  return api.post(`/api/bookings/${bookingId}/accept`).then((r) => r.data);
}

/** POST /api/bookings/:id/reject — cuidador rechaza reserva pagada. */
export function rejectBooking(
  bookingId: string,
  body: CancellationRequestBody
): Promise<ApiResponse<BookingResult>> {
  return api.post(`/api/bookings/${bookingId}/reject`, body).then((r) => r.data);
}

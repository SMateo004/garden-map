import { useQuery } from '@tanstack/react-query';
import { getBookingConfirm } from '@/api/bookings';

export const BOOKING_CONFIRM_QUERY_KEY = ['bookings', 'confirm'] as const;

export function useBookingConfirm(bookingId: string | undefined) {
  return useQuery({
    queryKey: [...BOOKING_CONFIRM_QUERY_KEY, bookingId],
    queryFn: async () => {
      if (!bookingId) throw new Error('Booking ID requerido');
      const res = await getBookingConfirm(bookingId);
      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Error al cargar reserva');
      }
      return res.data;
    },
    enabled: !!bookingId,
  });
}

import { useQuery } from '@tanstack/react-query';
import { getBookingById } from '@/api/bookings';

export function useBooking(bookingId: string | undefined) {
  return useQuery({
    queryKey: ['bookings', bookingId],
    queryFn: async () => {
      if (!bookingId) throw new Error('Booking ID requerido');
      const res = await getBookingById(bookingId);
      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Error al cargar reserva');
      }
      return res.data;
    },
    enabled: !!bookingId,
  });
}

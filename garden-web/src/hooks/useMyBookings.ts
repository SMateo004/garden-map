import { useQuery } from '@tanstack/react-query';
import { getMyBookings } from '@/api/bookings';

export function useMyBookings() {
  return useQuery({
    queryKey: ['bookings', 'my'],
    queryFn: async () => {
      const res = await getMyBookings();
      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Error al cargar reservas');
      }
      return res.data;
    },
  });
}

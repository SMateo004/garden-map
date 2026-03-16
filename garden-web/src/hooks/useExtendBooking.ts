import { useMutation, useQueryClient } from '@tanstack/react-query';
import { extendBooking } from '@/api/bookings';
import toast from 'react-hot-toast';

export function useExtendBooking() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ bookingId, newEndDate }: { bookingId: string; newEndDate: string }) => {
      const res = await extendBooking(bookingId, { newEndDate });
      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Error al extender reserva');
      }
      return res.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bookings'] });
      toast.success('Reserva extendida exitosamente');
    },
    onError: (error: Error) => {
      toast.error(error.message || 'Error al extender reserva');
    },
  });
}

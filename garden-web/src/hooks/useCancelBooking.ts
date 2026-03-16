import { useMutation, useQueryClient } from '@tanstack/react-query';
import { cancelBooking } from '@/api/bookings';
import toast from 'react-hot-toast';

export function useCancelBooking() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ bookingId, reason }: { bookingId: string; reason?: string }) => {
      const res = await cancelBooking(bookingId, { cancellationReason: reason });
      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Error al cancelar reserva');
      }
      return res.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bookings'] });
      toast.success('Reserva cancelada exitosamente');
    },
    onError: (error: Error) => {
      toast.error(error.message || 'Error al cancelar reserva');
    },
  });
}

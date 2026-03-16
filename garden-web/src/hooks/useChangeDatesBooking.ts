import { useMutation, useQueryClient } from '@tanstack/react-query';
import { changeDatesBooking } from '@/api/bookings';
import toast from 'react-hot-toast';

export function useChangeDatesBooking() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      bookingId,
      newStartDate,
      newEndDate,
    }: {
      bookingId: string;
      newStartDate: string;
      newEndDate: string;
    }) => {
      const res = await changeDatesBooking(bookingId, { newStartDate, newEndDate });
      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Error al cambiar fechas');
      }
      return res.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bookings'] });
      toast.success('Fechas actualizadas exitosamente');
    },
    onError: (error: Error) => {
      toast.error(error.message || 'Error al cambiar fechas');
    },
  });
}

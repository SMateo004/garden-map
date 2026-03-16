import { useMutation, useQueryClient } from '@tanstack/react-query';
import { initPayment, type InitPaymentBody } from '@/api/bookings';
import { BOOKING_CONFIRM_QUERY_KEY } from './useBookingConfirm';
import toast from 'react-hot-toast';

export function useInitPayment() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      bookingId,
      body,
    }: {
      bookingId: string;
      body: InitPaymentBody;
    }) => {
      const res = await initPayment(bookingId, body);
      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Error al iniciar pago');
      }
      return res.data;
    },
    onSuccess: (_data, { bookingId }) => {
      queryClient.invalidateQueries({ queryKey: [...BOOKING_CONFIRM_QUERY_KEY, bookingId] });
      queryClient.invalidateQueries({ queryKey: ['bookings'] });
    },
    onError: (error: Error) => {
      toast.error(error.message || 'Error al generar pago');
    },
  });
}

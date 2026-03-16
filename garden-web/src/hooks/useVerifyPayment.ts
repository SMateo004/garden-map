import { useMutation, useQueryClient } from '@tanstack/react-query';
import { verifyPaymentByQr } from '@/api/bookings';
import toast from 'react-hot-toast';

export function useVerifyPayment() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (qrId: string) => {
      const res = await verifyPaymentByQr({ qrId });
      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Error al verificar pago');
      }
      return res.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bookings'] });
      toast.success('Pago verificado exitosamente');
    },
    onError: (error: Error) => {
      toast.error(error.message || 'Error al verificar pago');
    },
  });
}

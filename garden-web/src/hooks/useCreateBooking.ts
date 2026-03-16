import { useMutation, useQueryClient } from '@tanstack/react-query';
import { createBooking, type CreateBookingBody } from '@/api/bookings';
import toast from 'react-hot-toast';

export function useCreateBooking() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (body: CreateBookingBody) => createBooking(body),
    onSuccess: (res) => {
      if (res.success && res.data) {
        toast.success('Reserva creada exitosamente');
      } else {
        toast.error(res.error?.message ?? 'Error al crear la reserva');
      }
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ['caregiver-availability'] });
      queryClient.invalidateQueries({ queryKey: ['public-caregiver-detail'] });
    },
    onError: (err: unknown) => {
      const ax = err as { response?: { data?: { message?: string; error?: { message?: string }; errors?: { field: string; message: string }[] } } };
      const data = ax.response?.data;
      if (Array.isArray(data?.errors) && data.errors.length > 0) {
        return;
      }
      const msg = data?.message ?? data?.error?.message ?? data?.errors?.[0]?.message ?? (err instanceof Error ? err.message : 'Error al crear la reserva');
      toast.error(msg);
    },
  });
}

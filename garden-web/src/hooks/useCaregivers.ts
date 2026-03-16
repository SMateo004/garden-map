import { useQuery, type UseQueryOptions } from '@tanstack/react-query';
import { listCaregivers } from '@/api/caregivers';
import type { ListCaregiversParams, PaginatedCaregivers } from '@/types/caregiver';

const CAREGIVERS_QUERY_KEY = 'caregivers';

export function useCaregivers(
  params: ListCaregiversParams = {},
  options?: Omit<UseQueryOptions<PaginatedCaregivers>, 'queryKey' | 'queryFn'>
) {
  return useQuery({
    queryKey: [CAREGIVERS_QUERY_KEY, params],
    queryFn: async () => {
      const res = await listCaregivers(params);
      if (!res.success || !res.data) throw new Error(res.error?.message ?? 'Error al cargar cuidadores');
      return res.data;
    },
    staleTime: 60 * 1000,
    ...options,
  });
}

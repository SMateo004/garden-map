import { useQuery, type UseQueryOptions } from '@tanstack/react-query';
import { getCaregiversList } from '@/api/admin';
import type { PendingCaregiversResponse, AdminCaregiversListParams } from '@/api/admin';

export const ADMIN_CAREGIVERS_QUERY_KEY = 'admin-caregivers';

export function useAdminCaregivers(
  params: AdminCaregiversListParams = {},
  options?: Omit<UseQueryOptions<PendingCaregiversResponse>, 'queryKey' | 'queryFn'>
) {
  return useQuery({
    queryKey: [ADMIN_CAREGIVERS_QUERY_KEY, params],
    queryFn: () => getCaregiversList(params),
    staleTime: 30 * 1000,
    ...options,
  });
}

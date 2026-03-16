import { useQuery, type UseQueryOptions } from '@tanstack/react-query';
import { getCaregiverDetail } from '@/api/admin';
import type { AdminCaregiverDetail } from '@/api/admin';

export const CAREGIVER_DETAIL_QUERY_KEY = 'admin-caregiver-detail';

/**
 * Detalle completo del cuidador para admin (GET /api/admin/caregivers/:id/detail).
 * Incluye photos, profilePhoto, ciAnversoUrl, ciReversoUrl y el resto de campos.
 */
export function useCaregiverDetail(
  profileId: string | undefined,
  options?: Omit<UseQueryOptions<AdminCaregiverDetail>, 'queryKey' | 'queryFn'>
) {
  return useQuery({
    queryKey: [CAREGIVER_DETAIL_QUERY_KEY, profileId],
    queryFn: () => getCaregiverDetail(profileId!),
    enabled: Boolean(profileId),
    staleTime: 60 * 1000,
    ...options,
  });
}

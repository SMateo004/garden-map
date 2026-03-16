import { useQuery, type UseQueryOptions } from '@tanstack/react-query';
import { getCaregiverById } from '@/api/caregivers';
import type { CaregiverDetail } from '@/types/caregiver';

export const PUBLIC_CAREGIVER_DETAIL_QUERY_KEY = 'public-caregiver-detail';

/** Hook para detalle público de cuidador (GET /api/caregivers/:id). Sin auth. Usar en CaregiverDetailPage. */
export function usePublicCaregiverDetail(
  profileId: string | undefined,
  options?: Omit<UseQueryOptions<CaregiverDetail>, 'queryKey' | 'queryFn'>
) {
  return useQuery({
    queryKey: [PUBLIC_CAREGIVER_DETAIL_QUERY_KEY, profileId],
    queryFn: async () => {
      const res = await getCaregiverById(profileId!);
      if (!res.success || !res.data) throw new Error('Cuidador no disponible');
      return res.data;
    },
    enabled: Boolean(profileId),
    staleTime: 60 * 1000,
    ...options,
  });
}

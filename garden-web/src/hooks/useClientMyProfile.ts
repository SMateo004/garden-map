import { useQuery, type UseQueryOptions } from '@tanstack/react-query';
import { getClientMyProfile, type ClientMyProfileData } from '@/api/clientProfile';

export const CLIENT_MY_PROFILE_QUERY_KEY = ['client', 'my-profile'] as const;

export function useClientMyProfile(
  options?: Omit<
    UseQueryOptions<ClientMyProfileData | null, Error>,
    'queryKey' | 'queryFn'
  > & { enabled?: boolean }
) {
  return useQuery({
    queryKey: CLIENT_MY_PROFILE_QUERY_KEY,
    queryFn: getClientMyProfile,
    staleTime: 2 * 60 * 1000,
    refetchOnMount: 'always',
    ...options,
  });
}

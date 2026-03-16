import { useQuery, useMutation, useQueryClient, type UseQueryOptions } from '@tanstack/react-query';
import { getClientMyProfile, patchClientProfile, type PatchClientProfilePayload, type ClientMyProfileData } from '@/api/clientProfile';

/** Misma key que useClientMyProfile para compartir cache (perfil con user y pets[].photoUrl). */
export const CLIENT_PROFILE_QUERY_KEY = ['client', 'my-profile'] as const;

export function useClientProfile(
  options?: Omit<UseQueryOptions<ClientMyProfileData | null>, 'queryKey' | 'queryFn'>
) {
  return useQuery({
    queryKey: CLIENT_PROFILE_QUERY_KEY,
    queryFn: getClientMyProfile,
    staleTime: 2 * 60 * 1000, // 2 minutos
    ...options,
  });
}

export function useUpdateClientProfile() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (payload: PatchClientProfilePayload) => {
      return await patchClientProfile(payload);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: CLIENT_PROFILE_QUERY_KEY });
    },
  });
}

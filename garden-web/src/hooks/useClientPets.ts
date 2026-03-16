import { useQuery, type UseQueryOptions } from '@tanstack/react-query';
import { getClientPets, type ClientPetListItem } from '@/api/clientPets';

export const CLIENT_PETS_QUERY_KEY = ['client-pets'] as const;

export function useClientPets(
  options?: Omit<
    UseQueryOptions<ClientPetListItem[], Error>,
    'queryKey' | 'queryFn'
  > & { enabled?: boolean }
) {
  return useQuery({
    queryKey: CLIENT_PETS_QUERY_KEY,
    queryFn: async () => {
      const res = await getClientPets();
      if (!res.success || !res.data) return [];
      return res.data;
    },
    staleTime: 2 * 60 * 1000,
    ...options,
  });
}

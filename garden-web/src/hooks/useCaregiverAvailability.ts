import { useQuery, type UseQueryOptions } from '@tanstack/react-query';
import { getCaregiverAvailability } from '@/api/caregivers';
import type { CaregiverAvailabilityResponse } from '@/types/caregiver';

const CAREGIVER_AVAILABILITY_KEY = 'caregiver-availability';

export function useCaregiverAvailability(
  id: string | undefined,
  from?: string,
  to?: string,
  options?: Omit<UseQueryOptions<CaregiverAvailabilityResponse | null>, 'queryKey' | 'queryFn'>
) {
  return useQuery({
    queryKey: [CAREGIVER_AVAILABILITY_KEY, id, from, to],
    queryFn: async () => {
      if (!id) {
        console.warn('[useCaregiverAvailability] No caregiver ID provided');
        return null;
      }

      try {
        console.debug('[useCaregiverAvailability] Fetching availability', { id, from, to });
        const res = await getCaregiverAvailability(id, from, to);

        if (!res.success) {
          const errorMessage = res.error?.message || 'Error al cargar disponibilidad';
          console.error('[useCaregiverAvailability] API error:', {
            error: errorMessage,
            code: res.error?.code,
            caregiverId: id,
          });
          throw new Error(errorMessage);
        }

        if (!res.data) {
          console.warn('[useCaregiverAvailability] No data returned', { id });
          // Retornar estructura vacía en lugar de null para evitar errores en el componente
          return {
            caregiverId: id,
            from: from || new Date().toISOString().slice(0, 10),
            to: to || new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10),
            hospedaje: [],
            paseos: {},
          };
        }

        console.debug('[useCaregiverAvailability] Availability loaded', {
          id,
          hospedajeCount: res.data.hospedaje.length,
          paseosCount: Object.keys(res.data.paseos).length,
        });

        return res.data;
      } catch (error) {
        // Log detallado del error para debugging
        console.error('[useCaregiverAvailability] Error fetching availability', {
          error: error instanceof Error ? error.message : String(error),
          stack: error instanceof Error ? error.stack : undefined,
          caregiverId: id,
          from,
          to,
        });

        // Re-lanzar el error para que React Query lo maneje
        throw error;
      }
    },
    enabled: !!id,
    staleTime: 2 * 60 * 1000, // 2 minutos
    retry: (failureCount, error) => {
      // No reintentar si es un error 404 (cuidador no encontrado)
      if (error instanceof Error && error.message.includes('no encontrado')) {
        return false;
      }
      // Reintentar máximo 1 vez para otros errores
      return failureCount < 1;
    },
    retryDelay: 1000, // 1 segundo entre reintentos
    ...options,
  });
}

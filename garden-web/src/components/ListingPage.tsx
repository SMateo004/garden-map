import { useState, useCallback } from 'react';
import { useCaregivers } from '@/hooks/useCaregivers';
import { ProfileCard } from '@/components/ProfileCard';
import { useAuth } from '@/contexts/AuthContext';
import { ClientDashboard } from './ClientDashboard';
import {
  ZONES_QUERY,
  ZONE_QUERY_LABELS,
  SPACE_TYPE_OPTIONS,
  SPACE_TYPE_QUERY_MAP,
  PRICE_RANGES,
  PRICE_RANGE_LABELS,
  SERVICE_OPTIONS,
  SERVICE_LABELS,
} from '@/types/caregiver';
import type { ListCaregiversParams, ZoneQuery } from '@/types/caregiver';

const DEFAULT_PARAMS: ListCaregiversParams = {
  page: 1,
  limit: 10,
};

export function ListingPage() {
  const { user, isAuthenticated } = useAuth();
  const [params, setParams] = useState<ListCaregiversParams>(DEFAULT_PARAMS);
  const { data, isLoading, isError, error } = useCaregivers(params);

  const isClient = isAuthenticated && user?.role === 'CLIENT';

  const setFilter = useCallback(<K extends keyof ListCaregiversParams>(key: K, value: ListCaregiversParams[K]) => {
    setParams((p) => ({ ...p, [key]: value, page: 1 }));
  }, []);

  const setPage = useCallback((page: number) => {
    setParams((p) => ({ ...p, page }));
  }, []);

  const clearFilters = useCallback(() => {
    setParams(DEFAULT_PARAMS);
  }, []);

  const hasFilters =
    params.service != null ||
    params.zone != null ||
    params.priceRange != null ||
    (params.spaceTypes != null && params.spaceTypes.length > 0);

  const currentPage = data?.pagination?.currentPage ?? params.page ?? 1;
  const totalPages = data?.pagination?.pages ?? 1;

  if (isClient && !hasFilters) {
    return (
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <h1 className="text-3xl font-black text-gray-900 dark:text-white mb-8 italic tracking-tighter">
          Bienvenido a tu Oasis, {user.firstName} 🌱
        </h1>
        <ClientDashboard featuredCaregivers={data} isLoadingCaregivers={isLoading} />
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-7xl space-y-6 px-4 py-6 sm:px-6 lg:px-8">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-2xl font-bold text-gray-900">Cuidadores verificados</h1>
      </div>

      {/* Filtros: dropdowns + chips para filtros activos (Subfase 2.2) */}
      <div className="space-y-3">
        <div className="flex flex-wrap items-center gap-3 rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <span className="text-sm font-medium text-gray-700">Filtros:</span>
          <select
            value={params.service ?? ''}
            onChange={(e) => setFilter('service', (e.target.value || undefined) as ListCaregiversParams['service'])}
            className="rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
          >
            <option value="">Servicio</option>
            {SERVICE_OPTIONS.map((s) => (
              <option key={s} value={s}>
                {SERVICE_LABELS[s]}
              </option>
            ))}
          </select>
          <select
            value={params.zone ?? ''}
            onChange={(e) => setFilter('zone', (e.target.value || undefined) as ZoneQuery)}
            className="rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
          >
            <option value="">Zona</option>
            {ZONES_QUERY.map((z) => (
              <option key={z} value={z}>
                {ZONE_QUERY_LABELS[z]}
              </option>
            ))}
          </select>
          <select
            value={params.priceRange ?? ''}
            onChange={(e) => setFilter('priceRange', (e.target.value || undefined) as ListCaregiversParams['priceRange'])}
            className="rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
          >
            <option value="">Precio</option>
            {PRICE_RANGES.map((r) => (
              <option key={r} value={r}>
                {PRICE_RANGE_LABELS[r]}
              </option>
            ))}
          </select>
          {/* Filtro de tipo de espacio: solo visible si servicio incluye Hospedaje o Ambos */}
          {(params.service === 'hospedaje' || params.service === 'ambos') && (
            <div className="relative">
              <details className="group">
                <summary className="cursor-pointer rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500">
                  Tipo espacio
                  {params.spaceTypes && params.spaceTypes.length > 0 && (
                    <span className="ml-2 rounded-full bg-green-100 px-2 py-0.5 text-xs text-green-800">
                      {params.spaceTypes.length}
                    </span>
                  )}
                </summary>
                <div className="absolute left-0 top-full z-10 mt-1 w-64 rounded-lg border border-gray-200 bg-white p-3 shadow-lg">
                  <div className="space-y-2">
                    {SPACE_TYPE_OPTIONS.map((option) => {
                      const queryValue = SPACE_TYPE_QUERY_MAP[option];
                      const isSelected = params.spaceTypes?.includes(queryValue) ?? false;
                      return (
                        <label
                          key={option}
                          className="flex cursor-pointer items-center gap-2 rounded-md p-2 hover:bg-gray-50"
                        >
                          <input
                            type="checkbox"
                            checked={isSelected}
                            onChange={(e) => {
                              const current = params.spaceTypes ?? [];
                              const next = e.target.checked
                                ? [...current, queryValue]
                                : current.filter((s) => s !== queryValue);
                              setFilter('spaceTypes', next.length > 0 ? next : undefined);
                            }}
                            className="h-4 w-4 rounded border-gray-300 text-green-600 focus:ring-2 focus:ring-green-500"
                          />
                          <span className="text-sm text-gray-700">{option}</span>
                        </label>
                      );
                    })}
                  </div>
                </div>
              </details>
            </div>
          )}
        </div>

        {/* Chips de filtros activos */}
        {hasFilters && (
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-medium text-gray-500">Filtros activos:</span>
            {params.service && (
              <span className="inline-flex items-center gap-1 rounded-full bg-green-100 px-3 py-1 text-xs font-medium text-green-800">
                {SERVICE_LABELS[params.service]}
                <button
                  type="button"
                  onClick={() => setFilter('service', undefined)}
                  className="ml-1 text-green-600 hover:text-green-800"
                  aria-label="Quitar filtro"
                >
                  ×
                </button>
              </span>
            )}
            {params.zone && (
              <span className="inline-flex items-center gap-1 rounded-full bg-green-100 px-3 py-1 text-xs font-medium text-green-800">
                {ZONE_QUERY_LABELS[params.zone]}
                <button
                  type="button"
                  onClick={() => setFilter('zone', undefined)}
                  className="ml-1 text-green-600 hover:text-green-800"
                  aria-label="Quitar filtro"
                >
                  ×
                </button>
              </span>
            )}
            {params.priceRange && (
              <span className="inline-flex items-center gap-1 rounded-full bg-green-100 px-3 py-1 text-xs font-medium text-green-800">
                {PRICE_RANGE_LABELS[params.priceRange]}
                <button
                  type="button"
                  onClick={() => setFilter('priceRange', undefined)}
                  className="ml-1 text-green-600 hover:text-green-800"
                  aria-label="Quitar filtro"
                >
                  ×
                </button>
              </span>
            )}
            {params.spaceTypes && params.spaceTypes.length > 0 && (
              <>
                {params.spaceTypes.map((st) => {
                  const displayValue = SPACE_TYPE_OPTIONS.find((opt) => SPACE_TYPE_QUERY_MAP[opt] === st) || st;
                  return (
                    <span
                      key={st}
                      className="inline-flex items-center gap-1 rounded-full bg-green-100 px-3 py-1 text-xs font-medium text-green-800"
                    >
                      {displayValue}
                      <button
                        type="button"
                        onClick={() => {
                          const next = params.spaceTypes?.filter((s) => s !== st);
                          setFilter('spaceTypes', next && next.length > 0 ? next : undefined);
                        }}
                        className="ml-1 text-green-600 hover:text-green-800"
                        aria-label="Quitar filtro"
                      >
                        ×
                      </button>
                    </span>
                  );
                })}
              </>
            )}
            <button
              type="button"
              onClick={clearFilters}
              className="rounded-lg border border-gray-300 bg-white px-3 py-1 text-xs text-gray-700 hover:bg-gray-50"
            >
              Limpiar todos
            </button>
          </div>
        )}
      </div>

      {isLoading && (
        <div className="py-12 text-center text-gray-500">Cargando cuidadores...</div>
      )}
      {isError && (
        <div className="rounded-lg bg-red-50 p-4 text-red-700">
          {(error as Error)?.message ?? 'Error al cargar'}
        </div>
      )}
      {data && (
        <>
          <p className="text-sm text-gray-600">
            {data.pagination.total} cuidador{data.pagination.total !== 1 ? 'es' : ''} disponible
            {data.pagination.total !== 1 ? 's' : ''}
          </p>
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            {data.caregivers.map((c) => (
              <ProfileCard key={c.id} caregiver={c} />
            ))}
          </div>
          {totalPages > 1 && (
            <div className="flex flex-wrap items-center justify-center gap-2 pt-6">
              <button
                type="button"
                disabled={currentPage === 1}
                onClick={() => setPage(currentPage - 1)}
                className="rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50"
              >
                Anterior
              </button>
              <span className="px-2 text-sm text-gray-600">
                Página {currentPage} de {totalPages}
              </span>
              <button
                type="button"
                disabled={currentPage >= totalPages}
                onClick={() => setPage(currentPage + 1)}
                className="rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50"
              >
                Siguiente
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}

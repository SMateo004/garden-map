import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useAdminCaregivers } from '@/hooks/useAdminCaregivers';
import type { PendingCaregiverItem } from '@/api/admin';

const STATUS_FILTER_OPTIONS: { value: string; label: string }[] = [
  { value: '', label: 'Todos' },
  { value: 'pendientes', label: 'Pendientes' },
  { value: 'APPROVED', label: 'Aprobados' },
  { value: 'REJECTED', label: 'Rechazados' },
  { value: 'NEEDS_REVISION', label: 'En revisión' },
  { value: 'DRAFT', label: 'Borrador' },
  { value: 'SUSPENDED', label: 'Suspendidos' },
];

const PAGE_SIZE = 20;

function StatusBadge({ status }: { status: string }) {
  const styles: Record<string, string> = {
    PENDING_REVIEW: 'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300',
    NEEDS_REVISION: 'bg-orange-100 text-orange-800 dark:bg-orange-900/30 dark:text-orange-300',
    APPROVED: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-300',
    REJECTED: 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300',
    DRAFT: 'bg-slate-100 text-slate-700 dark:bg-slate-700 dark:text-slate-200',
    SUSPENDED: 'bg-rose-100 text-rose-800 dark:bg-rose-900/30 dark:text-rose-300',
  };
  const label: Record<string, string> = {
    PENDING_REVIEW: 'Pendiente',
    NEEDS_REVISION: 'En revisión',
    APPROVED: 'Aprobado',
    REJECTED: 'Rechazado',
    DRAFT: 'Borrador',
    SUSPENDED: 'Suspendido',
  };
  const cls = styles[status] ?? 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300';
  return (
    <span className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${cls}`}>
      {label[status] ?? status}
    </span>
  );
}

function formatDate(iso: string) {
  try {
    return new Date(iso).toLocaleDateString('es-BO', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
    });
  } catch {
    return iso;
  }
}

export function AdminCaregiversListPage() {
  const [statusFilter, setStatusFilter] = useState('');
  const [page, setPage] = useState(1);

  const { data, isLoading, isError, error } = useAdminCaregivers({
    status: statusFilter || undefined,
    page,
    limit: PAGE_SIZE,
  });

  if (isLoading) {
    return (
      <div className="min-h-[40vh] flex items-center justify-center">
        <p className="text-gray-500 dark:text-gray-400">Cargando cuidadores…</p>
      </div>
    );
  }

  if (isError) {
    return (
      <div className="py-8 px-4">
        <p className="text-red-600 dark:text-red-400">
          {error instanceof Error ? error.message : 'Error al cargar el listado'}
        </p>
        <Link to="/admin/caregivers" className="mt-2 inline-block text-green-600 dark:text-green-400 hover:underline">
          Reintentar
        </Link>
      </div>
    );
  }

  if (!data) return null;
  const { caregivers, total } = data;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  return (
    <div className="py-6 px-4 max-w-6xl mx-auto">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
        <div>
          <h1 className="text-2xl font-semibold text-gray-900 dark:text-white">
            Cuidadores
          </h1>
          <Link
            to="/admin/caregivers/pending"
            className="text-sm text-green-600 dark:text-green-400 hover:underline mt-0.5 inline-block"
          >
            Ver solo pendientes de revisión
          </Link>
        </div>
        <div className="flex items-center gap-3">
          <label htmlFor="status-filter" className="text-sm font-medium text-gray-700 dark:text-gray-300 whitespace-nowrap">
            Estado:
          </label>
          <select
            id="status-filter"
            value={statusFilter}
            onChange={(e) => {
              setStatusFilter(e.target.value);
              setPage(1);
            }}
            className="rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white px-3 py-2 text-sm focus:ring-2 focus:ring-green-500 focus:border-green-500"
          >
            {STATUS_FILTER_OPTIONS.map((opt) => (
              <option key={opt.value || 'all'} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </select>
        </div>
      </div>

      <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
        {total} cuidador(es) en total
      </p>

      {/* Desktop: table */}
      <div className="hidden md:block rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 overflow-hidden shadow-sm">
        <table className="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead className="bg-gray-50 dark:bg-gray-900/50">
            <tr>
              <th scope="col" className="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Nombre
              </th>
              <th scope="col" className="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Email / Teléfono
              </th>
              <th scope="col" className="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Estado
              </th>
              <th scope="col" className="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Fecha registro
              </th>
              <th scope="col" className="px-4 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Acción
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200 dark:divide-gray-700">
            {caregivers.length === 0 ? (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-gray-500 dark:text-gray-400">
                  No hay cuidadores con los filtros seleccionados.
                </td>
              </tr>
            ) : (
              caregivers.map((c) => (
                <tr key={c.id} className="hover:bg-gray-50 dark:hover:bg-gray-800/50">
                  <td className="px-4 py-3">
                    <Link
                      to={`/admin/caregivers/${c.id}/review`}
                      className="font-medium text-green-600 dark:text-green-400 hover:underline"
                    >
                      {c.fullName}
                    </Link>
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-300">
                    <div>{c.email}</div>
                    <div className="text-gray-500 dark:text-gray-400">{c.phone}</div>
                  </td>
                  <td className="px-4 py-3">
                    <StatusBadge status={c.status} />
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-300">
                    {formatDate(c.createdAt)}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <Link
                      to={`/admin/caregivers/${c.id}/review`}
                      className="inline-flex items-center rounded-lg bg-green-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-green-700 dark:bg-green-500 dark:hover:bg-green-600"
                    >
                      Ver perfil
                    </Link>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Mobile: cards */}
      <div className="md:hidden space-y-4">
        {caregivers.length === 0 ? (
          <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-8 text-center text-gray-500 dark:text-gray-400">
            No hay cuidadores con los filtros seleccionados.
          </div>
        ) : (
          caregivers.map((c) => (
            <CaregiverCard key={c.id} caregiver={c} />
          ))
        )}
      </div>

      {totalPages > 1 && (
        <div className="mt-6 flex items-center justify-center gap-2">
          <button
            type="button"
            onClick={() => setPage((p) => Math.max(1, p - 1))}
            disabled={page <= 1}
            className="rounded-lg border border-gray-300 dark:border-gray-600 px-3 py-1.5 text-sm font-medium text-gray-700 dark:text-gray-300 disabled:opacity-50 disabled:cursor-not-allowed hover:bg-gray-50 dark:hover:bg-gray-800"
          >
            Anterior
          </button>
          <span className="text-sm text-gray-600 dark:text-gray-400">
            Página {page} de {totalPages}
          </span>
          <button
            type="button"
            onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
            disabled={page >= totalPages}
            className="rounded-lg border border-gray-300 dark:border-gray-600 px-3 py-1.5 text-sm font-medium text-gray-700 dark:text-gray-300 disabled:opacity-50 disabled:cursor-not-allowed hover:bg-gray-50 dark:hover:bg-gray-800"
          >
            Siguiente
          </button>
        </div>
      )}
    </div>
  );
}

function CaregiverCard({ caregiver }: { caregiver: PendingCaregiverItem }) {
  return (
    <Link
      to={`/admin/caregivers/${caregiver.id}/review`}
      className="block rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4 shadow-sm hover:border-green-300 dark:hover:border-green-600 transition-colors"
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 flex-1">
          <p className="font-medium text-gray-900 dark:text-white truncate">
            {caregiver.fullName}
          </p>
          <p className="text-sm text-gray-600 dark:text-gray-300 truncate">
            {caregiver.email}
          </p>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            {caregiver.phone}
          </p>
          <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">
            {formatDate(caregiver.createdAt)}
          </p>
        </div>
        <div className="flex flex-col items-end gap-2 shrink-0">
          <StatusBadge status={caregiver.status} />
          <span className="text-sm font-medium text-green-600 dark:text-green-400">
            Ver perfil →
          </span>
        </div>
      </div>
    </Link>
  );
}

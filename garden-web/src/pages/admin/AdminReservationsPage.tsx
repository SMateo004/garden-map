import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import {
  getAdminReservations,
  type AdminReservationItem,
} from '@/api/admin';

const STATUS_OPTIONS = [
  { value: '', label: 'Todos' },
  { value: 'PENDING_PAYMENT', label: 'Pendiente de pago' },
  { value: 'PAYMENT_PENDING_APPROVAL', label: 'Pago pend. aprobación' },
  { value: 'CONFIRMED', label: 'Confirmada' },
  { value: 'IN_PROGRESS', label: 'En curso' },
  { value: 'COMPLETED', label: 'Completada' },
  { value: 'CANCELLED', label: 'Cancelada' },
];

function formatDate(d: string | null | undefined): string {
  if (!d) return '—';
  return new Date(d).toLocaleDateString('es-BO', { day: '2-digit', month: 'short', year: 'numeric' });
}

export function AdminReservationsPage() {
  const [statusFilter, setStatusFilter] = useState('');
  const [searchTerm, setSearchTerm] = useState('');
  const { data, isLoading, error } = useQuery({
    queryKey: ['admin', 'reservations', statusFilter || undefined],
    queryFn: () => getAdminReservations(statusFilter || undefined),
  });

  if (isLoading) {
    return (
      <div className="py-12 text-center text-slate-500">
        Cargando reservas…
      </div>
    );
  }

  if (error) {
    return (
      <div className="mx-auto max-w-4xl px-4 py-8">
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-red-800">
          {error instanceof Error ? error.message : 'Error al cargar'}
        </div>
        <Link to="/admin/caregivers" className="mt-4 inline-block text-sm text-emerald-600 hover:underline">
          Volver al panel
        </Link>
      </div>
    );
  }

  const reservations = (data?.reservations ?? []).filter(r => 
    r.petName?.toLowerCase().includes(searchTerm.toLowerCase()) ||
    r.clientEmail?.toLowerCase().includes(searchTerm.toLowerCase()) ||
    r.caregiverName?.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="mx-auto max-w-5xl px-4 py-8">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Reservas</h1>
          <p className="mt-1 text-sm text-gray-500">
            Listado global de todas las reservas y su estado actual.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-4">
          <div className="relative">
            <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400">🔍</span>
            <input
              type="text"
              placeholder="Mascota, cliente o cuidador..."
              className="pl-9 pr-4 py-2 rounded-xl bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 text-sm focus:ring-2 focus:ring-green-500 outline-none w-64"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
        <label className="flex items-center gap-2">
          <span className="text-sm font-medium text-slate-700">Estado:</span>
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm"
          >
            {STATUS_OPTIONS.map((o) => (
              <option key={o.value || 'all'} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
        </label>
      </div>

      {reservations.length === 0 ? (
        <div className="rounded-2xl border border-slate-200 bg-white p-10 text-center shadow-sm">
          <p className="text-slate-600">
            {statusFilter ? 'No hay reservas con ese estado.' : 'No hay reservas.'}
          </p>
        </div>
      ) : (
        <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-slate-200">
              <thead className="bg-slate-50">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase text-slate-600">
                    Reserva / Servicio
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase text-slate-600">
                    Cliente / Cuidador
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase text-slate-600">
                    Fechas
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase text-slate-600">
                    Estado
                  </th>
                  <th className="px-4 py-3 text-right text-xs font-semibold uppercase text-slate-600">
                    Acciones
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-200 bg-white">
                {reservations.map((r: AdminReservationItem) => (
                  <tr key={r.id} className="hover:bg-slate-50/50">
                    <td className="px-4 py-3">
                      <span className="font-mono text-xs text-slate-500">{r.id.slice(0, 8)}…</span>
                      <p className="font-medium text-slate-900">
                        {r.serviceType === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseo'} · {r.petName}
                      </p>
                      <p className="text-sm font-semibold text-slate-700">
                        Bs {Number(r.totalAmount).toFixed(2)}
                      </p>
                    </td>
                    <td className="px-4 py-3 text-sm text-slate-600">
                      <p>{r.clientEmail ?? r.clientId}</p>
                      <p>{r.caregiverName ?? r.caregiverId}</p>
                    </td>
                    <td className="px-4 py-3 text-sm text-slate-600">
                      {r.serviceType === 'PASEO'
                        ? `${formatDate(r.walkDate)} ${r.timeSlot ?? ''}`
                        : `${formatDate(r.startDate)} – ${formatDate(r.endDate)}`}
                    </td>
                    <td className="px-4 py-3">
                      <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-700">
                        {r.status === 'CANCELLED' ? 'Cancelada' : r.status}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Link
                        to={`/admin/caregivers/${r.caregiverId}/detail`}
                        className="text-xs font-medium text-emerald-600 hover:underline"
                      >
                        Ver cuidador
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      <p className="mt-4 text-xs text-slate-500">
        Las cancelaciones son automáticas y definitivas tanto para clientes como para cuidadores.
      </p>
    </div>
  );
}

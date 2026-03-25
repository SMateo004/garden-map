import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getAdminDisputes, type AdminDisputeItem } from '@/api/admin';

export function AdminDisputesPage() {
  const [statusFilter, setStatusFilter] = useState('');
  
  const { data, isLoading, error } = useQuery({
    queryKey: ['admin', 'disputes', statusFilter],
    queryFn: () => getAdminDisputes(statusFilter || undefined),
  });

  if (isLoading) return <div className="text-center py-12 text-gray-500">Cargando disputas…</div>;
  if (error) return <div className="text-red-500 py-12">Error: {error instanceof Error ? error.message : 'Error al cargar'}</div>;

  const disputes = data || [];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Disputas (IA Resolution)</h1>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm px-3 py-2"
        >
          <option value="">Todos los estados</option>
          <option value="PENDING_CAREGIVER">Esperando Cuidador</option>
          <option value="PENDING_AI">Analizando (IA)</option>
          <option value="RESOLVED">Resueltas</option>
        </select>
      </div>

      <div className="grid gap-4">
        {disputes.length === 0 ? (
          <div className="bg-white dark:bg-gray-800 p-8 text-center rounded-2xl border border-gray-200 dark:border-gray-700 text-gray-500">
            No se encontraron disputas.
          </div>
        ) : (
          disputes.map((d: AdminDisputeItem) => (
            <div key={d.id} className="bg-white dark:bg-gray-800 p-6 rounded-2xl border border-gray-200 dark:border-gray-700 shadow-sm space-y-4">
              <div className="flex justify-between items-start">
                <div>
                  <h3 className="font-bold text-lg text-gray-900 dark:text-white">Reserva: {d.bookingId.slice(0,8)}</h3>
                  <p className="text-sm text-gray-500">{d.clientName} (Cliente) vs {d.caregiverName} (Cuidador)</p>
                </div>
                <span className={`px-3 py-1 rounded-full text-xs font-bold ${
                  d.status === 'RESOLVED' ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-700'
                }`}>
                  {d.status}
                </span>
              </div>

              <div className="grid md:grid-cols-2 gap-4 text-sm">
                <div className="bg-red-50 dark:bg-red-900/10 p-4 rounded-xl border border-red-100 dark:border-red-900/30">
                  <p className="font-bold text-red-800 dark:text-red-400 mb-2">Reporte del Cliente:</p>
                  <ul className="list-disc list-inside space-y-1 text-red-700 dark:text-red-300">
                    {d.clientReasons.map((r, i) => <li key={i}>{r}</li>)}
                  </ul>
                </div>
                <div className="bg-blue-50 dark:bg-blue-900/10 p-4 rounded-xl border border-blue-100 dark:border-blue-900/30">
                  <p className="font-bold text-blue-800 dark:text-blue-400 mb-2">Respuesta del Cuidador:</p>
                  {d.caregiverResponse ? (
                    <ul className="list-disc list-inside space-y-1 text-blue-700 dark:text-blue-300">
                      {d.caregiverResponse.map((r, i) => <li key={i}>{r}</li>)}
                    </ul>
                  ) : <p className="text-gray-400 italic">Esperando respuesta...</p>}
                </div>
              </div>

              {d.status === 'RESOLVED' && (
                <div className="bg-green-50 dark:bg-green-900/10 p-4 rounded-xl border border-green-100 dark:border-green-900/30">
                  <p className="font-bold text-green-800 dark:text-green-400 mb-1">Veredicto IA: {d.aiVerdict}</p>
                  <p className="text-sm text-green-700 dark:text-green-300 mb-2">{d.aiAnalysis}</p>
                  <p className="text-xs font-bold text-green-600 dark:text-green-500 uppercase tracking-widest">Resolución: {d.resolution}</p>
                </div>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  );
}

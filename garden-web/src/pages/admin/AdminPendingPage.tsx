import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import toast from 'react-hot-toast';
import { getPendingCaregivers, reviewCaregiver, type PendingCaregiverItem } from '@/api/admin';

export function AdminPendingPage() {
  const [list, setList] = useState<PendingCaregiverItem[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [acting, setActing] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    try {
      const data = await getPendingCaregivers(1, 50);
      setList(data.caregivers);
      setTotal(data.total);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al cargar');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  const handleReview = async (
    id: string,
    action: 'approve' | 'reject' | 'request_revision',
    reason?: string
  ) => {
    if (action === 'reject' && (!reason || !reason.trim())) {
      toast.error('Indica el motivo del rechazo');
      return;
    }
    setActing(id);
    try {
      await reviewCaregiver(id, action, { reason: reason?.trim() });
      toast.success(
        action === 'approve'
          ? 'Solicitud aprobada'
          : action === 'reject'
            ? 'Rechazada'
            : 'Solicitud de revisión enviada'
      );
      await load();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error');
    } finally {
      setActing(null);
    }
  };

  const handleRejectClick = (c: PendingCaregiverItem) => {
    const reason = window.prompt('Motivo del rechazo (obligatorio). El cuidador verá este mensaje en su dashboard:');
    if (reason == null) return;
    if (!reason.trim()) {
      toast.error('El motivo no puede estar vacío');
      return;
    }
    handleReview(c.id, 'reject', reason.trim());
  };

  if (loading) {
    return (
      <div className="py-12 text-center text-gray-500">
        Cargando solicitudes…
      </div>
    );
  }

  return (
    <div className="py-6">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-semibold text-gray-900 dark:text-white">
          Solicitudes de cuidadores
        </h1>
        <Link
          to="/"
          className="text-sm text-green-600 hover:text-green-700 dark:text-green-400"
        >
          ← Volver al listado
        </Link>
      </div>
      <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
        {total} solicitud(es) pendiente(s) de revisión (PENDING_REVIEW o NEEDS_REVISION).
      </p>
      {list.length === 0 ? (
        <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-8 text-center text-gray-500">
          No hay solicitudes pendientes.
        </div>
      ) : (
        <ul className="space-y-4">
          {list.map((c) => (
            <li
              key={c.id}
              className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4 shadow-sm"
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="font-medium text-gray-900 dark:text-white">{c.fullName}</p>
                  <p className="text-sm text-gray-500">{c.email}</p>
                  <p className="text-sm text-gray-500">{c.phone}</p>
                  <p className="mt-1 text-xs text-gray-400">
                    Estado: <span className="font-medium">{c.status}</span>
                    {c.rejectionReason && ` · ${c.rejectionReason}`}
                  </p>
                </div>
                <div className="flex flex-wrap gap-2 items-center">
                  <Link
                    to={`/admin/caregivers/${c.id}/review`}
                    className="rounded-lg bg-green-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-green-700 dark:bg-green-500 dark:hover:bg-green-600"
                  >
                    Revisar
                  </Link>
                  <button
                    type="button"
                    disabled={!!acting}
                    onClick={() => handleReview(c.id, 'approve')}
                    className="rounded-lg bg-green-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
                  >
                    {acting === c.id ? '…' : 'Aprobar'}
                  </button>
                  <button
                    type="button"
                    disabled={!!acting}
                    onClick={() => handleRejectClick(c)}
                    className="rounded-lg border border-red-300 bg-white px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50 dark:border-red-700 dark:bg-gray-800 dark:text-red-400 dark:hover:bg-gray-700 disabled:opacity-50"
                  >
                    Rechazar
                  </button>
                  <button
                    type="button"
                    disabled={!!acting}
                    onClick={() => handleReview(c.id, 'request_revision')}
                    className="rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700 disabled:opacity-50"
                  >
                    Pedir revisión
                  </button>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

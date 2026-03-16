import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import toast from 'react-hot-toast';
import {
  getPaymentsPending,
  rejectPayment,
  approvePaymentManual,
  type PendingPaymentItem,
} from '@/api/admin';

const SERVICE_LABELS: Record<string, string> = {
  HOSPEDAJE: 'Hospedaje',
  PASEO: 'Paseo',
};

function formatDate(iso: string | null): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('es-BO', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  });
}

export function AdminPaymentsPendingPage() {
  const [list, setList] = useState<PendingPaymentItem[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [acting, setActing] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    try {
      const data = await getPaymentsPending();
      setList(data.bookings);
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

  const handleApprove = async (b: PendingPaymentItem) => {
    setActing(b.id);
    try {
      await approvePaymentManual(b.id);
      toast.success('Pago aprobado. La reserva quedó confirmada.');
      await load();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al aprobar');
    } finally {
      setActing(null);
    }
  };

  const handleReject = async (b: PendingPaymentItem) => {
    setActing(b.id);
    try {
      await rejectPayment(b.id);
      toast.success('Pago rechazado. La reserva volvió a pendiente de pago.');
      await load();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al rechazar');
    } finally {
      setActing(null);
    }
  };

  if (loading) {
    return (
      <div className="py-12 text-center text-gray-500 dark:text-gray-400">
        Cargando pagos pendientes…
      </div>
    );
  }

  return (
    <div className="py-6">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-gray-900 dark:text-white">
          Pagos pendientes de aprobación
        </h1>
        <Link
          to="/admin/caregivers"
          className="text-sm text-green-600 hover:text-green-700 dark:text-green-400"
        >
          ← Cuidadores
        </Link>
      </div>
      <p className="mb-4 text-sm text-gray-500 dark:text-gray-400">
        {total} reserva(s) en espera de aprobación de pago manual (PAYMENT_PENDING_APPROVAL).
      </p>
      {list.length === 0 ? (
        <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-8 text-center text-gray-500 dark:text-gray-400">
          No hay pagos pendientes de aprobación.
        </div>
      ) : (
        <ul className="space-y-4">
          {list.map((b) => (
            <li
              key={b.id}
              className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4 shadow-sm"
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="font-medium text-gray-900 dark:text-white">
                    Reserva {b.id.slice(0, 8)}…
                  </p>
                  <p className="text-sm text-gray-500 dark:text-gray-400">
                    {SERVICE_LABELS[b.serviceType] ?? b.serviceType} · Mascota: {b.petName}
                  </p>
                  <p className="text-sm text-gray-500 dark:text-gray-400">
                    Cliente: {b.clientEmail ?? b.clientId} · Cuidador: {b.caregiverName ?? b.caregiverId}
                  </p>
                  <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
                    {b.serviceType === 'PASEO'
                      ? `${formatDate(b.walkDate)} ${b.timeSlot ?? ''}`
                      : `${formatDate(b.startDate)} – ${formatDate(b.endDate)}`}
                    {' · '}
                    <span className="font-medium text-gray-700 dark:text-gray-300">
                      Bs {Number(b.totalAmount).toFixed(2)}
                    </span>
                  </p>
                </div>
                <div className="flex shrink-0 flex-wrap gap-2">
                  <button
                    type="button"
                    disabled={!!acting}
                    onClick={() => handleApprove(b)}
                    className="rounded-lg bg-green-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50 dark:bg-green-500 dark:hover:bg-green-600"
                  >
                    {acting === b.id ? '…' : 'Aprobar pago'}
                  </button>
                  <button
                    type="button"
                    disabled={!!acting}
                    onClick={() => handleReject(b)}
                    className="rounded-lg border border-red-300 bg-white px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50 disabled:opacity-50 dark:border-red-700 dark:bg-gray-800 dark:text-red-400 dark:hover:bg-gray-700"
                  >
                    Rechazar pago
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

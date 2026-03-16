import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useMyBookings } from '@/hooks/useMyBookings';
import { useCancelBooking } from '@/hooks/useCancelBooking';
import type { BookingResult } from '@/api/bookings';

const STATUS_LABELS: Record<string, string> = {
  PENDING_PAYMENT: 'Pendiente de pago',
  PAYMENT_PENDING_APPROVAL: 'Pago pendiente de aprobación',
  CONFIRMED: 'Confirmada',
  IN_PROGRESS: 'En curso',
  COMPLETED: 'Completada',
  CANCELLED: 'Cancelada',
};

const STATUS_CLASS: Record<string, string> = {
  CONFIRMED: 'bg-emerald-100 text-emerald-800',
  IN_PROGRESS: 'bg-sky-100 text-sky-800',
  PENDING_PAYMENT: 'bg-amber-100 text-amber-800',
  CANCELLED: 'bg-slate-100 text-slate-600',
  default: 'bg-slate-100 text-slate-700',
};

const WHATSAPP_ADMIN_PLACEHOLDER = 'https://wa.me/591XXXXXXXX'; // Sustituir por número real

function formatDate(d: string | null | undefined): string {
  if (!d) return '—';
  return new Date(d).toLocaleDateString('es-BO', { day: '2-digit', month: 'short', year: 'numeric' });
}

export function ClientReservationsPage() {
  const { data: allBookings, isLoading, error, refetch } = useMyBookings();
  const cancelMutation = useCancelBooking();
  const [cancellingId, setCancellingId] = useState<string | null>(null);
  const [cancelReason, setCancelReason] = useState('');

  const upcoming = (allBookings ?? []).filter(
    (b) => b.status === 'CONFIRMED' || b.status === 'IN_PROGRESS'
  );

  const canCancel = (b: BookingResult) =>
    b.status === 'CONFIRMED' || b.status === 'PENDING_PAYMENT' || b.status === 'PAYMENT_PENDING_APPROVAL';

  const handleCancel = (bookingId: string) => {
    setCancellingId(bookingId);
    cancelMutation.mutate(
      { bookingId, reason: cancelReason || undefined },
      {
        onSettled: () => {
          setCancellingId(null);
          setCancelReason('');
          refetch();
        },
      }
    );
  };

  if (isLoading) {
    return (
      <div className="mx-auto max-w-4xl px-4 py-10 text-center text-slate-500">
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
        <Link to="/profile" className="mt-4 inline-block text-sm text-emerald-600 hover:underline">
          Volver al perfil
        </Link>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-4xl px-4 py-8">
      <div className="mb-8">
        <Link to="/profile" className="text-sm font-medium text-slate-600 hover:text-slate-900">
          ← Perfil
        </Link>
        <h1 className="mt-2 text-2xl font-semibold text-slate-900">Mis próximas reservas</h1>
        <p className="mt-1 text-sm text-slate-600">
          Reservas confirmadas y en curso. Cancela dentro de los plazos si lo necesitas.
        </p>
      </div>

      {upcoming.length === 0 ? (
        <div className="rounded-2xl border border-slate-200 bg-white p-10 text-center shadow-sm">
          <p className="text-slate-600">No tienes reservas próximas (confirmadas o en curso).</p>
          <Link
            to="/"
            className="mt-4 inline-block rounded-xl bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-700"
          >
            Explorar cuidadores
          </Link>
        </div>
      ) : (
        <ul className="space-y-4">
          {upcoming.map((b) => (
            <li
              key={b.id}
              className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm transition-shadow hover:shadow-md"
            >
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div className="min-w-0 flex-1">
                  <div className="mb-2 flex flex-wrap items-center gap-2">
                    <span
                      className={`inline-flex rounded-full px-2.5 py-1 text-xs font-medium ${STATUS_CLASS[b.status] ?? STATUS_CLASS.default
                        }`}
                    >
                      {STATUS_LABELS[b.status] ?? b.status}
                    </span>
                    <span className="text-sm font-medium text-slate-700">
                      {b.serviceType === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseo'}
                    </span>
                  </div>
                  <p className="text-slate-700">
                    <span className="font-medium">Mascota:</span> {b.petName}
                    {b.petBreed && ` · ${b.petBreed}`}
                  </p>
                  {b.serviceType === 'HOSPEDAJE' && b.startDate && b.endDate && (
                    <p className="mt-1 text-sm text-slate-600">
                      {formatDate(b.startDate)} – {formatDate(b.endDate)}
                      {b.totalDays != null && ` (${b.totalDays} días)`}
                    </p>
                  )}
                  {b.serviceType === 'PASEO' && b.walkDate && (
                    <p className="mt-1 text-sm text-slate-600">
                      {formatDate(b.walkDate)}
                      {b.timeSlot && ` · ${b.timeSlot === 'MANANA' ? 'Mañana' : b.timeSlot === 'TARDE' ? 'Tarde' : 'Noche'}`}
                      {b.startTime && ` (${b.startTime})`}
                      {b.duration && ` (${b.duration} min)`}
                    </p>
                  )}
                  <p className="mt-2 text-lg font-semibold text-slate-900">
                    Bs {Number(b.totalAmount).toFixed(2)}
                  </p>
                </div>
                <div className="flex flex-wrap gap-2">
                  <Link
                    to={`/bookings/${b.id}`}
                    className="rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
                  >
                    Ver detalle
                  </Link>
                  {canCancel(b) && (
                    <div className="flex flex-wrap items-center gap-2">
                      {cancellingId === b.id ? (
                        <>
                          <input
                            type="text"
                            placeholder="Motivo (opcional)"
                            value={cancelReason}
                            onChange={(e) => setCancelReason(e.target.value)}
                            className="rounded-lg border border-slate-300 px-3 py-2 text-sm"
                          />
                          <button
                            type="button"
                            disabled={cancelMutation.isPending}
                            onClick={() => handleCancel(b.id)}
                            className="rounded-xl bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-60"
                          >
                            {cancelMutation.isPending ? 'Cancelando…' : 'Confirmar cancelar'}
                          </button>
                          <button
                            type="button"
                            onClick={() => { setCancellingId(null); setCancelReason(''); }}
                            className="rounded-xl border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
                          >
                            Cerrar
                          </button>
                        </>
                      ) : (
                        <button
                          type="button"
                          onClick={() => setCancellingId(b.id)}
                          className="rounded-xl border border-red-200 bg-white px-4 py-2 text-sm font-medium text-red-700 hover:bg-red-50"
                        >
                          Cancelar
                        </button>
                      )}
                    </div>
                  )}
                  <a
                    href={WHATSAPP_ADMIN_PLACEHOLDER}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
                  >
                    Contactar admin
                  </a>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { getCaregiverBookings, type CaregiverBookingItem } from '@/api/caregiverProfile';
import { requestCancellationByCaregiver } from '@/api/bookings';
import toast from 'react-hot-toast';

const STATUS_LABELS: Record<string, string> = {
  PENDING_PAYMENT: 'Pendiente de pago',
  WAITING_CAREGIVER_APPROVAL: 'Esperando tu aprobación',
  CONFIRMED: 'Confirmada',
  IN_PROGRESS: 'En curso',
  COMPLETED: 'Completada',
  CANCELLED: 'Cancelada',
  REJECTED_BY_CAREGIVER: 'Rechazada por ti',
};

const WHATSAPP_ADMIN_PLACEHOLDER = 'https://wa.me/591XXXXXXXX';

function formatDate(d: string | null | undefined): string {
  if (!d) return '—';
  return new Date(d).toLocaleDateString('es-BO', { day: '2-digit', month: 'short', year: 'numeric' });
}

export function CaregiverReservationsPage() {
  const queryClient = useQueryClient();
  const { data: bookings, isLoading, error } = useQuery({
    queryKey: ['caregiver', 'bookings'],
    queryFn: getCaregiverBookings,
  });
  const [requestingId, setRequestingId] = useState<string | null>(null);
  const [rejectingId, setRejectingId] = useState<string | null>(null);
  const [reason, setReason] = useState('');

  const acceptMutation = useMutation({
    mutationFn: (id: string) => import('@/api/bookings').then(m => m.acceptBooking(id)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['caregiver', 'bookings'] });
      toast.success('¡Reserva aceptada y confirmada!');
    },
    onError: (e: Error) => toast.error(e.message ?? 'Error al aceptar'),
  });

  const rejectMutation = useMutation({
    mutationFn: ({ id, reason: r }: { id: string; reason: string }) =>
      import('@/api/bookings').then(m => m.rejectBooking(id, { reason: r })),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['caregiver', 'bookings'] });
      toast.success('Reserva rechazada. Se ha notificado al cliente.');
      setRejectingId(null);
      setReason('');
    },
    onError: (e: Error) => toast.error(e.message ?? 'Error al rechazar'),
  });

  const requestCancellationMutation = useMutation({
    mutationFn: ({ bookingId, reason: r }: { bookingId: string; reason: string }) =>
      requestCancellationByCaregiver(bookingId, { reason: r }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['caregiver', 'bookings'] });
      toast.success('Reserva cancelada exitosamente. Se ha notificado al dueño.');
      setRequestingId(null);
      setReason('');
    },
    onError: (e: Error) => toast.error(e.message ?? 'Error al enviar'),
  });

  const canRequestCancellation = (b: CaregiverBookingItem) =>
    (b.status === 'CONFIRMED' || b.status === 'IN_PROGRESS') && !b.cancellationRequestedAt;

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
        <Link to="/caregiver/dashboard" className="mt-4 inline-block text-sm text-emerald-600 hover:underline">
          Volver al dashboard
        </Link>
      </div>
    );
  }

  const list = (bookings ?? []).filter(b => b.status !== 'PENDING_PAYMENT' && b.status !== 'PAYMENT_PENDING_APPROVAL');

  return (
    <div className="mx-auto max-w-4xl px-4 py-8">
      <div className="mb-8">
        <Link to="/caregiver/dashboard" className="text-sm font-medium text-slate-600 hover:text-slate-900">
          ← Dashboard
        </Link>
        <h1 className="mt-2 text-2xl font-semibold text-slate-900">Mis reservas asignadas</h1>
        <p className="mt-1 text-sm text-slate-600">
          Gestiona tus reservas pagadas. Debes aprobar las nuevas solicitudes para que queden confirmadas.
        </p>
      </div>

      <div className="mb-6 flex justify-end">
        <a
          href={WHATSAPP_ADMIN_PLACEHOLDER}
          target="_blank"
          rel="noopener noreferrer"
          className="rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
        >
          Soporte técnico (WhatsApp)
        </a>
      </div>

      {list.length === 0 ? (
        <div className="rounded-2xl border border-slate-200 bg-white p-10 text-center shadow-sm">
          <p className="text-slate-600">No tienes reservas activas aún.</p>
        </div>
      ) : (
        <ul className="space-y-4">
          {list.map((b) => (
            <li
              key={b.id}
              className={`rounded-2xl border p-5 shadow-sm transition-shadow hover:shadow-md ${b.status === 'WAITING_CAREGIVER_APPROVAL' ? 'border-amber-200 bg-amber-50/30' : 'border-slate-200 bg-white'
                }`}
            >
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div className="min-w-0 flex-1">
                  <div className="mb-2 flex flex-wrap items-center gap-2">
                    <span className={`inline-flex rounded-full px-2.5 py-1 text-xs font-medium ${b.status === 'WAITING_CAREGIVER_APPROVAL'
                      ? 'bg-amber-100 text-amber-800'
                      : 'bg-slate-100 text-slate-700'
                      }`}>
                      {STATUS_LABELS[b.status] ?? b.status}
                    </span>
                    <span className="text-sm font-medium text-slate-700">
                      {b.serviceType === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseo'}
                    </span>
                  </div>
                  <p className="text-slate-700">
                    <span className="font-medium">Mascota:</span> {b.petName}
                  </p>
                  {b.serviceType === 'HOSPEDAJE' && b.startDate && b.endDate && (
                    <p className="mt-1 text-sm text-slate-600">
                      {formatDate(b.startDate)} – {formatDate(b.endDate)}
                    </p>
                  )}
                  {b.serviceType === 'PASEO' && b.walkDate && (
                    <p className="mt-1 text-sm text-slate-600">
                      {formatDate(b.walkDate)}
                      {b.timeSlot && ` · ${b.timeSlot === 'MANANA' ? 'Mañana' : b.timeSlot === 'TARDE' ? 'Tarde' : 'Noche'}`}
                      {b.startTime && ` (${b.startTime})`}
                      {b.duration != null && ` (${b.duration} min)`}
                    </p>
                  )}
                  <p className="mt-2 text-lg font-semibold text-emerald-700">
                    Bs {(Number(b.totalAmount) - Number(b.commissionAmount)).toFixed(2)} <span className="text-xs font-normal text-slate-500 italic">(Tu pago neto)</span>
                  </p>
                </div>
                <div className="flex flex-wrap gap-2">
                  {b.status === 'WAITING_CAREGIVER_APPROVAL' && (
                    <div className="flex flex-col gap-2">
                      {rejectingId === b.id ? (
                        <div className="flex flex-col gap-2 rounded-xl border border-amber-200 bg-white p-3 shadow-sm">
                          <textarea
                            placeholder="Indica el motivo del rechazo (se enviará al cliente)"
                            value={reason}
                            onChange={(e) => setReason(e.target.value)}
                            rows={2}
                            className="w-64 rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-amber-500 focus:ring-1 focus:ring-amber-500"
                          />
                          <div className="flex gap-2">
                            <button
                              type="button"
                              disabled={!reason.trim() || rejectMutation.isPending}
                              onClick={() => rejectMutation.mutate({ id: b.id, reason: reason.trim() })}
                              className="rounded-lg bg-red-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50"
                            >
                              {rejectMutation.isPending ? 'Rechazando…' : 'Confirmar Rechazo'}
                            </button>
                            <button
                              type="button"
                              onClick={() => { setRejectingId(null); setReason(''); }}
                              className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-100"
                            >
                              Cancelar
                            </button>
                          </div>
                        </div>
                      ) : (
                        <div className="flex gap-2">
                          <button
                            type="button"
                            disabled={acceptMutation.isPending}
                            onClick={() => acceptMutation.mutate(b.id)}
                            className="rounded-xl bg-emerald-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-emerald-700 disabled:opacity-50"
                          >
                            {acceptMutation.isPending ? 'Aceptando…' : 'Aceptar Reserva'}
                          </button>
                          <button
                            type="button"
                            onClick={() => setRejectingId(b.id)}
                            className="rounded-xl border border-red-200 bg-white px-4 py-2 text-sm font-medium text-red-700 hover:bg-red-50"
                          >
                            Rechazar
                          </button>
                        </div>
                      )}
                    </div>
                  )}

                  {requestingId === b.id ? (
                    <div className="flex flex-col gap-2 rounded-xl border border-slate-200 bg-slate-50 p-3">
                      <textarea
                        placeholder="Motivo de la cancelación (se enviará al cliente)"
                        value={reason}
                        onChange={(e) => setReason(e.target.value)}
                        rows={2}
                        className="w-64 rounded-lg border border-slate-300 px-3 py-2 text-sm"
                      />
                      <div className="flex gap-2">
                        <button
                          type="button"
                          disabled={!reason.trim() || requestCancellationMutation.isPending}
                          onClick={() =>
                            requestCancellationMutation.mutate({ bookingId: b.id, reason: reason.trim() })
                          }
                          className="rounded-lg bg-red-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50"
                        >
                          {requestCancellationMutation.isPending ? 'Cancelando…' : 'Confirmar cancelación'}
                        </button>
                        <button
                          type="button"
                          onClick={() => { setRequestingId(null); setReason(''); }}
                          className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-100"
                        >
                          Cerrar
                        </button>
                      </div>
                    </div>
                  ) : (
                    canRequestCancellation(b) && (
                      <button
                        type="button"
                        onClick={() => setRequestingId(b.id)}
                        className="rounded-xl border border-red-200 bg-white px-4 py-2 text-sm font-medium text-red-700 hover:bg-red-50"
                      >
                        Cancelar reserva
                      </button>
                    )
                  )}
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

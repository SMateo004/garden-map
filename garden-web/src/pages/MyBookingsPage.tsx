import { Link } from 'react-router-dom';
import { useMyBookings } from '@/hooks/useMyBookings';
import type { BookingResult } from '@/api/bookings';

function getStatusBadge(status: string) {
  const statusMap: Record<string, { label: string; className: string }> = {
    PENDING_PAYMENT: { label: 'Pendiente de pago', className: 'bg-yellow-100 text-yellow-800' },
    WAITING_CAREGIVER_APPROVAL: { label: 'Esperando al cuidador', className: 'bg-amber-100 text-amber-800 animate-pulse' },
    CONFIRMED: { label: 'Confirmada', className: 'bg-green-100 text-green-800' },
    IN_PROGRESS: { label: 'En curso', className: 'bg-blue-100 text-blue-800' },
    COMPLETED: { label: 'Completada', className: 'bg-gray-100 text-gray-800' },
    CANCELLED: { label: 'Cancelada', className: 'bg-red-100 text-red-800' },
    REJECTED_BY_CAREGIVER: { label: 'Rechazada por cuidador', className: 'bg-red-100 text-red-800' },
  };
  const statusInfo = statusMap[status] || { label: status, className: 'bg-gray-100 text-gray-800' };
  return (
    <span className={`inline-flex rounded-full px-2 py-1 text-xs font-medium ${statusInfo.className}`}>
      {statusInfo.label}
    </span>
  );
}

function BookingCard({ booking }: { booking: BookingResult }) {
  return (
    <div className="block rounded-xl border border-gray-200 bg-white p-6 shadow-sm transition-shadow hover:shadow-md">
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <div className="mb-2 flex items-center gap-3">
            <h3 className="text-lg font-semibold text-gray-900">
              {booking.serviceType === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseo'}
            </h3>
            {getStatusBadge(booking.status)}
          </div>
          <p className="text-sm text-gray-600">
            <span className="font-medium text-slate-700">Mascota:</span> {booking.petName}
            {booking.petBreed && ` (${booking.petBreed})`}
          </p>
          {booking.serviceType === 'HOSPEDAJE' && booking.startDate && booking.endDate && (
            <p className="mt-1 text-sm text-gray-600">
              <span className="font-medium text-slate-700">Fechas:</span>{' '}
              {new Date(booking.startDate).toLocaleDateString('es-BO')} -{' '}
              {new Date(booking.endDate).toLocaleDateString('es-BO')} ({booking.totalDays} días)
            </p>
          )}
          {booking.serviceType === 'PASEO' && booking.walkDate && (
            <p className="mt-1 text-sm text-gray-600">
              <span className="font-medium text-slate-700">Fecha:</span> {new Date(booking.walkDate).toLocaleDateString('es-BO')}
              {booking.timeSlot && ` - ${booking.timeSlot === 'MANANA' ? 'Mañana' : booking.timeSlot === 'TARDE' ? 'Tarde' : 'Noche'}`}
              {booking.startTime && ` (${booking.startTime})`}
              {booking.duration && ` (${booking.duration} min)`}
            </p>
          )}
          <p className="mt-2 text-lg font-semibold text-slate-900">Bs {booking.totalAmount}</p>
          {booking.status === 'REJECTED_BY_CAREGIVER' && booking.cancellationReason && (
            <div className="mt-4 rounded-lg bg-red-50 p-3 text-sm text-red-800">
              <p className="font-semibold">Reserva Rechazada:</p>
              <p>{booking.cancellationReason}</p>
              <p className="mt-1 italic opacity-80 text-xs">Se realizará tu reembolso en un plazo de 1 día hábil.</p>
            </div>
          )}
          {booking.status === 'WAITING_CAREGIVER_APPROVAL' && (
            <p className="mt-3 text-xs italic text-amber-700">
              * El cuidador ha sido notificado y debe aprobar tu reserva para confirmarla.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}

export function MyBookingsPage() {
  const { data: bookings, isLoading, error } = useMyBookings();

  if (isLoading) {
    return (
      <div className="mx-auto max-w-4xl px-4 py-12 text-center text-gray-500">
        Cargando tus reservas...
      </div>
    );
  }

  if (error) {
    return (
      <div className="mx-auto max-w-4xl px-4 py-8">
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-red-800 shadow-sm">
          Error al cargar reservas: {error instanceof Error ? error.message : 'Error desconocido'}
        </div>
      </div>
    );
  }

  const activeBookings = bookings?.filter(b =>
    b.status !== 'PENDING_PAYMENT' && b.status !== 'PAYMENT_PENDING_APPROVAL'
  ) ?? [];

  return (
    <div className="mx-auto max-w-4xl px-4 py-8">
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-gray-900">Mis Reservas</h1>
        <p className="mt-1 text-gray-600">Historial y estado de tus servicios contratados</p>
      </div>

      {activeBookings.length === 0 ? (
        <div className="rounded-2xl border border-slate-200 bg-white p-12 text-center shadow-sm">
          <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-slate-50">
            <svg className="h-8 w-8 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
          </div>
          <h3 className="text-lg font-semibold text-gray-900">Sin reservas activas</h3>
          <p className="mt-2 text-gray-500">Aún no tienes reservas pagadas o confirmadas.</p>
          <Link
            to="/"
            className="mt-6 inline-block rounded-xl bg-emerald-600 px-8 py-3 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-emerald-700"
          >
            Explorar cuidadores
          </Link>
        </div>
      ) : (
        <div className="space-y-6">
          {activeBookings.map((booking) => (
            <BookingCard key={booking.id} booking={booking} />
          ))}
        </div>
      )}
    </div>
  );
}

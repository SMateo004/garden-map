import { useState } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { useBooking } from '@/hooks/useBooking';
import { useCancelBooking } from '@/hooks/useCancelBooking';
import { useExtendBooking } from '@/hooks/useExtendBooking';
import { useChangeDatesBooking } from '@/hooks/useChangeDatesBooking';
import { useVerifyPayment } from '@/hooks/useVerifyPayment';
import { CancellationRulesTable } from '@/components/CancellationRulesTable';

function getStatusBadge(status: string) {
  const statusMap: Record<string, { label: string; className: string }> = {
    PENDING_PAYMENT: { label: 'Pendiente de pago', className: 'bg-yellow-100 text-yellow-800' },
    CONFIRMED: { label: 'Confirmada', className: 'bg-green-100 text-green-800' },
    IN_PROGRESS: { label: 'En curso', className: 'bg-blue-100 text-blue-800' },
    COMPLETED: { label: 'Completada', className: 'bg-gray-100 text-gray-800' },
    CANCELLED: { label: 'Cancelada', className: 'bg-red-100 text-red-800' },
  };
  const statusInfo = statusMap[status] || { label: status, className: 'bg-gray-100 text-gray-800' };
  return (
    <span className={`inline-flex rounded-full px-3 py-1 text-sm font-medium ${statusInfo.className}`}>
      {statusInfo.label}
    </span>
  );
}

export function BookingDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { data: booking, isLoading, error } = useBooking(id);
  const cancelMutation = useCancelBooking();
  const extendMutation = useExtendBooking();
  const changeDatesMutation = useChangeDatesBooking();
  const verifyPaymentMutation = useVerifyPayment();

  const [showCancelModal, setShowCancelModal] = useState(false);
  const [showExtendModal, setShowExtendModal] = useState(false);
  const [showChangeDatesModal, setShowChangeDatesModal] = useState(false);
  const [cancelReason, setCancelReason] = useState('');
  const [newEndDate, setNewEndDate] = useState('');
  const [newStartDate, setNewStartDate] = useState('');
  const [newEndDateChange, setNewEndDateChange] = useState('');

  if (isLoading) {
    return (
      <div className="mx-auto max-w-4xl px-4 py-8">
        <div className="text-center text-gray-500">Cargando reserva...</div>
      </div>
    );
  }

  if (error || !booking) {
    return (
      <div className="mx-auto max-w-4xl px-4 py-8">
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-red-800">
          {error instanceof Error ? error.message : 'Reserva no encontrada'}
        </div>
        <Link to="/bookings" className="mt-4 inline-block text-green-600 hover:underline">
          Volver a mis reservas
        </Link>
      </div>
    );
  }

  const canCancel = booking.status === 'PENDING_PAYMENT' || booking.status === 'CONFIRMED';
  const canExtend = booking.status === 'CONFIRMED' && booking.serviceType === 'HOSPEDAJE';
  const canChangeDates = booking.status === 'CONFIRMED' && booking.serviceType === 'HOSPEDAJE';
  const canVerifyPayment = booking.status === 'PENDING_PAYMENT' && booking.qrId;

  const handleCancel = () => {
    if (!id) return;
    cancelMutation.mutate(
      { bookingId: id, reason: cancelReason || undefined },
      {
        onSuccess: () => {
          setShowCancelModal(false);
          setCancelReason('');
        },
      }
    );
  };

  const handleExtend = () => {
    if (!id || !newEndDate) return;
    extendMutation.mutate(
      { bookingId: id, newEndDate },
      {
        onSuccess: () => {
          setShowExtendModal(false);
          setNewEndDate('');
        },
      }
    );
  };

  const handleChangeDates = () => {
    if (!id || !newStartDate || !newEndDateChange) return;
    changeDatesMutation.mutate(
      { bookingId: id, newStartDate, newEndDate: newEndDateChange },
      {
        onSuccess: () => {
          setShowChangeDatesModal(false);
          setNewStartDate('');
          setNewEndDateChange('');
        },
      }
    );
  };

  const handleVerifyPayment = () => {
    if (!booking.qrId) return;
    verifyPaymentMutation.mutate(booking.qrId, {
      onSuccess: () => {
        navigate(`/bookings/${id}`);
      },
    });
  };

  return (
    <div className="mx-auto max-w-4xl px-4 py-8">
      <Link to="/bookings" className="mb-4 inline-flex items-center text-sm text-gray-600 hover:text-gray-900">
        <svg className="mr-1 h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
        </svg>
        Volver a mis reservas
      </Link>

      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Detalle de Reserva</h1>
          <p className="mt-1 text-sm text-gray-600">ID: {booking.id.slice(0, 8)}...</p>
        </div>
        {getStatusBadge(booking.status)}
      </div>

      <div className="space-y-6">
        {/* Información de la reserva */}
        <div className="rounded-lg border border-gray-200 bg-white p-6">
          <h2 className="mb-4 text-lg font-semibold text-gray-900">Información de la Reserva</h2>
          <div className="space-y-3 text-sm">
            <div className="flex justify-between">
              <span className="text-gray-600">Servicio:</span>
              <span className="font-medium text-gray-900">
                {booking.serviceType === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseo'}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-600">Mascota:</span>
              <span className="font-medium text-gray-900">
                {booking.petName}
                {booking.petBreed && ` (${booking.petBreed})`}
                {booking.petAge && `, ${booking.petAge} años`}
              </span>
            </div>
            {booking.serviceType === 'HOSPEDAJE' && booking.startDate && booking.endDate && (
              <>
                <div className="flex justify-between">
                  <span className="text-gray-600">Check-in:</span>
                  <span className="font-medium text-gray-900">
                    {new Date(booking.startDate).toLocaleDateString('es-BO')}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-600">Check-out:</span>
                  <span className="font-medium text-gray-900">
                    {new Date(booking.endDate).toLocaleDateString('es-BO')}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-600">Días:</span>
                  <span className="font-medium text-gray-900">{booking.totalDays}</span>
                </div>
              </>
            )}
            {booking.serviceType === 'PASEO' && booking.walkDate && (
              <>
                <div className="flex justify-between">
                  <span className="text-gray-600">Fecha:</span>
                  <span className="font-medium text-gray-900">
                    {new Date(booking.walkDate).toLocaleDateString('es-BO')}
                  </span>
                </div>
                {booking.timeSlot && (
                  <div className="flex justify-between">
                    <span className="text-gray-600">Horario:</span>
                    <span className="font-medium text-gray-900">
                      {booking.timeSlot === 'MANANA' ? 'Mañana' : booking.timeSlot === 'TARDE' ? 'Tarde' : 'Noche'}
                      {booking.startTime && ` (${booking.startTime})`}
                    </span>
                  </div>
                )}
                {booking.duration && (
                  <div className="flex justify-between">
                    <span className="text-gray-600">Duración:</span>
                    <span className="font-medium text-gray-900">{booking.duration} minutos</span>
                  </div>
                )}
              </>
            )}
            {booking.specialNeeds && (
              <div className="flex justify-between">
                <span className="text-gray-600">Necesidades especiales:</span>
                <span className="font-medium text-gray-900">{booking.specialNeeds}</span>
              </div>
            )}
            <div className="mt-4 border-t border-gray-200 pt-4">
              <div className="flex justify-between text-lg font-semibold text-gray-900">
                <span>Total:</span>
                <span>Bs {booking.totalAmount}</span>
              </div>
            </div>
            {booking.refundAmount && booking.refundStatus && (
              <div className="flex justify-between text-sm">
                <span className="text-gray-600">Reembolso:</span>
                <span className="font-medium text-gray-900">
                  Bs {booking.refundAmount} ({booking.refundStatus})
                </span>
              </div>
            )}
          </div>
        </div>

        {/* Acciones */}
        {canCancel && (
          <div className="rounded-lg border border-gray-200 bg-white p-6">
            <h2 className="mb-4 text-lg font-semibold text-gray-900">Acciones</h2>
            <div className="flex flex-wrap gap-3">
              {canCancel && (
                <button
                  onClick={() => setShowCancelModal(true)}
                  className="rounded-lg border border-red-300 bg-red-50 px-4 py-2 text-sm font-medium text-red-700 hover:bg-red-100"
                >
                  Cancelar Reserva
                </button>
              )}
              {canExtend && (
                <button
                  onClick={() => setShowExtendModal(true)}
                  className="rounded-lg border border-green-300 bg-green-50 px-4 py-2 text-sm font-medium text-green-700 hover:bg-green-100"
                >
                  Extender Hospedaje
                </button>
              )}
              {canChangeDates && (
                <button
                  onClick={() => setShowChangeDatesModal(true)}
                  className="rounded-lg border border-blue-300 bg-blue-50 px-4 py-2 text-sm font-medium text-blue-700 hover:bg-blue-100"
                >
                  Cambiar Fechas
                </button>
              )}
              {canVerifyPayment && (
                <button
                  onClick={handleVerifyPayment}
                  disabled={verifyPaymentMutation.isPending}
                  className="rounded-lg border border-green-300 bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
                >
                  {verifyPaymentMutation.isPending ? 'Verificando...' : 'Verificar Pago QR'}
                </button>
              )}
            </div>
          </div>
        )}

        {/* Reglas de cancelación */}
        <div className="rounded-lg border border-gray-200 bg-white p-6">
          <h2 className="mb-4 text-lg font-semibold text-gray-900">Política de Cancelación</h2>
          <CancellationRulesTable />
        </div>

        {/* Link al cuidador */}
        <div className="rounded-lg border border-gray-200 bg-white p-6">
          <Link
            to={`/caregivers/${booking.caregiverId}`}
            className="inline-flex items-center text-green-600 hover:text-green-700"
          >
            Ver perfil del cuidador
            <svg className="ml-1 h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
          </Link>
        </div>
      </div>

      {/* Modal Cancelar */}
      {showCancelModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
          <div className="mx-4 w-full max-w-md rounded-lg bg-white p-6">
            <h3 className="mb-4 text-lg font-semibold text-gray-900">Cancelar Reserva</h3>
            <p className="mb-4 text-sm text-gray-600">
              ¿Estás seguro de que deseas cancelar esta reserva? Se aplicará la política de reembolso según las
              reglas del MVP.
            </p>
            <textarea
              value={cancelReason}
              onChange={(e) => setCancelReason(e.target.value)}
              placeholder="Motivo de cancelación (opcional)"
              className="mb-4 w-full rounded-lg border border-gray-300 p-2 text-sm"
              rows={3}
            />
            <div className="flex gap-3">
              <button
                onClick={() => {
                  setShowCancelModal(false);
                  setCancelReason('');
                }}
                className="flex-1 rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
              >
                Cancelar
              </button>
              <button
                onClick={handleCancel}
                disabled={cancelMutation.isPending}
                className="flex-1 rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50"
              >
                {cancelMutation.isPending ? 'Cancelando...' : 'Confirmar Cancelación'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Modal Extender */}
      {showExtendModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
          <div className="mx-4 w-full max-w-md rounded-lg bg-white p-6">
            <h3 className="mb-4 text-lg font-semibold text-gray-900">Extender Hospedaje</h3>
            <p className="mb-4 text-sm text-gray-600">
              Selecciona la nueva fecha de salida. El monto se recalculará automáticamente.
            </p>
            <input
              type="date"
              value={newEndDate}
              onChange={(e) => setNewEndDate(e.target.value)}
              min={
                booking.endDate
                  ? new Date(new Date(booking.endDate).getTime() + 24 * 60 * 60 * 1000)
                    .toISOString()
                    .slice(0, 10)
                  : undefined
              }
              className="mb-4 w-full rounded-lg border border-gray-300 p-2 text-sm"
            />
            <div className="flex gap-3">
              <button
                onClick={() => {
                  setShowExtendModal(false);
                  setNewEndDate('');
                }}
                className="flex-1 rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
              >
                Cancelar
              </button>
              <button
                onClick={handleExtend}
                disabled={extendMutation.isPending || !newEndDate}
                className="flex-1 rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
              >
                {extendMutation.isPending ? 'Extendiendo...' : 'Confirmar Extensión'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Modal Cambiar Fechas */}
      {showChangeDatesModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
          <div className="mx-4 w-full max-w-md rounded-lg bg-white p-6">
            <h3 className="mb-4 text-lg font-semibold text-gray-900">Cambiar Fechas</h3>
            <p className="mb-4 text-sm text-gray-600">
              Selecciona las nuevas fechas de entrada y salida. El monto se recalculará automáticamente.
            </p>
            <div className="mb-4 space-y-3">
              <div>
                <label className="mb-1 block text-sm font-medium text-gray-700">Nueva fecha de entrada</label>
                <input
                  type="date"
                  value={newStartDate}
                  onChange={(e) => setNewStartDate(e.target.value)}
                  min={new Date().toISOString().slice(0, 10)}
                  className="w-full rounded-lg border border-gray-300 p-2 text-sm"
                />
              </div>
              <div>
                <label className="mb-1 block text-sm font-medium text-gray-700">Nueva fecha de salida</label>
                <input
                  type="date"
                  value={newEndDateChange}
                  onChange={(e) => setNewEndDateChange(e.target.value)}
                  min={
                    newStartDate
                      ? new Date(new Date(newStartDate).getTime() + 2 * 24 * 60 * 60 * 1000)
                        .toISOString()
                        .slice(0, 10)
                      : undefined
                  }
                  className="w-full rounded-lg border border-gray-300 p-2 text-sm"
                />
              </div>
            </div>
            <div className="flex gap-3">
              <button
                onClick={() => {
                  setShowChangeDatesModal(false);
                  setNewStartDate('');
                  setNewEndDateChange('');
                }}
                className="flex-1 rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
              >
                Cancelar
              </button>
              <button
                onClick={handleChangeDates}
                disabled={changeDatesMutation.isPending || !newStartDate || !newEndDateChange}
                className="flex-1 rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-50"
              >
                {changeDatesMutation.isPending ? 'Cambiando...' : 'Confirmar Cambio'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

import { useLocation, Link, useNavigate } from 'react-router-dom';
import { useVerifyPayment } from '@/hooks/useVerifyPayment';
import type { BookingResult } from '@/api/bookings';
import { getImageUrl } from '@/utils/images';

export function BookingSuccessPage() {
  const location = useLocation();
  const navigate = useNavigate();
  const booking = location.state?.booking as BookingResult | undefined;
  const verifyPaymentMutation = useVerifyPayment();

  const handleVerifyPayment = () => {
    if (!booking?.qrId) return;
    verifyPaymentMutation.mutate(booking.qrId, {
      onSuccess: () => {
        navigate(`/bookings/${booking.id}`);
      },
    });
  };

  if (!booking) {
    return (
      <div className="mx-auto max-w-2xl rounded-xl border border-gray-200 bg-white p-6 text-center">
        <h1 className="text-xl font-bold text-gray-900">Reserva no encontrada</h1>
        <Link to="/" className="mt-4 inline-block text-green-600 hover:underline">
          Volver al inicio
        </Link>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6 px-4 py-6 sm:px-6 lg:px-8">
      <div className="rounded-xl border border-green-200 bg-green-50 p-6 text-center">
        <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-green-600">
          <svg className="h-8 w-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
        </div>
        <h1 className="text-2xl font-bold text-gray-900">¡Reserva creada exitosamente!</h1>
        <p className="mt-2 text-gray-600">
          Tu reserva está pendiente de pago. Usa el código QR para completar el pago.
        </p>
      </div>

      <div className="rounded-xl border border-gray-200 bg-white p-6">
        <h2 className="mb-4 text-lg font-semibold text-gray-900">Detalles de la reserva</h2>
        <div className="space-y-2 text-sm">
          <div className="flex justify-between">
            <span className="text-gray-600">ID de reserva:</span>
            <span className="font-medium text-gray-900">{booking.id.slice(0, 8)}...</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-600">Mascota:</span>
            <span className="font-medium text-gray-900">{booking.petName}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-600">Servicio:</span>
            <span className="font-medium text-gray-900">
              {booking.serviceType === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseo'}
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
            </>
          )}
          {booking.serviceType === 'PASEO' && booking.walkDate && (
            <div className="flex justify-between">
              <span className="text-gray-600">Fecha:</span>
              <span className="font-medium text-gray-900">
                {new Date(booking.walkDate).toLocaleDateString('es-BO')}
              </span>
            </div>
          )}
          <div className="mt-4 border-t border-gray-200 pt-4">
            <div className="flex justify-between text-lg font-semibold text-gray-900">
              <span>Total a pagar:</span>
              <span>Bs {booking.totalAmount}</span>
            </div>
          </div>
        </div>
      </div>

      {booking.qrId && (
        <div className="rounded-xl border border-gray-200 bg-white p-6 text-center">
          <h2 className="mb-4 text-lg font-semibold text-gray-900">Código QR para pago</h2>
          {booking.qrImageUrl ? (
            <img
              src={getImageUrl(booking.qrImageUrl)}
              alt="QR de pago"
              loading="lazy"
              className="mx-auto mb-4 h-64 w-64 rounded-lg border border-gray-200"
            />
          ) : (
            <div className="mx-auto mb-4 flex h-64 w-64 items-center justify-center rounded-lg border border-gray-200 bg-gray-50">
              <p className="text-sm text-gray-500">QR placeholder</p>
            </div>
          )}
          <p className="mb-4 text-xs text-gray-500">
            Escanea este código QR para completar el pago. Válido hasta{' '}
            {booking.qrExpiresAt
              ? new Date(booking.qrExpiresAt).toLocaleString('es-BO')
              : '24 horas'}
          </p>
          <button
            onClick={handleVerifyPayment}
            disabled={verifyPaymentMutation.isPending}
            className="rounded-lg bg-green-600 px-6 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
          >
            {verifyPaymentMutation.isPending ? 'Verificando pago...' : 'Verificar Pago QR'}
          </button>
        </div>
      )}

      <div className="flex gap-4">
        <Link
          to="/"
          className="flex-1 rounded-lg border border-gray-300 bg-white px-6 py-3 text-center font-medium text-gray-700 hover:bg-gray-50"
        >
          Volver al inicio
        </Link>
        <Link
          to={`/caregivers/${booking.caregiverId}`}
          className="flex-1 rounded-lg bg-green-600 px-6 py-3 text-center font-medium text-white hover:bg-green-700"
        >
          Ver perfil del cuidador
        </Link>
      </div>
    </div>
  );
}

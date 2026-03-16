import { useEffect, useState } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { useBookingConfirm } from '@/hooks/useBookingConfirm';
import { useInitPayment } from '@/hooks/useInitPayment';
import { useVerifyPayment } from '@/hooks/useVerifyPayment';
import { getImageUrl } from '@/utils/images';
import toast from 'react-hot-toast';

/** Minutos de validez del QR en página de pago (debe coincidir con backend QR_VALIDITY_MINUTES_PAYMENT). */
const QR_VALIDITY_MINUTES = 15;

function formatRemaining(ms: number): string {
  if (ms <= 0) return '0:00';
  const totalSeconds = Math.floor(ms / 1000);
  const m = Math.floor(totalSeconds / 60);
  const s = totalSeconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export function PaymentPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { data: booking, isLoading: loadingBooking, refetch } = useBookingConfirm(id);
  const initPaymentMutation = useInitPayment();
  const verifyPaymentMutation = useVerifyPayment();

  const [remainingMs, setRemainingMs] = useState<number | null>(null);
  const [qrExpiresAt, setQrExpiresAt] = useState<string | null>(null);

  // Sincronizar qrExpiresAt desde la reserva (tras refetch o carga)
  useEffect(() => {
    if (booking?.qrExpiresAt) setQrExpiresAt(booking.qrExpiresAt);
  }, [booking?.qrExpiresAt]);

  // Generar QR al montar si la reserva está PENDING_PAYMENT y no tiene QR
  useEffect(() => {
    if (!id || !booking) return;
    if (booking.status !== 'PENDING_PAYMENT') return;
    if (booking.qrId && booking.qrImageUrl) return;
    initPaymentMutation.mutate(
      { bookingId: id, body: { method: 'qr' } },
      {
        onSuccess: (data) => {
          if (data.qrExpiresAt) setQrExpiresAt(data.qrExpiresAt);
          refetch();
        },
      }
    );
  }, [id, booking?.status, booking?.qrId]); // eslint-disable-line react-hooks/exhaustive-deps

  // Timer de expiración (15 min)
  useEffect(() => {
    if (!qrExpiresAt) return;
    const expiresAt = new Date(qrExpiresAt).getTime();
    const tick = () => {
      const now = Date.now();
      const remaining = expiresAt - now;
      setRemainingMs(remaining);
      if (remaining <= 0) return;
    };
    tick();
    const interval = setInterval(tick, 1000);
    return () => clearInterval(interval);
  }, [qrExpiresAt]);

  const qrImageUrl = booking?.qrImageUrl ?? initPaymentMutation.data?.qrImageUrl ?? null;
  const qrId = booking?.qrId ?? initPaymentMutation.data?.qrId ?? null;
  const isExpired = remainingMs !== null && remainingMs <= 0;
  const pendingPayment =
    booking?.status === 'PENDING_PAYMENT' || booking?.status === 'PAYMENT_PENDING_APPROVAL';

  const handleYaPague = () => {
    if (!qrId) {
      toast.error('No hay código QR para verificar');
      return;
    }
    verifyPaymentMutation.mutate(qrId, {
      onSuccess: () => {
        navigate(`/bookings/${id}`, { replace: true });
      },
    });
  };

  const handlePagoManual = () => {
    if (!id) return;
    initPaymentMutation.mutate(
      { bookingId: id, body: { method: 'manual' } },
      {
        onSuccess: () => {
          toast.success('Solicitud enviada. Un administrador revisará el pago.');
          refetch();
        },
      }
    );
  };

  const handleRegenerarQr = () => {
    if (!id) return;
    setQrExpiresAt(null);
    setRemainingMs(null);
    initPaymentMutation.mutate(
      { bookingId: id, body: { method: 'qr' } },
      {
        onSuccess: (data) => {
          if (data.qrExpiresAt) setQrExpiresAt(data.qrExpiresAt);
          toast.success('Nuevo QR generado');
          refetch();
        },
      }
    );
  };

  if (loadingBooking) {
    return (
      <div className="flex min-h-[40vh] items-center justify-center px-4">
        <p className="text-slate-500" role="status">
          Cargando…
        </p>
      </div>
    );
  }

  if (!booking) {
    return (
      <div className="mx-auto max-w-lg px-4 py-8">
        <div className="rounded-xl border border-red-200 bg-red-50/80 p-6 text-red-800">
          <p className="font-medium">Reserva no encontrada</p>
          <Link to="/bookings" className="mt-4 inline-block text-sm underline">
            Volver a mis reservas
          </Link>
        </div>
      </div>
    );
  }

  if (booking.status === 'CONFIRMED' || booking.status === 'IN_PROGRESS' || booking.status === 'COMPLETED') {
    return (
      <div className="mx-auto max-w-lg px-4 py-8">
        <div className="rounded-xl border border-emerald-200 bg-emerald-50/50 p-6 text-emerald-800">
          <p className="font-medium">Esta reserva ya está pagada y confirmada.</p>
          <Link
            to={`/bookings/${booking.id}`}
            className="mt-4 inline-block rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-700"
          >
            Ver reserva
          </Link>
        </div>
      </div>
    );
  }

  if (booking.status === 'PAYMENT_PENDING_APPROVAL') {
    return (
      <div className="mx-auto max-w-lg px-4 py-8">
        <div className="rounded-xl border border-amber-200 bg-amber-50/50 p-6 text-amber-900">
          <h2 className="text-lg font-semibold">Pago pendiente de aprobación</h2>
          <p className="mt-2 text-sm">
            Tu solicitud de pago manual fue enviada. Un administrador la revisará y te notificaremos cuando se confirme.
          </p>
          <Link
            to={`/bookings/${booking.id}`}
            className="mt-4 inline-block text-sm font-medium text-amber-800 underline"
          >
            Ver reserva
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-md px-4 py-8 sm:px-6">
      <nav className="mb-6" aria-label="Navegación">
        <Link
          to={`/booking/${id}/confirm`}
          className="text-sm font-medium text-emerald-700 hover:text-emerald-800"
        >
          ← Volver al resumen
        </Link>
      </nav>

      <h1 className="mb-2 text-2xl font-semibold text-slate-800">Pagar reserva</h1>
      <p className="mb-6 text-slate-600">
        Escanea el código QR con la app de tu banco para completar el pago.
      </p>

      <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
        {initPaymentMutation.isPending && !qrImageUrl ? (
          <div className="flex flex-col items-center justify-center py-12">
            <p className="text-slate-500">Generando código QR…</p>
          </div>
        ) : qrImageUrl ? (
          <>
            <div className="flex flex-col items-center">
              <img
                src={getImageUrl(qrImageUrl)}
                alt="Código QR para pago"
                loading="lazy"
                className={`h-56 w-56 rounded-xl border-2 border-slate-200 bg-white p-3 object-contain ${
                  isExpired ? 'opacity-50 grayscale' : ''
                }`}
              />
              {remainingMs !== null && (
                <p
                  className={`mt-4 text-sm font-medium ${
                    isExpired ? 'text-red-600' : 'text-slate-600'
                  }`}
                  role="timer"
                  aria-live="polite"
                >
                  {isExpired
                    ? 'QR expirado'
                    : `Expira en ${formatRemaining(remainingMs)}`}
                </p>
              )}
            </div>

            <div className="mt-6 flex flex-col gap-3">
              {!isExpired && (
                <button
                  type="button"
                  onClick={handleYaPague}
                  disabled={verifyPaymentMutation.isPending}
                  className="w-full rounded-xl bg-emerald-600 py-3 text-sm font-semibold text-white shadow-sm hover:bg-emerald-700 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-offset-2 disabled:opacity-60"
                >
                  {verifyPaymentMutation.isPending ? 'Verificando…' : 'Ya pagué'}
                </button>
              )}
              {isExpired && (
                <button
                  type="button"
                  onClick={handleRegenerarQr}
                  disabled={initPaymentMutation.isPending}
                  className="w-full rounded-xl border border-emerald-600 py-3 text-sm font-semibold text-emerald-700 hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-offset-2 disabled:opacity-60"
                >
                  Generar nuevo QR
                </button>
              )}
              <button
                type="button"
                onClick={handlePagoManual}
                disabled={initPaymentMutation.isPending || !pendingPayment}
                className="w-full rounded-xl border border-slate-300 py-3 text-sm font-medium text-slate-700 hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-slate-400 focus:ring-offset-2 disabled:opacity-50"
              >
                La API bancaria no responde / Pago manual
              </button>
            </div>
            <p className="mt-4 text-center text-xs text-slate-500">
              Si el pago por QR falla, solicita aprobación manual. Un administrador revisará tu pago.
            </p>
          </>
        ) : (
          <div className="py-8 text-center text-slate-500">
            No se pudo generar el QR. Intenta de nuevo o usa pago manual.
            <button
              type="button"
              onClick={handleRegenerarQr}
              className="mt-3 block w-full text-sm font-medium text-emerald-600 hover:underline"
            >
              Reintentar
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

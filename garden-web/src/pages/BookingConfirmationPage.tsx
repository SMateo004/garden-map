import { useParams, Link, useNavigate } from 'react-router-dom';
import { useBookingConfirm } from '@/hooks/useBookingConfirm';
import { usePublicCaregiverDetail } from '@/hooks/usePublicCaregiverDetail';
import { useClientMyProfile } from '@/hooks/useClientMyProfile';
import { useInitPayment } from '@/hooks/useInitPayment';
import { ZONE_LABELS } from '@/types/caregiver';
import { getImageUrl } from '@/utils/images';
import toast from 'react-hot-toast';

const TIME_SLOT_LABELS: Record<string, string> = {
  MANANA: 'Mañana',
  TARDE: 'Tarde',
  NOCHE: 'Noche',
};

const SERVICE_LABELS: Record<string, string> = {
  HOSPEDAJE: 'Hospedaje',
  PASEO: 'Paseo',
};

function formatDate(dateStr: string | null | undefined): string {
  if (!dateStr) return '—';
  const d = new Date(dateStr + 'Z');
  return d.toLocaleDateString('es-BO', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
}

function zoneLabel(zone: string | null | undefined): string {
  if (!zone) return '—';
  return (ZONE_LABELS as Record<string, string>)[zone] ?? zone;
}

export function BookingConfirmationPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { data: booking, isLoading: loadingBooking, error } = useBookingConfirm(id);
  const { data: caregiver, isLoading: loadingCaregiver } = usePublicCaregiverDetail(
    booking?.caregiverId,
    { enabled: !!booking?.caregiverId }
  );
  const { data: myProfile } = useClientMyProfile({ enabled: !!booking?.petId });
  const initPaymentMutation = useInitPayment();

  const pet = booking?.petId
    ? myProfile?.pets?.find((p) => p.id === booking.petId)
    : undefined;
  const petPhotoUrl = pet?.photoUrl ?? null;

  const handleConfirmAndPay = () => {
    if (!id) return;
    navigate(`/booking/${id}/payment`, { replace: true });
  };

  const handleEditDates = () => {
    if (booking?.caregiverId) {
      navigate(`/reservar/${booking.caregiverId}`, { replace: true });
    }
  };

  if (loadingBooking || (booking?.caregiverId && loadingCaregiver)) {
    return (
      <div className="flex min-h-[40vh] items-center justify-center px-4">
        <p className="text-slate-500" role="status">
          Cargando resumen de reserva…
        </p>
      </div>
    );
  }

  if (error || !booking) {
    return (
      <div className="mx-auto max-w-lg px-4 py-8">
        <div
          className="rounded-xl border border-red-200 bg-red-50/80 p-6 text-red-800"
          role="alert"
        >
          <p className="font-medium">
            {error instanceof Error ? error.message : 'Reserva no encontrada'}
          </p>
          <Link
            to="/bookings"
            className="mt-4 inline-block text-sm font-medium text-red-700 underline underline-offset-2 hover:no-underline"
          >
            Volver a mis reservas
          </Link>
        </div>
      </div>
    );
  }

  const isPaseo = booking.serviceType === 'PASEO';
  const pendingPayment =
    booking.status === 'PENDING_PAYMENT' || booking.status === 'PAYMENT_PENDING_APPROVAL';
  const hasQr = Boolean(
    (booking.qrId && booking.qrImageUrl && pendingPayment) ||
    (initPaymentMutation.data?.qrId && initPaymentMutation.data?.qrImageUrl)
  );

  return (
    <div className="mx-auto max-w-2xl px-4 py-8 sm:px-6 lg:px-8">
      <nav className="mb-6" aria-label="Navegación">
        <Link
          to="/bookings"
          className="text-sm font-medium text-emerald-700 hover:text-emerald-800 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-offset-2 rounded"
        >
          ← Mis reservas
        </Link>
      </nav>

      <h1 className="mb-2 text-2xl font-semibold text-slate-800">
        Confirmar reserva
      </h1>
      <p className="mb-8 text-slate-600">
        Revisa los datos antes de proceder al pago.
      </p>

      <article
        className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
        aria-labelledby="resumen-reserva"
      >
        <div className="border-b border-slate-100 bg-slate-50/60 px-6 py-4">
          <h2 id="resumen-reserva" className="text-lg font-semibold text-slate-800">
            Resumen de la reserva
          </h2>
        </div>

        <div className="space-y-6 p-6">
          {/* Cuidador */}
          <section aria-labelledby="cuidador-heading">
            <h3 id="cuidador-heading" className="mb-3 text-sm font-semibold uppercase tracking-wide text-slate-500">
              Cuidador
            </h3>
            <div className="flex items-center gap-4">
              <div className="h-16 w-16 shrink-0 overflow-hidden rounded-full bg-slate-200">
                <img
                  src={getImageUrl(caregiver?.profilePicture ?? caregiver?.photos?.[0])}
                  alt="Foto del cuidador"
                  loading="lazy"
                  className="h-full w-full object-cover"
                />
              </div>
              <div>
                <p className="font-medium text-slate-800">
                  {caregiver
                    ? `${caregiver.firstName} ${caregiver.lastName}`
                    : 'Cargando…'}
                </p>
                <p className="text-sm text-slate-600">
                  {caregiver ? zoneLabel(caregiver.zone) : '—'}
                </p>
              </div>
            </div>
          </section>

          {/* Servicio y fechas */}
          <section aria-labelledby="servicio-heading">
            <h3 id="servicio-heading" className="mb-3 text-sm font-semibold uppercase tracking-wide text-slate-500">
              Servicio y horario
            </h3>
            <p className="font-medium text-slate-800">
              {SERVICE_LABELS[booking.serviceType] ?? booking.serviceType}
            </p>
            {isPaseo ? (
              <p className="mt-1 text-slate-700">
                {formatDate(booking.walkDate ?? null)}
                {booking.timeSlot && (
                  <span className="ml-1 font-medium">
                    · {TIME_SLOT_LABELS[booking.timeSlot] ?? booking.timeSlot}
                    {booking.duration ? ` (${booking.duration} min)` : ''}
                  </span>
                )}
              </p>
            ) : (
              <p className="mt-1 text-slate-700">
                {formatDate(booking.startDate ?? null)} — {formatDate(booking.endDate ?? null)}
                {booking.totalDays != null && (
                  <span className="ml-1 text-slate-600">
                    ({booking.totalDays} {booking.totalDays === 1 ? 'día' : 'días'})
                  </span>
                )}
              </p>
            )}
          </section>

          {/* Mascota */}
          <section aria-labelledby="mascota-heading">
            <h3 id="mascota-heading" className="mb-3 text-sm font-semibold uppercase tracking-wide text-slate-500">
              Mascota
            </h3>
            <div className="flex items-center gap-4">
              <div className="h-14 w-14 shrink-0 overflow-hidden rounded-xl bg-slate-200">
                <img
                  src={getImageUrl(petPhotoUrl)}
                  alt="Foto de la mascota"
                  loading="lazy"
                  className="h-full w-full object-cover"
                />
              </div>
              <div>
                <p className="font-medium text-slate-800">{booking.petName}</p>
                <p className="text-sm text-slate-600">
                  {booking.petBreed ?? 'Sin raza indicada'}
                </p>
              </div>
            </div>
          </section>

          {/* Montos */}
          <section aria-labelledby="montos-heading">
            <h3 id="montos-heading" className="mb-3 text-sm font-semibold uppercase tracking-wide text-slate-500">
              Monto
            </h3>
            <div className="rounded-xl bg-slate-50 p-4">
              <div className="flex justify-between text-slate-700">
                <span>Total a pagar</span>
                <span className="font-semibold">
                  Bs {Number(booking.totalAmount).toFixed(2)}
                </span>
              </div>
              <div className="mt-1 flex justify-between text-sm text-slate-500">
                <span>Comisión plataforma (incl.)</span>
                <span>Bs {Number(booking.commissionAmount).toFixed(2)}</span>
              </div>
            </div>
          </section>

        </div>

        <div className="flex flex-col gap-3 border-t border-slate-100 bg-slate-50/40 px-6 py-5 sm:flex-row sm:justify-between">
          {pendingPayment ? (
            <>
              <button
                type="button"
                onClick={handleEditDates}
                className="order-2 rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-medium text-slate-700 shadow-sm hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-offset-2 sm:order-1"
              >
                Editar fechas / horario
              </button>
              {hasQr ? (
                <Link
                  to={`/booking/${id}/payment`}
                  className="order-1 rounded-xl bg-emerald-600 px-5 py-3 text-center text-sm font-semibold text-white shadow-sm hover:bg-emerald-700 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-offset-2 sm:order-2"
                >
                  Ir a pagar
                </Link>
              ) : (
                <button
                  type="button"
                  onClick={handleConfirmAndPay}
                  className="order-1 rounded-xl bg-emerald-600 px-5 py-3 text-sm font-semibold text-white shadow-sm hover:bg-emerald-700 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-offset-2 sm:order-2"
                >
                  Confirmar y pagar
                </button>
              )}
            </>
          ) : (
            <Link
              to={`/bookings/${booking.id}`}
              className="rounded-xl bg-emerald-600 px-5 py-3 text-center text-sm font-semibold text-white shadow-sm hover:bg-emerald-700 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-offset-2"
            >
              Ver reserva
            </Link>
          )}
        </div>
      </article>
    </div>
  );
}

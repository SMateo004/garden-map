import { useEffect, useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { getMyProfile, getCaregiverBookings, type MyProfileResponse, type CaregiverBookingItem } from '@/api/caregiverProfile';

function useProgress(profile: MyProfileResponse | null | undefined) {
  const onboarding = (profile?.onboardingStatus as any);
  const backendPercent = onboarding?.percentage;
  const isApproved = profile?.profileStatus === 'APPROVED' || profile?.status === 'APPROVED';

  const personalComplete = !!profile?.personalInfoComplete || isApproved;
  const caregiverComplete = !!profile?.caregiverProfileComplete || isApproved;
  const availabilityComplete = !!profile?.availabilityComplete || isApproved;
  const allComplete = personalComplete && caregiverComplete && availabilityComplete;

  const done = [personalComplete, caregiverComplete, availabilityComplete].filter(Boolean).length;
  const percent = isApproved ? 100 : (backendPercent ?? Math.round((done / 3) * 100));

  return { allComplete, percent, personalComplete, caregiverComplete, availabilityComplete, started: (onboarding?.completedCount ?? 0) > 0 || isApproved };
}

export function CaregiverDashboard() {
  const { user, isCaregiver, logout } = useAuth();
  const navigate = useNavigate();
  const [profile, setProfile] = useState<MyProfileResponse | null | undefined>(undefined);
  const [bookings, setBookings] = useState<CaregiverBookingItem[]>([]);
  const [showApprovalBanner, setShowApprovalBanner] = useState(false);

  const refetchProfile = () => {
    if (!isCaregiver) return;
    getMyProfile()
      .then(p => {
        setProfile(p);
        if (p?.profileStatus === 'APPROVED' && p?.approvedAt) {
          const approvedDate = new Date(p.approvedAt).getTime();
          const now = new Date().getTime();
          const diffMinutes = (now - approvedDate) / (1000 * 60);
          if (diffMinutes < 5) {
            setShowApprovalBanner(true);
            const remaining = (5 - diffMinutes) * 60 * 1000;
            setTimeout(() => setShowApprovalBanner(false), remaining);
          }
        }
      })
      .catch(() => setProfile(null));
  };

  const fetchBookings = () => {
    if (!isCaregiver) return;
    getCaregiverBookings().then(setBookings).catch(console.error);
  };

  useEffect(() => {
    refetchProfile();
    fetchBookings();
  }, [isCaregiver]);

  if (!isCaregiver || !user) {
    navigate('/caregiver/auth');
    return null;
  }

  const profileStatus = profile?.profileStatus ?? profile?.status ?? '';
  const isApproved = profileStatus === 'APPROVED' || profile?.status === 'APPROVED';
  const { allComplete, percent, started } = useProgress(profile);

  const confirmedBookings = bookings.filter(b => b.status === 'CONFIRMED' || b.status === 'IN_PROGRESS');
  const pendingBookings = bookings.filter(b => b.status === 'WAITING_CAREGIVER_APPROVAL' || b.status === 'PENDING_PAYMENT' || b.status === 'PAYMENT_PENDING_APPROVAL');

  const handleStartService = (id: string) => {
    navigate(`/caregiver/service/${id}`);
  };

  const handleAcceptBooking = async (id: string) => {
    try {
      const { acceptBooking } = await import('@/api/bookings');
      const res = await acceptBooking(id);
      if (res.success) {
        import('react-hot-toast').then(m => m.default.success('Reserva aceptada correctamente'));
        fetchBookings();
      } else {
        throw new Error(res.error?.message || 'Error al aceptar reserva');
      }
    } catch (err: any) {
      import('react-hot-toast').then(m => m.default.error(err.message));
    }
  };

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      <div className="mx-auto max-w-4xl px-4 py-6">

        <div className="mb-8 flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-2xl font-black text-gray-900 dark:text-white">
              Hola {user.firstName}, ¡qué gusto verte de nuevo! 🐾
            </h1>
            <p className="text-gray-500 dark:text-gray-400 mt-1 font-medium">
              Gestiona tus servicios y cuida a tus huéspedes con amor.
            </p>
          </div>
          <button
            onClick={() => navigate('/caregiver/calendar')}
            className="flex items-center gap-2 px-6 py-3 bg-white dark:bg-gray-800 border border-gray-100 dark:border-gray-700 rounded-2xl shadow-sm hover:shadow-md transition-all text-sm font-black text-gray-700 dark:text-white uppercase tracking-widest"
          >
            <span className="text-xl">📅</span>
            Mi Calendario
          </button>
        </div>

        {showApprovalBanner && (
          <div className="rounded-xl border border-green-200 dark:border-green-800 bg-green-50 dark:bg-green-900/20 p-5 mb-6 animate-in fade-in slide-in-from-top-4 duration-500 shadow-sm">
            <div className="flex items-center gap-3">
              <span className="text-xl">🎉</span>
              <p className="font-bold text-green-800 dark:text-green-200">¡Perfil aprobado! Ya eres parte oficial de la comunidad GARDEN.</p>
            </div>
          </div>
        )}

        {!isApproved && (
          <div className="space-y-6 mb-8">
            {!allComplete && !started && profileStatus === 'INCOMPLETE' && (
              <div className="rounded-2xl border border-green-100 dark:border-green-900/30 bg-green-50/50 dark:bg-green-900/10 p-6 flex items-center justify-between gap-4 shadow-sm">
                <div>
                  <h3 className="text-green-800 dark:text-green-300 font-bold text-lg">¡Bienvenido a GARDEN! 🌿</h3>
                  <p className="text-green-700 dark:text-green-400/80 text-sm mt-1">
                    Para comenzar a recibir reservas, primero debes completar tu perfil de cuidador.
                  </p>
                </div>
                <button
                  onClick={() => navigate('/caregiver/profile')}
                  className="shrink-0 px-6 py-2.5 bg-green-600 hover:bg-green-700 text-white rounded-xl font-bold shadow-lg shadow-green-200 dark:shadow-none transition-all hover:scale-105 active:scale-95"
                >
                  Completar perfil
                </button>
              </div>
            )}

            {!allComplete && started && profile && (
              <div className="rounded-2xl border border-gray-100 dark:border-gray-800 bg-white dark:bg-gray-900 p-5 shadow-sm">
                <div className="flex items-center justify-between mb-3">
                  <span className="text-sm font-bold text-gray-700 dark:text-gray-300">Progreso de tu perfil</span>
                  <span className="text-sm font-black text-green-600 dark:text-green-400">{percent}%</span>
                </div>
                <div className="h-3 bg-gray-100 dark:bg-gray-800 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-gradient-to-r from-green-400 to-green-600 transition-all duration-700 ease-out shadow-[0_0_10px_rgba(34,197,94,0.3)]"
                    style={{ width: `${percent}%` }}
                  />
                </div>
                <p className="text-xs text-gray-500 mt-3 italic">
                  Una vez llegues al 100%, tu perfil se enviará automáticamente a revisión.
                </p>
              </div>
            )}
          </div>
        )}

        {isApproved && (
          <div className="space-y-10">
            {/* Confirmed Bookings Section */}
            <div>
              <div className="flex items-center justify-between mb-4 border-b border-gray-200 dark:border-gray-700 pb-2">
                <h2 className="text-lg font-bold text-gray-900 dark:text-white flex items-center gap-2">
                  🟢 Reservas Confirmadas
                  <span className="bg-green-100 text-green-700 text-xs px-2 py-0.5 rounded-full">{confirmedBookings.length}</span>
                </h2>
                <button onClick={() => navigate('/caregiver/reservations')} className="text-xs text-green-600 hover:underline font-bold">Ver historial</button>
              </div>

              {confirmedBookings.length === 0 ? (
                <div className="bg-white dark:bg-gray-800 rounded-3xl p-12 text-center border border-dashed border-gray-300 dark:border-gray-700">
                  <span className="text-4xl block mb-4">🏠</span>
                  <p className="text-gray-500 dark:text-gray-400 font-medium">No tienes reservas confirmadas para hoy.</p>
                </div>
              ) : (
                <div className="grid gap-4">
                  {confirmedBookings.map(b => (
                    <BookingCard
                      key={b.id}
                      booking={b}
                      onStart={() => handleStartService(b.id)}
                    />
                  ))}
                </div>
              )}
            </div>

            {/* Pending Bookings Section */}
            <div>
              <div className="flex items-center justify-between mb-4 border-b border-gray-200 dark:border-gray-700 pb-2">
                <h2 className="text-lg font-bold text-gray-900 dark:text-white flex items-center gap-2">
                  ⏳ Por Confirmar
                  <span className="bg-amber-100 text-amber-700 text-xs px-2 py-0.5 rounded-full">{pendingBookings.length}</span>
                </h2>
              </div>

              {pendingBookings.length === 0 ? (
                <div className="bg-white dark:bg-gray-800 rounded-3xl p-12 text-center border border-dashed border-gray-300 dark:border-gray-700">
                  <span className="text-4xl block mb-4">🕒</span>
                  <p className="text-gray-500 dark:text-gray-400 font-medium">No tienes solicitudes pendientes por ahora.</p>
                </div>
              ) : (
                <div className="grid gap-4">
                  {pendingBookings.map(b => (
                    <BookingCard
                      key={b.id}
                      booking={b}
                      pending
                      onAccept={() => handleAcceptBooking(b.id)}
                    />
                  ))}
                </div>
              )}
            </div>
          </div>
        )}

        <div className="mt-12 flex justify-between items-center pt-8 border-t border-gray-100 dark:border-gray-800">
          <button
            type="button"
            onClick={() => { logout(); navigate('/'); }}
            className="text-xs font-bold text-gray-400 hover:text-red-500 transition-colors uppercase tracking-widest"
          >
            Cerrar sesión
          </button>
          <p className="text-[10px] text-gray-300 font-black uppercase tracking-tighter">GARDEN Caregiver OS v21.4</p>
        </div>
      </div>
    </div>
  );
}

function BookingCard({
  booking,
  pending,
  onStart,
  onAccept
}: {
  booking: CaregiverBookingItem;
  pending?: boolean;
  onStart?: () => void;
  onAccept?: () => void;
}) {
  const navigate = useNavigate();
  const isHospedaje = booking.serviceType === 'HOSPEDAJE';
  const statusColor = booking.status === 'IN_PROGRESS' ? 'bg-blue-100 text-blue-700' : 'bg-green-100 text-green-700';

  return (
    <div className="bg-white dark:bg-gray-800 rounded-3xl border border-gray-50 dark:border-gray-700 p-6 shadow-sm hover:shadow-xl hover:scale-[1.01] transition-all group">
      <div className="flex items-start justify-between">
        <div className="flex gap-5">
          <div className="w-14 h-14 bg-gradient-to-br from-green-50 to-green-100 dark:from-green-900/20 dark:to-green-900/40 rounded-2xl flex items-center justify-center text-3xl shadow-inner">
            {isHospedaje ? '🏠' : '🦮'}
          </div>
          <div>
            <h3 className="text-lg font-black text-gray-900 dark:text-white group-hover:text-green-600 transition-colors uppercase tracking-tight">{booking.petName}</h3>
            <p className="text-[11px] font-bold text-gray-400 uppercase tracking-widest">
              {isHospedaje ? 'Hospedaje' : 'Paseo'} • {isHospedaje ? `${booking.startDate} al ${booking.endDate}` : booking.walkDate}
            </p>
            {pending && (
              <div className="flex flex-col gap-1 mt-3">
                <span className="inline-block px-3 py-1 bg-amber-50 text-amber-700 text-[10px] font-black rounded-full border border-amber-100 uppercase tracking-tighter w-fit">
                  {booking.status === 'PAYMENT_PENDING_APPROVAL' ? 'Pago por Verificar' : 'Esperando Acción'}
                </span>
                {booking.status === 'PAYMENT_PENDING_APPROVAL' && (
                  <p className="text-[9px] font-bold text-amber-600/70 italic ml-1">Admin verificando el pago...</p>
                )}
              </div>
            )}
            {!pending && (
              <span className={`inline-block mt-3 px-3 py-1 ${statusColor} text-[10px] font-black rounded-full uppercase tracking-tighter`}>
                {booking.status === 'IN_PROGRESS' ? 'En Servicio' : 'Confirmada'}
              </span>
            )}
          </div>
        </div>
        <div className="text-right">
          <p className="text-xl font-black text-gray-900 dark:text-white">
            Bs {(Number(booking.totalAmount) - Number(booking.commissionAmount)).toFixed(2)}
          </p>
          <p className="text-[10px] font-bold text-gray-400 mt-1">TU PAGO NETO</p>
          <p className="text-[9px] font-bold text-gray-300 mt-1 uppercase tracking-tighter">REF: {booking.id.slice(0, 8)}</p>
        </div>
      </div>

      <div className="mt-8 pt-5 border-t border-gray-50 dark:border-gray-700 grid grid-cols-2 sm:flex sm:items-center gap-3">
        <Link
          to={`/caregiver/reservations/${booking.id}`}
          className="flex-1 sm:flex-none px-5 py-2.5 bg-gray-50 dark:bg-gray-700 hover:bg-gray-100 dark:hover:bg-gray-600 text-center text-gray-600 dark:text-gray-300 text-[11px] font-black rounded-xl transition-all uppercase tracking-widest"
        >
          Detalles
        </Link>

        {!pending && (
          <>
            <button
              onClick={() => navigate(`/caregiver/reservations/${booking.id}/cancel`)}
              className="flex-1 sm:flex-none px-5 py-2.5 bg-red-50 dark:bg-red-900/10 hover:bg-red-100 text-red-600 dark:text-red-400 text-[11px] font-black rounded-xl transition-all uppercase tracking-widest"
            >
              Cancelar
            </button>
            <button
              onClick={() => navigate('/caregiver/inbox')}
              className="flex-1 sm:flex-none px-5 py-2.5 bg-blue-50 dark:bg-blue-900/10 hover:bg-blue-100 text-blue-600 dark:text-blue-400 text-[11px] font-black rounded-xl transition-all uppercase tracking-widest"
            >
              Contactar
            </button>
            <button
              onClick={onStart}
              className="col-span-2 sm:col-span-1 sm:ml-auto px-8 py-2.5 bg-green-600 hover:bg-green-700 text-white text-[11px] font-black rounded-xl shadow-lg shadow-green-100 dark:shadow-none transition-all active:scale-95 uppercase tracking-widest"
            >
              {booking.status === 'IN_PROGRESS' ? 'Gestionar Seguimiento' : 'Iniciar Servicio'}
            </button>
          </>
        )}

        {pending && booking.status === 'WAITING_CAREGIVER_APPROVAL' && (
          <button
            onClick={onAccept}
            className="col-span-2 sm:col-span-1 sm:ml-auto px-8 py-2.5 bg-green-600 hover:bg-green-700 text-white text-[11px] font-black rounded-xl shadow-lg shadow-green-100 transition-all uppercase tracking-widest active:scale-95"
          >
            Aceptar Reserva
          </button>
        )}
      </div>
    </div>
  );
}

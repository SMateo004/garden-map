import { useState } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { usePublicCaregiverDetail } from '@/hooks/usePublicCaregiverDetail';
import { ProfileDetail } from '@/components/ProfileDetail';
import { LoginRequiredModal } from '@/components/LoginRequiredModal';
import { AuthPrompt } from '@/components/AuthPrompt';
import { useAuth } from '@/contexts/AuthContext';
import { useClientMyProfile } from '@/hooks/useClientMyProfile';
import toast from 'react-hot-toast';

/**
 * Página de detalle público de cuidador (vista cliente). Sin login requerido.
 * GET /api/caregivers/:id (público) y /api/caregivers/:id/availability.
 */
export function CaregiverDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { isAuthenticated, user } = useAuth();
  const { data: caregiver, isLoading, isError } = usePublicCaregiverDetail(id);
  const { data: myProfile, isLoading: loadingClientProfile } = useClientMyProfile({
    enabled: isAuthenticated && user?.role === 'CLIENT',
  });
  const [showLoginModal, setShowLoginModal] = useState(false);

  const isProfileComplete = myProfile?.isComplete === true;

  // Guard: no reservar si CLIENT y perfil de mascota incompleto
  const handleReserveClick = () => {
    if (!isAuthenticated) {
      setShowLoginModal(true);
      return;
    }

    if (user?.role === 'CLIENT') {
      if (!loadingClientProfile && !isProfileComplete) {
        toast.error('Completa el perfil de tu mascota para reservar');
        navigate('/profile', {
          state: { returnTo: `/caregivers/${id}` },
        });
        return;
      }
    }

    navigate(`/reservar/${id}`);
  };


  if (isLoading) {
    return (
      <div className="py-12 text-center text-gray-500">
        Cargando perfil...
      </div>
    );
  }

  if (isError || !caregiver) {
    return (
      <div className="rounded-lg bg-red-50 p-4 text-red-700">
        <p>No se encontró el perfil.</p>
        <Link to="/" className="mt-2 inline-block underline">
          Volver al listado
        </Link>
      </div>
    );
  }


  return (
    <div className="mx-auto max-w-5xl space-y-8 pb-12">
      <Link
        to="/"
        className="inline-flex items-center gap-2 text-sm font-semibold text-green-600 hover:text-green-700 transition-colors"
      >
        <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 19l-7-7m0 0l7-7m-7 7h18" />
        </svg>
        Volver al listado
      </Link>

      {/* ProfileDetail ahora contiene el nuevo diseño con fotos distribuidas, detalles y rating */}
      <ProfileDetail caregiver={caregiver} />

      {/* Botón Reservar o AuthPrompt: Ahora flotante o pegado al final con estilo premium */}
      <div className="border-t border-gray-100 pt-8 text-center sm:text-left">
        {!isAuthenticated ? (
          <AuthPrompt
            title="Para reservar debes iniciar sesión o registrarte como Dueño"
            subtitle="Necesitas una cuenta de cliente para realizar una reserva"
            returnTo={`/reservar/${id}`}
            onAuthSuccess={() => {
              // Después de login/registro exitoso, verificar perfil y redirigir
              if (id) {
                // El guard en BookingPage verificará el perfil automáticamente
                navigate(`/reservar/${id}`);
              }
            }}
          />
        ) : (
          <button
            onClick={handleReserveClick}
            disabled={isAuthenticated && user?.role === 'CLIENT' && loadingClientProfile}
            className="inline-block rounded-lg bg-green-600 px-6 py-3 font-medium text-white hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isAuthenticated && user?.role === 'CLIENT' && loadingClientProfile
              ? 'Cargando…'
              : 'Reservar ahora'}
          </button>
        )}
      </div>

      <LoginRequiredModal
        isOpen={showLoginModal}
        onClose={() => setShowLoginModal(false)}
        onSuccess={() => {
          // Después de login/registro exitoso, verificar perfil y redirigir
          if (id) {
            navigate(`/reservar/${id}`);
          }
        }}
        returnTo={`/reservar/${id}`}
      />
    </div>
  );
}

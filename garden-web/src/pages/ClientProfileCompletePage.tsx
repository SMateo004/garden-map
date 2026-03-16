import { Link } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';

/**
 * Página de bienvenida después del registro de cliente.
 * Redirige a la página principal o permite completar perfil (futuro).
 */
export function ClientProfileCompletePage() {
  const { user } = useAuth();

  return (
    <div className="mx-auto max-w-2xl px-4 py-12 text-center">
      <div className="rounded-2xl border border-gray-200 bg-white p-8 shadow-sm">
        <div className="mb-6">
          <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-green-100">
            <svg
              className="h-8 w-8 text-green-600"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M5 13l4 4L19 7"
              />
            </svg>
          </div>
          <h1 className="text-2xl font-bold text-gray-900">
            ¡Bienvenido a GARDEN, {user?.firstName}!
          </h1>
          <p className="mt-2 text-gray-600">
            Tu cuenta ha sido creada exitosamente. Ya puedes reservar servicios de cuidado para tu mascota.
          </p>
        </div>

        <div className="mt-8 space-y-4">
          <Link
            to="/"
            className="inline-block w-full rounded-lg bg-green-600 px-6 py-3 font-medium text-white hover:bg-green-700"
          >
            Explorar cuidadores
          </Link>
          <Link
            to="/bookings"
            className="inline-block w-full rounded-lg border-2 border-green-600 px-6 py-3 font-medium text-green-600 hover:bg-green-50"
          >
            Ver mis reservas
          </Link>
        </div>
      </div>
    </div>
  );
}

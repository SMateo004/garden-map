import { useState } from 'react';
import { LoginRequiredModal } from './LoginRequiredModal';

interface AuthPromptProps {
  /** Mensaje principal a mostrar */
  title?: string;
  /** Mensaje secundario opcional */
  subtitle?: string;
  /** Callback cuando el usuario completa login/registro exitosamente */
  onAuthSuccess?: () => void;
  /** URL a la que redirigir después de completar el perfil (si es necesario) */
  returnTo?: string;
  /** Tamaño del botón: 'large' para botones destacados, 'default' para tamaño normal */
  size?: 'large' | 'default';
}

/**
 * Componente que muestra un botón destacado para iniciar sesión o registrarse.
 * Ideal para páginas de reserva y detalle de cuidador cuando el usuario no está autenticado.
 */
export function AuthPrompt({ 
  title = 'Para reservar debes iniciar sesión o registrarte como Dueño',
  subtitle = 'Necesitas una cuenta de cliente para realizar una reserva',
  onAuthSuccess,
  returnTo,
  size = 'large',
}: AuthPromptProps) {
  const [showModal, setShowModal] = useState(false);

  const buttonClasses = size === 'large'
    ? 'w-full rounded-lg bg-green-600 px-8 py-4 text-lg font-semibold text-white hover:bg-green-700 transition-colors shadow-lg hover:shadow-xl'
    : 'rounded-lg bg-green-600 px-6 py-3 font-medium text-white hover:bg-green-700 transition-colors';

  return (
    <>
      <div className="mx-auto max-w-2xl rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
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
                d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
              />
            </svg>
          </div>
          <h2 className="text-2xl font-bold text-gray-900">{title}</h2>
          {subtitle && (
            <p className="mt-2 text-gray-600">{subtitle}</p>
          )}
        </div>
        
        <button
          onClick={() => setShowModal(true)}
          className={buttonClasses}
        >
          Iniciar sesión o Registrarme
        </button>
        
        <p className="mt-4 text-sm text-gray-500">
          Al registrarte, podrás reservar servicios de cuidado para tu mascota
        </p>
      </div>

      <LoginRequiredModal
        isOpen={showModal}
        onClose={() => setShowModal(false)}
        onSuccess={() => {
          onAuthSuccess?.();
          setShowModal(false);
        }}
        returnTo={returnTo}
      />
    </>
  );
}

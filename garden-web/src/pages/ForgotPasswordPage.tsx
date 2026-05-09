/**
 * /forgot-password
 * User enters their email → backend sends reset link → we show confirmation.
 * Works for both CAREGIVER and CLIENT roles.
 */
import { useState } from 'react';
import { Link } from 'react-router-dom';
import toast from 'react-hot-toast';
import { api } from '@/api/client';

type State = 'idle' | 'loading' | 'sent';

export function ForgotPasswordPage() {
  const [email, setEmail] = useState('');
  const [state, setState] = useState<State>('idle');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = email.trim().toLowerCase();
    if (!trimmed || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) {
      toast.error('Ingresa un correo electrónico válido');
      return;
    }
    setState('loading');
    try {
      await api.post('/api/auth/forgot-password', { email: trimmed });
      setState('sent');
    } catch (err: any) {
      // Rate-limit or server error — still show "sent" to prevent enumeration
      const code = err?.response?.data?.error?.code;
      if (code === 'TOO_MANY_REQUESTS') {
        toast.error('Demasiados intentos. Espera 15 minutos e inténtalo de nuevo.');
        setState('idle');
      } else {
        // On any other error still show "sent" (same as success)
        setState('sent');
      }
    }
  };

  return (
    <div className="min-h-[80vh] bg-green-50 dark:bg-gray-900 py-8 px-4 flex items-center justify-center">
      <div className="w-full max-w-md">
        <div className="rounded-3xl border border-gray-100 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-xl overflow-hidden">
          {/* Header */}
          <div className="p-8 text-center bg-green-600">
            <img src="/logo-white.png" alt="Garden" className="h-10 w-auto mx-auto" />
            <p className="text-green-100 mt-2">Recuperar contraseña</p>
          </div>

          <div className="p-8">
            {state === 'sent' ? (
              /* ── Sent confirmation ── */
              <div className="text-center space-y-4">
                <div className="w-16 h-16 mx-auto bg-green-100 dark:bg-green-900/30 rounded-full flex items-center justify-center text-3xl">
                  📧
                </div>
                <h2 className="text-xl font-semibold text-gray-900 dark:text-white">
                  Revisa tu correo
                </h2>
                <p className="text-sm text-gray-500 dark:text-gray-400 leading-relaxed">
                  Si el correo{' '}
                  <span className="font-semibold text-gray-700 dark:text-gray-200">{email}</span>{' '}
                  está registrado, recibirás un enlace para restablecer tu contraseña en los próximos minutos.
                </p>
                <p className="text-xs text-gray-400 dark:text-gray-500">
                  ¿No lo recibiste? Revisa tu carpeta de spam o espera unos minutos antes de intentar de nuevo.
                </p>
                <div className="pt-2 space-y-2">
                  <button
                    type="button"
                    onClick={() => { setState('idle'); setEmail(''); }}
                    className="w-full py-3 rounded-2xl border border-gray-200 dark:border-gray-600 text-sm font-medium text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors"
                  >
                    Intentar con otro correo
                  </button>
                  <Link
                    to="/caregiver/auth"
                    className="block w-full py-3 rounded-2xl bg-green-600 hover:bg-green-700 text-white font-bold text-sm text-center transition-colors"
                  >
                    Volver al inicio de sesión
                  </Link>
                </div>
              </div>
            ) : (
              /* ── Email form ── */
              <>
                <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-2">
                  ¿Olvidaste tu contraseña?
                </h2>
                <p className="text-sm text-gray-500 dark:text-gray-400 mb-6">
                  Ingresa tu correo registrado y te enviaremos un enlace para crear una nueva contraseña.
                </p>

                <form onSubmit={handleSubmit} className="space-y-5">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                      Correo electrónico
                    </label>
                    <input
                      type="email"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      placeholder="tucorreo@email.com"
                      required
                      autoFocus
                      className="block w-full rounded-2xl border border-gray-200 dark:border-gray-600 bg-gray-50 dark:bg-gray-700 text-gray-900 dark:text-white px-5 py-3.5 focus:ring-2 focus:ring-green-500 focus:bg-white dark:focus:bg-gray-600 transition-all outline-none"
                    />
                  </div>

                  <button
                    type="submit"
                    disabled={state === 'loading'}
                    className="w-full rounded-2xl bg-green-600 hover:bg-green-700 disabled:opacity-50 text-white font-bold py-4 px-6 shadow-lg shadow-green-200 dark:shadow-none transition-all hover:-translate-y-0.5"
                  >
                    {state === 'loading' ? 'Enviando…' : 'Enviar enlace de recuperación'}
                  </button>

                  <div className="text-center">
                    <Link
                      to="/caregiver/auth"
                      className="text-sm text-gray-500 dark:text-gray-400 hover:text-green-600 dark:hover:text-green-400 transition-colors"
                    >
                      ← Volver al inicio de sesión
                    </Link>
                  </div>
                </form>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

/**
 * /reset-password?token=<raw>
 * Validates the token on mount, shows the new-password form, then redirects to login.
 *
 * Human-error cases handled:
 *  - Expired token → clear error + "request new link" button
 *  - Already-used token → same
 *  - Invalid/tampered token → same
 *  - Passwords don't match → inline validation
 *  - Password too short → inline validation
 *  - Same password as current → server-side error displayed
 *  - No token in URL → redirect to /forgot-password
 */
import { useState, useEffect } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import toast from 'react-hot-toast';
import { api } from '@/api/client';

type TokenState = 'validating' | 'valid' | 'invalid' | 'expired' | 'used';
type SubmitState = 'idle' | 'loading' | 'success';

const MIN_LENGTH = 8;

export function ResetPasswordPage() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const token = searchParams.get('token') ?? '';

  const [tokenState, setTokenState] = useState<TokenState>('validating');
  const [tokenEmail, setTokenEmail] = useState('');
  const [tokenError, setTokenError] = useState('');

  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [submitState, setSubmitState] = useState<SubmitState>('idle');

  // ── Validate token on mount ────────────────────────────────────────────────
  useEffect(() => {
    if (!token) {
      navigate('/forgot-password', { replace: true });
      return;
    }
    (async () => {
      try {
        const res = await api.get<{ success: boolean; data: { email: string } }>(
          `/api/auth/validate-reset-token?token=${encodeURIComponent(token)}`
        );
        setTokenEmail(res.data.data.email);
        setTokenState('valid');
      } catch (err: any) {
        const code = err?.response?.data?.error?.code;
        if (code === 'RESET_TOKEN_EXPIRED') {
          setTokenState('expired');
          setTokenError('Este enlace ha expirado. Solicita uno nuevo.');
        } else if (code === 'TOKEN_ALREADY_USED') {
          setTokenState('used');
          setTokenError('Este enlace ya fue utilizado. Si necesitas restablecer de nuevo, solicita otro.');
        } else {
          setTokenState('invalid');
          setTokenError('El enlace no es válido o ya no está disponible.');
        }
      }
    })();
  }, [token, navigate]);

  // ── Inline validation ──────────────────────────────────────────────────────
  const passwordMismatch = confirm.length > 0 && password !== confirm;
  const passwordTooShort = password.length > 0 && password.length < MIN_LENGTH;

  const canSubmit =
    password.length >= MIN_LENGTH &&
    password === confirm &&
    submitState === 'idle';

  // ── Submit ─────────────────────────────────────────────────────────────────
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!canSubmit) return;

    setSubmitState('loading');
    try {
      await api.post('/api/auth/reset-password', { token, password, confirmPassword: confirm });
      setSubmitState('success');
      toast.success('¡Contraseña restablecida correctamente!');
    } catch (err: any) {
      const code = err?.response?.data?.error?.code;
      const msg = err?.response?.data?.error?.message;
      if (code === 'RESET_TOKEN_EXPIRED') {
        setTokenState('expired');
        setTokenError('El enlace expiró mientras rellenabas el formulario. Solicita uno nuevo.');
      } else if (code === 'TOKEN_ALREADY_USED') {
        setTokenState('used');
        setTokenError('Este enlace ya fue utilizado.');
      } else if (code === 'SAME_PASSWORD') {
        toast.error('La nueva contraseña no puede ser igual a la actual.');
      } else {
        toast.error(msg ?? 'Error al restablecer la contraseña. Intenta de nuevo.');
      }
      setSubmitState('idle');
    }
  };

  // ── Render: validating ─────────────────────────────────────────────────────
  if (tokenState === 'validating') {
    return (
      <div className="min-h-[80vh] flex items-center justify-center">
        <div className="text-center space-y-3">
          <div className="animate-spin h-8 w-8 border-4 border-green-500 border-t-transparent rounded-full mx-auto" />
          <p className="text-sm text-gray-500 dark:text-gray-400">Verificando enlace…</p>
        </div>
      </div>
    );
  }

  // ── Render: invalid / expired / used ──────────────────────────────────────
  if (tokenState !== 'valid') {
    return (
      <div className="min-h-[80vh] bg-red-50 dark:bg-gray-900 py-8 px-4 flex items-center justify-center">
        <div className="w-full max-w-md">
          <div className="rounded-3xl border border-red-100 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-xl overflow-hidden">
            <div className="p-8 text-center bg-red-600">
              <img src="/logo-white.png" alt="Garden" className="h-10 w-auto mx-auto" />
              <p className="text-red-100 mt-1">Recuperar contraseña</p>
            </div>
            <div className="p-8 text-center space-y-4">
              <div className="text-4xl">🔗</div>
              <h2 className="text-xl font-semibold text-gray-900 dark:text-white">
                Enlace no disponible
              </h2>
              <p className="text-sm text-gray-500 dark:text-gray-400">{tokenError}</p>
              <Link
                to="/forgot-password"
                className="block w-full py-4 rounded-2xl bg-green-600 hover:bg-green-700 text-white font-bold text-center transition-colors"
              >
                Solicitar nuevo enlace
              </Link>
              <Link
                to="/caregiver/auth"
                className="block text-sm text-gray-400 hover:text-green-600 transition-colors"
              >
                ← Volver al inicio de sesión
              </Link>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // ── Render: success ────────────────────────────────────────────────────────
  if (submitState === 'success') {
    return (
      <div className="min-h-[80vh] bg-green-50 dark:bg-gray-900 py-8 px-4 flex items-center justify-center">
        <div className="w-full max-w-md">
          <div className="rounded-3xl border border-gray-100 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-xl overflow-hidden">
            <div className="p-8 text-center bg-green-600">
              <img src="/logo-white.png" alt="Garden" className="h-10 w-auto mx-auto" />
              <p className="text-green-100 mt-1">Contraseña restablecida</p>
            </div>
            <div className="p-8 text-center space-y-4">
              <div className="text-4xl">✅</div>
              <h2 className="text-xl font-semibold text-gray-900 dark:text-white">
                ¡Listo!
              </h2>
              <p className="text-sm text-gray-500 dark:text-gray-400">
                Tu contraseña fue restablecida correctamente. Ahora puedes iniciar sesión con tu nueva contraseña.
              </p>
              <p className="text-xs text-amber-600 dark:text-amber-400 bg-amber-50 dark:bg-amber-900/20 rounded-xl px-4 py-2">
                Por seguridad, todas tus sesiones activas fueron cerradas.
              </p>
              <Link
                to="/caregiver/auth"
                className="block w-full py-4 rounded-2xl bg-green-600 hover:bg-green-700 text-white font-bold text-center transition-colors"
              >
                Iniciar sesión
              </Link>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // ── Render: password form ──────────────────────────────────────────────────
  return (
    <div className="min-h-[80vh] bg-green-50 dark:bg-gray-900 py-8 px-4 flex items-center justify-center">
      <div className="w-full max-w-md">
        <div className="rounded-3xl border border-gray-100 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-xl overflow-hidden">
          <div className="p-8 text-center bg-green-600">
            <img src="/logo-white.png" alt="Garden" className="h-10 w-auto mx-auto" />
            <p className="text-green-100 mt-2">Nueva contraseña</p>
          </div>

          <div className="p-8">
            <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-1">
              Crea tu nueva contraseña
            </h2>
            <p className="text-sm text-gray-500 dark:text-gray-400 mb-6">
              Para la cuenta{' '}
              <span className="font-semibold text-gray-700 dark:text-gray-200">{tokenEmail}</span>
            </p>

            <form onSubmit={handleSubmit} className="space-y-5">
              {/* New password */}
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Nueva contraseña
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="Mínimo 8 caracteres"
                    required
                    autoFocus
                    autoComplete="new-password"
                    className={`block w-full rounded-2xl border pr-12 bg-gray-50 dark:bg-gray-700 text-gray-900 dark:text-white px-5 py-3.5 focus:ring-2 focus:ring-green-500 focus:bg-white dark:focus:bg-gray-600 transition-all outline-none ${
                      passwordTooShort
                        ? 'border-red-400 dark:border-red-500'
                        : 'border-gray-200 dark:border-gray-600'
                    }`}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200"
                    tabIndex={-1}
                  >
                    {showPassword ? '🙈' : '👁️'}
                  </button>
                </div>
                {passwordTooShort && (
                  <p className="text-xs text-red-500 mt-1">Mínimo {MIN_LENGTH} caracteres</p>
                )}

                {/* Strength indicators */}
                {password.length > 0 && (
                  <div className="mt-2 flex gap-1">
                    {[
                      password.length >= 8,
                      /[A-Z]/.test(password),
                      /[0-9]/.test(password),
                      /[^A-Za-z0-9]/.test(password),
                    ].map((met, i) => (
                      <div
                        key={i}
                        className={`h-1 flex-1 rounded-full transition-colors ${met ? 'bg-green-500' : 'bg-gray-200 dark:bg-gray-600'}`}
                      />
                    ))}
                  </div>
                )}
                {password.length > 0 && (
                  <p className="text-xs text-gray-400 mt-1">
                    Recomendado: mayúscula, número y símbolo
                  </p>
                )}
              </div>

              {/* Confirm password */}
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Confirmar contraseña
                </label>
                <input
                  type={showPassword ? 'text' : 'password'}
                  value={confirm}
                  onChange={(e) => setConfirm(e.target.value)}
                  placeholder="Repite la contraseña"
                  required
                  autoComplete="new-password"
                  className={`block w-full rounded-2xl border bg-gray-50 dark:bg-gray-700 text-gray-900 dark:text-white px-5 py-3.5 focus:ring-2 focus:ring-green-500 focus:bg-white dark:focus:bg-gray-600 transition-all outline-none ${
                    passwordMismatch
                      ? 'border-red-400 dark:border-red-500'
                      : password.length >= MIN_LENGTH && confirm === password
                      ? 'border-green-400 dark:border-green-500'
                      : 'border-gray-200 dark:border-gray-600'
                  }`}
                />
                {passwordMismatch && (
                  <p className="text-xs text-red-500 mt-1">Las contraseñas no coinciden</p>
                )}
                {password.length >= MIN_LENGTH && confirm === password && (
                  <p className="text-xs text-green-500 mt-1">✓ Las contraseñas coinciden</p>
                )}
              </div>

              <button
                type="submit"
                disabled={!canSubmit}
                className="w-full rounded-2xl bg-green-600 hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed text-white font-bold py-4 px-6 shadow-lg shadow-green-200 dark:shadow-none transition-all hover:-translate-y-0.5"
              >
                {submitState === 'loading' ? 'Guardando…' : 'Guardar nueva contraseña'}
              </button>

              <div className="text-center">
                <Link
                  to="/caregiver/auth"
                  className="text-sm text-gray-400 hover:text-green-600 dark:hover:text-green-400 transition-colors"
                >
                  ← Cancelar e ir al inicio de sesión
                </Link>
              </div>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}

import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { useAuth } from '@/contexts/AuthContext';
import * as authApi from '@/api/auth';

export function CaregiverAuthPage() {
  const navigate = useNavigate();
  const { login, isCaregiver } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isCheckingEmail, setIsCheckingEmail] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleContinue = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email || !email.includes('@')) {
      toast.error('Ingresa un email válido');
      return;
    }

    setIsCheckingEmail(true);
    try {
      const exists = await authApi.checkEmailExists(email);
      if (exists) {
        setShowPassword(true);
      } else {
        toast.success('¡Bienvenido! Completa tu registro.');
        navigate('/caregiver/register', { state: { email } });
      }
    } catch (e) {
      toast.error('Error al verificar email');
    } finally {
      setIsCheckingEmail(false);
    }
  };

  const onLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);
    try {
      await login(email, password, true);
      toast.success('Sesión iniciada');
      navigate('/caregiver/dashboard');
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'Email o contraseña incorrectos';
      toast.error(msg);
    } finally {
      setIsSubmitting(false);
    }
  };

  if (isCaregiver) {
    navigate('/caregiver/dashboard');
    return null;
  }

  return (
    <div className="min-h-[80vh] bg-green-50 dark:bg-gray-900 py-8 px-4 sm:px-6 flex items-center justify-center">
      <div className="w-full max-w-md">
        <div className="rounded-3xl border border-gray-100 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-xl overflow-hidden">
          <div className="p-8 text-center bg-green-600">
            <h1 className="text-2xl font-bold text-white">GARDEN</h1>
            <p className="text-green-100 mt-1">Cuidadores de confianza</p>
          </div>

          <div className="p-8">
            <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-6">
              {showPassword ? 'Ingresa tu contraseña' : 'Sé un cuidador GARDEN'}
            </h2>

            {!showPassword ? (
              <form onSubmit={handleContinue} className="space-y-5">
                <div>
                  <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Correo electrónico
                  </label>
                  <input
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="block w-full rounded-2xl border border-gray-200 dark:border-gray-600 bg-gray-50 dark:bg-gray-700 text-gray-900 dark:text-white px-5 py-3.5 focus:ring-2 focus:ring-green-500 focus:bg-white dark:focus:bg-gray-600 transition-all outline-none"
                    placeholder="tucorreo@email.com"
                    required
                  />
                </div>
                <button
                  type="submit"
                  disabled={isCheckingEmail}
                  className="w-full rounded-2xl bg-green-600 hover:bg-green-700 disabled:opacity-50 text-white font-bold py-4 px-6 shadow-lg shadow-green-200 dark:shadow-none transition-all hover:-translate-y-0.5"
                >
                  {isCheckingEmail ? 'Verificando...' : 'Continuar →'}
                </button>
                <div className="relative py-4">
                  <div className="absolute inset-0 flex items-center"><div className="w-full border-t border-gray-100 dark:border-gray-600"></div></div>
                  <div className="relative flex justify-center text-xs uppercase"><span className="bg-white dark:bg-gray-800 px-2 text-gray-400">¿Nuevo en Garden?</span></div>
                </div>
                <p className="text-sm text-gray-500 text-center">
                  Si no tienes cuenta, te llevaremos al registro.
                </p>
              </form>
            ) : (
              <form onSubmit={onLogin} className="space-y-5">
                <div className="flex items-center gap-3 p-3 bg-gray-50 dark:bg-gray-700 rounded-2xl mb-4 border border-gray-100 dark:border-gray-600">
                  <div className="w-10 h-10 rounded-full bg-green-100 dark:bg-green-900 flex items-center justify-center text-green-600 dark:text-green-400 font-bold">
                    {email.charAt(0).toUpperCase()}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-gray-900 dark:text-white truncate">{email}</p>
                    <button type="button" onClick={() => setShowPassword(false)} className="text-xs text-green-600 dark:text-green-400 hover:underline">Cambiar correo</button>
                  </div>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Contraseña
                  </label>
                  <input
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className="block w-full rounded-2xl border border-gray-200 dark:border-gray-600 bg-gray-50 dark:bg-gray-700 text-gray-900 dark:text-white px-5 py-3.5 focus:ring-2 focus:ring-green-500 focus:bg-white dark:focus:bg-gray-600 transition-all outline-none"
                    placeholder="••••••••"
                    required
                    autoFocus
                  />
                </div>
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="w-full rounded-2xl bg-green-600 hover:bg-green-700 disabled:opacity-50 text-white font-bold py-4 px-6 shadow-lg shadow-green-200 dark:shadow-none transition-all hover:-translate-y-0.5"
                >
                  {isSubmitting ? 'Iniciando sesión...' : 'Entrar'}
                </button>
              </form>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import toast from 'react-hot-toast';
import { useAuth } from '@/contexts/AuthContext';

const loginSchema = z.object({
  email: z.string().email('Email inválido'),
  password: z.string().min(1, 'Contraseña requerida'),
});

type LoginFormValues = z.infer<typeof loginSchema>;

export function AdminAuthPage() {
  const navigate = useNavigate();
  const { login, isAdmin } = useAuth();
  const [isSubmitting, setIsSubmitting] = useState(false);

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: '', password: '' },
  });

  const onLogin = handleSubmit(async (data) => {
    setIsSubmitting(true);
    try {
      const user = await login(data.email, data.password, false);
      if (user?.role === 'ADMIN') {
        toast.success('Sesión de admin iniciada');
        navigate('/admin/caregivers');
      } else {
        toast.error('Esta cuenta no es de administrador');
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'Email o contraseña incorrectos';
      toast.error(msg);
    } finally {
      setIsSubmitting(false);
    }
  });

  if (isAdmin) {
    navigate('/admin/caregivers');
    return null;
  }

  return (
    <div className="min-h-[80vh] bg-gray-50 dark:bg-gray-900 py-8 px-4 sm:px-6">
      <div className="mx-auto max-w-md">
        <div className="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm overflow-hidden">
          <div className="p-6 text-center border-b border-gray-200 dark:border-gray-700">
            <h1 className="text-xl font-semibold text-gray-900 dark:text-white">
              Acceso administrador
            </h1>
            <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
              Inicia sesión con una cuenta de administrador
            </p>
          </div>
          <div className="p-6">
            <form onSubmit={onLogin} className="space-y-4">
              <div>
                <label htmlFor="admin-email" className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Email
                </label>
                <input
                  id="admin-email"
                  type="email"
                  autoComplete="email"
                  className="block w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white text-base sm:text-sm px-4 py-2.5 focus:ring-2 focus:ring-green-500 focus:border-green-500"
                  placeholder="admin@garden.bo"
                  {...register('email')}
                />
                {errors.email && (
                  <p className="mt-1 text-sm text-red-600 dark:text-red-400" role="alert">{errors.email.message}</p>
                )}
              </div>
              <div>
                <label htmlFor="admin-password" className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Contraseña
                </label>
                <input
                  id="admin-password"
                  type="password"
                  autoComplete="current-password"
                  className="block w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white text-base sm:text-sm px-4 py-2.5 focus:ring-2 focus:ring-green-500 focus:border-green-500"
                  {...register('password')}
                />
                {errors.password && (
                  <p className="mt-1 text-sm text-red-600 dark:text-red-400" role="alert">{errors.password.message}</p>
                )}
              </div>
              <button
                type="submit"
                disabled={isSubmitting}
                className="w-full rounded-xl bg-green-600 hover:bg-green-700 disabled:opacity-50 text-white font-semibold py-2.5 px-4 transition-colors"
              >
                {isSubmitting ? 'Entrando…' : 'Iniciar sesión'}
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}

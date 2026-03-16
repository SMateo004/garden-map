import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useAuth } from '@/contexts/AuthContext';
import { registerClient, checkEmailExists } from '@/api/auth';
import type { RegisterClientPayload } from '@/api/auth';
import toast from 'react-hot-toast';

const emailSchema = z.object({
  email: z.string().email('Email inválido'),
});

const loginSchema = z.object({
  email: z.string().email('Email inválido'),
  password: z.string().min(1, 'Contraseña requerida'),
});

/** Teléfono: 8 dígitos, empieza con 6 o 7 (sin +591) */
const phoneClientSchema = z
  .string()
  .min(1, 'Teléfono requerido')
  .transform((s) => s.replace(/\D/g, '').replace(/^591/, ''))
  .refine((s) => /^[67][0-9]{7}$/.test(s), '8 dígitos, debe empezar con 6 o 7');

const registerSchema = z.object({
  fullName: z.string().min(2, 'Nombre completo requerido').max(200, 'Máximo 200 caracteres'),
  email: z.string().email('Email inválido'),
  password: z.string()
    .min(8, 'Mínimo 8 caracteres')
    .regex(/[A-Z]/, 'Debe contener al menos una mayúscula')
    .regex(/[a-z]/, 'Debe contener al menos una minúscula')
    .regex(/[0-9]/, 'Debe contener al menos un número'),
  confirmPassword: z.string(),
  phone: phoneClientSchema,
  address: z.string().max(500, 'Máximo 500 caracteres').optional().or(z.literal('')),
}).refine((data) => data.password === data.confirmPassword, {
  message: 'Las contraseñas no coinciden',
  path: ['confirmPassword'],
});

type EmailFormValues = z.infer<typeof emailSchema>;
type LoginFormValues = z.infer<typeof loginSchema>;
type RegisterFormValues = z.infer<typeof registerSchema>;

interface LoginRequiredModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: () => void;
  /** URL a la que redirigir después de completar el perfil (si es necesario) */
  returnTo?: string;
}

export function LoginRequiredModal({ isOpen, onClose, onSuccess, returnTo }: LoginRequiredModalProps) {
  const navigate = useNavigate();
  const { login: authLogin, refreshUser } = useAuth();
  const [mode, setMode] = useState<'email' | 'login' | 'register'>('email');
  const [emailForLogin, setEmailForLogin] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isCheckingEmail, setIsCheckingEmail] = useState(false);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});

  const {
    register: registerEmail,
    handleSubmit: handleEmailSubmit,
    formState: { errors: emailErrors },
    reset: resetEmail,
  } = useForm<EmailFormValues>({
    resolver: zodResolver(emailSchema),
    defaultValues: { email: '' },
  });

  const {
    register: registerLogin,
    handleSubmit: handleLoginSubmit,
    formState: { errors: loginErrors },
    reset: resetLogin,
    setValue: setLoginValue,
  } = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: '', password: '' },
  });

  const {
    register: registerRegister,
    handleSubmit: handleRegisterSubmit,
    formState: { errors: registerErrors },
    reset: resetRegister,
    setValue: setRegisterValue,
    getValues: getRegisterValues,
  } = useForm<RegisterFormValues>({
    resolver: zodResolver(registerSchema),
    defaultValues: {
      fullName: '',
      email: '',
      password: '',
      confirmPassword: '',
      phone: '',
      address: '',
    },
  });

  const onEmailStep = handleEmailSubmit(async (data) => {
    setIsCheckingEmail(true);
    setFieldErrors({});
    try {
      const exists = await checkEmailExists(data.email);
      if (exists) {
        setEmailForLogin(data.email);
        setLoginValue('email', data.email);
        setMode('login');
      } else {
        setRegisterValue('email', data.email);
        setMode('register');
      }
    } catch {
      toast.error('Error al verificar email. Intenta de nuevo.');
    } finally {
      setIsCheckingEmail(false);
    }
  });

  const onLogin = handleLoginSubmit(async (data: LoginFormValues) => {
    setIsSubmitting(true);
    try {
      const user = await authLogin(data.email, data.password, false);
      toast.success('Sesión iniciada');
      resetLogin();
      onSuccess?.();
      onClose();
      // Redirigir según rol después de un breve delay (para que se vea el toast)
      setTimeout(() => {
        if (user?.role === 'ADMIN') {
          navigate('/admin/caregivers');
        } else if (user?.role === 'CAREGIVER') {
          navigate('/caregiver/dashboard');
        } else if (user?.role === 'CLIENT') {
          if (user.clientProfile?.isComplete !== true) {
            navigate('/profile/complete-pet', {
              state: { returnTo: returnTo || '/', message: 'Completa el perfil de tu mascota para poder reservar' },
            });
          } else {
            navigate(returnTo || '/');
          }
        } else {
          navigate(returnTo || '/');
        }
      }, 400);
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'Email o contraseña incorrectos';
      toast.error(msg);
    } finally {
      setIsSubmitting(false);
    }
  });

  const onRegister = handleRegisterSubmit(async (data) => {
    setIsSubmitting(true);
    setFieldErrors({});
    try {
      const payload: RegisterClientPayload = {
        fullName: data.fullName,
        email: data.email,
        password: data.password,
        phone: data.phone,
        address: data.address || undefined,
      };
      await registerClient(payload);
      toast.success('Registro exitoso. Bienvenido a GARDEN.');
      resetRegister();
      onSuccess?.();
      onClose();
      await refreshUser();
      navigate('/profile/complete-pet', {
        state: {
          message: 'Completa el perfil de tu mascota para poder reservar servicios',
          returnTo: returnTo || '/',
        },
      });
    } catch (e: any) {
      if (e?.statusCode === 400 && Array.isArray(e?.errors)) {
        const errorsByField: Record<string, string> = {};
        e.errors.forEach((err: { field: string; message: string }) => {
          errorsByField[err.field] = err.message;
        });
        setFieldErrors(errorsByField);
        toast.error('Datos inválidos. Revisa los campos marcados.');
      } else if (e?.statusCode === 409 || e?.response?.status === 409) {
        const field = e?.field || e?.response?.data?.error?.field;
        const code = e?.code || e?.response?.data?.error?.code;
        if (field === 'email' || code === 'EMAIL_EXISTS') {
          setFieldErrors({ email: 'Este correo ya está en uso' });
          toast.error('Este correo electrónico ya está registrado');
        } else if (field === 'phone' || code === 'PHONE_EXISTS') {
          setFieldErrors({ phone: 'Este número ya está registrado' });
          toast.error('Este número de teléfono ya está registrado');
        } else {
          toast.error(e?.message || 'Ya existe una cuenta con estos datos');
        }
      } else if (e?.response?.status === 500 || e?.statusCode === 500) {
        const backendMessage =
          e?.response?.data?.message ??
          e?.response?.data?.error?.message ??
          (e instanceof Error ? e.message : null);
        toast.error(backendMessage || 'Error al registrar. Intenta más tarde.');
      } else {
        const msg = e?.response?.data?.error?.message ?? (e instanceof Error ? e.message : 'Error al registrarse');
        toast.error(msg);
      }
    } finally {
      setIsSubmitting(false);
    }
  });

  const handleBackToEmail = () => {
    setMode('email');
    setFieldErrors({});
    resetLogin();
    resetRegister();
    resetEmail();
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={onClose}>
      <div
        className="w-full max-w-md rounded-2xl bg-white shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="border-b border-gray-200 p-6">
          <h2 className="text-xl font-bold text-gray-900">
            {mode === 'email' && 'Iniciar sesión / Registrarme'}
            {mode === 'login' && 'Iniciar sesión'}
            {mode === 'register' && 'Registrarme como Dueño de mascota'}
          </h2>
          <p className="mt-1 text-sm text-gray-600">
            {mode === 'email' && 'Ingresa tu email para continuar'}
            {mode === 'login' && 'Ingresa tu contraseña'}
            {mode === 'register' && 'Crea tu cuenta para reservar servicios de cuidado de mascotas'}
          </p>
        </div>

        <div className="p-6">
          {mode === 'email' ? (
            <form onSubmit={onEmailStep} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700">Email</label>
                <input
                  type="email"
                  {...registerEmail('email')}
                  className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
                  placeholder="tu@email.com"
                />
                {emailErrors.email && (
                  <p className="mt-1 text-xs text-red-600">{emailErrors.email.message}</p>
                )}
              </div>
              <button
                type="submit"
                disabled={isCheckingEmail}
                className="w-full rounded-lg bg-green-600 px-4 py-2 font-medium text-white hover:bg-green-700 disabled:opacity-50"
              >
                {isCheckingEmail ? 'Verificando…' : 'Continuar'}
              </button>
            </form>
          ) : mode === 'login' ? (
            <form onSubmit={onLogin} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700">Email</label>
                <input
                  type="email"
                  {...registerLogin('email')}
                  readOnly
                  className="mt-1 w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-sm text-gray-700"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700">Contraseña</label>
                <input
                  type="password"
                  {...registerLogin('password')}
                  className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
                />
                {loginErrors.password && (
                  <p className="mt-1 text-xs text-red-600">{loginErrors.password.message}</p>
                )}
              </div>
              <button
                type="submit"
                disabled={isSubmitting}
                className="w-full rounded-lg bg-green-600 px-4 py-2 font-medium text-white hover:bg-green-700 disabled:opacity-50"
              >
                {isSubmitting ? 'Iniciando sesión...' : 'Iniciar sesión'}
              </button>
            </form>
          ) : (
            <form onSubmit={onRegister} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700">Nombre completo</label>
                <input
                  type="text"
                  {...registerRegister('fullName')}
                  className={`mt-1 w-full rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-1 ${
                    fieldErrors.fullName || registerErrors.fullName
                      ? 'border-red-500 focus:border-red-500 focus:ring-red-500'
                      : 'border-gray-300 focus:border-green-500 focus:ring-green-500'
                  }`}
                />
                {(fieldErrors.fullName || registerErrors.fullName) && (
                  <p className="mt-1 text-xs text-red-600">
                    {fieldErrors.fullName || registerErrors.fullName?.message}
                  </p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700">Email</label>
                <input
                  type="email"
                  {...registerRegister('email')}
                  className={`mt-1 w-full rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-1 ${
                    fieldErrors.email || registerErrors.email
                      ? 'border-red-500 focus:border-red-500 focus:ring-red-500'
                      : 'border-gray-300 focus:border-green-500 focus:ring-green-500'
                  }`}
                />
                {(fieldErrors.email || registerErrors.email) && (
                  <p className="mt-1 text-xs text-red-600">
                    {fieldErrors.email || registerErrors.email?.message}
                  </p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700">Teléfono</label>
                <input
                  type="tel"
                  placeholder="71234567 (8 dígitos, 6 o 7)"
                  maxLength={8}
                  {...registerRegister('phone')}
                  className={`mt-1 w-full rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-1 ${
                    fieldErrors.phone || registerErrors.phone
                      ? 'border-red-500 focus:border-red-500 focus:ring-red-500'
                      : 'border-gray-300 focus:border-green-500 focus:ring-green-500'
                  }`}
                />
                {(fieldErrors.phone || registerErrors.phone) && (
                  <p className="mt-1 text-xs text-red-600">
                    {fieldErrors.phone || registerErrors.phone?.message}
                  </p>
                )}
                <p className="mt-1 text-xs text-gray-500">8 dígitos, debe empezar con 6 o 7</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700">Dirección (opcional)</label>
                <input
                  type="text"
                  {...registerRegister('address')}
                  className={`mt-1 w-full rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-1 ${
                    fieldErrors.address || registerErrors.address
                      ? 'border-red-500 focus:border-red-500 focus:ring-red-500'
                      : 'border-gray-300 focus:border-green-500 focus:ring-green-500'
                  }`}
                />
                {(fieldErrors.address || registerErrors.address) && (
                  <p className="mt-1 text-xs text-red-600">
                    {fieldErrors.address || registerErrors.address?.message}
                  </p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700">Contraseña</label>
                <input
                  type="password"
                  {...registerRegister('password')}
                  className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
                />
                {registerErrors.password && (
                  <p className="mt-1 text-xs text-red-600">{registerErrors.password.message}</p>
                )}
                <p className="mt-1 text-xs text-gray-500">
                  Mínimo 8 caracteres, 1 mayúscula, 1 minúscula, 1 número
                </p>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700">Confirmar contraseña</label>
                <input
                  type="password"
                  {...registerRegister('confirmPassword')}
                  className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
                />
                {registerErrors.confirmPassword && (
                  <p className="mt-1 text-xs text-red-600">{registerErrors.confirmPassword.message}</p>
                )}
              </div>
              <button
                type="submit"
                disabled={isSubmitting}
                className="w-full rounded-lg bg-green-600 px-4 py-2 font-medium text-white hover:bg-green-700 disabled:opacity-50"
              >
                {isSubmitting ? 'Registrando...' : 'Registrarme'}
              </button>
            </form>
          )}

          <div className="mt-4 border-t border-gray-200 pt-4 space-y-2">
            {mode !== 'email' && (
              <button
                type="button"
                onClick={handleBackToEmail}
                className="w-full text-sm text-gray-600 hover:text-gray-800"
              >
                ← Usar otro email
              </button>
            )}
            {mode === 'login' && (
              <button
                type="button"
                onClick={() => {
                  setRegisterValue('email', emailForLogin);
                  setMode('register');
                  setFieldErrors({});
                  resetLogin();
                }}
                className="w-full text-sm text-green-600 hover:text-green-700"
              >
                ¿No tienes cuenta? Regístrate como Dueño
              </button>
            )}
            {mode === 'register' && (
              <button
                type="button"
                onClick={() => {
                  const email = getRegisterValues('email') || emailForLogin;
                  setEmailForLogin(email);
                  setLoginValue('email', email);
                  setMode('login');
                  setFieldErrors({});
                  resetRegister();
                }}
                className="w-full text-sm text-green-600 hover:text-green-700"
              >
                ¿Ya tienes cuenta? Inicia sesión
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

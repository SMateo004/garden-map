import { useState, useEffect, useRef } from 'react';
import toast from 'react-hot-toast';
import { sendVerifyEmail, verifyEmailCode } from '@/api/caregiverProfile';

interface VerifyEmailModalProps {
  email: string;
  onSuccess: () => void;
  onClose: () => void;
  /** If true the caller already sent the code before opening the modal */
  codeSent?: boolean;
}

const RESEND_COOLDOWN = 60;

export function VerifyEmailModal({ email, onSuccess, onClose, codeSent = false }: VerifyEmailModalProps) {
  const [code, setCode] = useState('');
  const [verifying, setVerifying] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<'expired' | 'incorrect' | 'too_many' | null>(null);
  const [cooldown, setCooldown] = useState(codeSent ? RESEND_COOLDOWN : 0);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Start cooldown timer
  const startCooldown = () => {
    setCooldown(RESEND_COOLDOWN);
    timerRef.current = setInterval(() => {
      setCooldown(prev => {
        if (prev <= 1) {
          clearInterval(timerRef.current!);
          timerRef.current = null;
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
  };

  useEffect(() => {
    if (codeSent) startCooldown();
    return () => { if (timerRef.current) clearInterval(timerRef.current); };
  }, []);

  const handleSendCode = async () => {
    if (cooldown > 0 || sending) return;
    setSending(true);
    setError(null);
    try {
      await sendVerifyEmail();
      toast.success('Código enviado. Revisa tu bandeja de entrada.');
      startCooldown();
    } catch (err: any) {
      const msg = err?.response?.data?.error?.message ?? 'Error al enviar el código';
      // If it's a cooldown error from backend, still start the timer
      if (err?.response?.data?.error?.code === 'RESEND_TOO_SOON') {
        startCooldown();
      }
      toast.error(msg);
    } finally {
      setSending(false);
    }
  };

  const handleVerify = async (e: React.FormEvent) => {
    e.preventDefault();
    if (code.length < 6) {
      toast.error('Ingresa el código de 6 dígitos');
      return;
    }
    setVerifying(true);
    setError(null);
    try {
      const res = await verifyEmailCode(code);
      if (res.success) {
        toast.success(res.message || '¡Email verificado!');
        onSuccess();
        onClose();
      } else {
        setError('incorrect');
        toast.error(res.message || 'Código incorrecto');
      }
    } catch (err: any) {
      const codeErr = err?.response?.data?.error?.code;
      const msg = err?.response?.data?.error?.message;
      if (codeErr === 'EXPIRED_VERIFY_CODE' || codeErr === 'EXPIRED_CODE') setError('expired');
      else if (codeErr === 'TOO_MANY_ATTEMPTS') setError('too_many');
      else setError('incorrect');
      toast.error(msg ?? 'Error al verificar');
    } finally {
      setVerifying(false);
    }
  };

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <div className="w-full max-w-sm bg-white dark:bg-gray-800 rounded-3xl shadow-2xl overflow-hidden">
        <div className="p-6 text-center border-b border-gray-100 dark:border-gray-700">
          <div className="w-16 h-16 bg-blue-100 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400 rounded-full flex items-center justify-center mx-auto mb-4">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-8 w-8" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
            </svg>
          </div>
          <h3 className="text-xl font-bold text-gray-900 dark:text-white">Verifica tu email</h3>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
            Código enviado a <span className="font-semibold text-gray-700 dark:text-gray-200">{email}</span>
          </p>
        </div>

        <form onSubmit={handleVerify} className="p-6 space-y-4">
          <div>
            <label className="block text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wider mb-2 text-center">
              Código de 6 dígitos
            </label>
            <input
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              value={code}
              onChange={(e) => { setCode(e.target.value.replace(/\D/g, '')); setError(null); }}
              placeholder="000000"
              className={`w-full text-center text-2xl font-black tracking-[0.5em] py-3 rounded-2xl border-2 bg-gray-50 dark:bg-gray-950 focus:ring-0 outline-none transition-all ${
                error ? 'border-red-400 dark:border-red-600' : 'border-gray-100 dark:border-gray-700 focus:border-blue-500'
              }`}
              autoFocus
            />
            {error === 'expired' && (
              <p className="text-sm text-amber-600 dark:text-amber-400 mt-2 text-center">
                El código ha expirado. Solicita uno nuevo abajo.
              </p>
            )}
            {error === 'incorrect' && (
              <p className="text-sm text-red-600 dark:text-red-400 mt-2 text-center">
                Código incorrecto. Revisa e intenta de nuevo.
              </p>
            )}
            {error === 'too_many' && (
              <p className="text-sm text-red-600 dark:text-red-400 mt-2 text-center">
                Demasiados intentos. Solicita un nuevo código.
              </p>
            )}
          </div>

          <button
            type="submit"
            disabled={verifying || code.length < 6}
            className="w-full py-4 bg-blue-600 hover:bg-blue-700 disabled:opacity-50 text-white font-bold rounded-2xl shadow-lg shadow-blue-200 dark:shadow-none transition-all active:scale-95"
          >
            {verifying ? 'Verificando...' : 'Verificar código'}
          </button>

          <div className="text-center pt-1">
            {cooldown > 0 ? (
              <p className="text-sm text-gray-400">
                Reenviar en <span className="font-bold text-gray-600 dark:text-gray-300 tabular-nums">{cooldown}s</span>
              </p>
            ) : (
              <button
                type="button"
                onClick={handleSendCode}
                disabled={sending}
                className="text-sm font-medium text-blue-600 dark:text-blue-400 hover:underline disabled:opacity-50"
              >
                {sending ? 'Enviando...' : '¿No recibiste el código? Reenviar'}
              </button>
            )}
          </div>

          <button
            type="button"
            onClick={onClose}
            className="w-full py-2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 text-sm font-medium transition-colors"
          >
            Cancelar
          </button>
        </form>
      </div>
    </div>
  );
}

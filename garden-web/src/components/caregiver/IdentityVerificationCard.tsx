import { useNavigate } from 'react-router-dom';

type Status = 'PENDING' | 'REVIEW' | 'VERIFIED' | 'REJECTED';

interface IdentityVerificationCardProps {
  status: Status | string | null;
  caregiverId: string;
  token: string | null;
}

const STATUS_LABELS: Record<string, string> = {
  PENDING: 'Pendiente',
  REVIEW: 'En Revisión (Humana)',
  VERIFIED: 'Verificado',
  REJECTED: 'Rechazado',
};

export function IdentityVerificationCard({ status, caregiverId, token }: IdentityVerificationCardProps) {
  const navigate = useNavigate();
  const s = (status === 'IN_PROGRESS' ? 'REVIEW' : (status ?? 'PENDING')) as Status;
  const isVerified = s === 'VERIFIED';
  const isInReview = s === 'REVIEW';
  const isRejected = s === 'REJECTED';

  const handleStart = () => {
    if (!token) {
      navigate(`/caregiver/${caregiverId}/verify`);
    } else {
      navigate(`/caregiver/${caregiverId}/verify?token=${encodeURIComponent(token)}`);
    }
  };

  return (
    <div className="rounded-[2rem] border-2 border-green-100 dark:border-green-900/30 bg-green-50/30 dark:bg-green-900/5 p-8 h-full flex flex-col justify-between shadow-sm">
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <h3 className="text-xl font-black text-green-900 dark:text-green-100 uppercase tracking-tight">
            Identidad
          </h3>
          <span
            className={`rounded-full px-4 py-1.5 text-[10px] font-black uppercase tracking-widest border transition-all ${isVerified
              ? 'bg-green-500 text-white border-green-400 shadow-lg shadow-green-500/20'
              : isInReview
                ? 'bg-amber-400 text-white border-amber-300 shadow-lg shadow-amber-500/20'
                : isRejected
                  ? 'bg-red-500 text-white border-red-400 shadow-lg shadow-red-500/20'
                  : 'bg-white dark:bg-gray-800 text-gray-400 border-gray-200 dark:border-gray-700'
              }`}
          >
            {STATUS_LABELS[s] || s}
          </span>
        </div>

        <p className="text-sm text-green-800 dark:text-green-200/70 font-medium leading-relaxed">
          {isVerified
            ? 'Tu identidad ha sido confirmada con éxito. Esto genera máxima confianza en los dueños de mascotas.'
            : isInReview
              ? 'Verificación en revisión manual. Recibirás una notificación pronto.'
              : isRejected
                ? 'Tu validación de identidad no fue exitosa. Por favor intenta con fotos más claras.'
                : 'Verifica tu identidad con una selfie y tu carnet para empezar a recibir reservas.'}
        </p>
      </div>

      <div className="mt-8">
        {(!isVerified && !isInReview) ? (
          <button
            onClick={handleStart}
            className={`group relative w-full py-5 rounded-2xl ${isRejected ? 'bg-red-600 hover:bg-red-700' : 'bg-green-600 hover:bg-green-700'} text-white font-black text-sm shadow-xl transition-all transform hover:scale-[1.02] active:scale-95 overflow-hidden`}
          >
            <span className="relative z-10">{isRejected ? 'REINTENTAR VERIFICACIÓN' : 'INICIAR VERIFICACIÓN'} →</span>
            <div className={`absolute inset-0 ${isRejected ? 'bg-red-400' : 'bg-white/20'} translate-y-full group-hover:translate-y-0 transition-transform duration-300`} />
          </button>
        ) : isVerified ? (
          <div className="flex items-center gap-4 p-5 rounded-3xl bg-green-500/10 border-2 border-green-500/20">
            <div>
              <p className="font-black text-green-900 dark:text-green-100 text-sm">PERFIL VERIFICADO</p>
              <p className="text-[10px] text-green-700 dark:text-green-400 font-bold uppercase tracking-wider">Confianza máxima</p>
            </div>
          </div>
        ) : (
          <div className="flex items-center gap-4 p-5 rounded-3xl bg-amber-400/10 border-2 border-amber-400/20">
            <div>
              <p className="font-black text-amber-900 dark:text-amber-100 text-sm italic">EN REVISIÓN</p>
              <p className="text-[10px] text-amber-700 dark:text-amber-400 font-bold uppercase tracking-wider">Procesando fotos...</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

import { CaregiverAvailabilityPage } from '@/pages/caregiver/CaregiverAvailabilityPage';

export function AvailabilitySection({ profile }: { profile: any }) {
  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between">
        <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Disponibilidad</h2>
        {(profile?.availabilityComplete || profile?.profileStatus === 'APPROVED') ? (
          <span className="text-xs font-medium px-2.5 py-1 rounded-full bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400">
            ✓ Completado
          </span>
        ) : (
          <div
            className="px-4 py-1.5 rounded-lg bg-red-600 text-white text-xs font-black uppercase tracking-tight shadow-md shadow-red-600/20 animate-pulse active:scale-95 transition-all"
          >
            Completar
          </div>
        )}
      </div>
      <p className="text-sm text-gray-500 dark:text-gray-400">
        Por defecto estás disponible todos los días. Haz clic en las fechas donde NO estés disponible para marcarlas como excepciones.
      </p>
      <div className="mt-4">
        <CaregiverAvailabilityPage standalone />
      </div>
    </div>
  );
}

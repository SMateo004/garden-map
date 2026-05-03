interface ServiceSelectorModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSelect: (service: 'HOSPEDAJE' | 'PASEO') => void;
  pricePerDay?: number | null;
  pricePerWalk60?: number | null;
  pricePerWalk30?: number | null;
}

export function ServiceSelectorModal({
  isOpen,
  onClose,
  onSelect,
  pricePerDay,
  pricePerWalk60,
  pricePerWalk30,
}: ServiceSelectorModalProps) {
  if (!isOpen) return null;

  const walkPrice = (pricePerWalk60 ?? 0) > 0 ? pricePerWalk60 : pricePerWalk30;
  const walkLabel = (pricePerWalk60 ?? 0) > 0 ? '60 min' : '30 min';

  return (
    <div
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      role="dialog"
      aria-modal="true"
      aria-label="Seleccionar servicio"
    >
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/40 backdrop-blur-sm"
        onClick={onClose}
      />

      {/* Panel */}
      <div className="relative z-10 w-full max-w-md rounded-t-2xl sm:rounded-2xl bg-white dark:bg-gray-900 p-6 shadow-2xl border border-gray-100 dark:border-gray-700">
        {/* Handle bar (mobile) */}
        <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-gray-200 dark:bg-gray-700 sm:hidden" />

        <h2 className="mb-1 text-lg font-bold text-gray-900 dark:text-white">
          ¿Qué servicio necesitas?
        </h2>
        <p className="mb-5 text-sm text-gray-500 dark:text-gray-400">
          Este cuidador ofrece ambos servicios. Elige uno para continuar.
        </p>

        <div className="space-y-3">
          {/* Hospedaje */}
          <button
            type="button"
            onClick={() => onSelect('HOSPEDAJE')}
            className="flex w-full items-center gap-4 rounded-xl border border-green-100 dark:border-green-900/30 bg-green-50 dark:bg-green-900/10 p-4 text-left transition hover:border-green-300 hover:bg-green-100 dark:hover:bg-green-900/20 focus:outline-none focus:ring-2 focus:ring-green-500"
          >
            <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-green-100 dark:bg-green-900/30 text-xl">
              🏠
            </span>
            <div className="flex-1">
              <p className="font-semibold text-gray-900 dark:text-white">Hospedaje</p>
              {(pricePerDay ?? 0) > 0 && (
                <p className="text-sm font-bold text-green-600">Bs {pricePerDay}/noche</p>
              )}
            </div>
            <svg className="h-5 w-5 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
          </button>

          {/* Paseo */}
          <button
            type="button"
            onClick={() => onSelect('PASEO')}
            className="flex w-full items-center gap-4 rounded-xl border border-blue-100 dark:border-blue-900/30 bg-blue-50 dark:bg-blue-900/10 p-4 text-left transition hover:border-blue-300 hover:bg-blue-100 dark:hover:bg-blue-900/20 focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-blue-100 dark:bg-blue-900/30 text-xl">
              🦮
            </span>
            <div className="flex-1">
              <p className="font-semibold text-gray-900 dark:text-white">Paseo</p>
              {(walkPrice ?? 0) > 0 && (
                <p className="text-sm font-bold text-blue-600">Bs {walkPrice}/{walkLabel}</p>
              )}
            </div>
            <svg className="h-5 w-5 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
          </button>
        </div>

        <button
          type="button"
          onClick={onClose}
          className="mt-4 w-full rounded-xl border border-gray-200 dark:border-gray-700 py-2.5 text-sm font-medium text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-800 transition focus:outline-none focus:ring-2 focus:ring-gray-400"
        >
          Cancelar
        </button>
      </div>
    </div>
  );
}

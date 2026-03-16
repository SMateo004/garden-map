import { useState, useCallback, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import Calendar from 'react-calendar';
import 'react-calendar/dist/Calendar.css';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import {
  getMyAvailability,
  patchAvailability,
  getMyProfile,
} from '@/api/caregiverProfile';
import { useAuth } from '@/contexts/AuthContext';

/** Time blocks configuration - keys MUST match backend Zod schema */
const TIME_BLOCKS_CONFIG = {
  morning: { label: 'Mañana', defaultStart: '08:00', defaultEnd: '11:00' },
  afternoon: { label: 'Tarde', defaultStart: '13:00', defaultEnd: '17:00' },
  night: { label: 'Noche', defaultStart: '19:00', defaultEnd: '22:00' },
} as const;

type SlotKey = keyof typeof TIME_BLOCKS_CONFIG;

/** Timezone-safe: local YYYY-MM-DD without UTC conversion */
function toLocalDateStr(d: Date): string {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

type SlotValue = {
  enabled: boolean;
  start?: string;
  end?: string;
} | null;

type TimeBlocks = {
  morning?: SlotValue;
  afternoon?: SlotValue;
  night?: SlotValue;
};

type DayOverride = {
  isAvailable: boolean;
  timeBlocks?: TimeBlocks;
};

export function CaregiverAvailabilityPage({ standalone = false }: { standalone?: boolean }) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { isCaregiver } = useAuth();
  const [from] = useState(() => toLocalDateStr(new Date()));
  const [to] = useState(() => {
    const d = new Date();
    d.setDate(d.getDate() + 90);
    return toLocalDateStr(d);
  });

  const [overrides, setOverrides] = useState<Record<string, DayOverride>>({});
  const [selectedDate, setSelectedDate] = useState<string | null>(null);

  // 1. Fetch Profile to check services
  const { data: profile } = useQuery({
    queryKey: ['caregiver', 'profile'],
    queryFn: getMyProfile,
    enabled: isCaregiver,
  });

  const services = profile?.servicesOffered || [];
  const isBoarder = services.includes('HOSPEDAJE');
  const isWalker = services.includes('PASEO') || services.includes('VISITA'); // assuming VISITA might also need slots

  const { data, isLoading } = useQuery({
    queryKey: ['caregiver', 'my-availability', from, to],
    queryFn: () => getMyAvailability(from, to),
    enabled: isCaregiver,
  });

  useEffect(() => {
    if (!data?.dates) return;
    const normalized: Record<string, DayOverride> = {};
    for (const [date, val] of Object.entries(data.dates)) {
      const tb: TimeBlocks = {
        morning: { enabled: true, start: TIME_BLOCKS_CONFIG.morning.defaultStart, end: TIME_BLOCKS_CONFIG.morning.defaultEnd },
        afternoon: { enabled: true, start: TIME_BLOCKS_CONFIG.afternoon.defaultStart, end: TIME_BLOCKS_CONFIG.afternoon.defaultEnd },
        night: { enabled: true, start: TIME_BLOCKS_CONFIG.night.defaultStart, end: TIME_BLOCKS_CONFIG.night.defaultEnd },
      };

      const raw = (val.timeBlocks as any) ?? null;
      if (raw) {
        const src = raw.slots || raw;
        if (src && typeof src === 'object') {
          (Object.keys(TIME_BLOCKS_CONFIG) as SlotKey[]).forEach(k => {
            const s = src[k];
            if (s && typeof s === 'object') {
              tb[k] = {
                enabled: s.enabled ?? true,
                start: s.start || TIME_BLOCKS_CONFIG[k].defaultStart,
                end: s.end || TIME_BLOCKS_CONFIG[k].defaultEnd,
              };
            }
          });
        }
      }
      normalized[date] = { isAvailable: val.isAvailable, timeBlocks: tb };
    }
    setOverrides(normalized);
  }, [data?.dates]);

  const patchMutation = useMutation({
    mutationFn: patchAvailability,
    onSuccess: () => {
      toast.success('Disponibilidad guardada');
      queryClient.invalidateQueries({ queryKey: ['caregiver', 'my-availability'] });
    },
    onError: (e) => {
      toast.error(e instanceof Error ? e.message : 'Error al guardar');
    },
  });

  const handleSave = useCallback(() => {
    patchMutation.mutate({ overrides });
  }, [overrides, patchMutation]);

  // Logic: Default is Available (true)
  const getSlotForDay = useCallback((dateStr: string): { enabled: boolean; slots: Record<SlotKey, { enabled: boolean; start: string; end: string }> } => {
    const day = overrides[dateStr];
    // Default to TRUE if no override exists
    const isAvailable = day ? day.isAvailable : true;

    const rawTb = (day?.timeBlocks as any) ?? {};
    const tb = rawTb.slots || rawTb;

    const slots = (Object.keys(TIME_BLOCKS_CONFIG) as SlotKey[]).reduce((acc, key) => {
      const raw = tb[key];
      acc[key] = {
        enabled: raw?.enabled ?? true, // Standard default for slot is enabled
        start: raw?.start ?? TIME_BLOCKS_CONFIG[key].defaultStart,
        end: raw?.end ?? TIME_BLOCKS_CONFIG[key].defaultEnd,
      };
      return acc;
    }, {} as Record<SlotKey, { enabled: boolean; start: string; end: string }>);

    return { enabled: isAvailable, slots };
  }, [overrides]);

  const handleDayClick = useCallback((date: Date) => {
    const str = toLocalDateStr(date);
    const today = toLocalDateStr(new Date());
    if (str < today) return;
    setSelectedDate(str);
  }, []);

  const toggleDayAvailability = useCallback((dateStr: string) => {
    setOverrides(prev => {
      const cur = prev[dateStr] ?? { isAvailable: true };
      return {
        ...prev,
        [dateStr]: { ...cur, isAvailable: !cur.isAvailable }
      };
    });
  }, []);

  const updateSlot = useCallback((dateStr: string, key: SlotKey, update: Partial<{ enabled: boolean; start: string; end: string }>) => {
    setOverrides(prev => {
      const day = prev[dateStr] ?? { isAvailable: true };
      const rawTb = (day.timeBlocks as any) ?? {};
      const oldTb = rawTb.slots || rawTb;
      const oldSlot = oldTb[key] ?? { enabled: true, start: TIME_BLOCKS_CONFIG[key].defaultStart, end: TIME_BLOCKS_CONFIG[key].defaultEnd };
      return {
        ...prev,
        [dateStr]: {
          ...day,
          timeBlocks: {
            ...oldTb,
            [key]: { ...oldSlot, ...update },
          },
        },
      };
    });
  }, []);

  const tileClassName = useCallback(({ date }: { date: Date }) => {
    const str = toLocalDateStr(date);
    const today = toLocalDateStr(new Date());
    if (str < today) return 'opacity-30';

    // Check if definitely NOT available
    const day = overrides[str];
    const isAvailable = day ? day.isAvailable : true;

    // Check if partial (some slots disabled)
    let isPartial = false;
    if (day?.isAvailable !== false && day?.timeBlocks) {
      const slots = day.timeBlocks as any;
      if (Object.values(slots).some((s: any) => s.enabled === false)) {
        isPartial = true;
      }
    }

    if (str === selectedDate) return 'ring-2 ring-green-500 rounded-xl bg-green-200 dark:bg-green-800/40 font-semibold';
    if (!isAvailable) return 'bg-gray-100 dark:bg-gray-800 text-gray-400 rounded-xl';
    if (isPartial) return 'bg-amber-100 dark:bg-amber-900/40 text-amber-800 dark:text-amber-200 rounded-xl';

    // Default green
    return 'bg-green-100 dark:bg-green-900/40 text-green-800 dark:text-green-200 rounded-xl';
  }, [overrides, selectedDate]);

  if (!isCaregiver && !standalone) {
    navigate('/caregiver/auth');
    return null;
  }

  if (isLoading) return <div className="py-12 text-center text-gray-400 font-bold">Cargando disponibilidad...</div>;

  const selDay = selectedDate ? getSlotForDay(selectedDate) : null;

  return (
    <div className={standalone ? '' : 'mx-auto max-w-4xl px-4 py-6'}>
      {!standalone && (
        <header className="mb-8 rounded-2xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-6">
          <h1 className="text-xl font-bold text-gray-900 dark:text-white">Mi calendario</h1>
          <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 flex flex-wrap gap-x-4 gap-y-1">
            <span className="flex items-center gap-1.5"><div className="h-2 w-2 rounded-full bg-green-500" /> Disponible por defecto</span>
            <span className="flex items-center gap-1.5"><div className="h-2 w-2 rounded-full bg-amber-500" /> Horas limitadas</span>
            <span className="flex items-center gap-1.5"><div className="h-2 w-2 rounded-full bg-gray-400" /> No disponible</span>
          </div>
        </header>
      )}

      <div className="grid gap-8 lg:grid-cols-[1fr_350px]">
        {/* Calendar Side */}
        <section className="relative rounded-3xl border-2 border-gray-100 dark:border-gray-800 bg-white dark:bg-gray-900 p-6 shadow-sm">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-lg font-black text-gray-900 dark:text-white uppercase tracking-tight">Selecciona Fechas</h2>
            <div className="hidden sm:flex gap-3">
              <div className="flex items-center gap-1.5">
                <div className="h-3 w-3 rounded-full bg-green-400" />
                <span className="text-[10px] uppercase font-black text-gray-400">Total</span>
              </div>
              <div className="flex items-center gap-1.5">
                <div className="h-3 w-3 rounded-full bg-amber-400" />
                <span className="text-[10px] uppercase font-black text-gray-400">Parcial</span>
              </div>
            </div>
          </div>
          <Calendar
            onClickDay={handleDayClick}
            tileClassName={tileClassName}
            className="w-full !border-0 !font-sans !bg-transparent text-sm [&_.react-calendar__navigation]:mb-4 [&_.react-calendar__navigation_button]:text-lg [&_.react-calendar__navigation_button]:font-black [&_.react-calendar__month-view__weekdays]:font-black [&_.react-calendar__month-view__weekdays]:uppercase [&_.react-calendar__month-view__weekdays__weekday]:no-underline [&_.react-calendar__month-view__weekdays__weekday_abbr]:no-underline [&_.react-calendar__tile]:aspect-square [&_.react-calendar__tile]:rounded-xl"
          />
          <p className="mt-4 text-[10px] text-gray-400 text-center uppercase font-black tracking-widest">
            Por defecto estás disponible todos los días. Marca solo donde NO puedas.
          </p>
        </section>

        {/* Configuration Side */}
        <section className="space-y-4">
          <div className="rounded-3xl border-2 border-gray-100 dark:border-gray-800 bg-white dark:bg-gray-900 p-6 shadow-sm">
            <h2 className="mb-4 text-lg font-black text-gray-900 dark:text-white uppercase tracking-tight">Ajustes</h2>

            {selectedDate && selDay ? (
              <div className="space-y-4">
                <div className="rounded-2xl bg-gray-50 dark:bg-gray-800 p-3 border border-gray-100 dark:border-gray-700">
                  <p className="text-[10px] uppercase font-black text-gray-400 mb-0.5">Fecha</p>
                  <p className="font-bold text-gray-700 dark:text-gray-200 text-sm">{selectedDate}</p>
                </div>

                <div className="flex items-center justify-between group">
                  <div className="flex flex-col">
                    <span className="font-black text-xs text-gray-900 dark:text-white uppercase tracking-widest mb-0.5">Disponibilidad del día</span>
                    <span className={`text-[10px] font-bold ${selDay.enabled ? 'text-green-600' : 'text-red-500'}`}>
                      {selDay.enabled ? 'ESTÁS DISPONIBLE' : 'NO DISPONIBLE'}
                    </span>
                  </div>
                  <button
                    onClick={() => toggleDayAvailability(selectedDate)}
                    className={`h-7 w-12 rounded-full transition-all flex items-center px-1 shadow-inner ${selDay.enabled ? 'bg-green-600 justify-end' : 'bg-gray-300 dark:bg-gray-700 justify-start'}`}
                  >
                    <div className="h-5 w-5 rounded-full bg-white shadow-xl" />
                  </button>
                </div>

                {/* Hide hours if Hospedaje is the primary service and it's a boarder profile without walks */}
                {selDay.enabled && (isWalker || !isBoarder) && (
                  <div className="space-y-3 pt-3 border-t-2 border-gray-50 dark:border-gray-800">
                    <p className="text-[10px] uppercase font-black text-gray-400">Franjas de Paseos</p>
                    {(Object.entries(TIME_BLOCKS_CONFIG) as [SlotKey, (typeof TIME_BLOCKS_CONFIG)[SlotKey]][]).map(([key, cfg]) => {
                      const slot = selDay.slots[key];
                      return (
                        <div key={key} className={`space-y-2 rounded-2xl border-2 transition-all p-3 ${slot.enabled ? 'border-gray-100 bg-white dark:bg-gray-800' : 'border-gray-200 bg-gray-50 opacity-60'}`}>
                          <div className="flex items-center justify-between">
                            <span className="font-black text-[10px] text-gray-500 dark:text-gray-400 uppercase tracking-widest">{cfg.label}</span>
                            <div className="flex items-center gap-2">
                              <span className={`text-[9px] font-black ${slot.enabled ? 'text-green-500' : 'text-gray-400'}`}>{slot.enabled ? 'ON' : 'OFF'}</span>
                              <input
                                type="checkbox"
                                checked={slot.enabled}
                                onChange={(e) => updateSlot(selectedDate, key, { enabled: e.target.checked })}
                                className="h-4 w-4 rounded border-gray-300 text-green-600 focus:ring-green-500"
                              />
                            </div>
                          </div>
                          {slot.enabled && (
                            <div className="flex items-center gap-1 pr-2">
                              <input
                                type="time"
                                value={slot.start}
                                onChange={(e) => updateSlot(selectedDate, key, { start: e.target.value })}
                                className="w-full rounded-lg border border-gray-100 bg-gray-50 dark:bg-gray-900 px-2 py-1.5 text-[11px] font-black text-gray-900 dark:text-white outline-none focus:ring-1 focus:ring-green-500"
                              />
                              <span className="text-gray-300 text-[10px] font-black">TO</span>
                              <input
                                type="time"
                                value={slot.end}
                                onChange={(e) => updateSlot(selectedDate, key, { end: e.target.value })}
                                className="w-full rounded-lg border border-gray-100 bg-gray-50 dark:bg-gray-900 px-2 py-1.5 text-[11px] font-black text-gray-900 dark:text-white outline-none focus:ring-1 focus:ring-green-500"
                              />
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                )}

                {selDay.enabled && isBoarder && !isWalker && (
                  <div className="p-4 rounded-2xl bg-green-50 dark:bg-green-900/20 border border-green-100 dark:border-green-800 text-[11px] text-green-700 dark:text-green-400 font-bold leading-relaxed text-center italic">
                    Como eres cuidador de hospedaje, tu disponibilidad es por día completo. ¡Genereas confianza al estar disponible!
                  </div>
                )}
              </div>
            ) : (
              <div className="flex flex-col items-center justify-center py-16 text-center">
                <div className="mb-4 text-5xl grayscale opacity-30">📅</div>
                <p className="text-[10px] font-black uppercase text-gray-400 tracking-[0.2em] max-w-[150px]">
                  Toca una fecha para modificarla
                </p>
              </div>
            )}
          </div>

          <div className="rounded-2xl bg-gray-900 p-5 shadow-lg border border-gray-800">
            <div className="flex items-center justify-between mb-3 pb-3 border-b border-gray-800">
              <h3 className="text-[10px] font-black text-gray-400 uppercase tracking-widest">Resumen de Cambios</h3>
              <span className="text-[10px] font-black text-green-500 bg-green-500/10 px-2 py-0.5 rounded-full">{Object.keys(overrides).length} EXCEPCIONES</span>
            </div>
            <p className="text-[11px] text-gray-300 font-medium leading-relaxed">
              Todas las fechas sin marcar se consideran <span className="text-green-500 font-black">DISPONIBLES</span> automáticamente. Solo guarda si has hecho cambios.
            </p>
          </div>

          <button
            onClick={handleSave}
            disabled={patchMutation.isPending}
            className="group relative w-full overflow-hidden rounded-3xl bg-green-600 py-4 text-sm font-black text-white shadow-2xl shadow-green-600/20 transition-all hover:bg-green-700 hover:shadow-green-600/40 active:scale-[0.98] disabled:opacity-50"
          >
            <div className="relative z-10 flex items-center justify-center gap-2">
              <span className="text-lg">💾</span>
              <span>{patchMutation.isPending ? 'GUARDANDO...' : 'GUARDAR CAMBIOS'}</span>
            </div>
          </button>
        </section>
      </div>
    </div>
  );
}

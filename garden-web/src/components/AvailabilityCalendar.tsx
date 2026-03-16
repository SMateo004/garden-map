import { useMemo } from 'react';
import Calendar from 'react-calendar';
import 'react-calendar/dist/Calendar.css';
import type { CaregiverAvailabilityResponse } from '@/types/caregiver';

interface AvailabilityCalendarProps {
  availability: CaregiverAvailabilityResponse | null;
  serviceType: 'HOSPEDAJE' | 'PASEO';
  selectedDate?: Date | null;
  onDateChange?: (date: Date | null) => void;
  disabled?: boolean;
  minDate?: Date;
  selectRange?: boolean;
  onRangeChange?: (range: [Date | null, Date | null]) => void;
  selectedRange?: [Date | null, Date | null];
}

const toDateString = (date: Date) => {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
};

/**
 * Calendario de disponibilidad con días bloqueados en gris.
 * Para hospedaje: muestra días disponibles (isAvailable=true).
 * Para paseos: muestra días con bloques disponibles (timeBlocks).
 */
export function AvailabilityCalendar({
  availability,
  serviceType,
  onDateChange,
  selectedDate,
  disabled = false,
  minDate,
  selectRange = false,
  onRangeChange,
  selectedRange,
}: AvailabilityCalendarProps) {
  const defaultMinDate = useMemo(() => {
    const d = new Date();
    d.setDate(d.getDate() + 1); // Mañana
    d.setHours(0, 0, 0, 0);
    return d;
  }, []);

  const effectiveMinDate = minDate || defaultMinDate;

  const availableDates = useMemo(() => {
    if (!availability) {
      console.debug('[AvailabilityCalendar] No availability data', { serviceType });
      return new Set<string>();
    }
    try {
      if (serviceType === 'HOSPEDAJE') {
        const dates = Array.isArray(availability.hospedaje) ? availability.hospedaje : [];
        return new Set(dates);
      }
      const paseosKeys = availability.paseos && typeof availability.paseos === 'object'
        ? Object.keys(availability.paseos)
        : [];
      return new Set(paseosKeys);
    } catch (error) {
      console.error('[AvailabilityCalendar] Error processing availability', {
        error: error instanceof Error ? error.message : String(error),
        serviceType,
        availability,
      });
      return new Set<string>();
    }
  }, [availability, serviceType]);

  const tileDisabled = ({ date }: { date: Date }) => {
    // Si el componente está deshabilitado, deshabilitar todas las fechas
    if (disabled) return true;
    const dateStr = toDateString(date);
    const checkDate = new Date(dateStr + 'T00:00:00Z');
    const minD = new Date(toDateString(effectiveMinDate) + 'T00:00:00Z');
    return checkDate < minD || !availableDates.has(dateStr);
  };

  const tileClassName = ({ date }: { date: Date }) => {
    const dateStr = toDateString(date);
    if (!availableDates.has(dateStr)) {
      return 'opacity-40 bg-gray-100 dark:bg-gray-800';
    }
    return '';
  };

  return (
    <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 p-4">
      <h3 className="mb-3 text-sm font-semibold text-gray-900 dark:text-gray-100">
        Disponibilidad {serviceType === 'HOSPEDAJE' ? 'para hospedaje' : 'para paseos'}
      </h3>
      <Calendar
        onChange={(value) => {
          if (disabled) return;
          if (selectRange && onRangeChange) {
            const range = value as [Date | null, Date | null];
            onRangeChange(range);
          } else if (onDateChange) {
            const date = Array.isArray(value) ? value[0] : value;
            onDateChange(date ? new Date(date) : null);
          }
        }}
        selectRange={selectRange}
        value={(selectRange ? selectedRange : selectedDate) || undefined}
        tileDisabled={tileDisabled}
        tileClassName={tileClassName}
        minDate={effectiveMinDate}
        prev2Label={null} // Quitar salto de año
        next2Label={null} // Quitar salto de año
        className="w-full border-0 !bg-transparent text-sm dark:text-gray-200 [&_.react-calendar__tile]:aspect-square [&_.react-calendar__tile]:rounded-lg [&_.react-calendar__tile--active]:bg-green-600 [&_.react-calendar__tile--range]:bg-green-100 dark:[&_.react-calendar__tile--range]:bg-green-900/40 [&_.react-calendar__navigation_button]:text-gray-900 dark:[&_.react-calendar__navigation_button]:text-gray-100 hover:[&_.react-calendar__navigation_button]:bg-gray-100 dark:hover:[&_.react-calendar__navigation_button]:bg-gray-800"
      />
      <p className="mt-2 text-[10px] text-gray-500 uppercase font-black">
        {selectRange
          ? 'Selecciona el rango de entrada y salida'
          : 'Selecciona una fecha disponible para continuar'}
      </p>
    </div>
  );
}

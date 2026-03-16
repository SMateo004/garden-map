import { useState, useCallback, useMemo } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import Calendar from 'react-calendar';
import 'react-calendar/dist/Calendar.css';
import { useQuery } from '@tanstack/react-query';
import { getCaregiverBookings, type CaregiverBookingItem } from '@/api/caregiverProfile';
import { useAuth } from '@/contexts/AuthContext';
import { format, isSameDay, parseISO } from 'date-fns';
import { es } from 'date-fns/locale';

/** Timezone-safe: local YYYY-MM-DD without UTC conversion */
function toLocalDateStr(d: Date): string {
    const yyyy = d.getFullYear();
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
}

export function CaregiverCalendarPage() {
    const navigate = useNavigate();
    const { isCaregiver } = useAuth();
    const [selectedDate, setSelectedDate] = useState<Date>(new Date());

    const { data: bookings = [], isLoading } = useQuery({
        queryKey: ['caregiver', 'bookings'],
        queryFn: getCaregiverBookings,
        enabled: isCaregiver,
    });

    const selectedDateStr = useMemo(() => toLocalDateStr(selectedDate), [selectedDate]);

    // Group bookings by date for easy lookup in tileClassName
    const bookingsByDate = useMemo(() => {
        const map: Record<string, CaregiverBookingItem[]> = {};
        bookings.forEach(b => {
            if (b.serviceType === 'PASEO' && b.walkDate) {
                map[b.walkDate] = [...(map[b.walkDate] || []), b];
            } else if (b.serviceType === 'HOSPEDAJE' && b.startDate && b.endDate) {
                // For boardings, we mark all days in the range
                let current = parseISO(b.startDate);
                const end = parseISO(b.endDate);
                while (current <= end) {
                    const dateStr = toLocalDateStr(current);
                    map[dateStr] = [...(map[dateStr] || []), b];
                    current.setDate(current.getDate() + 1);
                }
            }
        });
        return map;
    }, [bookings]);

    const bookingsForSelectedDay = useMemo(() => {
        return bookingsByDate[selectedDateStr] || [];
    }, [bookingsByDate, selectedDateStr]);

    const tileClassName = useCallback(({ date, view }: { date: Date; view: string }) => {
        if (view !== 'month') return '';
        const str = toLocalDateStr(date);
        const hasBookings = !!bookingsByDate[str];

        const classes = ['transition-all duration-200 rounded-xl relative'];

        if (hasBookings) {
            classes.push('!bg-green-50 !text-green-800 font-bold border-2 border-green-200');
        }

        if (isSameDay(date, selectedDate)) {
            classes.push('!bg-green-600 !text-white !border-green-600 shadow-lg shadow-green-200 scale-105 z-10');
        }

        return classes.join(' ');
    }, [bookingsByDate, selectedDate]);

    const tileContent = useCallback(({ date, view }: { date: Date; view: string }) => {
        if (view !== 'month') return null;
        const str = toLocalDateStr(date);
        const count = bookingsByDate[str]?.length || 0;

        if (count === 0) return null;

        return (
            <div className="absolute top-1 right-1 flex gap-0.5">
                <div className="h-1.5 w-1.5 rounded-full bg-green-500 shadow-sm" />
            </div>
        );
    }, [bookingsByDate]);

    if (!isCaregiver) {
        navigate('/caregiver/auth');
        return null;
    }

    return (
        <div className="mx-auto max-w-5xl px-4 py-8">
            <div className="mb-10 flex flex-col md:flex-row md:items-end justify-between gap-6">
                <div>
                    <Link to="/caregiver/dashboard" className="text-xs font-black text-gray-400 hover:text-green-600 transition-colors uppercase tracking-widest flex items-center gap-2 mb-4">
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M15 19l-7-7 7-7" /></svg>
                        Volver al Dashboard
                    </Link>
                    <h1 className="text-4xl font-black text-gray-900 dark:text-white uppercase tracking-tighter leading-none">
                        Mi <span className="text-green-600">Calendario</span>
                    </h1>
                    <p className="mt-2 text-xs font-bold text-gray-400 uppercase tracking-widest">Visualiza y gestiona todas tus reservas</p>
                </div>
                <div className="bg-white dark:bg-gray-800 px-6 py-4 rounded-3xl border border-gray-100 dark:border-gray-700 shadow-sm">
                    <p className="text-[10px] font-black text-gray-400 uppercase tracking-widest mb-1">Total Reservas</p>
                    <p className="text-3xl font-black text-green-600">{bookings.length}</p>
                </div>
            </div>

            <div className="grid gap-8 lg:grid-cols-[1fr_400px]">
                {/* Calendar Side */}
                <section className="bg-white dark:bg-gray-900 rounded-[2.5rem] p-8 shadow-sm border border-gray-100 dark:border-gray-800">
                    <div className="mb-6 flex items-center justify-between">
                        <h2 className="text-xl font-black text-gray-900 dark:text-white uppercase tracking-tight italic">
                            {format(selectedDate, 'MMMM yyyy', { locale: es })}
                        </h2>
                        <div className="flex gap-4">
                            <div className="flex items-center gap-2">
                                <div className="h-3 w-3 rounded-full bg-green-500" />
                                <span className="text-[10px] uppercase font-black text-gray-400 italic">Con Reservas</span>
                            </div>
                        </div>
                    </div>

                    <Calendar
                        onChange={(d) => setSelectedDate(d as Date)}
                        value={selectedDate}
                        locale="es-ES"
                        tileClassName={tileClassName}
                        tileContent={tileContent}
                        className="w-full !border-0 !font-sans !bg-transparent text-lg [&_.react-calendar__navigation]:mb-8 [&_.react-calendar__navigation_button]:text-2xl [&_.react-calendar__navigation_button]:font-black [&_.react-calendar__navigation_button]:text-gray-900 dark:text-white [&_.react-calendar__month-view__weekdays]:font-black [&_.react-calendar__month-view__weekdays]:uppercase [&_.react-calendar__month-view__weekdays]:mb-4 [&_.react-calendar__month-view__weekdays__weekday]:no-underline [&_.react-calendar__month-view__weekdays__weekday_abbr]:no-underline [&_.react-calendar__tile]:aspect-square [&_.react-calendar__tile]:flex [&_.react-calendar__tile]:items-center [&_.react-calendar__tile]:justify-center [&_.react-calendar__tile]:text-sm [&_.react-calendar__tile--now]:bg-gray-50 [&_.react-calendar__tile--now]:text-green-600 font-bold"
                    />
                </section>

                {/* Details Side */}
                <section className="space-y-6">
                    <div className="bg-white dark:bg-gray-800 rounded-[2.5rem] p-8 shadow-sm border border-gray-100 dark:border-gray-700 h-full">
                        <div className="flex items-center justify-between mb-8 pb-4 border-b border-gray-50 dark:border-gray-700">
                            <div className="text-left">
                                <p className="text-[10px] font-black text-gray-400 uppercase tracking-widest mb-1">Reservas para el</p>
                                <h2 className="text-2xl font-black text-gray-900 dark:text-white uppercase tracking-tighter">
                                    {format(selectedDate, 'EEEE d', { locale: es })}
                                </h2>
                            </div>
                            <div className="w-12 h-12 bg-green-50 dark:bg-green-900/20 rounded-2xl flex items-center justify-center text-xl">
                                📅
                            </div>
                        </div>

                        {isLoading ? (
                            <div className="py-20 text-center">
                                <div className="w-10 h-10 border-4 border-green-600 border-t-transparent rounded-full animate-spin mx-auto mb-4" />
                                <p className="text-xs font-bold text-gray-400 uppercase tracking-widest">Actualizando...</p>
                            </div>
                        ) : bookingsForSelectedDay.length === 0 ? (
                            <div className="py-20 text-center px-4">
                                <div className="text-5xl grayscale opacity-20 mb-6">🏜️</div>
                                <p className="text-sm font-black text-gray-300 uppercase leading-relaxed italic">
                                    No tienes reservas programadas para este día.
                                </p>
                            </div>
                        ) : (
                            <div className="space-y-4">
                                {bookingsForSelectedDay.map(b => (
                                    <Link
                                        key={b.id}
                                        to={`/caregiver/reservations/${b.id}`}
                                        className="block p-5 rounded-3xl bg-gray-50 dark:bg-gray-900 border border-transparent hover:border-green-200 transition-all group"
                                    >
                                        <div className="flex items-center gap-4">
                                            <div className="w-14 h-14 bg-white dark:bg-gray-800 rounded-2xl flex items-center justify-center text-2xl shadow-sm group-hover:scale-110 transition-transform">
                                                {b.serviceType === 'HOSPEDAJE' ? '🏠' : '🦮'}
                                            </div>
                                            <div className="flex-1 min-w-0">
                                                <h3 className="font-black text-gray-900 dark:text-white uppercase tracking-tighter truncate">{b.petName}</h3>
                                                <p className="text-[10px] font-bold text-gray-500 uppercase flex items-center gap-1.5 mt-0.5">
                                                    {b.serviceType === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseo'} •
                                                    <span className="text-green-600">Bs {Number(b.totalAmount) - Number(b.commissionAmount)}</span>
                                                </p>
                                                {b.timeSlot && (
                                                    <span className="inline-block mt-2 px-2 py-0.5 bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400 text-[8px] font-black rounded-full uppercase tracking-widest">
                                                        {b.timeSlot} {b.startTime ? `(${b.startTime})` : ''}
                                                    </span>
                                                )}
                                            </div>
                                            <div className="text-gray-300 group-hover:text-green-500 transition-colors">
                                                <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M9 5l7 7-7 7" /></svg>
                                            </div>
                                        </div>
                                    </Link>
                                ))}
                            </div>
                        )}
                    </div>

                    <div className="bg-gray-900 rounded-3xl p-6 shadow-xl border border-gray-800">
                        <div className="flex items-center gap-4">
                            <div className="text-3xl">💡</div>
                            <p className="text-[11px] text-gray-300 font-medium leading-relaxed">
                                <span className="font-black text-white uppercase block mb-1">Pro Tip:</span>
                                Toca cualquier día marcado en <span className="text-green-500 font-black">verde</span> para ver rápidamente quién es el huésped y acceder a su historial completo.
                            </p>
                        </div>
                    </div>
                </section>
            </div>

            {/* Calendar Custom Styling Overrides */}
            <style dangerouslySetInnerHTML={{
                __html: `
                .react-calendar {
                    width: 100% !important;
                    background: transparent !important;
                }
                .react-calendar__tile {
                    padding: 0 !important;
                    height: auto !important;
                    min-height: 80px;
                }
                .react-calendar__month-view__days__day--neighboringMonth {
                    opacity: 0.2 !important;
                }
                .react-calendar__navigation button:enabled:hover,
                .react-calendar__navigation button:enabled:focus {
                    background-color: transparent !important;
                    color: #16a34a !important;
                }
                .react-calendar__tile:enabled:hover,
                .react-calendar__tile:enabled:focus {
                    background-color: transparent !important;
                }
                @media (max-width: 640px) {
                    .react-calendar__tile {
                        min-height: 60px;
                    }
                }
            `}} />
        </div>
    );
}


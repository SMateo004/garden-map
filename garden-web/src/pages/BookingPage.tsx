import { useState, useMemo, useEffect } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { usePublicCaregiverDetail } from '@/hooks/usePublicCaregiverDetail';
import { useCaregiverAvailability } from '@/hooks/useCaregiverAvailability';
import { useCreateBooking } from '@/hooks/useCreateBooking';
import { useAuth } from '@/contexts/AuthContext';
import { useClientMyProfile } from '@/hooks/useClientMyProfile';
import { AvailabilityCalendar } from '@/components/AvailabilityCalendar';
import { CancellationRulesTable } from '@/components/CancellationRulesTable';
import { AuthPrompt } from '@/components/AuthPrompt';
import { MascotaSelector } from '@/components/MascotaSelector';
import type { ServiceType, TimeSlot } from '@/types/caregiver';
import type { CreateBookingBody } from '@/api/bookings';
import toast from 'react-hot-toast';

const toDateString = (date: Date) => {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
};

interface BookingFormPaseo {
  timeSlot: TimeSlot;
  duration: number;
  startTime: string;
}

const timeToMins = (t: string) => {
  const [h, m] = t.split(':').map(Number);
  return h * 60 + m;
};

const rangesOverlap = (s1: number, e1: number, s2: number, e2: number) => {
  return s1 < e2 && s2 < e1;
};

export function BookingPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { isAuthenticated, user } = useAuth();
  const { data: caregiver, isLoading: loadingCaregiver } = usePublicCaregiverDetail(id);
  const { data: myProfile, isLoading: loadingClientProfile } = useClientMyProfile({
    enabled: isAuthenticated && user?.role === 'CLIENT',
  });
  const [serviceType, setServiceType] = useState<ServiceType | null>(null);
  const [selectedStartDate, setSelectedStartDate] = useState<Date | null>(null);
  const [selectedEndDate, setSelectedEndDate] = useState<Date | null>(null);
  const [selectedWalkDate, setSelectedWalkDate] = useState<Date | null>(null);
  const [selectedPetId, setSelectedPetId] = useState<string | null>(null);
  const [serverErrors, setServerErrors] = useState<{ field: string; message: string }[]>([]);

  const fromDate = useMemo(() => {
    const d = new Date();
    d.setDate(d.getDate() + 1); // Mínimo 1 día de anticipación
    return toDateString(d);
  }, []);
  const toDate = useMemo(() => {
    const d = new Date();
    d.setDate(d.getDate() + 91); // 90 días desde mañana
    return toDateString(d);
  }, []);

  const { data: availability, isLoading: loadingAvailability } = useCaregiverAvailability(
    id,
    fromDate,
    toDate
  );

  const { register, handleSubmit, watch, setValue, setError } = useForm<BookingFormPaseo>({
    defaultValues: {
      timeSlot: 'MANANA',
      duration: 30,
      startTime: '',
    },
  });

  const createBookingMutation = useCreateBooking();

  const watchedDuration = watch('duration') as number | undefined;

  // Guard: no permitir reservar si CLIENT sin perfil o con perfil de mascota incompleto
  useEffect(() => {
    if (isAuthenticated && user?.role === 'CLIENT' && !loadingClientProfile) {
      const mustComplete = !myProfile || !myProfile.isComplete;
      if (mustComplete) {
        toast.error('Completa el perfil de tu mascota para reservar');
        navigate('/profile', { replace: true, state: { returnTo: `/reservar/${id}` } });
      }
    }
  }, [isAuthenticated, user?.role, loadingClientProfile, myProfile, navigate, id]);

  // Sincronizar bloque de tiempo: seleccionar el primero disponible si el actual no existe en el día elegido
  const watchedTimeSlot = watch('timeSlot');
  useEffect(() => {
    if (serviceType !== 'PASEO' || !selectedWalkDate || !availability?.paseos) return;
    const dateStr = toDateString(selectedWalkDate);
    const slots = availability.paseos[dateStr] || [];
    const enabledSlots = slots.filter(s => s.enabled);

    if (enabledSlots.length > 0) {
      const isCurrentValid = enabledSlots.some(s => s.slot === watchedTimeSlot);
      if (!isCurrentValid) {
        setValue('timeSlot', enabledSlots[0].slot);
      }
    }
  }, [serviceType, selectedWalkDate, availability?.paseos, setValue, watchedTimeSlot]);

  // Limpiar hora de inicio cuando cambian los parámetros relevantes para invalidar selección previa
  useEffect(() => {
    setValue('startTime', '');
  }, [selectedWalkDate, watchedTimeSlot, setValue]);

  const calculatePrice = useMemo(() => {
    if (!caregiver || !serviceType) return null;
    if (serviceType === 'HOSPEDAJE') {
      if (!selectedStartDate || !selectedEndDate || !caregiver.pricePerDay) return null;
      const days = Math.ceil(
        (selectedEndDate.getTime() - selectedStartDate.getTime()) / (24 * 60 * 60 * 1000)
      );
      return days * caregiver.pricePerDay;
    }
    if (serviceType === 'PASEO') {
      const duration = watchedDuration ?? 30;
      const hourlyRate = caregiver.pricePerWalk60 || (caregiver.pricePerWalk30 ? caregiver.pricePerWalk30 * 2 : null);

      if (!hourlyRate) return null;

      // Si la duración es exactamente 30 min y existe precio30, usarlo directamente por si no es exactamente la mitad
      if (duration === 30 && caregiver.pricePerWalk30) return caregiver.pricePerWalk30;

      return (hourlyRate * duration) / 60;
    }
    return null;
  }, [caregiver, serviceType, selectedStartDate, selectedEndDate, watchedDuration]);

  const onSubmit = async (data: BookingFormPaseo) => {
    if (!id || !isAuthenticated) {
      toast.error('Debes iniciar sesión para reservar');
      return;
    }
    if (!serviceType) {
      toast.error('Selecciona un tipo de servicio');
      return;
    }
    if (!selectedPetId) {
      toast.error('Selecciona la mascota para la reserva');
      return;
    }

    let body: CreateBookingBody;
    if (serviceType === 'HOSPEDAJE') {
      if (!selectedStartDate || !selectedEndDate) {
        toast.error('Selecciona fechas de inicio y fin');
        return;
      }
      const days = Math.ceil(
        (selectedEndDate.getTime() - selectedStartDate.getTime()) / (24 * 60 * 60 * 1000)
      );
      body = {
        serviceType: 'HOSPEDAJE',
        caregiverId: id,
        petId: selectedPetId,
        startDate: selectedStartDate.toISOString().slice(0, 10),
        endDate: selectedEndDate.toISOString().slice(0, 10),
        totalDays: days,
      };
    } else {
      if (!selectedWalkDate) {
        toast.error('Selecciona una fecha para el paseo');
        return;
      }
      if (!data.startTime) {
        toast.error('Selecciona la hora específica para el paseo');
        return;
      }
      body = {
        serviceType: 'PASEO',
        caregiverId: id,
        petId: selectedPetId,
        walkDate: toDateString(selectedWalkDate),
        timeSlot: data.timeSlot,
        duration: data.duration,
        startTime: data.startTime,
      };
    }

    setServerErrors([]);
    try {
      const res = await createBookingMutation.mutateAsync(body);
      if (res.success && res.data) {
        navigate(`/booking/${res.data.id}/confirm`, { state: { booking: res.data } });
      }
    } catch (err: unknown) {
      const ax = err as {
        response?: {
          status: number;
          data?: {
            message?: string;
            error?: { message?: string };
            errors?: { field: string; message: string }[];
          };
        };
      };
      const status = ax.response?.status;
      const data = ax.response?.data;

      const fallbackMessage =
        'Selecciona tipo de servicio (HOSPEDAJE o PASEO) y completa todos los campos requeridos';

      if (status === 400 || status === 409) {
        const serverErrors = Array.isArray(data?.errors) ? data.errors : [];
        if (serverErrors.length > 0) {
          const finalMessage = (msg: string) =>
            msg.includes('Invalid input') || msg.includes('union')
              ? 'Debes seleccionar HOSPEDAJE o PASEO y completar todos los campos para ese tipo'
              : msg;
          const normalized = serverErrors.map((e: { field: string; message: string }) => ({
            field: e.field,
            message: finalMessage(e.message),
          }));
          normalized.forEach((e: { field: string; message: string }) => {
            try {
              setError(e.field as 'timeSlot' | 'duration', { type: 'manual', message: e.message });
            } catch {
              /* campo no existe en el formulario */
            }
            toast.error(`${e.field}: ${e.message}`);
          });
          setServerErrors(normalized);
          return;
        }
        const msg =
          data?.message ||
          data?.error?.message ||
          fallbackMessage;
        toast.error(msg);
        setServerErrors([{ field: 'general', message: msg }]);
        return;
      }

      if (status === 403) {
        const msg = data?.message ?? data?.error?.message ?? 'No tienes permiso para esta acción.';
        toast.error(msg);
        setServerErrors([{ field: 'general', message: msg }]);
        return;
      }

      toast.error('Error al confirmar reserva. Intenta más tarde.');
      setServerErrors([{ field: 'general', message: 'Error al confirmar reserva. Intenta más tarde.' }]);
    }
  };

  if (loadingCaregiver || (isAuthenticated && user?.role === 'CLIENT' && loadingClientProfile)) {
    return (
      <div className="py-12 text-center text-gray-500">Cargando información...</div>
    );
  }

  if (!caregiver) {
    return (
      <div className="rounded-lg bg-red-50 p-4 text-red-700">
        <p>No se encontró el cuidador.</p>
        <Link to="/" className="mt-2 inline-block underline">Volver al listado</Link>
      </div>
    );
  }

  if (!isAuthenticated) {
    return (
      <div className="mx-auto max-w-4xl px-4 py-6 sm:px-6 lg:px-8">
        <Link to={`/caregivers/${id}`} className="text-sm text-green-600 hover:underline">
          ← Volver al perfil
        </Link>
        <AuthPrompt
          title="Para reservar debes iniciar sesión o registrarte como Dueño"
          subtitle="Necesitas una cuenta de cliente para realizar una reserva"
          returnTo={`/reservar/${id}`}
          onAuthSuccess={() => {
            // El guard en useEffect verificará el perfil automáticamente
          }}
        />
      </div>
    );
  }

  const availableServices = caregiver.services;
  const hasHospedaje = availableServices.includes('HOSPEDAJE');
  const hasPaseo = availableServices.includes('PASEO');

  return (
    <div className="mx-auto max-w-4xl space-y-6 px-4 py-6 sm:px-6 lg:px-8">
      <Link to={`/caregivers/${id}`} className="text-sm text-green-600 hover:underline">
        ← Volver al perfil
      </Link>
      <h1 className="text-2xl font-bold text-gray-900">
        Reservar con {caregiver.firstName} {caregiver.lastName}
      </h1>

      <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
        {/* Selección de servicio */}
        <div className="rounded-xl border border-gray-200 bg-white p-4">
          <h2 className="mb-3 text-sm font-semibold text-gray-900">Tipo de servicio</h2>
          <div className="flex flex-wrap gap-3">
            {hasHospedaje && (
              <button
                type="button"
                onClick={() => {
                  setServiceType('HOSPEDAJE');
                  setSelectedStartDate(null);
                  setSelectedEndDate(null);
                }}
                className={`rounded-lg border-2 px-4 py-2 text-sm font-medium transition ${serviceType === 'HOSPEDAJE'
                  ? 'border-green-600 bg-green-50 text-green-700'
                  : 'border-gray-200 bg-white text-gray-700 hover:border-gray-300'
                  }`}
              >
                Hospedaje
                {caregiver.pricePerDay && (
                  <span className="ml-2 text-xs text-gray-500">Bs {caregiver.pricePerDay}/día</span>
                )}
              </button>
            )}
            {hasPaseo && (
              <button
                type="button"
                onClick={() => {
                  setServiceType('PASEO');
                  setSelectedWalkDate(null);
                }}
                className={`rounded-lg border-2 px-4 py-2 text-sm font-medium transition ${serviceType === 'PASEO'
                  ? 'border-green-600 bg-green-50 text-green-700'
                  : 'border-gray-200 bg-white text-gray-700 hover:border-gray-300'
                  }`}
              >
                Paseo
                {(caregiver.pricePerWalk30 || caregiver.pricePerWalk60) && (
                  <span className="ml-2 text-xs text-gray-500">
                    Bs {caregiver.pricePerWalk30 ?? caregiver.pricePerWalk60}/30min
                  </span>
                )}
              </button>
            )}
          </div>
        </div>

        {/* Calendario y selección de fechas */}
        {serviceType && (
          <div className="space-y-4">
            {serviceType === 'HOSPEDAJE' ? (
              <AvailabilityCalendar
                availability={availability ?? null}
                serviceType="HOSPEDAJE"
                selectRange
                selectedRange={[selectedStartDate, selectedEndDate]}
                onRangeChange={(range) => {
                  setSelectedStartDate(range[0]);
                  setSelectedEndDate(range[1]);
                }}
                disabled={loadingAvailability}
              />
            ) : (
              <>
                <AvailabilityCalendar
                  availability={availability ?? null}
                  serviceType="PASEO"
                  selectedDate={selectedWalkDate}
                  onDateChange={setSelectedWalkDate}
                  disabled={loadingAvailability}
                />
                {selectedWalkDate && availability?.paseos[toDateString(selectedWalkDate)] && (
                  <div className="rounded-xl border border-gray-200 bg-white p-4">
                    <h3 className="mb-3 text-sm font-semibold text-gray-900">Bloque de tiempo</h3>
                    <div className="flex flex-wrap gap-3">
                      {availability.paseos[toDateString(selectedWalkDate)]
                        .filter(s => s.enabled)
                        .map((slotInfo) => (
                          <label
                            key={slotInfo.slot}
                            className="flex cursor-pointer items-center gap-2 rounded-lg border border-gray-300 p-3 hover:bg-gray-50 has-[:checked]:border-green-600 has-[:checked]:bg-green-50"
                          >
                            <input
                              type="radio"
                              value={slotInfo.slot}
                              {...register('timeSlot', { required: serviceType === 'PASEO' })}
                              className="h-4 w-4 text-green-600"
                            />
                            <div className="flex flex-col">
                              <span className="text-sm font-medium">
                                {slotInfo.slot === 'MANANA' ? 'Mañana' : slotInfo.slot === 'TARDE' ? 'Tarde' : 'Noche'}
                              </span>
                              {slotInfo.start && (
                                <span className="text-xs text-gray-500">
                                  {slotInfo.start} {slotInfo.end ? `- ${slotInfo.end}` : ''}
                                </span>
                              )}
                            </div>
                          </label>
                        ))
                      }
                    </div>
                    {/* Selector de hora específica dinámico - AHORA PRIMERO */}
                    <div className="mt-5 border-t border-gray-100 pt-4">
                      <div className="mb-3 flex items-center justify-between">
                        <div className="flex flex-col">
                          <h4 className="text-sm font-bold text-gray-900">1. ¿A qué hora iniciará el paseo?</h4>
                          <p className="text-[10px] text-gray-500 italic leading-tight">Mostrando horarios disponibles en este bloque</p>
                        </div>
                        <span className="flex items-center gap-1 text-[10px] text-gray-400">
                          <span className="h-2 w-2 rounded-full bg-gray-200"></span>
                          Ocupado / Descanso
                        </span>
                      </div>

                      <div className="grid grid-cols-4 gap-2 sm:grid-cols-6 lg:grid-cols-8">
                        {(() => {
                          const watchedSlot = watch('timeSlot');
                          const watchedStartTime = watch('startTime');
                          const dStr = toDateString(selectedWalkDate);
                          const block = availability?.paseos[dStr]?.find(s => s.slot === watchedSlot);

                          if (!block?.start || !block?.end) {
                            return <p className="col-span-full text-xs text-gray-500 italic">No se definió un rango horario para este bloque.</p>;
                          }

                          const startM = timeToMins(block.start || '00:00');
                          const endM = timeToMins(block.end || '23:59');
                          const booked = availability?.bookedPaseos?.filter(b => b.date === dStr) || [];
                          const options = [];

                          // Un horario 'm' es elegible si cabe AL MENOS un paseo de 30 min + 30 min de descanso
                          for (let m = startM; m <= endM - 30; m += 30) {
                            const hh = Math.floor(m / 60).toString().padStart(2, '0');
                            const mm = (m % 60).toString().padStart(2, '0');
                            const ts = `${hh}:${mm}`;

                            // ¿Cabe un paseo de 30 min?
                            const isBusy30 = booked.some(b => {
                              const bS = timeToMins(b.startTime || '00:00');
                              const bDur = b.duration || 60;
                              const bE = bS + bDur + 30; // Fin de reserva previa + descanso

                              // El nuevo paseo (hipotético 30m) ocuparía [m, m + 30 + 30]
                              return rangesOverlap(m, m + 60, bS, bE);
                            });

                            options.push(
                              <button
                                key={ts}
                                type="button"
                                disabled={isBusy30}
                                onClick={() => setValue('startTime', ts)}
                                className={`rounded-lg border py-2 text-center text-xs font-medium transition-all ${watchedStartTime === ts
                                  ? 'border-green-600 bg-green-600 text-white shadow-md scale-105'
                                  : isBusy30
                                    ? 'bg-gray-50 text-gray-300 line-through border-gray-100'
                                    : 'bg-white text-gray-700 hover:border-green-400 hover:bg-green-50 border-gray-200'
                                  }`}
                              >
                                {ts}
                              </button>
                            );
                          }
                          return options.length > 0 ? options : <p className="col-span-full text-xs text-red-500 text-center py-4">No hay cupos disponibles en este bloque.</p>;
                        })()}
                      </div>
                    </div>

                    {/* Selector de Duración - AHORA SEGUNDO Y DEPENDE DE LA HORA */}
                    {watch('startTime') && (
                      <div className="mt-5 border-t border-gray-100 pt-4 animate-in fade-in slide-in-from-top-2">
                        <h4 className="mb-3 text-sm font-bold text-gray-900">2. ¿Cuánto tiempo durará el paseo?</h4>
                        <div className="flex flex-wrap gap-4">
                          {(() => {
                            const watchedSlot = watch('timeSlot');
                            const watchedStartTime = watch('startTime');
                            const watchedDuration = watch('duration');
                            const dStr = toDateString(selectedWalkDate);
                            const block = availability?.paseos[dStr]?.find(s => s.slot === watchedSlot);
                            if (!block) return null;

                            const startM = timeToMins(watchedStartTime || '00:00');
                            const endM = timeToMins(block.end || '23:59');
                            const booked = availability?.bookedPaseos?.filter(b => b.date === dStr) || [];

                            const durations = [30, 60, 90, 120, 150, 180, 240, 300, 360, 420, 480];
                            const hourlyRate = caregiver.pricePerWalk60 || (caregiver.pricePerWalk30 ? caregiver.pricePerWalk30 * 2 : 0);

                            return durations.map(dur => {
                              // Calcular precio para esta duración específica
                              let durPrice = 0;
                              if (dur === 30 && caregiver.pricePerWalk30) {
                                durPrice = caregiver.pricePerWalk30;
                              } else if (hourlyRate > 0) {
                                durPrice = (hourlyRate * dur) / 60;
                              } else {
                                return null; // No hay precio base
                              }

                              // Verificar si esta duración cabe (incluyendo buffer de 30 min)
                              const fitsInBlock = startM + dur <= endM;
                              const conflicts = booked.some(b => {
                                const bS = timeToMins(b.startTime || '00:00');
                                const bE = bS + b.duration + 30;
                                return rangesOverlap(startM, startM + dur + 30, bS, bE);
                              });

                              const isAvailable = fitsInBlock && !conflicts;

                              const label = dur < 60 ? `${dur} min` : (dur % 60 === 0 ? `${dur / 60} h` : `${Math.floor(dur / 60)}h 30m`);

                              return (
                                <label
                                  key={dur}
                                  onClick={isAvailable ? () => setValue('duration', dur) : undefined}
                                  className={`flex min-w-[80px] flex-1 cursor-pointer items-center justify-center gap-2 rounded-xl border-2 p-3 text-center transition-all ${watchedDuration === dur
                                    ? 'border-green-600 bg-green-50 ring-1 ring-green-600'
                                    : isAvailable
                                      ? 'border-gray-200 bg-white hover:border-green-300'
                                      : 'opacity-40 grayscale cursor-not-allowed bg-gray-50 border-gray-100'
                                    }`}
                                >
                                  <input
                                    type="radio"
                                    value={dur}
                                    {...register('duration', { valueAsNumber: true })}
                                    checked={watchedDuration === dur}
                                    className="hidden"
                                  />
                                  <div className="flex flex-col">
                                    <span className={`text-xs font-bold leading-tight ${watchedDuration === dur ? 'text-green-700' : 'text-gray-900'}`}>{label}</span>
                                    <span className="text-[10px] text-gray-500 font-medium">Bs {durPrice}</span>
                                  </div>
                                </label>
                              );
                            });
                          })()}
                        </div>
                        <p className="mt-4 text-[10px] italic text-gray-400">
                          * Nota: El sistema bloquea automáticamente 30 min después de cada paseo para el descanso del cuidador (sin costo adicional).
                        </p>
                      </div>
                    )}
                  </div>
                )}
              </>
            )}
          </div>
        )}

        {/* Selección de mascota */}
        {serviceType && isAuthenticated && user?.role === 'CLIENT' && (
          <MascotaSelector
            value={selectedPetId}
            onChange={setSelectedPetId}
            returnTo={id ? `/reservar/${id}` : '/'}
            disabled={false}
          />
        )}

        {/* Resumen de precio */}
        {serviceType && calculatePrice !== null && (
          <div className="rounded-xl border border-gray-200 bg-green-50 p-4">
            <h2 className="mb-2 text-sm font-semibold text-gray-900">Resumen</h2>
            <div className="space-y-1 text-sm">
              {serviceType === 'HOSPEDAJE' && selectedStartDate && selectedEndDate && (
                <>
                  <div className="flex justify-between">
                    <span className="text-gray-600">
                      {Math.ceil(
                        (selectedEndDate.getTime() - selectedStartDate.getTime()) / (24 * 60 * 60 * 1000)
                      )}{' '}
                      día(s) × Bs {caregiver.pricePerDay}
                    </span>
                    <span className="font-medium text-gray-900">Bs {calculatePrice}</span>
                  </div>
                </>
              )}
              {serviceType === 'PASEO' && watchedDuration && (
                <div className="flex justify-between">
                  <span className="text-gray-600">
                    Paseo {watchedDuration} min
                  </span>
                  <span className="font-medium text-gray-900">Bs {calculatePrice}</span>
                </div>
              )}
              <div className="mt-2 border-t border-green-200 pt-2">
                <div className="flex justify-between font-semibold text-gray-900">
                  <span>Total</span>
                  <span>Bs {calculatePrice}</span>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Reglas de cancelación */}
        <CancellationRulesTable />

        {/* Los campos ocultos para RHF que no tienen inputs visibles directos */}
        <input type="hidden" {...register('startTime', { required: serviceType === 'PASEO' })} />

        {/* Errores del servidor (400/409) */}
        {serverErrors.length > 0 && (
          <div
            className="rounded-xl border border-amber-200 bg-amber-50 p-5 mb-6 shadow-sm"
            role="alert"
          >
            <div className="flex items-center gap-3 mb-3">
              <svg
                className="w-6 h-6 text-amber-600 shrink-0"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                />
              </svg>
              <p className="font-medium text-amber-800">Corrige lo siguiente:</p>
            </div>
            <ul className="list-disc pl-6 text-amber-800 space-y-1.5">
              {serverErrors.map((err, i) => (
                <li key={i} className="text-sm">
                  {err.message}
                </li>
              ))}
            </ul>
          </div>
        )}

        {/* Botón submit */}
        {serviceType && (
          <button
            type="submit"
            disabled={
              createBookingMutation.isPending ||
              !serviceType ||
              calculatePrice === null ||
              !selectedPetId
            }
            className="w-full rounded-lg bg-green-600 px-6 py-3 font-medium text-white hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {createBookingMutation.isPending ? 'Creando reserva...' : 'Confirmar reserva'}
          </button>
        )}
      </form>
    </div>
  );
}

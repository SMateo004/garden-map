import { useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useBooking } from '@/hooks/useBooking';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { acceptBooking, rejectBooking } from '@/api/bookings';
import toast from 'react-hot-toast';

function getStatusBadge(status: string) {
    const statusMap: Record<string, { label: string; className: string }> = {
        WAITING_CAREGIVER_APPROVAL: { label: 'Esperando tu aprobación', className: 'bg-amber-100 text-amber-800 border-amber-200' },
        CONFIRMED: { label: 'Confirmada', className: 'bg-green-100 text-green-800 border-green-200' },
        IN_PROGRESS: { label: 'En curso', className: 'bg-blue-100 text-blue-800 border-blue-200' },
        COMPLETED: { label: 'Completada', className: 'bg-gray-100 text-gray-800 border-gray-200' },
        CANCELLED: { label: 'Cancelada', className: 'bg-red-100 text-red-800 border-red-200' },
    };
    const statusInfo = statusMap[status] || { label: status, className: 'bg-gray-50 text-gray-600 border-gray-100' };
    return (
        <span className={`inline-flex rounded-full px-3 py-1 text-xs font-black uppercase tracking-widest border ${statusInfo.className}`}>
            {statusInfo.label}
        </span>
    );
}

export function CaregiverBookingDetailPage() {
    const { id } = useParams<{ id: string }>();
    const queryClient = useQueryClient();
    const { data: booking, isLoading, error } = useBooking(id);

    const [showRejectModal, setShowRejectModal] = useState(false);
    const [rejectReason, setRejectReason] = useState('');

    const acceptMutation = useMutation({
        mutationFn: (bookingId: string) => acceptBooking(bookingId),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['booking', id] });
            toast.success('¡Reserva aceptada!');
        },
        onError: (e: Error) => toast.error(e.message),
    });

    const rejectMutation = useMutation({
        mutationFn: (params: { id: string; reason: string }) => rejectBooking(params.id, { reason: params.reason }),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['booking', id] });
            toast.success('Reserva rechazada.');
            setShowRejectModal(false);
        },
        onError: (e: Error) => toast.error(e.message),
    });

    if (isLoading) {
        return (
            <div className="mx-auto max-w-4xl px-4 py-12 flex flex-col items-center">
                <div className="w-12 h-12 border-4 border-green-600 border-t-transparent rounded-full animate-spin mb-4" />
                <p className="text-gray-500 font-bold uppercase tracking-widest text-[10px]">Cargando reserva...</p>
            </div>
        );
    }

    if (error || !booking) {
        return (
            <div className="mx-auto max-w-2xl px-4 py-12">
                <div className="rounded-3xl border border-red-100 bg-red-50 p-8 text-center">
                    <p className="text-red-800 font-black uppercase tracking-tighter text-xl mb-4">¡Ups! Algo salió mal</p>
                    <p className="text-red-600 text-sm mb-6">{error instanceof Error ? error.message : 'No pudimos encontrar esta reserva.'}</p>
                    <Link to="/caregiver/dashboard" className="px-6 py-3 bg-red-600 text-white rounded-2xl font-black text-xs uppercase tracking-widest hover:bg-red-700 transition-colors inline-block">
                        Volver al Dashboard
                    </Link>
                </div>
            </div>
        );
    }

    const isHospedaje = booking.serviceType === 'HOSPEDAJE';
    const netEarnings = Number(booking.totalAmount) - Number(booking.commissionAmount);

    return (
        <div className="mx-auto max-w-4xl px-4 py-10 pb-20">

            {/* Header */}
            <div className="mb-10 flex flex-col md:flex-row md:items-end justify-between gap-6">
                <div>
                    <Link to="/caregiver/dashboard" className="text-xs font-black text-gray-400 hover:text-green-600 transition-colors uppercase tracking-widest flex items-center gap-2 mb-4">
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M15 19l-7-7 7-7" /></svg>
                        Volver al Dashboard
                    </Link>
                    <h1 className="text-4xl font-black text-gray-900 dark:text-white uppercase tracking-tighter leading-none">
                        Detalle de <span className="text-green-600">Servicio</span>
                    </h1>
                    <p className="mt-2 text-xs font-bold text-gray-400 uppercase tracking-widest">Reserva #{booking.id.split('-')[0].toUpperCase()}</p>
                </div>
                <div className="flex flex-col items-end gap-3">
                    {getStatusBadge(booking.status)}
                    <div className="bg-white dark:bg-gray-800 px-6 py-4 rounded-3xl border border-gray-100 dark:border-gray-700 shadow-sm text-right">
                        <p className="text-[10px] font-black text-gray-400 uppercase tracking-widest mb-1">Tu ganancia neta</p>
                        <p className="text-3xl font-black text-green-600">Bs {netEarnings.toFixed(2)}</p>
                    </div>
                </div>
            </div>

            <div className="grid md:grid-cols-3 gap-8">

                {/* Left Col: Main Details */}
                <div className="md:col-span-2 space-y-8">

                    {/* Pet Info */}
                    <section className="bg-white dark:bg-gray-800 rounded-[2.5rem] p-8 shadow-sm border border-gray-50 dark:border-gray-700">
                        <h2 className="text-xl font-black text-gray-900 dark:text-white mb-6 italic">🐾 Mascota a cuidar</h2>
                        <div className="flex items-center gap-6">
                            <div className="w-24 h-24 bg-green-50 rounded-3xl flex items-center justify-center text-4xl shadow-inner">🐶</div>
                            <div>
                                <h3 className="text-2xl font-black text-gray-900 dark:text-white uppercase tracking-tighter">{booking.petName}</h3>
                                <div className="flex flex-wrap gap-2 mt-2">
                                    {booking.petBreed && <span className="px-3 py-1 bg-gray-100 dark:bg-gray-700 rounded-full text-[10px] font-black uppercase text-gray-500 tracking-widest">{booking.petBreed}</span>}
                                    {booking.petAge != null && <span className="px-3 py-1 bg-gray-100 dark:bg-gray-700 rounded-full text-[10px] font-black uppercase text-gray-500 tracking-widest">{booking.petAge} años</span>}
                                </div>
                            </div>
                        </div>

                        {booking.specialNeeds && (
                            <div className="mt-8 p-6 bg-amber-50 dark:bg-amber-900/10 rounded-3xl border border-amber-100 dark:border-amber-900/30">
                                <p className="text-[10px] font-black text-amber-700 uppercase tracking-widest mb-2">⚠️ Notas Especiales / Cuidados</p>
                                <p className="text-sm text-amber-900 dark:text-amber-200 font-medium leading-relaxed">{booking.specialNeeds}</p>
                            </div>
                        )}
                    </section>

                    {/* Service Details */}
                    <section className="bg-white dark:bg-gray-800 rounded-[2.5rem] p-8 shadow-sm border border-gray-50 dark:border-gray-700">
                        <h2 className="text-xl font-black text-gray-900 dark:text-white mb-6 italic">📅 Detalles del Servicio</h2>
                        <div className="grid grid-cols-2 gap-6">
                            <div>
                                <p className="text-[10px] font-black text-gray-400 uppercase tracking-widest mb-1">Tipo de Servicio</p>
                                <p className="text-lg font-black text-gray-800 dark:text-gray-100 uppercase">{isHospedaje ? 'Hospedaje 🏠' : 'Paseo 🦮'}</p>
                            </div>

                            {isHospedaje ? (
                                <>
                                    <div>
                                        <p className="text-[10px] font-black text-gray-400 uppercase tracking-widest mb-1">Entrada / Salida</p>
                                        <p className="text-lg font-black text-gray-800 dark:text-gray-100 uppercase">{booking.startDate} • {booking.endDate}</p>
                                    </div>
                                    <div>
                                        <p className="text-[10px] font-black text-gray-400 uppercase tracking-widest mb-1">Duración Total</p>
                                        <p className="text-lg font-black text-gray-800 dark:text-gray-100 uppercase">{booking.totalDays} noches</p>
                                    </div>
                                </>
                            ) : (
                                <>
                                    <div>
                                        <p className="text-[10px] font-black text-gray-400 uppercase tracking-widest mb-1">Fecha del Paseo</p>
                                        <p className="text-lg font-black text-gray-800 dark:text-gray-100 uppercase">{booking.walkDate}</p>
                                    </div>
                                    <div>
                                        <p className="text-[10px] font-black text-gray-400 uppercase tracking-widest mb-1">Bloque / Hora</p>
                                        <p className="text-lg font-black text-gray-800 dark:text-gray-100 uppercase">
                                            {booking.timeSlot === 'MANANA' ? 'Mañana' : booking.timeSlot === 'TARDE' ? 'Tarde' : 'Noche'}
                                            {booking.startTime && ` (${booking.startTime})`}
                                        </p>
                                    </div>
                                </>
                            )}
                        </div>
                    </section>
                </div>

                {/* Right Col: Client & Actions */}
                <div className="space-y-8">

                    {/* Actions */}
                    {booking.status === 'WAITING_CAREGIVER_APPROVAL' && (
                        <section className="bg-green-600 rounded-[2rem] p-8 shadow-xl shadow-green-100 dark:shadow-none text-white">
                            <h2 className="text-xl font-black mb-6 uppercase tracking-tight italic">Acciones Requeridas</h2>
                            <div className="space-y-3">
                                <button
                                    onClick={() => acceptMutation.mutate(booking.id)}
                                    disabled={acceptMutation.isPending}
                                    className="w-full py-4 bg-white text-green-600 rounded-2xl font-black text-xs uppercase tracking-widest hover:scale-[1.02] active:scale-95 transition-all shadow-md disabled:opacity-50"
                                >
                                    {acceptMutation.isPending ? 'Aceptando...' : 'Aceptar Reserva ✅'}
                                </button>
                                <button
                                    onClick={() => setShowRejectModal(true)}
                                    className="w-full py-4 bg-green-700/50 text-white rounded-2xl font-black text-xs uppercase tracking-widest hover:bg-green-700 transition-all border border-green-400/30"
                                >
                                    Rechazar Reserva ❌
                                </button>
                            </div>
                        </section>
                    )}

                    {/* Owner Info */}
                    <section className="bg-white dark:bg-gray-800 rounded-[2.5rem] p-8 shadow-sm border border-gray-50 dark:border-gray-700">
                        <h2 className="text-xl font-black text-gray-900 dark:text-white mb-6 italic">👤 Dueño</h2>
                        <div className="space-y-4">
                            <div>
                                <p className="text-[9px] font-black text-gray-400 uppercase tracking-widest mb-1">Nombre Completo</p>
                                <p className="text-sm font-black text-gray-800 dark:text-gray-100 uppercase">{booking.clientName || '—'}</p>
                            </div>
                            <div>
                                <p className="text-[9px] font-black text-gray-400 uppercase tracking-widest mb-1">Email</p>
                                <p className="text-sm font-bold text-gray-600">{booking.clientEmail || '—'}</p>
                            </div>
                            {booking.clientPhone && (
                                <div>
                                    <p className="text-[9px] font-black text-gray-400 uppercase tracking-widest mb-1">Teléfono / WhatsApp</p>
                                    <a
                                        href={`https://wa.me/${booking.clientPhone.replace(/\D/g, '')}`}
                                        target="_blank"
                                        className="inline-flex items-center gap-2 px-4 py-2 bg-green-50 dark:bg-green-900/20 text-green-700 rounded-xl font-black text-[10px] uppercase tracking-widest hover:bg-green-100 transition-all"
                                    >
                                        💬 Contactar ahora
                                    </a>
                                </div>
                            )}
                        </div>
                    </section>

                    {/* Financial Breakdown */}
                    <section className="bg-gray-50 dark:bg-gray-800/50 rounded-[2rem] p-6 border border-gray-100 dark:border-gray-700">
                        <div className="space-y-2">
                            <div className="flex justify-between text-[10px] font-bold text-gray-400 uppercase">
                                <span>Monto Total Cliente</span>
                                <span>Bs {booking.totalAmount}</span>
                            </div>
                            <div className="flex justify-between text-[10px] font-bold text-red-400 uppercase border-b border-gray-100 dark:border-gray-700 pb-2">
                                <span>Comisión GARDEN</span>
                                <span>- Bs {booking.commissionAmount}</span>
                            </div>
                            <div className="flex justify-between pt-2 text-xs font-black text-green-600 uppercase">
                                <span>Tu Pago Final</span>
                                <span>Bs {netEarnings.toFixed(2)}</span>
                            </div>
                        </div>
                    </section>

                </div>
            </div>

            {/* Reject Modal */}
            {showRejectModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-gray-900/60 backdrop-blur-sm p-4">
                    <div className="bg-white dark:bg-gray-800 rounded-[2.5rem] p-8 max-w-md w-full shadow-2xl animate-in zoom-in-95 duration-200">
                        <h3 className="text-2xl font-black text-gray-900 dark:text-white uppercase tracking-tighter mb-4 italic">Rechazar Reserva</h3>
                        <p className="text-sm text-gray-500 font-medium mb-6">Indica el motivo del rechazo. Este mensaje será enviado al dueño de la mascota.</p>

                        <textarea
                            className="w-full bg-gray-50 dark:bg-gray-700 border-none rounded-3xl p-5 text-sm font-medium focus:ring-2 focus:ring-red-500 mb-6 placeholder:text-gray-300 h-32"
                            placeholder="Ej: Lo siento, me surgió una emergencia familiar..."
                            value={rejectReason}
                            onChange={e => setRejectReason(e.target.value)}
                        />

                        <div className="flex gap-3">
                            <button
                                onClick={() => setShowRejectModal(false)}
                                className="flex-1 py-4 bg-gray-100 dark:bg-gray-700 text-gray-500 rounded-2xl font-black text-[10px] uppercase tracking-widest hover:bg-gray-200"
                            >
                                Volver
                            </button>
                            <button
                                disabled={!rejectReason.trim() || rejectMutation.isPending}
                                onClick={() => rejectMutation.mutate({ id: booking.id, reason: rejectReason.trim() })}
                                className="flex-[2] py-4 bg-red-600 text-white rounded-2xl font-black text-[10px] uppercase tracking-widest hover:bg-red-700 disabled:opacity-50"
                            >
                                {rejectMutation.isPending ? 'Procesando...' : 'Confirmar Rechazo'}
                            </button>
                        </div>
                    </div>
                </div>
            )}

        </div>
    );
}

import { Link, useNavigate } from 'react-router-dom';
import { useNotifications, useMarkNotificationRead, useMarkAllNotificationsRead } from '@/hooks/useNotifications';
import { useAuth } from '@/contexts/AuthContext';
import { useEffect, useState } from 'react';
import { getMyProfile, type MyProfileResponse } from '@/api/caregiverProfile';
import { formatDistanceToNow } from 'date-fns';
import { es } from 'date-fns/locale';
import { NotificationModal } from '@/components/NotificationModal';

const WELCOME_MESSAGE = {
    greeting: '¡Bienvenido a GARDEN!',
    intro: 'Gracias por registrarte como cuidador. Tu solicitud será revisada por nuestro equipo en 24-48 horas.',
    reviewProcess: 'Proceso de revisión: Revisaremos tu perfil, fotos y disponibilidad. Te notificaremos por email cuando esté aprobado.',
    action: 'Para acelerar la revisión, completa tu perfil al 100%:',
    steps: [
        'Información personal: foto de perfil, datos de contacto y verificación',
        'Perfil de cuidador: responde el cuestionario completo con tu experiencia y preferencias',
        'Mi disponibilidad: indica en qué días y horarios puedes recibir mascotas',
    ],
    cta: 'Completar mi perfil',
};

const APPROVED_MESSAGE = {
    greeting: '¡Felicidades!',
    intro: 'Tu perfil ha sido aprobado y ya es visible para los dueños de mascotas.',
    reviewProcess: '¡Ya puedes empezar a recibir solicitudes de reserva! Mantén tu calendario actualizado para mejores resultados.',
    action: 'Pasos recomendados para tener más éxito:',
    steps: [
        'Verifica tu disponibilidad frecuentemente en "Mi disponibilidad"',
        'Asegúrate de que tus fotos de espacio sean atractivas',
        'Responde rápido a los mensajes de los dueños para mejorar tu ranking',
    ],
    cta: 'Ver mi perfil público',
};

export function InboxPage() {
    const navigate = useNavigate();
    const { isCaregiver } = useAuth();
    const { data: notifications = [], isLoading: loadingNotifs, error } = useNotifications();
    const markRead = useMarkNotificationRead();
    const markAllRead = useMarkAllNotificationsRead();

    const [profile, setProfile] = useState<MyProfileResponse | null>(null);
    const [loadingProfile, setLoadingProfile] = useState(false);
    const [selectedNotification, setSelectedNotification] = useState<any | null>(null);

    useEffect(() => {
        if (isCaregiver) {
            setLoadingProfile(true);
            getMyProfile()
                .then(setProfile)
                .finally(() => setLoadingProfile(false));
        }
    }, [isCaregiver]);

    const handleNotificationClick = (n: any) => {
        setSelectedNotification(n);
        if (!n.read) {
            markRead.mutate(n.id);
        }
    };

    if (loadingNotifs || loadingProfile) {
        return (
            <div className="mx-auto max-w-4xl px-4 py-10 text-center text-slate-500">
                <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-green-600 mx-auto mb-4"></div>
                Cargando buzón…
            </div>
        );
    }

    if (error) {
        return (
            <div className="mx-auto max-w-4xl px-4 py-8">
                <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-red-800 shadow-sm">
                    Error al cargar el buzón: {error instanceof Error ? error.message : 'Error desconocido'}
                </div>
            </div>
        );
    }

    const unreadCount = notifications.filter((n) => !n.read).length;
    const isApproved = profile?.status === 'APPROVED';
    const caregiverContent = isApproved ? APPROVED_MESSAGE : WELCOME_MESSAGE;

    return (
        <div className="mx-auto max-w-4xl px-4 py-8">
            <div className="mb-8 flex flex-col sm:flex-row sm:items-end justify-between gap-4">
                <div>
                    <Link
                        to={isCaregiver ? "/caregiver/dashboard" : "/profile"}
                        className="text-sm font-medium text-slate-600 hover:text-slate-900 transition-colors"
                    >
                        ← {isCaregiver ? 'Volver al panel' : 'Volver al perfil'}
                    </Link>
                    <h1 className="mt-2 text-3xl font-extrabold text-slate-900 flex items-center gap-3">
                        <svg className="w-8 h-8 text-slate-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                        </svg>
                        Buzón
                    </h1>
                    <p className="mt-1 text-slate-600">
                        {isCaregiver
                            ? 'Mensajes y actualizaciones sobre tu cuenta de cuidador y reservas.'
                            : 'Información importante sobre tus mascotas y reservas.'}
                    </p>
                </div>
                {unreadCount > 0 && (
                    <button
                        onClick={() => markAllRead.mutate()}
                        className="text-sm font-bold text-green-600 hover:text-green-700 transition-colors"
                    >
                        Marcar todo como leído
                    </button>
                )}
            </div>

            {/* Bloque especial para cuidadores (Onboarding/Tips) */}
            {isCaregiver && profile && (
                <div className="mb-8 rounded-2xl border border-green-100 bg-white shadow-sm overflow-hidden">
                    <div className="bg-green-50/50 p-6">
                        <h2 className="text-xl font-bold text-slate-900 mb-3">{caregiverContent.greeting}</h2>
                        <p className="text-slate-700 leading-relaxed mb-4">{caregiverContent.intro}</p>
                        <div className="p-4 rounded-xl bg-white border border-green-100/50 text-sm text-slate-600">
                            {caregiverContent.reviewProcess}
                        </div>
                    </div>
                    <div className="p-6 border-t border-green-50">
                        <h3 className="font-bold text-slate-900 mb-3">{caregiverContent.action}</h3>
                        <ul className="space-y-3">
                            {caregiverContent.steps.map((step, i) => (
                                <li key={i} className="flex items-start gap-3 text-slate-600 text-sm">
                                    <div className="mt-1 flex-shrink-0 w-5 h-5 rounded-full bg-green-100 text-green-700 flex items-center justify-center font-bold text-xs">
                                        {i + 1}
                                    </div>
                                    {step}
                                </li>
                            ))}
                        </ul>
                        <button
                            type="button"
                            onClick={() => navigate(isApproved ? `/caregivers/${profile.id}` : '/caregiver/profile')}
                            className="mt-6 w-full sm:w-auto rounded-xl bg-green-600 hover:bg-green-700 text-white font-bold px-8 py-3 transition-all shadow-sm hover:shadow-md"
                        >
                            {caregiverContent.cta}
                        </button>
                    </div>
                </div>
            )}

            {/* Lista de Notificaciones General */}
            <h2 className="text-sm font-bold text-slate-400 uppercase tracking-wider mb-4">
                Historial de notificaciones
            </h2>

            {notifications.length === 0 ? (
                <div className="rounded-2xl border border-dashed border-slate-300 bg-slate-50 p-16 text-center">
                    <div className="mx-auto mb-4 flex h-20 w-20 items-center justify-center rounded-full bg-white text-slate-300 shadow-sm">
                        <svg className="h-10 w-10" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
                        </svg>
                    </div>
                    <p className="text-slate-500 font-medium">No tienes notificaciones todavía.</p>
                </div>
            ) : (
                <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
                    <ul className="divide-y divide-slate-100">
                        {notifications.map((n) => (
                            <li
                                key={n.id}
                                className={`p-6 transition-colors hover:bg-slate-50/50 cursor-pointer ${n.read ? 'bg-white' : 'bg-green-50/20'}`}
                                onClick={() => handleNotificationClick(n)}
                            >
                                <div className="flex gap-5">
                                    <div className={`mt-2 flex-shrink-0 w-3 h-3 rounded-full ${n.read ? 'bg-transparent border border-slate-200' : 'bg-green-500 shadow-[0_0_8px_rgba(34,197,94,0.4)]'}`} />
                                    <div className="flex-1">
                                        <div className="flex items-start justify-between gap-4">
                                            <h3 className={`text-base font-bold text-slate-900 ${n.read ? 'opacity-80' : ''}`}>
                                                {n.title}
                                            </h3>
                                            <span className="flex-shrink-0 text-[11px] font-bold text-slate-400 bg-slate-100 px-2 py-0.5 rounded-full uppercase">
                                                {formatDistanceToNow(new Date(n.createdAt), { addSuffix: true, locale: es })}
                                            </span>
                                        </div>
                                        <div className="mt-2 text-sm text-slate-600 leading-relaxed whitespace-pre-wrap line-clamp-2">
                                            {n.message}
                                        </div>
                                    </div>
                                </div>
                            </li>
                        ))}
                    </ul>
                </div>
            )}

            <NotificationModal
                isOpen={!!selectedNotification}
                notification={selectedNotification}
                onClose={() => setSelectedNotification(null)}
            />
        </div>
    );
}

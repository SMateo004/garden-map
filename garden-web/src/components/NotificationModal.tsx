import { formatDistanceToNow } from 'date-fns';
import { es } from 'date-fns/locale';

interface Notification {
    id: string;
    title: string;
    message: string;
    createdAt: string;
    read: boolean;
}

interface NotificationModalProps {
    notification: Notification | null;
    isOpen: boolean;
    onClose: () => void;
}

export function NotificationModal({ notification, isOpen, onClose }: NotificationModalProps) {
    if (!notification || !isOpen) return null;

    return (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
            {/* Overlay */}
            <div
                className="absolute inset-0 bg-slate-900/60 backdrop-blur-sm transition-opacity animate-in fade-in duration-300"
                onClick={onClose}
            />

            {/* Modal Content */}
            <div className="relative w-full max-w-lg transform overflow-hidden rounded-3xl bg-white shadow-2xl transition-all animate-in zoom-in-95 slide-in-from-bottom-5 duration-300 dark:bg-slate-800">
                {/* Header */}
                <div className="flex items-center justify-between border-b border-slate-100 bg-slate-50/50 px-6 py-4 dark:border-slate-700 dark:bg-slate-800/50">
                    <div className="flex items-center gap-3">
                        <div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-green-100 text-green-600 dark:bg-green-900/30 dark:text-green-400">
                            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
                            </svg>
                        </div>
                        <h3 className="text-lg font-bold text-slate-900 dark:text-white">Detalle de notificación</h3>
                    </div>
                    <button
                        onClick={onClose}
                        className="rounded-full p-2 text-slate-400 hover:bg-slate-100 transition-colors dark:hover:bg-slate-700"
                    >
                        <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                        </svg>
                    </button>
                </div>

                {/* Body */}
                <div className="px-8 py-10 text-center sm:text-left">
                    <div className="mb-2 flex items-center justify-between gap-4 flex-wrap">
                        <span className="inline-flex items-center rounded-full bg-slate-100 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-slate-500 dark:bg-slate-700 dark:text-slate-400">
                            {formatDistanceToNow(new Date(notification.createdAt), { addSuffix: true, locale: es })}
                        </span>
                        {!notification.read && (
                            <span className="inline-flex items-center gap-1.5 rounded-full bg-green-100 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-green-700 dark:bg-green-900/30 dark:text-green-400">
                                <span className="h-1.5 w-1.5 rounded-full bg-green-500" />
                                Nuevo
                            </span>
                        )}
                    </div>

                    <h2 className="mb-4 text-2xl font-bold text-slate-900 dark:text-white leading-tight">
                        {notification.title}
                    </h2>

                    <div className="mt-6 text-base text-slate-600 dark:text-slate-300 leading-relaxed whitespace-pre-wrap text-left bg-slate-50 dark:bg-slate-900/50 p-6 rounded-2xl border border-slate-100 dark:border-slate-700/50">
                        {notification.message}
                    </div>

                    <div className="mt-10">
                        <button
                            type="button"
                            onClick={onClose}
                            className="w-full rounded-2xl bg-slate-900 py-4 text-base font-bold text-white shadow-xl shadow-slate-900/10 transition-all hover:bg-slate-800 active:scale-[0.98] dark:bg-white dark:text-slate-900 dark:hover:bg-slate-100"
                        >
                            Entendido
                        </button>
                    </div>
                </div>
            </div>
        </div>
    );
}

import { useState, useRef, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useNotifications, useUnreadNotificationsCount, useMarkNotificationRead, useMarkAllNotificationsRead } from '@/hooks/useNotifications';
import { formatDistanceToNow } from 'date-fns';
import { es } from 'date-fns/locale';
import { NotificationModal } from '@/components/NotificationModal';

export function NotificationBell() {
    const { data: notifications = [], isLoading } = useNotifications();
    const { data: unreadCount = 0 } = useUnreadNotificationsCount();
    const markRead = useMarkNotificationRead();
    const markAllRead = useMarkAllNotificationsRead();
    const [isOpen, setIsOpen] = useState(false);
    const dropdownRef = useRef<HTMLDivElement>(null);
    const [selectedNotification, setSelectedNotification] = useState<any | null>(null);

    useEffect(() => {
        function handleClickOutside(e: MouseEvent) {
            if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
                setIsOpen(false);
            }
        }
        document.addEventListener('mousedown', handleClickOutside);
        return () => document.removeEventListener('mousedown', handleClickOutside);
    }, []);

    const handleNotificationClick = (n: any) => {
        setSelectedNotification(n);
        if (!n.read) {
            markRead.mutate(n.id);
        }
    };

    return (
        <div className="relative" ref={dropdownRef}>
            <button
                type="button"
                onClick={() => setIsOpen(!isOpen)}
                className="relative flex flex-col items-center p-1 rounded-lg text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors focus:outline-none"
            >
                <div className="relative">
                    <svg
                        className="h-6 w-6"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                    >
                        <path
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            strokeWidth={2}
                            d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"
                        />
                    </svg>
                    {unreadCount > 0 && (
                        <span className="absolute -top-1 -right-1 flex h-4 w-4 items-center justify-center rounded-full bg-red-500 text-[10px] font-bold text-white border-2 border-white dark:border-gray-800">
                            {unreadCount > 9 ? '9+' : unreadCount}
                        </span>
                    )}
                </div>
                <span className="text-[10px] font-medium leading-none mt-0.5">Notificaciones</span>
            </button>

            {isOpen && (
                <div className="absolute right-0 mt-2 w-80 sm:w-96 rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-xl overflow-hidden z-50 animate-in fade-in slide-in-from-top-2">
                    <div className="flex items-center justify-between p-4 border-b border-gray-100 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50">
                        <h3 className="text-sm font-bold text-gray-900 dark:text-white">Buzón</h3>
                        {unreadCount > 0 && (
                            <button
                                onClick={() => markAllRead.mutate()}
                                className="text-xs text-green-600 hover:text-green-700 font-medium"
                            >
                                Marcar todo como leído
                            </button>
                        )}
                    </div>

                    <div className="max-h-[70vh] overflow-y-auto">
                        {isLoading ? (
                            <div className="p-8 text-center text-gray-500 text-sm">Cargando...</div>
                        ) : notifications.length === 0 ? (
                            <div className="p-8 text-center">
                                <p className="text-sm text-gray-500">No tienes notificaciones</p>
                            </div>
                        ) : (
                            <ul className="divide-y divide-gray-100 dark:divide-gray-700">
                                {notifications.slice(0, 10).map((n) => (
                                    <li
                                        key={n.id}
                                        className={`p-4 transition-colors cursor-pointer hover:bg-slate-50 dark:hover:bg-slate-700/50 ${n.read ? 'bg-white dark:bg-gray-800' : 'bg-green-50/50 dark:bg-green-900/10'}`}
                                        onClick={() => handleNotificationClick(n)}
                                    >
                                        <div className="flex gap-3">
                                            <div className={`mt-1 flex-shrink-0 w-2 h-2 rounded-full ${n.read ? 'bg-transparent' : 'bg-green-600'}`} />
                                            <div className="flex-1 min-w-0">
                                                <p className="text-sm font-bold text-gray-900 dark:text-white leading-tight">
                                                    {n.title}
                                                </p>
                                                <p className="mt-1 text-xs text-gray-600 dark:text-gray-400 line-clamp-2">
                                                    {n.message}
                                                </p>
                                                <p className="mt-2 text-[10px] text-gray-400 font-medium">
                                                    {formatDistanceToNow(new Date(n.createdAt), { addSuffix: true, locale: es })}
                                                </p>
                                            </div>
                                        </div>
                                    </li>
                                ))}
                            </ul>
                        )}
                    </div>
                    <div className="p-3 border-t border-gray-100 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 text-center">
                        <Link
                            to="/inbox"
                            onClick={() => setIsOpen(false)}
                            className="text-xs font-bold text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
                        >
                            Ir al Buzón completado
                        </Link>
                    </div>
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

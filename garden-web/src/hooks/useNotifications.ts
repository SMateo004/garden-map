import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import * as api from '@/api/notifications';

export const NOTIFICATIONS_KEY = 'notifications';
export const UNREAD_COUNT_KEY = 'unread-notifications-count';

export function useNotifications() {
    return useQuery({
        queryKey: [NOTIFICATIONS_KEY],
        queryFn: () => api.getMyNotifications().then(res => res.data),
        staleTime: 30000, // 30 seconds
        refetchInterval: 60000, // 1 minute
    });
}

export function useUnreadNotificationsCount() {
    return useQuery({
        queryKey: [UNREAD_COUNT_KEY],
        queryFn: () => api.getUnreadCount().then(res => res.count),
        staleTime: 30000,
        refetchInterval: 60000,
    });
}

export function useMarkNotificationRead() {
    const queryClient = useQueryClient();
    return useMutation({
        mutationFn: (id: string) => api.markAsRead(id),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: [NOTIFICATIONS_KEY] });
            queryClient.invalidateQueries({ queryKey: [UNREAD_COUNT_KEY] });
        },
    });
}

export function useMarkAllNotificationsRead() {
    const queryClient = useQueryClient();
    return useMutation({
        mutationFn: () => api.markAllAsRead(),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: [NOTIFICATIONS_KEY] });
            queryClient.invalidateQueries({ queryKey: [UNREAD_COUNT_KEY] });
        },
    });
}

import { api } from './client';

export interface Notification {
    id: string;
    userId: string;
    title: string;
    message: string;
    type: string;
    read: boolean;
    createdAt: string;
}

export interface NotificationsResponse {
    success: boolean;
    data: Notification[];
}

export interface UnreadCountResponse {
    success: boolean;
    count: number;
}

export const getMyNotifications = (): Promise<NotificationsResponse> =>
    api.get('/api/notifications/my').then(r => r.data);

export const getUnreadCount = (): Promise<UnreadCountResponse> =>
    api.get('/api/notifications/unread-count').then(r => r.data);

export const markAsRead = (id: string): Promise<{ success: boolean }> =>
    api.patch(`/api/notifications/${id}/read`).then(r => r.data);

export const markAllAsRead = (): Promise<{ success: boolean }> =>
    api.patch('/api/notifications/read-all').then(r => r.data);

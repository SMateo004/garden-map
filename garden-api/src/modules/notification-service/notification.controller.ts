import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as notificationService from './notification.service.js';

export const getMy = asyncHandler(async (req: Request, res: Response) => {
    const userId = req.user!.userId;
    const notifications = await notificationService.getMyNotifications(userId);
    res.json({ success: true, data: notifications });
});

export const getUnreadCount = asyncHandler(async (req: Request, res: Response) => {
    const userId = req.user!.userId;
    const count = await notificationService.getUnreadCount(userId);
    res.json({ success: true, count });
});

export const markRead = asyncHandler(async (req: Request, res: Response) => {
    const userId = req.user!.userId;
    const notificationId = req.params.id!;
    await notificationService.markAsRead(notificationId, userId);
    res.json({ success: true });
});

export const markAllRead = asyncHandler(async (req: Request, res: Response) => {
    const userId = req.user!.userId;
    await notificationService.markAllAsRead(userId);
    res.json({ success: true });
});

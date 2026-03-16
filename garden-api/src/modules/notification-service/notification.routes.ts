import { Router } from 'express';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import * as notificationController from './notification.controller.js';

const router = Router();

router.use(authMiddleware);

router.get('/my', notificationController.getMy);
router.get('/unread-count', notificationController.getUnreadCount);
router.patch('/:id/read', notificationController.markRead);
router.patch('/read-all', notificationController.markAllRead);

export default router;

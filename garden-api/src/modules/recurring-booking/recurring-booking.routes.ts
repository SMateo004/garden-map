import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as recurringBookingController from './recurring-booking.controller.js';

const router = Router();

router.use(authMiddleware);
router.use(requireRole('CLIENT'));

router.post('/', recurringBookingController.create);
router.get('/my', recurringBookingController.getMy);
router.patch('/:id/pause', recurringBookingController.pause);
router.patch('/:id/resume', recurringBookingController.resume);
router.delete('/:id', recurringBookingController.cancel);

export default router;

import { Router } from 'express';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import * as ctrl from './meet-and-greet.controller.js';

const router = Router();
router.use(authMiddleware);

router.get('/:bookingId', ctrl.get);
router.post('/:bookingId/propose', ctrl.propose);
router.post('/:bookingId/accept', ctrl.accept);
router.post('/:bookingId/reschedule', ctrl.reschedule);
router.post('/:bookingId/complete', ctrl.complete);
router.post('/:bookingId/cancel', ctrl.cancel);

export default router;

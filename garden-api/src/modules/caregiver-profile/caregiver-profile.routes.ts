import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as caregiverProfileController from './caregiver-profile.controller.js';

const router = Router();

// Todas las rutas requieren auth + role CAREGIVER
router.use(authMiddleware);
router.use(requireRole('CAREGIVER'));

router.get('/my-profile', caregiverProfileController.getMyProfile);
router.patch('/profile', caregiverProfileController.patchProfile);
router.patch('/user-info', caregiverProfileController.patchUserInfo);
router.post('/submit', caregiverProfileController.submit);
router.post('/send-verify-email', caregiverProfileController.sendVerifyEmail);
router.post('/verify-email', caregiverProfileController.verifyEmail);
router.get('/availability', caregiverProfileController.getMyAvailability);
router.patch('/availability', caregiverProfileController.patchAvailability);
router.get('/bookings', caregiverProfileController.getMyBookingsAsCaregiver);
router.get('/notifications', caregiverProfileController.getNotifications);
router.patch('/notifications/:id/read', caregiverProfileController.markNotificationRead);

export default router;

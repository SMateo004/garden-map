import { Router } from 'express';
import multer from 'multer';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import { requireStaffMembership, auditStaffAction, actAsOwner } from '../../middleware/require-staff-membership.middleware.js';
import * as caregiverStaffController from './caregiver-staff.controller.js';
import * as caregiverProfileController from '../caregiver-profile/caregiver-profile.controller.js';
import * as bookingController from '../booking-service/booking.controller.js';
import * as serviceExecutionController from '../booking-service/service-execution.controller.js';

const router = Router();

// Mismo límite que booking.routes.ts — evita que multer corte el stream de fotos/video grandes.
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 80 * 1024 * 1024 } });

// ── Autoservicio del empleado (sin auth) ─────────────────────────────────────
router.get('/invites/:code/preview', caregiverStaffController.previewInvite);
router.post('/register', caregiverStaffController.registerStaff);

// ── Gestión del dueño (empresa) ──────────────────────────────────────────────
router.post('/invites', authMiddleware, requireRole('CAREGIVER'), caregiverStaffController.createInvite);
router.get('/invites', authMiddleware, requireRole('CAREGIVER'), caregiverStaffController.listInvites);
router.delete('/invites/:id', authMiddleware, requireRole('CAREGIVER'), caregiverStaffController.revokeInvite);
router.get('/members', authMiddleware, requireRole('CAREGIVER'), caregiverStaffController.listStaffMembers);
router.delete('/members/:id', authMiddleware, requireRole('CAREGIVER'), caregiverStaffController.removeStaffMember);
router.patch('/members/:id/suspend', authMiddleware, requireRole('CAREGIVER'), caregiverStaffController.suspendStaffMember);
router.patch('/members/:id/reactivate', authMiddleware, requireRole('CAREGIVER'), caregiverStaffController.reactivateStaffMember);

// ── Operativo del empleado ────────────────────────────────────────────────────
// requireStaffMembership resuelve la membresía con una consulta fresca por
// request; actAsOwner sustituye req.user.userId por el del dueño justo antes
// de delegar en los handlers YA EXISTENTES de reservas/ejecución de servicio
// (sin duplicar esa lógica) — ver require-staff-membership.middleware.ts.
router.get('/whoami', authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, caregiverStaffController.whoami);

router.get(
  '/bookings',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner,
  caregiverProfileController.getMyBookingsAsCaregiver
);
router.get(
  '/bookings/:id',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner,
  bookingController.getById
);
router.post(
  '/bookings/:id/start',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, auditStaffAction('STAFF_START_SERVICE'), actAsOwner,
  serviceExecutionController.start
);
router.post(
  '/bookings/:id/en-route',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, auditStaffAction('STAFF_EN_ROUTE'), actAsOwner,
  serviceExecutionController.enRoute
);
router.post(
  '/bookings/:id/arrive',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, auditStaffAction('STAFF_ARRIVE'), actAsOwner,
  serviceExecutionController.arrive
);
router.post(
  '/bookings/:id/event',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, auditStaffAction('STAFF_ADD_EVENT'), actAsOwner,
  upload.single('photo'),
  serviceExecutionController.addEvent
);
router.post(
  '/bookings/:id/track',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner,
  serviceExecutionController.track
);
router.post(
  '/bookings/:id/location-ping',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner,
  serviceExecutionController.locationPing
);
router.post(
  '/bookings/:id/conclude',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, auditStaffAction('STAFF_CONCLUDE_SERVICE'), actAsOwner,
  upload.single('photo'),
  serviceExecutionController.conclude
);
router.post(
  '/bookings/:id/confirm-end',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, auditStaffAction('STAFF_CONFIRM_END'), actAsOwner,
  serviceExecutionController.confirmEnd
);

export default router;

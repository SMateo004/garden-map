import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as bookingController from './booking.controller.js';
import * as serviceExecutionController from './service-execution.controller.js';
import multer from 'multer';

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });
const router = Router();

/** GET /api/bookings/my — obtener todas las reservas del cliente autenticado. */
router.get(
  '/my',
  authMiddleware,
  requireRole('CLIENT'),
  bookingController.getMyBookings
);

/** GET /api/bookings/:id/confirm — datos para página de confirmación. Solo cliente titular. */
router.get(
  '/:id/confirm',
  authMiddleware,
  requireRole('CLIENT'),
  bookingController.getConfirm
);

/** GET /api/bookings/:id — obtener una reserva por ID. Cliente titular o Cuidador asignado. */
router.get(
  '/:id',
  authMiddleware,
  bookingController.getById
);

/** POST /api/bookings — crear reserva (hospedaje o paseo). Solo clientes autenticados. */
router.post(
  '/',
  authMiddleware,
  requireRole('CLIENT'),
  bookingController.create
);

/** POST /api/bookings/:id/payment — iniciar pago (QR o solicitud aprobación manual). Solo cliente titular. */
router.post(
  '/:id/payment',
  authMiddleware,
  requireRole('CLIENT'),
  bookingController.initPayment
);

/** POST /api/bookings/:id/cancel — cancelar reserva; aplica reembolso según MVP (48h hospedaje / 12h paseos). */
router.post(
  '/:id/cancel',
  authMiddleware,
  requireRole('CLIENT'),
  bookingController.cancel
);

/** POST /api/bookings/:id/cancellation-request — cuidador solicita cancelación (requiere aprobación admin). */
router.post(
  '/:id/cancellation-request',
  authMiddleware,
  requireRole('CAREGIVER'),
  bookingController.requestCancellationByCaregiver
);

/** POST /api/bookings/:id/extend — extender hospedaje (nueva endDate). Solo CONFIRMED. */
router.post(
  '/:id/extend',
  authMiddleware,
  requireRole('CLIENT'),
  bookingController.extend
);

/** POST /api/bookings/:id/change-dates — cambiar fechas de hospedaje. Solo CONFIRMED; mín 48h. */
router.post(
  '/:id/change-dates',
  authMiddleware,
  requireRole('CLIENT'),
  bookingController.changeDates
);

/** GET /api/bookings/:id/extension-availability — minutos disponibles para extender paseo. */
router.get(
  '/:id/extension-availability',
  authMiddleware,
  requireRole('CLIENT'),
  bookingController.extensionAvailability
);

/** POST /api/bookings/:id/extend-paseo — cliente extiende paseo en curso (15/30/60 min). */
router.post(
  '/:id/extend-paseo',
  authMiddleware,
  requireRole('CLIENT'),
  bookingController.extendPaseo
);

/** POST /api/bookings/:id/accept — cuidador acepta reserva pagada. */
router.post(
  '/:id/accept',
  authMiddleware,
  requireRole('CAREGIVER'),
  bookingController.accept
);

/** POST /api/bookings/:id/reject — cuidador rechaza reserva pagada. */
router.post(
  '/:id/reject',
  authMiddleware,
  requireRole('CAREGIVER'),
  bookingController.reject
);

/** SERVICE EXECUTION ROUTES (CAREGIVER) */

/** GET /api/bookings/:id/track — GPS track history. Cliente o cuidador de la reserva. */
router.get(
  '/:id/track',
  authMiddleware,
  serviceExecutionController.getTrack
);

router.post(
  '/:id/start',
  authMiddleware,
  requireRole('CAREGIVER'),
  serviceExecutionController.start
);

router.post(
  '/:id/event',
  authMiddleware,
  requireRole('CAREGIVER'),
  upload.single('photo'),
  serviceExecutionController.addEvent
);

router.post(
  '/:id/track',
  authMiddleware,
  requireRole('CAREGIVER'),
  serviceExecutionController.track
);

router.post(
  '/:id/conclude',
  authMiddleware,
  requireRole('CAREGIVER'),
  upload.single('photo'),
  serviceExecutionController.conclude
);

/** CLIENT ACTIONS */

router.post(
  '/:id/confirm-receipt',
  authMiddleware,
  requireRole('CLIENT'),
  serviceExecutionController.confirmReceipt
);

export default router;

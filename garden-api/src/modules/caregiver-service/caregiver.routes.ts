import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import { uploadCaregiverPhotos } from './upload.middleware.js';
import * as caregiverController from './caregiver.controller.js';

const router = Router();

router.get('/', caregiverController.list);
/** GET /api/caregivers/price-stats?zone=X&service=Y — price statistics for wizard */
router.get('/price-stats', caregiverController.getPriceStats);
router.get('/:id/availability', caregiverController.getAvailability);
router.get('/:id', caregiverController.getById);

// POST: crear o actualizar perfil (upsert). multipart/form-data + 4–6 fotos (jpg/png, <5MB).
router.post(
  '/',
  authMiddleware,
  requireRole('CAREGIVER'),
  uploadCaregiverPhotos,
  caregiverController.create
);

export default router;

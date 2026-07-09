/**
 * Rutas: CRUD de servicios extra (ExtraService).
 * Montado en /api/caregiver/extra-services (ver app.ts).
 * Todas las rutas requieren auth + role CAREGIVER.
 */

import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as extraServiceController from './extra-service.controller.js';

const router = Router();

router.use(authMiddleware);
router.use(requireRole('CAREGIVER'));

router.get('/', extraServiceController.listMyExtraServices);
router.post('/', extraServiceController.createExtraService);
router.patch('/:id', extraServiceController.patchExtraService);
router.delete('/:id', extraServiceController.deleteExtraService);

export default router;

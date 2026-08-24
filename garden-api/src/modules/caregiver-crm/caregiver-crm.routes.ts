import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as crmController from './caregiver-crm.controller.js';

/** Rutas del dueño — acceso directo, req.user.userId es su propio userId. */
const router = Router();

router.get('/crm/clients', authMiddleware, requireRole('CAREGIVER'), crmController.listClients);
router.get('/crm/clients/:id', authMiddleware, requireRole('CAREGIVER'), crmController.getClient);
router.post('/crm/clients', authMiddleware, requireRole('CAREGIVER'), crmController.createClient);
router.patch('/crm/clients/:id', authMiddleware, requireRole('CAREGIVER'), crmController.updateClient);
router.delete('/crm/clients/:id', authMiddleware, requireRole('CAREGIVER'), crmController.deleteClient);

router.post('/crm/clients/:clientId/pets', authMiddleware, requireRole('CAREGIVER'), crmController.createPet);
router.patch('/crm/pets/:id', authMiddleware, requireRole('CAREGIVER'), crmController.updatePet);
router.delete('/crm/pets/:id', authMiddleware, requireRole('CAREGIVER'), crmController.deletePet);

router.post('/crm/pets/:petId/check-in', authMiddleware, requireRole('CAREGIVER'), crmController.checkIn);
router.post('/crm/visits/:visitId/check-out', authMiddleware, requireRole('CAREGIVER'), crmController.checkOut);

router.get('/crm/occupancy', authMiddleware, requireRole('CAREGIVER'), crmController.getOccupancy);

export default router;

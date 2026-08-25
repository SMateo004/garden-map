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
router.get('/crm/pets/:id', authMiddleware, requireRole('CAREGIVER'), crmController.getPet);
router.patch('/crm/pets/:id', authMiddleware, requireRole('CAREGIVER'), crmController.updatePet);
router.delete('/crm/pets/:id', authMiddleware, requireRole('CAREGIVER'), crmController.deletePet);

router.post('/crm/pets/:petId/check-in', authMiddleware, requireRole('CAREGIVER'), crmController.checkIn);
router.get('/crm/visits/:id', authMiddleware, requireRole('CAREGIVER'), crmController.getVisit);
router.post('/crm/visits/:visitId/check-out', authMiddleware, requireRole('CAREGIVER'), crmController.checkOut);
router.patch('/crm/visits/:id', authMiddleware, requireRole('CAREGIVER'), crmController.updateVisit);
router.post('/crm/visits/:id/events', authMiddleware, requireRole('CAREGIVER'), crmController.addEvent);

router.get('/crm/occupancy', authMiddleware, requireRole('CAREGIVER'), crmController.getOccupancy);

// Reportes — solo dueño, nunca montados en caregiver-staff.routes.ts (staff
// opera pero no ve datos de negocio/plata, misma regla que wallet/pricing).
router.get('/crm/reports/occupancy', authMiddleware, requireRole('CAREGIVER'), crmController.getOccupancyReport);
router.get('/crm/reports/cash', authMiddleware, requireRole('CAREGIVER'), crmController.getCashReport);

export default router;

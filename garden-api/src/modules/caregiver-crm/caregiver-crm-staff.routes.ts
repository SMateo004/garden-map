import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import { requireStaffMembership, actAsOwner, captureActingUser, auditStaffAction } from '../../middleware/require-staff-membership.middleware.js';
import * as crmController from './caregiver-crm.controller.js';

/**
 * Rutas del empleado — mismos handlers que caregiver-crm.routes.ts, pero
 * actAsOwner sustituye req.user.userId por el del dueño antes de llegar ahí,
 * así que no hay lógica duplicada. captureActingUser + auditStaffAction van
 * ANTES de actAsOwner para que el check-in/check-out queden atribuidos al
 * empleado real, no al dueño.
 */
const router = Router();

router.get('/crm/clients', authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner, crmController.listClients);
router.get('/crm/clients/:id', authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner, crmController.getClient);
router.post('/crm/clients', authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, captureActingUser, actAsOwner, crmController.createClient);
router.patch('/crm/clients/:id', authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner, crmController.updateClient);
router.delete('/crm/clients/:id', authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner, crmController.deleteClient);

router.post('/crm/clients/:clientId/pets', authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner, crmController.createPet);
router.get('/crm/pets/:id', authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner, crmController.getPet);
router.patch('/crm/pets/:id', authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner, crmController.updatePet);
router.delete('/crm/pets/:id', authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner, crmController.deletePet);

router.post(
  '/crm/pets/:petId/check-in',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership,
  captureActingUser, auditStaffAction('STAFF_CRM_CHECK_IN', 'WalkInVisit', 'petId'),
  actAsOwner,
  crmController.checkIn
);
router.get('/crm/visits/:id', authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner, crmController.getVisit);
router.post(
  '/crm/visits/:visitId/check-out',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership,
  captureActingUser, auditStaffAction('STAFF_CRM_CHECK_OUT', 'WalkInVisit', 'visitId'),
  actAsOwner,
  crmController.checkOut
);
router.patch(
  '/crm/visits/:id',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership,
  captureActingUser, auditStaffAction('STAFF_CRM_VISIT_UPDATE', 'WalkInVisit', 'id'),
  actAsOwner,
  crmController.updateVisit
);
router.post(
  '/crm/visits/:id/events',
  authMiddleware, requireRole('CAREGIVER'), requireStaffMembership,
  captureActingUser, auditStaffAction('STAFF_CRM_VISIT_EVENT', 'WalkInVisit', 'id'),
  actAsOwner,
  crmController.addEvent
);

router.get('/crm/occupancy', authMiddleware, requireRole('CAREGIVER'), requireStaffMembership, actAsOwner, crmController.getOccupancy);

// Nota: /crm/reports/* deliberadamente NO se montan acá — son datos de
// negocio (ocupación histórica, caja) reservados al dueño, igual que
// wallet/pricing en caregiver-staff.service.ts.

export default router;

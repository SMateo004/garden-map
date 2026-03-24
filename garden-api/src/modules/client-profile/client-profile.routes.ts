import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as clientProfileController from './client-profile.controller.js';
import * as clientPetsController from './client-pets.controller.js';

const router = Router();

// Todas las rutas requieren auth + role CLIENT
router.use(authMiddleware);
router.use(requireRole('CLIENT'));

router.get('/my-profile', clientProfileController.getMyProfile);
router.patch('/profile', clientProfileController.patchProfile);
router.get('/pets', clientPetsController.getPets);
router.post('/pets', clientPetsController.createPet);
router.patch('/pets/:petId', clientPetsController.patchPet);

router.get('/favorites', clientProfileController.getFavorites);
router.post('/favorites/:caregiverId', clientProfileController.toggleFavorite);

export default router;

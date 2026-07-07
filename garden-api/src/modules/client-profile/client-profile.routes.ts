import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as clientProfileController from './client-profile.controller.js';
import * as clientPetsController from './client-pets.controller.js';

const router = Router();

// Rutas accesibles para CLIENT y CAREGIVER (un cuidador también puede tener mascotas)
router.use(authMiddleware);
router.use(requireRole('CLIENT', 'CAREGIVER'));

router.get('/my-profile', clientProfileController.getMyProfile);
router.patch('/profile', clientProfileController.patchProfile);
router.get('/pets', clientPetsController.getPets);
router.post('/pets', clientPetsController.createPet);
router.patch('/pets/:petId', clientPetsController.patchPet);
router.delete('/pets/:petId', clientPetsController.deletePet);

router.get('/favorites', clientProfileController.getFavorites);
router.post('/favorites/:caregiverId', clientProfileController.toggleFavorite);

router.get('/my-reviews', clientProfileController.getMyReviews);
router.get('/my-donations', clientProfileController.getMyDonationsSummary);

export default router;

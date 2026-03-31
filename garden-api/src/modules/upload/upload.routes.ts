import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import { uploadCaregiverPhotos } from '../caregiver-service/upload.middleware.js';
import * as uploadController from './upload.controller.js';

const router = Router();

// Ruta pública para fotos de registro de cuidadores
router.post(
  '/registration-photos',
  uploadCaregiverPhotos,
  uploadController.uploadRegistrationPhotosHandler
);

// Ruta protegida: foto principal de perfil cuidador (upload + persist en caregiver_profiles.profilePhoto)
router.post('/profile-photo', authMiddleware, requireRole('CAREGIVER'), ...uploadController.uploadProfilePhotoHandler);

// Ruta protegida para foto de mascota (requiere auth CLIENT)
router.post('/pet-photo', authMiddleware, requireRole('CLIENT'), uploadController.uploadPetPhotoHandler);

// Ruta protegida para fotos de servicio (caregiver start/end)
router.post('/service-photo', authMiddleware, requireRole('CAREGIVER'), ...uploadController.uploadServicePhotoHandler);

// Ruta para foto de perfil de usuario (CLIENT o CAREGIVER) — actualiza User.profilePicture
router.post('/user-photo', authMiddleware, ...uploadController.uploadUserPhotoHandler);

// Ruta publica para 1 sola foto de perfil / temporal durante onboarding
router.post('/public-single-photo', ...uploadController.uploadPublicSinglePhotoHandler);

export default router;

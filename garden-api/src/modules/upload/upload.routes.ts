import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import { uploadCaregiverPhotos } from '../caregiver-service/upload.middleware.js';
import * as uploadController from './upload.controller.js';

const router = Router();

// 20 unauthenticated photo uploads per 15 min per IP — prevents Cloudinary/S3 storage abuse
const publicUploadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'RATE_LIMITED', message: 'Demasiadas subidas. Espera 15 minutos.' } },
});

// Ruta pública para fotos de registro de cuidadores
router.post(
  '/registration-photos',
  publicUploadLimiter,
  uploadCaregiverPhotos,
  uploadController.uploadRegistrationPhotosHandler
);

// Ruta protegida: foto principal de perfil cuidador (upload + persist en caregiver_profiles.profilePhoto)
router.post('/profile-photo', authMiddleware, requireRole('CAREGIVER'), ...uploadController.uploadProfilePhotoHandler);

// Ruta protegida para foto de mascota (requiere auth CLIENT)
router.post('/pet-photo', authMiddleware, requireRole('CLIENT'), ...uploadController.uploadPetPhotoHandler);

// Ruta protegida para fotos de servicio (caregiver start/end)
router.post('/service-photo', authMiddleware, requireRole('CAREGIVER'), ...uploadController.uploadServicePhotoHandler);

// Ruta para foto de perfil de usuario (CLIENT o CAREGIVER) — actualiza User.profilePicture
router.post('/user-photo', authMiddleware, ...uploadController.uploadUserPhotoHandler);

// Ruta publica para 1 sola foto de perfil / temporal durante onboarding
router.post('/public-single-photo', publicUploadLimiter, ...uploadController.uploadPublicSinglePhotoHandler);

export default router;

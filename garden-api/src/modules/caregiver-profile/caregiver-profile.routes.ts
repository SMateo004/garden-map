import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as caregiverProfileController from './caregiver-profile.controller.js';
import { asyncHandler } from '../../shared/async-handler.js';
import { prisma } from '../../config/database.js';
import multer from 'multer';

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });

const router = Router();

// Todas las rutas requieren auth + role CAREGIVER
router.use(authMiddleware);
router.use(requireRole('CAREGIVER'));

router.get('/my-profile', caregiverProfileController.getMyProfile);
router.patch('/profile', caregiverProfileController.patchProfile);
router.patch('/user-info', caregiverProfileController.patchUserInfo);
router.post('/submit', caregiverProfileController.submit);
router.post('/send-verify-email', caregiverProfileController.sendVerifyEmail);
router.post('/verify-email', caregiverProfileController.verifyEmail);
router.get('/availability', caregiverProfileController.getMyAvailability);
router.patch('/availability', caregiverProfileController.patchAvailability);
router.get('/bookings', caregiverProfileController.getMyBookingsAsCaregiver);
router.get('/notifications', caregiverProfileController.getNotifications);
router.patch('/notifications/:id/read', caregiverProfileController.markNotificationRead);

router.post('/profile/service-photo', authMiddleware, requireRole('CAREGIVER'),
  upload.single('servicePhoto'),
  asyncHandler(async (req, res) => {
    const userId = (req as any).user.userId;
    const file = req.file;
    if (!file) return res.status(400).json({ success: false, error: { message: 'No se proporcionó foto' } });
    
    // Guardar en uploads/service-photos
    const fs = await import('fs/promises');
    const path = await import('path');
    const filename = `service-${userId}-${Date.now()}.jpg`;
    const uploadDir = path.join(process.cwd(), 'uploads', 'service-photos');
    await fs.mkdir(uploadDir, { recursive: true });
    await fs.writeFile(path.join(uploadDir, filename), file.buffer);
    
    const photoUrl = `${process.env.API_BASE_URL || 'http://localhost:3000'}/uploads/service-photos/${filename}`;
    
    // Obtener fotos actuales para no sobrescribir, sino agregar
    const profile = await prisma.caregiverProfile.findFirst({ where: { userId } });
    const currentPhotos = profile?.photos ?? [];
    if (currentPhotos.length >= 6) {
      return res.status(400).json({ success: false, error: { message: 'Máximo 6 fotos permitidas' } });
    }

    await prisma.caregiverProfile.update({
      where: { userId },
      data: { photos: [...currentPhotos, photoUrl] },
    });
    
    res.json({ success: true, data: { photoUrl } });
  })
);

router.post('/profile/photo', authMiddleware, requireRole('CAREGIVER'), 
  upload.single('photo'), 
  asyncHandler(async (req, res) => {
    const userId = (req as any).user.userId;
    const file = req.file;
    if (!file) {
      return res.status(400).json({ success: false, error: { message: 'No se proporcionó foto' } });
    }
    
    // Guardar en uploads/profile
    const fs = await import('fs/promises');
    const path = await import('path');
    const filename = `profile-${userId}-${Date.now()}.jpg`;
    const uploadDir = path.join(process.cwd(), 'uploads', 'profiles');
    await fs.mkdir(uploadDir, { recursive: true });
    await fs.writeFile(path.join(uploadDir, filename), file.buffer);
    
    const photoUrl = `${process.env.API_BASE_URL || 'http://localhost:3000'}/uploads/profiles/${filename}`;
    
    // Actualizar en DB tanto el perfil como el usuario para consistencia
    await prisma.$transaction([
      prisma.caregiverProfile.update({
        where: { userId },
        data: { profilePhoto: photoUrl },
      }),
      prisma.user.update({
        where: { id: userId },
        data: { profilePicture: photoUrl },
      }),
    ]);
    
    res.json({ success: true, data: { photoUrl } });
  })
);

export default router;

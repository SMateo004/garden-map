import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import { AppError, CaregiverProfileValidationError } from '../../shared/errors.js';
import { caregiverPhotosFilesSchema, PHOTO_COUNT } from '../caregiver-service/caregiver.validation.js';
import logger from '../../shared/logger.js';
import prisma from '../../config/database.js';
import { delByPrefix } from '../../shared/cache.js';
import multer from 'multer';
import { randomUUID } from 'crypto';
import { uploadImage, uploadImages } from '../../services/storage.service.js';

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
});

/** POST /api/upload/registration-photos — multipart 'photos' (4-6). No auth. */
export const uploadRegistrationPhotosHandler = asyncHandler(async (req: Request, res: Response) => {
  const files = (req.files as Express.Multer.File[] | undefined) ?? [];
  try {
    caregiverPhotosFilesSchema.parse(files);
  } catch (err) {
    throw new CaregiverProfileValidationError(
      `Se requieren entre ${PHOTO_COUNT.min} y ${PHOTO_COUNT.max} fotos (JPG/PNG, máx. 5MB cada una)`
    );
  }

  const tempId = randomUUID();
  const buffers = files.map((f) => f.buffer);
  const urls = await uploadImages(buffers, { folder: 'caregivers', name: `reg-${tempId}` });

  urls.forEach((url) => logger.info('Foto subida', { url, field: 'photos', tempId }));
  res.json({ success: true, data: { urls } });
});

/** POST /api/upload/profile-photo — multipart 'profilePhoto'. Requires auth CAREGIVER. */
export const uploadProfilePhotoHandler = [
  upload.single('profilePhoto'),
  asyncHandler(async (req: Request, res: Response) => {
    const file = req.file;
    const userId = req.user!.userId;

    if (!file) throw new CaregiverProfileValidationError('Se requiere una foto (campo profilePhoto)');
    if (!file.mimetype.startsWith('image/')) throw new CaregiverProfileValidationError('El archivo debe ser una imagen');
    if (file.size > 5 * 1024 * 1024) throw new CaregiverProfileValidationError('La foto no debe superar 5 MB');

    const profile = await prisma.caregiverProfile.findUnique({ where: { userId } });
    if (!profile) throw new CaregiverProfileValidationError('No tienes perfil de cuidador.');

    const url = await uploadImage(file.buffer, { folder: 'caregivers', name: `profile-${userId}-${Date.now()}` });

    await prisma.caregiverProfile.update({ where: { userId }, data: { profilePhoto: url } });
    await delByPrefix('caregivers:');
    logger.info('Foto perfil actualizada', { url, userId });
    res.json({ success: true, data: { profilePhoto: url } });
  }),
];

/** POST /api/upload/pet-photo — multipart 'photo'. Requires auth CLIENT. */
export const uploadPetPhotoHandler = [
  upload.single('photo'),
  asyncHandler(async (req: Request, res: Response) => {
    const file = req.file;
    const userId = req.user!.userId;

    if (!file) throw new CaregiverProfileValidationError('Se requiere una foto (JPG/PNG, máx. 5MB)');
    if (!file.mimetype.startsWith('image/')) throw new CaregiverProfileValidationError('El archivo debe ser una imagen');

    const url = await uploadImage(file.buffer, { folder: 'pets', name: `pet-${userId}-${Date.now()}` });

    await prisma.clientProfile.upsert({
      where: { userId },
      create: { userId, petPhoto: url, isComplete: false },
      update: { petPhoto: url },
    });
    logger.info('Foto mascota actualizada', { url, userId });
    res.json({ success: true, data: { url, petPhoto: url } });
  }),
];

/** POST /api/upload/service-photo — multipart 'photo'. Requires auth CAREGIVER. */
export const uploadServicePhotoHandler = [
  upload.single('photo'),
  asyncHandler(async (req: Request, res: Response) => {
    const file = req.file;
    const userId = req.user!.userId;

    if (!file) throw new CaregiverProfileValidationError('Se requiere una foto (JPG/PNG, máx. 5MB)');
    if (!file.mimetype.startsWith('image/')) throw new CaregiverProfileValidationError('El archivo debe ser una imagen');

    const url = await uploadImage(file.buffer, { folder: 'service-events', name: `svc-${userId}-${Date.now()}` });
    logger.info('Foto servicio subida', { url, userId });
    res.json({ success: true, data: { url } });
  }),
];

/** POST /api/upload/public-single-photo — multipart 'photo'. No auth. */
export const uploadPublicSinglePhotoHandler = [
  upload.single('photo'),
  asyncHandler(async (req: Request, res: Response) => {
    const file = req.file;
    if (!file) throw new CaregiverProfileValidationError('Se requiere una foto');
    if (!file.mimetype.startsWith('image/')) throw new CaregiverProfileValidationError('El archivo debe ser una imagen');

    const url = await uploadImage(file.buffer, { folder: 'public', name: `pub-${randomUUID()}` });
    res.json({ success: true, data: { url } });
  }),
];

/** POST /api/upload/user-photo — multipart 'photo'. Updates User.profilePicture. Requires any auth. */
export const uploadUserPhotoHandler = [
  upload.single('photo'),
  asyncHandler(async (req: Request, res: Response) => {
    const file = req.file;
    const userId = req.user!.userId;

    if (!file) throw new CaregiverProfileValidationError('Se requiere una foto (JPG/PNG, máx. 5MB)');
    if (!file.mimetype.startsWith('image/')) throw new CaregiverProfileValidationError('El archivo debe ser una imagen');

    const url = await uploadImage(file.buffer, { folder: 'users', name: `user-${userId}-${Date.now()}` });

    await prisma.user.update({ where: { id: userId }, data: { profilePicture: url } });
    logger.info('Foto usuario actualizada', { url, userId });
    res.json({ success: true, data: { url } });
  }),
];

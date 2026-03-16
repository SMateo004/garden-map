import { Request, Response } from 'express';
import { randomUUID } from 'crypto';
import path from 'path';
import fs from 'fs/promises';
import { processAndUploadToCloudinary } from '../caregiver-service/upload.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import { AppError, CaregiverProfileValidationError } from '../../shared/errors.js';
import { caregiverPhotosFilesSchema, PHOTO_COUNT } from '../caregiver-service/caregiver.validation.js';
import { isCloudinaryConfigured, CLOUDINARY_FOLDER, CLOUDINARY_FOLDER_PETS, CLOUDINARY_FOLDER_CI } from '../../config/cloudinary.js';
import { env } from '../../config/env.js';
import logger from '../../shared/logger.js';
import prisma from '../../config/database.js';
import { delByPrefix } from '../../shared/cache.js';
import multer from 'multer';
import sharp from 'sharp';
import { v2 as cloudinary } from 'cloudinary';

const SHARP_MAX_SIZE = 1024;

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
});

// Obsolete CI logic removed per "No CI images" requirement

/** Saves buffers to local disk at uploads/registration/{folderId}/ and returns full accessible URLs. */
async function saveRegistrationPhotosToLocal(
  buffers: Buffer[],
  folderId: string
): Promise<string[]> {
  const baseDir = path.join(process.cwd(), 'uploads', 'registration', folderId);
  await fs.mkdir(baseDir, { recursive: true });
  const baseUrl = env.API_PUBLIC_URL || 'http://localhost:3000';
  const urls: string[] = [];

  for (let i = 0; i < buffers.length; i++) {
    try {
      const processed = await sharp(buffers[i])
        .resize(SHARP_MAX_SIZE, SHARP_MAX_SIZE, { fit: 'inside', withoutEnlargement: true })
        .jpeg({ quality: 85 })
        .toBuffer();
      const filename = `photo_${i + 1}.jpg`;
      const filePath = path.join(baseDir, filename);
      await fs.writeFile(filePath, processed);
      const url = `${baseUrl.replace(/\/$/, '')}/uploads/registration/${folderId}/${filename}`;
      urls.push(url);
    } catch (err) {
      logger.error('Error procesando imagen local con Sharp', { error: err });
      throw new CaregiverProfileValidationError('Una de las fotos es inválida o está corrupta.');
    }
  }
  return urls;
}

/** POST /api/upload/registration-photos — multipart 'photos' (4-6). Returns URLs for use in caregiver register. No auth. */
export const uploadRegistrationPhotosHandler = asyncHandler(async (req: Request, res: Response) => {
  const files = (req.files as Express.Multer.File[] | undefined) ?? [];
  try {
    caregiverPhotosFilesSchema.parse(files);
  } catch (err) {
    logger.warn('Validación de fotos fallida', {
      count: files.length,
      min: PHOTO_COUNT.min,
      max: PHOTO_COUNT.max,
      error: err instanceof Error ? err.message : String(err)
    });
    throw new CaregiverProfileValidationError(`Se requieren entre ${PHOTO_COUNT.min} y ${PHOTO_COUNT.max} fotos (JPG/PNG, máx. 5MB cada una)`);
  }
  const tempId = randomUUID();
  const buffers = files.map((f) => f.buffer);

  let urls: string[];
  if (isCloudinaryConfigured()) {
    try {
      urls = await processAndUploadToCloudinary(buffers, `registration-${tempId}`);
    } catch (err) {
      logger.error('Error en fotos (registration-photos) -> intentando local', {
        error: err instanceof Error ? err.message : String(err),
      });
      urls = await saveRegistrationPhotosToLocal(buffers, tempId);
    }
  } else {
    urls = await saveRegistrationPhotosToLocal(buffers, tempId);
    logger.info('Fotos guardadas localmente (Cloudinary off)', { count: urls.length, folderId: tempId });
  }

  urls.forEach((url) => {
    logger.info('Foto subida y guardada', { url, field: 'photos', tempId });
  });
  res.json({ success: true, data: { urls } });
});

/**
 * Sube una sola foto de mascota a Cloudinary.
 * Similar a processAndUploadToCloudinary pero para una sola foto.
 */
async function uploadSinglePetPhoto(buffer: Buffer, userId: string): Promise<string> {
  if (!isCloudinaryConfigured()) {
    throw new AppError(
      'Subida de fotos no configurada. Configure CLOUDINARY_* en el servidor.',
      503,
      'UPLOAD_NOT_CONFIGURED'
    );
  }

  const folder = `${CLOUDINARY_FOLDER_PETS}/${userId}`;
  const SHARP_MAX_SIZE = 1024;

  // Procesar imagen (resize y optimizar)
  const processed = await sharp(buffer)
    .resize(SHARP_MAX_SIZE, SHARP_MAX_SIZE, { fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 85 })
    .toBuffer();

  const publicId = `pet_${userId}_${Date.now()}`;
  const result = await new Promise<{ secure_url: string }>((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      {
        folder,
        resource_type: 'image',
        public_id: publicId,
      },
      (err, res) => {
        if (err) reject(err);
        else if (res) resolve({ secure_url: res.secure_url });
        else reject(new Error('No response from Cloudinary'));
      }
    );
    stream.end(processed);
  });

  logger.info('Foto subida y guardada', { url: result.secure_url, field: 'petPhoto', userId });
  return result.secure_url;
}

/**
 * Sube una sola foto de perfil de cuidador a Cloudinary.
 * Folder: garden/caregivers/{userId}. Persiste en caregiver_profiles.profilePhoto.
 */
async function uploadProfilePhotoToCloudinary(buffer: Buffer, userId: string): Promise<string> {
  if (!isCloudinaryConfigured()) {
    throw new AppError(
      'Subida de fotos no configurada. Configure CLOUDINARY_* en el servidor.',
      503,
      'UPLOAD_NOT_CONFIGURED'
    );
  }
  const folder = `${CLOUDINARY_FOLDER}/${userId}`;
  const SHARP_MAX = 1024;
  const processed = await sharp(buffer)
    .resize(SHARP_MAX, SHARP_MAX, { fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 85 })
    .toBuffer();

  const publicId = `profile_${Date.now()}`;
  const result = await new Promise<{ secure_url: string }>((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      { folder, resource_type: 'image', public_id: publicId },
      (err, res) => {
        if (err) reject(err);
        else if (res) resolve({ secure_url: res.secure_url });
        else reject(new Error('No response from Cloudinary'));
      }
    );
    stream.end(processed);
  });
  return result.secure_url;
}

/** POST /api/upload/profile-photo — multipart 'profilePhoto' (single file). Uploads to Cloudinary, persists in caregiver_profiles.profilePhoto. Requires auth CAREGIVER. */
export const uploadProfilePhotoHandler = [
  upload.single('profilePhoto'),
  asyncHandler(async (req: Request, res: Response) => {
    const file = req.file;
    const userId = req.user!.userId;
    logger.info('profile-photo upload', { hasFile: !!file, fileName: file?.originalname, userId });

    if (!file) {
      throw new CaregiverProfileValidationError('Se requiere una foto (campo profilePhoto)');
    }
    if (!file.mimetype.startsWith('image/')) {
      throw new CaregiverProfileValidationError('El archivo debe ser una imagen (image/*)');
    }
    const fiveMB = 5 * 1024 * 1024;
    if (file.size > fiveMB) {
      throw new CaregiverProfileValidationError('La foto no debe superar 5 MB');
    }

    const profile = await prisma.caregiverProfile.findUnique({ where: { userId } });
    if (!profile) {
      throw new CaregiverProfileValidationError('No tienes perfil de cuidador. Completa el registro primero.');
    }

    let url: string;
    if (isCloudinaryConfigured()) {
      try {
        url = await uploadProfilePhotoToCloudinary(file.buffer, userId);
      } catch (err) {
        logger.error('Fallo al subir a Cloudinary, intentando local', { error: err });
        const urls = await saveRegistrationPhotosToLocal([file.buffer], `profile-${userId}`);
        url = urls[0]!;
      }
    } else {
      const urls = await saveRegistrationPhotosToLocal([file.buffer], `profile-${userId}`);
      url = urls[0]!;
      logger.info('Foto perfil guardada localmente (Cloudinary off)', { url, userId });
    }

    await prisma.caregiverProfile.update({
      where: { userId },
      data: { profilePhoto: url },
    });
    await delByPrefix('caregivers:');
    res.json({ success: true, data: { profilePhoto: url } });
  }),
];

/** POST /api/upload/pet-photo — multipart 'photo' (single file). Returns URL for pet photo. Requires auth CLIENT. */
export const uploadPetPhotoHandler = [
  upload.single('photo'),
  asyncHandler(async (req: Request, res: Response) => {
    const file = req.file;
    const userId = req.user!.userId;

    if (!file) {
      throw new CaregiverProfileValidationError('Se requiere una foto (JPG/PNG, máx. 5MB)');
    }
    if (!file.mimetype.startsWith('image/')) {
      throw new CaregiverProfileValidationError('El archivo debe ser una imagen (JPG/PNG)');
    }

    let url: string;
    if (isCloudinaryConfigured()) {
      try {
        url = await uploadSinglePetPhoto(file.buffer, userId);
      } catch (err) {
        logger.error('Fallo al subir petPhoto a Cloudinary, intentando local', { error: err });
        const urls = await saveRegistrationPhotosToLocal([file.buffer], `pet-${userId}`);
        url = urls[0]!;
      }
    } else {
      const urls = await saveRegistrationPhotosToLocal([file.buffer], `pet-${userId}`);
      url = urls[0]!;
      logger.info('Foto mascota guardada localmente (Cloudinary off)', { url, userId });
    }

    await prisma.clientProfile.upsert({
      where: { userId },
      create: { userId, petPhoto: url, isComplete: false },
      update: { petPhoto: url },
    });
    res.json({ success: true, data: { url, petPhoto: url } });
  }),
];

/** POST /api/upload/service-photo — multipart 'photo' (single file). Returns URL. Requires auth CAREGIVER. */
export const uploadServicePhotoHandler = [
  upload.single('photo'),
  asyncHandler(async (req: Request, res: Response) => {
    const file = req.file;
    const userId = req.user!.userId;

    if (!file) {
      throw new CaregiverProfileValidationError('Se requiere una foto (JPG/PNG, máx. 5MB)');
    }
    if (!file.mimetype.startsWith('image/')) {
      throw new CaregiverProfileValidationError('El archivo debe ser una imagen (JPG/PNG)');
    }

    let url: string;
    if (isCloudinaryConfigured()) {
      try {
        url = await uploadSinglePetPhoto(file.buffer, userId); // Reutilizamos lógica de subida simple
      } catch (err) {
        logger.error('Fallo al subir servicePhoto a Cloudinary, intentando local', { error: err });
        const urls = await saveRegistrationPhotosToLocal([file.buffer], `service-${userId}`);
        url = urls[0]!;
      }
    } else {
      const urls = await saveRegistrationPhotosToLocal([file.buffer], `service-${userId}`);
      url = urls[0]!;
      logger.info('Foto servicio guardada localmente (Cloudinary off)', { url, userId });
    }

    res.json({ success: true, data: { url } });
  }),
];

// Obsolete CI handlers removed per requirement

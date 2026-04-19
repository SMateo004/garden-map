import multer from 'multer';
import { Request } from 'express';
import { PhotoUploadError } from '../../shared/errors.js';
import { ALLOWED_MIME_TYPES, MAX_FILE_SIZE_BYTES, PHOTO_COUNT } from './caregiver.validation.js';
import logger from '../../shared/logger.js';

/** Memoria: no hay archivos temp en disco; no hace falta limpiar después del upload */
const storage = multer.memoryStorage();

function fileFilter(
  _req: Request,
  file: Express.Multer.File,
  cb: multer.FileFilterCallback
): void {
  if (!file.mimetype || !ALLOWED_MIME_TYPES.includes(file.mimetype as (typeof ALLOWED_MIME_TYPES)[number])) {
    cb(new PhotoUploadError(`Tipo de archivo no permitido. Solo: ${ALLOWED_MIME_TYPES.join(', ')}`));
    return;
  }
  if (file.size > MAX_FILE_SIZE_BYTES) {
    cb(new PhotoUploadError('Archivo demasiado grande (máx. 5MB)'));
    return;
  }
  cb(null, true);
}

/** Array 'photos', maxCount 6. Validación min 4 se hace en controlador. */
export const uploadCaregiverPhotos = multer({
  storage,
  fileFilter,
  limits: {
    fileSize: MAX_FILE_SIZE_BYTES,
    files: PHOTO_COUNT.max,
  },
}).array('photos', PHOTO_COUNT.max);

/**
 * Procesa y sube fotos de cuidador usando storage.service (S3 → Cloudinary → local).
 */
export async function processAndUploadToCloudinary(
  buffers: Buffer[],
  userId: string
): Promise<string[]> {
  if (buffers.length < PHOTO_COUNT.min || buffers.length > PHOTO_COUNT.max) {
    throw new PhotoUploadError(`Se requieren entre ${PHOTO_COUNT.min} y ${PHOTO_COUNT.max} fotos`);
  }
  // Usar storage.service unificado (S3 → Cloudinary → local)
  const { uploadImages } = await import('../../services/storage.service.js');
  try {
    return await uploadImages(buffers, { folder: 'caregivers', name: `${userId}` });
  } catch (err) {
    logger.error('Error en processAndUploadToCloudinary via storage.service', { error: err });
    throw new PhotoUploadError('Error al procesar o subir una de las fotos. Asegura que sean imágenes válidas.');
  }
}

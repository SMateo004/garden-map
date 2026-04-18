import multer from 'multer';
import sharp from 'sharp';
import { v2 as cloudinary } from 'cloudinary';
import { Request } from 'express';
import { AppError, PhotoUploadError } from '../../shared/errors.js';
import { CLOUDINARY_FOLDER, isCloudinaryConfigured } from '../../config/cloudinary.js';
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

const SHARP_MAX_SIZE = 1024;

/**
 * Procesa buffers (resize 1024x1024 max para performance) y sube a Cloudinary.
 * Folder final: garden/caregivers/{userId}
 * Flexible: en el futuro se puede extender con photoTypes (casa/patio, cuidador con mascota, etc.).
 */
export async function processAndUploadToCloudinary(
  buffers: Buffer[],
  userId: string
): Promise<string[]> {
  if (buffers.length < PHOTO_COUNT.min || buffers.length > PHOTO_COUNT.max) {
    throw new PhotoUploadError(`Se requieren entre ${PHOTO_COUNT.min} y ${PHOTO_COUNT.max} fotos`);
  }
  if (!isCloudinaryConfigured()) {
    throw new AppError(
      'Subida de fotos no configurada. Configure CLOUDINARY_* en el servidor.',
      503,
      'UPLOAD_NOT_CONFIGURED'
    );
  }

  const folder = `${CLOUDINARY_FOLDER}/${userId}`;
  const urls: string[] = [];

  for (let i = 0; i < buffers.length; i++) {
    try {
      const processed = await sharp(buffers[i])
        .resize(SHARP_MAX_SIZE, SHARP_MAX_SIZE, { fit: 'inside', withoutEnlargement: true })
        .jpeg({ quality: 85, progressive: true })
        .toBuffer();

      const result = await new Promise<{ secure_url: string }>((resolve, reject) => {
        const stream = cloudinary.uploader.upload_stream(
          {
            folder,
            resource_type: 'image',
            public_id: `photo_${i + 1}`,
          },
          (err, res) => {
            if (err) reject(err);
            else if (res) resolve({ secure_url: res.secure_url });
            else reject(new Error('No response from Cloudinary'));
          }
        );
        stream.end(processed);
      });

      urls.push(result.secure_url);
      logger.info('Foto subida y guardada', { url: result.secure_url, field: 'photos', userId });
    } catch (err) {
      logger.error('Error en processAndUploadToCloudinary', { error: err });
      throw new PhotoUploadError('Error al procesar o subir una de las fotos. Asegura que sean imágenes válidas.');
    }
  }

  return urls;
}

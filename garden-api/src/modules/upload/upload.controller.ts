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
import { assertImageBuffer } from '../../shared/mime-validation.js';
import { validarFoto, type CategoriaFoto } from '../../agents/foto-validacion.agent.js';

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 20 * 1024 * 1024 },
});

const CLAUDE_VISION_MIMES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif']);

/**
 * Valida que la foto corresponda a la categoría esperada — lanza un error
 * claro (que el frontend muestra y deja reintentar) si no. Formatos que
 * Claude no soporta en visión (avif/heic/heif) se dejan pasar sin revisar
 * (fail-open, igual que un error técnico del agente).
 */
async function assertFotoValida(buffer: Buffer, mime: string, categoria: CategoriaFoto, userId?: string, contexto?: string) {
  if (!CLAUDE_VISION_MIMES.has(mime)) return;
  const resultado = await validarFoto({
    imageBuffer: buffer,
    mediaType: mime as 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif',
    categoria,
    userId,
    contexto,
  });
  if (!resultado.valida) {
    throw new AppError(resultado.razon, 422, 'FOTO_NO_VALIDA');
  }
}

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

  // Validate magic bytes for every file to prevent MIME spoofing
  const mimes = await Promise.all(files.map((f) => assertImageBuffer(f.buffer)));
  // Estas son fotos del espacio/hogar del cuidador (living, patio, etc.) —
  // no rostro ni mascota. Se validan todas antes de subir cualquiera, para
  // no dejar fotos "huérfanas" en Cloudinary si una del lote es inválida.
  await Promise.all(files.map((f, i) => assertFotoValida(f.buffer, mimes[i]!, 'ESPACIO_HOGAR', undefined, 'registration-photos')));

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
    if (file.size > 20 * 1024 * 1024) throw new CaregiverProfileValidationError('La foto no debe superar 20 MB');
    // Magic bytes check — client-supplied MIME headers cannot be trusted
    const mime = await assertImageBuffer(file.buffer);
    await assertFotoValida(file.buffer, mime, 'ROSTRO_HUMANO', userId, 'profile-photo');

    const profile = await prisma.caregiverProfile.findUnique({ where: { userId } });
    if (!profile) throw new CaregiverProfileValidationError('No tienes perfil de cuidador.');

    const url = await uploadImage(file.buffer, { folder: 'caregivers', name: `profile-${userId}-${Date.now()}` });

    await prisma.$transaction([
      prisma.caregiverProfile.update({ where: { userId }, data: { profilePhoto: url } }),
      prisma.user.update({ where: { id: userId }, data: { profilePicture: url } }),
    ]);
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
    const mime = await assertImageBuffer(file.buffer);
    await assertFotoValida(file.buffer, mime, 'MASCOTA', userId, 'pet-photo');

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
    const mime = await assertImageBuffer(file.buffer);
    // Este endpoint genérico no conoce la reserva/servicio — se asume MASCOTA
    // (evidencia del animal), a diferencia de addEvent en service-execution
    // (booking-service) que sí sabe el tipo de servicio y elige entre
    // MASCOTA/ESPACIO_HOGAR según corresponda.
    await assertFotoValida(file.buffer, mime, 'MASCOTA', userId, 'service-photo');

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
    await assertImageBuffer(file.buffer);

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
    const mime = await assertImageBuffer(file.buffer);
    await assertFotoValida(file.buffer, mime, 'ROSTRO_HUMANO', userId, 'user-photo');

    const url = await uploadImage(file.buffer, { folder: 'users', name: `user-${userId}-${Date.now()}` });

    await prisma.user.update({ where: { id: userId }, data: { profilePicture: url } });
    // Si este usuario también tiene perfil de cuidador (doble rol), se
    // sincroniza para que no queden dos fotos distintas del mismo usuario.
    await prisma.caregiverProfile.updateMany({ where: { userId }, data: { profilePhoto: url } });
    logger.info('Foto usuario actualizada', { url, userId });
    res.json({ success: true, data: { url } });
  }),
];

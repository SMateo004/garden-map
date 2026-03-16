import { v2 as cloudinary } from 'cloudinary';
import { env } from './env.js';

if (env.CLOUDINARY_CLOUD_NAME && env.CLOUDINARY_API_KEY && env.CLOUDINARY_API_SECRET) {
  cloudinary.config({
    cloud_name: env.CLOUDINARY_CLOUD_NAME,
    api_key: env.CLOUDINARY_API_KEY,
    api_secret: env.CLOUDINARY_API_SECRET,
  });
}

export { cloudinary };

/** True si las tres variables CLOUDINARY_* están definidas y no vacías. */
export function isCloudinaryConfigured(): boolean {
  return !!(
    env.CLOUDINARY_CLOUD_NAME?.trim() &&
    env.CLOUDINARY_API_KEY?.trim() &&
    env.CLOUDINARY_API_SECRET?.trim()
  );
}

/** Base folder en Cloudinary para fotos de cuidadores: garden/caregivers/{userId}/ */
export const CLOUDINARY_FOLDER = 'garden/caregivers';
/** Folder para fotos de mascotas (Pet.photoUrl). */
export const CLOUDINARY_FOLDER_PETS = 'garden/pets';
/** Folder para documentos CI (ciAnversoUrl, ciReversoUrl). */
export const CLOUDINARY_FOLDER_CI = 'garden/ci';

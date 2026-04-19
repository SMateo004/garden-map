/**
 * storage.service.ts — servicio unificado de almacenamiento de imágenes.
 *
 * Prioridad:
 *   1. AWS S3 (pública) — requiere AWS_S3_BUCKET + AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY
 *   2. Cloudinary       — requiere CLOUDINARY_CLOUD_NAME + CLOUDINARY_API_KEY + CLOUDINARY_API_SECRET
 *   3. Disco local      — ephemeral en Render (imágenes se pierden al reiniciar) — solo dev
 */

import path from 'path';
import fs from 'fs/promises';
import sharp from 'sharp';
import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { v2 as cloudinary } from 'cloudinary';
import { randomUUID } from 'crypto';
import { env } from '../config/env.js';
import { isCloudinaryConfigured } from '../config/cloudinary.js';
import logger from '../shared/logger.js';

const SHARP_MAX = 1024;

// ── S3 ───────────────────────────────────────────────────────────────────────

function getS3Client(): S3Client | null {
  if (env.AWS_ACCESS_KEY_ID && env.AWS_SECRET_ACCESS_KEY && env.AWS_S3_BUCKET) {
    return new S3Client({
      region: env.AWS_REGION ?? 'us-east-1',
      credentials: {
        accessKeyId: env.AWS_ACCESS_KEY_ID,
        secretAccessKey: env.AWS_SECRET_ACCESS_KEY,
      },
    });
  }
  return null;
}

export function isS3Configured(): boolean {
  return !!(env.AWS_ACCESS_KEY_ID && env.AWS_SECRET_ACCESS_KEY && env.AWS_S3_BUCKET);
}

async function uploadToS3Public(buffer: Buffer, folder: string, filename: string): Promise<string> {
  const client = getS3Client();
  if (!client || !env.AWS_S3_BUCKET) throw new Error('S3 not configured');

  const key = `${folder}/${filename}`;
  await client.send(
    new PutObjectCommand({
      Bucket: env.AWS_S3_BUCKET,
      Key: key,
      Body: buffer,
      ContentType: 'image/jpeg',
      // Acceso público — el bucket debe tener Block Public Access desactivado
      // y una bucket policy que permita s3:GetObject a *
      ACL: 'public-read',
    })
  );

  const region = env.AWS_REGION ?? 'us-east-1';
  // URL pública estándar de S3
  return `https://${env.AWS_S3_BUCKET}.s3.${region}.amazonaws.com/${key}`;
}

// ── Cloudinary ────────────────────────────────────────────────────────────────

async function uploadToCloudinary(buffer: Buffer, folder: string, publicId: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      { folder, resource_type: 'image', public_id: publicId },
      (err, res) => {
        if (err) reject(err);
        else if (res) resolve(res.secure_url);
        else reject(new Error('No response from Cloudinary'));
      }
    );
    stream.end(buffer);
  });
}

// ── Local (fallback dev) ──────────────────────────────────────────────────────

async function uploadToLocal(buffer: Buffer, subfolder: string, filename: string): Promise<string> {
  const dir = path.join(process.cwd(), 'uploads', subfolder);
  await fs.mkdir(dir, { recursive: true });
  const filePath = path.join(dir, filename);
  await fs.writeFile(filePath, buffer);
  const base = (env.API_PUBLIC_URL ?? 'http://localhost:3000').replace(/\/$/, '');
  return `${base}/uploads/${subfolder}/${filename}`;
}

// ── Procesamiento con Sharp ───────────────────────────────────────────────────

async function processImage(buffer: Buffer): Promise<Buffer> {
  return sharp(buffer)
    .resize(SHARP_MAX, SHARP_MAX, { fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 85, progressive: true })
    .toBuffer();
}

// ── API pública ───────────────────────────────────────────────────────────────

export interface UploadOptions {
  /** Carpeta lógica: 'caregivers', 'pets', 'service-events', etc. */
  folder: string;
  /** Nombre base del archivo (sin extensión). Por defecto: UUID. */
  name?: string;
}

/**
 * Sube una imagen al almacenamiento persistente (S3 → Cloudinary → local).
 * La imagen es procesada con Sharp antes de subirse.
 * Devuelve la URL pública permanente.
 */
export async function uploadImage(buffer: Buffer, opts: UploadOptions): Promise<string> {
  const processed = await processImage(buffer);
  const name = opts.name ?? randomUUID();
  const filename = `${name}.jpg`;

  // 1. S3 (preferido — persistente, gratis dentro del free tier)
  if (isS3Configured()) {
    try {
      const url = await uploadToS3Public(processed, `garden/${opts.folder}`, filename);
      logger.info('storage.service: imagen subida a S3', { url, folder: opts.folder });
      return url;
    } catch (err) {
      logger.error('storage.service: fallo S3, intentando Cloudinary', { error: err });
    }
  }

  // 2. Cloudinary (fallback)
  if (isCloudinaryConfigured()) {
    try {
      const url = await uploadToCloudinary(processed, `garden/${opts.folder}`, name);
      logger.info('storage.service: imagen subida a Cloudinary', { url, folder: opts.folder });
      return url;
    } catch (err) {
      logger.error('storage.service: fallo Cloudinary, usando disco local', { error: err });
    }
  }

  // 3. Disco local (solo dev — ephemeral en Render)
  if (env.NODE_ENV === 'production') {
    logger.error(
      'storage.service: ⚠️  NINGÚN STORAGE PERSISTENTE CONFIGURADO. ' +
      'Las imágenes se perderán al reiniciar. ' +
      'Configura AWS_S3_BUCKET o CLOUDINARY_* en las variables de entorno de Render.',
      { folder: opts.folder }
    );
  }
  const url = await uploadToLocal(processed, opts.folder, filename);
  logger.info('storage.service: imagen guardada localmente', { url, folder: opts.folder });
  return url;
}

/**
 * Sube múltiples imágenes en paralelo.
 */
export async function uploadImages(buffers: Buffer[], opts: UploadOptions): Promise<string[]> {
  return Promise.all(
    buffers.map((buf, i) =>
      uploadImage(buf, { ...opts, name: opts.name ? `${opts.name}_${i + 1}` : undefined })
    )
  );
}

/**
 * Log de estado del storage al iniciar el servidor.
 */
export function logStorageStatus(): void {
  if (isS3Configured()) {
    logger.info(`✅ Storage: AWS S3 (bucket: ${env.AWS_S3_BUCKET})`);
  } else if (isCloudinaryConfigured()) {
    logger.info(`✅ Storage: Cloudinary (cloud: ${env.CLOUDINARY_CLOUD_NAME})`);
  } else {
    logger.warn(
      '⚠️  Storage: disco local EPHEMERAL — las imágenes SE PIERDEN al reiniciar Render. ' +
      'Configura AWS_S3_BUCKET (+ AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) en Render.'
    );
  }
}

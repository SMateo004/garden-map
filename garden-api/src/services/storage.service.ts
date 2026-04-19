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
import logger from '../shared/logger.js';

const SHARP_MAX = 1024;

// ── Cloudinary setup ──────────────────────────────────────────────────────────
// Read directly from process.env (bypasses Zod parsing issues with empty strings
// from committed .env file overriding Render panel values).
function isCloudinaryConfigured(): boolean {
  const name = (process.env['CLOUDINARY_CLOUD_NAME'] ?? '').trim();
  const key  = (process.env['CLOUDINARY_API_KEY'] ?? '').trim();
  const sec  = (process.env['CLOUDINARY_API_SECRET'] ?? '').trim();
  if (name && key && sec) {
    cloudinary.config({ cloud_name: name, api_key: key, api_secret: sec });
    return true;
  }
  // Diagnostic: log which credentials are missing
  logger.warn('storage.service: Cloudinary NOT configured', {
    CLOUDINARY_CLOUD_NAME: name ? `"${name.slice(0,4)}…"` : '(empty)',
    CLOUDINARY_API_KEY:    key  ? `"${key.slice(0,4)}…"`  : '(empty)',
    CLOUDINARY_API_SECRET: sec  ? '(present)'              : '(empty)',
  });
  return false;
}

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
  const isProd = env.NODE_ENV === 'production';

  // 1. S3 (preferido — persistente, gratis dentro del free tier)
  if (isS3Configured()) {
    try {
      const url = await uploadToS3Public(processed, `garden/${opts.folder}`, filename);
      logger.info('storage.service: imagen subida a S3', { url, folder: opts.folder });
      return url;
    } catch (err) {
      logger.error('storage.service: fallo S3, intentando Cloudinary', { error: err });
      // En producción, si S3 falla y no hay Cloudinary, lanzar error
      // continuar al siguiente fallback
    }
  }

  // 2. Cloudinary (preferido cuando S3 no está — persistente)
  if (isCloudinaryConfigured()) {
    // Reintentar hasta 2 veces en caso de error transitorio
    let lastErr: unknown;
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        const url = await uploadToCloudinary(processed, `garden/${opts.folder}`, name);
        logger.info('storage.service: imagen subida a Cloudinary', { url, folder: opts.folder });
        return url;
      } catch (err) {
        lastErr = err;
        logger.warn(`storage.service: fallo Cloudinary intento ${attempt}/2`, { error: err });
        if (attempt < 2) await new Promise(r => setTimeout(r, 1000));
      }
    }
    logger.error('storage.service: Cloudinary falló tras 2 intentos, cayendo a disco local', { error: lastErr });
  }

  // 3. Disco local — fallback (ephemeral en Render: las imágenes SE PIERDEN al reiniciar)
  if (isProd) {
    logger.error(
      'storage.service: ⚠️  GUARDANDO EN DISCO LOCAL EPHEMERAL. ' +
      'Las imágenes SE PERDERÁN al reiniciar Render. ' +
      'Agrega CLOUDINARY_CLOUD_NAME + CLOUDINARY_API_KEY + CLOUDINARY_API_SECRET en Render > Environment.',
      { folder: opts.folder }
    );
  }
  const url = await uploadToLocal(processed, opts.folder, filename);
  logger.info('storage.service: imagen guardada localmente', { url, folder: opts.folder, isProd });
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
  const nodeEnv = process.env['NODE_ENV'];
  const cloudName = (process.env['CLOUDINARY_CLOUD_NAME'] ?? '').trim();
  const cloudKey  = (process.env['CLOUDINARY_API_KEY'] ?? '').trim();
  const cloudSec  = (process.env['CLOUDINARY_API_SECRET'] ?? '').trim();

  logger.info('storage.service: diagnóstico de credenciales', {
    NODE_ENV: nodeEnv,
    CLOUDINARY_CLOUD_NAME: cloudName ? `"${cloudName.slice(0,6)}…"` : '(vacío)',
    CLOUDINARY_API_KEY:    cloudKey  ? `"${cloudKey.slice(0,6)}…"`  : '(vacío)',
    CLOUDINARY_API_SECRET: cloudSec  ? '(present)'                   : '(vacío)',
  });

  if (isS3Configured()) {
    logger.info(`✅ Storage: AWS S3 (bucket: ${env.AWS_S3_BUCKET})`);
  } else if (cloudName && cloudKey && cloudSec) {
    logger.info(`✅ Storage: Cloudinary (cloud: ${cloudName})`);
  } else {
    logger.error(
      '❌ Storage: disco local EPHEMERAL — las imágenes SE PIERDEN al reiniciar Render. ' +
      'Agrega CLOUDINARY_CLOUD_NAME + CLOUDINARY_API_KEY + CLOUDINARY_API_SECRET en Render > Environment.'
    );
  }
}

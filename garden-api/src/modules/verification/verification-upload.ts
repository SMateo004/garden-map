/**
 * Upload verification images: S3 (private) when configured, else Cloudinary/local.
 * S3 keys are stored for signed URLs; Cloudinary/local returns full URLs.
 */

import path from 'path';
import fs from 'fs/promises';
import sharp from 'sharp';
import { v2 as cloudinary } from 'cloudinary';
import { env } from '../../config/env.js';
import { isCloudinaryConfigured } from '../../config/cloudinary.js';
import {
  isS3Configured,
  uploadToS3,
  getSignedUrlForKey,
} from './s3-verification.service.js';

const VERIFICATION_FOLDER = 'garden/verification';

/** Result: S3 key (verification/...) or full URL. */
export async function uploadVerificationImage(buffer: Buffer, prefix: string, userId: string): Promise<string> {
  const processed = await sharp(buffer)
    .resize(1200, 1200, { fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 85, progressive: true })
    .toBuffer();

  if (isS3Configured()) {
    const key = `${userId}/${prefix}-${Date.now()}.jpg`;
    await uploadToS3(processed, key);
    return `verification/${key}`;
  }

  if (isCloudinaryConfigured()) {
    const result = await new Promise<{ secure_url: string }>((resolve, reject) => {
      const stream = cloudinary.uploader.upload_stream(
        {
          folder: `${VERIFICATION_FOLDER}/${userId}`,
          resource_type: 'image',
          public_id: `${prefix}-${Date.now()}`,
        },
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

  const baseDir = path.join(process.cwd(), 'uploads', 'verification', userId);
  await fs.mkdir(baseDir, { recursive: true });
  const filename = `${prefix}-${Date.now()}.jpg`;
  const filePath = path.join(baseDir, filename);
  await fs.writeFile(filePath, processed);
  const baseUrl = env.API_PUBLIC_URL || 'http://localhost:3000';
  return `${baseUrl.replace(/\/$/, '')}/uploads/verification/${userId}/${filename}`;
}

/**
 * Resolve URL for admin viewing. If S3 key (starts with verification/), return signed URL.
 */
export async function resolveUrlForAdmin(stored: string | null): Promise<string | null> {
  if (!stored) return null;
  if (stored.startsWith('verification/')) {
    return getSignedUrlForKey(stored);
  }
  return stored;
}

/**
 * S3 storage for verification images (private bucket, signed URLs for admin).
 */

import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { env } from '../../config/env.js';

const BUCKET = env.AWS_S3_BUCKET;
const PREFIX = 'verification';
const SIGNED_URL_EXPIRY = 60 * 60; // 1 hour

function getS3Client(): S3Client | null {
  if (env.AWS_ACCESS_KEY_ID && env.AWS_SECRET_ACCESS_KEY && BUCKET) {
    return new S3Client({
      region: env.AWS_REGION,
      credentials: {
        accessKeyId: env.AWS_ACCESS_KEY_ID,
        secretAccessKey: env.AWS_SECRET_ACCESS_KEY,
      },
    });
  }
  return null;
}

export function isS3Configured(): boolean {
  return !!getS3Client();
}

export async function uploadToS3(
  buffer: Buffer,
  key: string,
  contentType = 'image/jpeg'
): Promise<string> {
  const client = getS3Client();
  if (!client || !BUCKET) {
    throw new Error('S3 not configured');
  }

  const fullKey = `${PREFIX}/${key}`;
  await client.send(
    new PutObjectCommand({
      Bucket: BUCKET,
      Key: fullKey,
      Body: buffer,
      ContentType: contentType,
    })
  );

  return fullKey;
}

/**
 * Returns a signed URL for private S3 object. Use for admin viewing.
 */
export async function getSignedUrlForKey(key: string): Promise<string> {
  const client = getS3Client();
  if (!client || !BUCKET) {
    return key;
  }

  const { GetObjectCommand } = await import('@aws-sdk/client-s3');
  const command = new GetObjectCommand({ Bucket: BUCKET, Key: key });
  return getSignedUrl(client, command, { expiresIn: SIGNED_URL_EXPIRY });
}

/**
 * Magic-bytes MIME validation
 *
 * Uses the `file-type` package to inspect the actual binary content of an
 * uploaded buffer instead of trusting the client-supplied Content-Type header.
 * A malicious client can set Content-Type: image/jpeg on a PDF, script, or
 * executable; magic bytes cannot be faked without corrupting the file.
 *
 * Usage:
 *   await assertImageBuffer(file.buffer);  // throws AppError on mismatch
 */

import { fileTypeFromBuffer } from 'file-type';
import { AppError } from './errors.js';

/** MIME types that we accept as valid images. */
const ALLOWED_IMAGE_MIMES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/avif',
  'image/heic',
  'image/heif',
]);

/**
 * Throws a 400 AppError if the buffer does not start with the magic bytes of
 * a recognised image format. Returns the detected MIME type (from magic
 * bytes, not the client-supplied header) — callers that need to know the
 * real type (e.g. to pass to Claude vision, which only accepts a subset of
 * these) can use it instead of re-detecting.
 */
export async function assertImageBuffer(buffer: Buffer): Promise<string> {
  const type = await fileTypeFromBuffer(buffer);

  if (!type || !ALLOWED_IMAGE_MIMES.has(type.mime)) {
    throw new AppError(
      `Formato de archivo no permitido${type ? ` (${type.mime})` : ''}. Solo se aceptan imágenes (JPG, PNG, WEBP, GIF).`,
      400,
      'INVALID_FILE_TYPE',
    );
  }
  return type.mime;
}

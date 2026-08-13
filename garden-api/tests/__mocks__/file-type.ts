/**
 * Manual mock de `file-type` (paquete ESM-only — Jest/ts-jest no puede
 * transformar su `import` sin meterse en configuración ESM completa, ver
 * SyntaxError "Cannot use import statement outside a module"). Ningún test
 * depende hoy de detección real de magic bytes (los que tocan upload mockean
 * la capa de middleware/storage antes de llegar a mime-validation.ts), pero
 * esto sniffea los formatos reales igual por si algún test futuro sí lo
 * necesita — más fiel que devolver siempre undefined.
 *
 * Jest la usa automáticamente para cualquier `import ... from 'file-type'`
 * porque vive en __mocks__ adyacente a la carpeta que jest.config.js declara
 * como `roots` (tests/), sin necesidad de jest.mock('file-type') en cada test.
 */

export interface FileTypeResult {
  ext: string;
  mime: string;
}

const SIGNATURES: Array<{ mime: string; ext: string; match: (b: Buffer) => boolean }> = [
  { mime: 'image/jpeg', ext: 'jpg', match: (b) => b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff },
  {
    mime: 'image/png',
    ext: 'png',
    match: (b) => b.length >= 8 && b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
  },
  { mime: 'image/gif', ext: 'gif', match: (b) => b.length >= 6 && (b.subarray(0, 6).toString('ascii') === 'GIF87a' || b.subarray(0, 6).toString('ascii') === 'GIF89a') },
  {
    mime: 'image/webp',
    ext: 'webp',
    match: (b) => b.length >= 12 && b.subarray(0, 4).toString('ascii') === 'RIFF' && b.subarray(8, 12).toString('ascii') === 'WEBP',
  },
  { mime: 'application/pdf', ext: 'pdf', match: (b) => b.length >= 4 && b.subarray(0, 4).toString('ascii') === '%PDF' },
];

export async function fileTypeFromBuffer(input: Uint8Array | ArrayBuffer): Promise<FileTypeResult | undefined> {
  const buffer = Buffer.isBuffer(input) ? input : Buffer.from(input as ArrayBuffer);
  const hit = SIGNATURES.find((s) => s.match(buffer));
  return hit ? { ext: hit.ext, mime: hit.mime } : undefined;
}

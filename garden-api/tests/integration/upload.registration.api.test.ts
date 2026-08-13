/**
 * Integration tests: POST /api/upload/registration-photos (mock uploads).
 * The controller delegates to storage.service.uploadImages — mock that instead
 * of the old upload.middleware.processAndUploadToCloudinary.
 */

const FAKE_URLS = [
  'https://res.cloudinary.com/1.jpg',
  'https://res.cloudinary.com/2.jpg',
  'https://res.cloudinary.com/3.jpg',
  'https://res.cloudinary.com/4.jpg',
];

const mockUploadImages = jest.fn().mockResolvedValue(FAKE_URLS);

jest.mock('../../src/services/storage.service', () => ({
  uploadImages: (...args: unknown[]) => mockUploadImages(...args),
  uploadImage: jest.fn().mockResolvedValue('https://res.cloudinary.com/single.jpg'),
}));

// Minimal valid JPEG magic bytes (FF D8 FF) — uploadRegistrationPhotosHandler
// calls assertImageBuffer() for real (mocking upload.middleware only bypasses
// multer, not the handler's own magic-byte check), so the fake buffer needs to
// actually sniff as an image or it 400s with INVALID_FILE_TYPE.
const FAKE_JPEG_BUFFER = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);

// Inject 4 fake photo buffers via the upload.middleware mock
jest.mock('../../src/modules/caregiver-service/upload.middleware', () => ({
  uploadCaregiverPhotos: (req: { files?: unknown[] }, _res: unknown, next: () => void) => {
    req.files = Array(4).fill(null).map((_, i) => ({
      buffer: FAKE_JPEG_BUFFER,
      fieldname: 'photos',
      originalname: `photo${i + 1}.jpg`,
      mimetype: 'image/jpeg',
      size: 100,
    }));
    next();
  },
  processAndUploadToCloudinary: jest.fn().mockResolvedValue(FAKE_URLS),
}));

// image/jpeg sí dispara validarFoto (CLAUDE_VISION_MIMES) — mockear para no
// pegarle a la API real de Claude en el test.
jest.mock('../../src/agents/foto-validacion.agent', () => ({
  validarFoto: jest.fn().mockResolvedValue({ valida: true, razon: '' }),
}));

// Bypass maintenance mode
jest.mock('../../src/utils/settings-cache', () => ({
  getBoolSetting: jest.fn().mockResolvedValue(false),
  getNumericSetting: jest.fn().mockResolvedValue(0),
  getStringSetting: jest.fn().mockResolvedValue(''),
  invalidateSetting: jest.fn(),
}));
jest.mock('../../src/middleware/maintenance.middleware', () => ({
  maintenanceMiddleware: (_req: unknown, _res: unknown, next: () => void) => next(),
}));

import request from 'supertest';
import app from '../../src/app';

describe('Upload registration API (integration)', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockUploadImages.mockResolvedValue(FAKE_URLS);
  });

  it('returns 200 and urls when mock injects 4 files', async () => {
    const res = await request(app).post('/api/upload/registration-photos');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.urls).toHaveLength(4);
    expect(res.body.data.urls[0]).toContain('cloudinary');
    expect(mockUploadImages).toHaveBeenCalledWith(
      expect.any(Array),
      expect.objectContaining({ folder: 'caregivers' })
    );
  });
});

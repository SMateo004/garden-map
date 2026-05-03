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

// Inject 4 fake photo buffers via the upload.middleware mock
jest.mock('../../src/modules/caregiver-service/upload.middleware', () => ({
  uploadCaregiverPhotos: (req: { files?: unknown[] }, _res: unknown, next: () => void) => {
    req.files = Array(4).fill(null).map((_, i) => ({
      buffer: Buffer.from('fake-image-data'),
      fieldname: 'photos',
      originalname: `photo${i + 1}.jpg`,
      mimetype: 'image/jpeg',
      size: 100,
    }));
    next();
  },
  processAndUploadToCloudinary: jest.fn().mockResolvedValue(FAKE_URLS),
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

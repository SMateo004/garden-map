/**
 * Integration tests: POST /api/upload/registration-photos (mock uploads).
 */

const mockProcessAndUpload = jest.fn().mockResolvedValue([
  'https://res.cloudinary.com/1.jpg',
  'https://res.cloudinary.com/2.jpg',
  'https://res.cloudinary.com/3.jpg',
  'https://res.cloudinary.com/4.jpg',
]);

jest.mock('../../src/modules/caregiver-service/upload.middleware', () => ({
  uploadCaregiverPhotos: (req: { files?: unknown[] }, _res: unknown, next: () => void) => {
    req.files = Array(4).fill(null).map((_, i) => ({
      buffer: Buffer.alloc(100),
      fieldname: 'photos',
      originalname: `photo${i + 1}.jpg`,
      mimetype: 'image/jpeg',
      size: 100,
    }));
    next();
  },
  processAndUploadToCloudinary: mockProcessAndUpload,
}));

jest.mock('../../src/config/cloudinary', () => ({
  isCloudinaryConfigured: () => true,
  CLOUDINARY_FOLDER: 'garden/caregivers',
  CLOUDINARY_FOLDER_PETS: 'garden/pets',
  CLOUDINARY_FOLDER_CI: 'garden/ci',
}));

import request from 'supertest';
import app from '../../src/app';

describe('Upload registration API (integration)', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockProcessAndUpload.mockResolvedValue([
      'https://res.cloudinary.com/1.jpg',
      'https://res.cloudinary.com/2.jpg',
      'https://res.cloudinary.com/3.jpg',
      'https://res.cloudinary.com/4.jpg',
    ]);
  });

  it('returns 200 and urls when mock injects 4 files', async () => {
    const res = await request(app).post('/api/upload/registration-photos');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.urls).toHaveLength(4);
    expect(res.body.data.urls[0]).toContain('cloudinary');
    expect(mockProcessAndUpload).toHaveBeenCalledWith(expect.any(Array), expect.stringMatching(/^registration-/));
  });
});

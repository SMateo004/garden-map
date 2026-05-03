/**
 * Unit: processAndUploadToCloudinary
 *
 * The function delegates to storage.service.uploadImages — mock that module
 * instead of mocking Cloudinary/sharp directly (those are internal details).
 */
import { processAndUploadToCloudinary } from '../../src/modules/caregiver-service/upload.middleware';
import { PhotoUploadError } from '../../src/shared/errors';

const mockUploadImages = jest.fn();

// Mock the dynamic import inside processAndUploadToCloudinary
jest.mock('../../src/services/storage.service', () => ({
  uploadImages: (...args: unknown[]) => mockUploadImages(...args),
}));

describe('Upload middleware (storage.service mock)', () => {
  beforeEach(() => {
    mockUploadImages.mockClear();
    mockUploadImages.mockResolvedValue([
      'https://cloudinary.com/photo_1.jpg',
      'https://cloudinary.com/photo_2.jpg',
      'https://cloudinary.com/photo_3.jpg',
      'https://cloudinary.com/photo_4.jpg',
    ]);
  });

  it('throws when fewer than 2 buffers (current minimum)', async () => {
    await expect(processAndUploadToCloudinary([], 'user-1')).rejects.toThrow(PhotoUploadError);
    await expect(processAndUploadToCloudinary([Buffer.alloc(1)], 'user-1')).rejects.toThrow(
      PhotoUploadError
    );
  });

  it('throws when more than 6 buffers', async () => {
    const seven = Array(7).fill(Buffer.alloc(1));
    await expect(processAndUploadToCloudinary(seven, 'user-1')).rejects.toThrow(PhotoUploadError);
  });

  it('returns 4 URLs when given 4 buffers', async () => {
    const buffers = Array(4).fill(Buffer.alloc(1));
    const urls = await processAndUploadToCloudinary(buffers, 'user-1');
    expect(urls).toHaveLength(4);
    expect(urls.every((u) => u.startsWith('https://'))).toBe(true);
    expect(mockUploadImages).toHaveBeenCalledTimes(1);
  });

  it('calls uploadImages with folder "caregivers" and name containing userId', async () => {
    const buffers = Array(4).fill(Buffer.alloc(1));
    await processAndUploadToCloudinary(buffers, 'caregiver-123');
    expect(mockUploadImages).toHaveBeenCalledWith(
      buffers,
      expect.objectContaining({
        folder: 'caregivers',
        name: expect.stringContaining('caregiver-123'),
      })
    );
  });

  it('wraps storage errors in PhotoUploadError', async () => {
    mockUploadImages.mockRejectedValue(new Error('S3 timeout'));
    const buffers = Array(4).fill(Buffer.alloc(1));
    await expect(processAndUploadToCloudinary(buffers, 'user-1')).rejects.toThrow(PhotoUploadError);
  });
});

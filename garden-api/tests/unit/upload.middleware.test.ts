/**
 * Unit: processAndUploadToCloudinary con Cloudinary y sharp mockeados
 */
import { processAndUploadToCloudinary } from '../../src/modules/caregiver-service/upload.middleware';
import { PhotoUploadError } from '../../src/shared/errors';

jest.mock('../../src/config/cloudinary', () => ({
  isCloudinaryConfigured: () => true,
  cloudinary: {
    uploader: {
      upload_stream: jest.fn(),
    },
  },
}));

jest.mock('sharp', () => {
  return jest.fn(() => ({
    resize: jest.fn().mockReturnThis(),
    jpeg: jest.fn().mockReturnThis(),
    toBuffer: jest.fn().mockResolvedValue(Buffer.from('fake-jpeg')),
  }));
});

const mockUploadStream = jest.fn();
jest.mock('cloudinary', () => ({
  v2: {
    uploader: {
      upload_stream(opts: unknown, cb: (err: null, res: { secure_url: string }) => void) {
        mockUploadStream(opts);
        const stream = {
          end(_data: Buffer) {
            setImmediate(() => cb(null, { secure_url: 'https://cloudinary.com/photo_1.jpg' }));
          },
        };
        return stream;
      },
    },
  },
}));

describe('Upload middleware (Cloudinary mock)', () => {
  beforeEach(() => {
    mockUploadStream.mockClear();
  });

  it('throws when fewer than 2 buffers (current minimum)', async () => {
    // 0 buffers
    await expect(processAndUploadToCloudinary([], 'user-1')).rejects.toThrow(PhotoUploadError);
    // 1 buffer
    await expect(processAndUploadToCloudinary([Buffer.alloc(1)], 'user-1')).rejects.toThrow(
      PhotoUploadError
    );
  });

  it('throws when more than 6 buffers', async () => {
    const seven = Array(7).fill(Buffer.alloc(1));
    await expect(processAndUploadToCloudinary(seven, 'user-1')).rejects.toThrow(PhotoUploadError);
  });

  it('returns 4 URLs when given 4 buffers', async () => {
    const buffers = [Buffer.alloc(1), Buffer.alloc(1), Buffer.alloc(1), Buffer.alloc(1)];
    const urls = await processAndUploadToCloudinary(buffers, 'user-1');
    expect(urls).toHaveLength(4);
    expect(urls.every((u) => u.startsWith('https://'))).toBe(true);
    expect(mockUploadStream).toHaveBeenCalledTimes(4);
  });

  it('calls upload_stream with folder containing userId', async () => {
    const buffers = Array(4).fill(Buffer.alloc(1));
    await processAndUploadToCloudinary(buffers, 'caregiver-123');
    expect(mockUploadStream).toHaveBeenCalledWith(
      expect.objectContaining({
        folder: expect.stringContaining('caregiver-123'),
        resource_type: 'image',
        public_id: expect.stringMatching(/photo_\d/),
      })
    );
  });
});

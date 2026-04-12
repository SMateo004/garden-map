import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as bookingService from './booking.service.js';

export const start = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const caregiverUserId = req.user!.userId;
    const { photo } = req.body;
    const booking = await bookingService.startService(bookingId, caregiverUserId, photo);
    res.json({ success: true, data: booking });
});

export const addEvent = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const caregiverUserId = req.user!.userId;
    const { type, description } = req.body;
    let photoUrl = req.body.photoUrl;

    if (req.file) {
        let uploaded = false;
        try {
            const { isCloudinaryConfigured, CLOUDINARY_FOLDER } = await import('../../config/cloudinary.js');
            if (isCloudinaryConfigured()) {
                const { v2: cloudinary } = await import('cloudinary');
                const folder = `${CLOUDINARY_FOLDER}/service-events`;
                const publicId = `event_${bookingId}_${Date.now()}`;
                photoUrl = await new Promise<string>((resolve, reject) => {
                    const stream = cloudinary.uploader.upload_stream(
                        { folder, resource_type: 'image', public_id: publicId },
                        (err, result) => {
                            if (err) reject(err);
                            else if (result) resolve(result.secure_url);
                            else reject(new Error('No response from Cloudinary'));
                        }
                    );
                    stream.end(req.file!.buffer);
                });
                uploaded = true;
            }
        } catch (err) {
            console.error('[addEvent] Cloudinary upload failed, falling back to local:', err);
        }
        if (!uploaded) {
            // Fallback to local filesystem
            const fs = await import('fs/promises');
            const path = await import('path');
            const filename = `event-${bookingId}-${Date.now()}.jpg`;
            const uploadDir = path.join(process.cwd(), 'uploads', 'service-events');
            await fs.mkdir(uploadDir, { recursive: true });
            await fs.writeFile(path.join(uploadDir, filename), req.file.buffer);
            photoUrl = `${process.env.API_PUBLIC_URL || process.env.API_BASE_URL || 'http://localhost:3000'}/uploads/service-events/${filename}`;
        }
    }

    const booking = await bookingService.addServiceEvent(bookingId, caregiverUserId, type, description, photoUrl);
    res.json({ success: true, data: booking });
});

export const track = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const caregiverUserId = req.user!.userId;
    const { lat, lng, accuracy } = req.body;
    await bookingService.trackServiceLocation(bookingId, caregiverUserId, lat, lng, accuracy);
    res.json({ success: true });
});

export const getTrack = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const userId = req.user!.userId;
    const track = await bookingService.getGpsTrack(bookingId, userId);
    res.json({ success: true, data: track });
});

export const conclude = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const caregiverUserId = req.user!.userId;
    const { photo, lat, lng } = req.body;
    const booking = await bookingService.concludeService(bookingId, caregiverUserId, photo, lat, lng);
    res.json({ success: true, data: booking });
});

export const confirmReceipt = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const clientId = req.user!.userId;
    const { rating, comment } = req.body;
    const booking = await bookingService.confirmReceiptByClient(bookingId, clientId, Number(rating), comment);
    res.json({ success: true, data: booking });
});

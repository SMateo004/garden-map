import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as bookingService from './booking.service.js';
import { uploadImage } from '../../services/storage.service.js';
import {
  startServiceBodySchema,
  trackLocationBodySchema,
  concludeServiceBodySchema,
  confirmReceiptBodySchema,
  addEventBodySchema,
} from './booking.validation.js';
import { BadRequestError } from '../../shared/errors.js';

export const start = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const caregiverUserId = req.user!.userId;

    const parsed = startServiceBodySchema.safeParse(req.body);
    if (!parsed.success) {
        throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
    }

    const booking = await bookingService.startService(bookingId, caregiverUserId, parsed.data.photo);
    res.json({ success: true, data: booking });
});

export const addEvent = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const caregiverUserId = req.user!.userId;

    // If a file was uploaded, resolve URL first then merge into body for validation
    let uploadedPhotoUrl: string | undefined;
    if (req.file) {
        uploadedPhotoUrl = await uploadImage(req.file.buffer, {
            folder: 'service-events',
            name: `event_${bookingId}_${Date.now()}`,
        });
    }

    const bodyToValidate = {
        type: req.body.type,
        description: req.body.description,
        photoUrl: uploadedPhotoUrl ?? req.body.photoUrl,
    };

    const parsed = addEventBodySchema.safeParse(bodyToValidate);
    if (!parsed.success) {
        throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
    }

    const booking = await bookingService.addServiceEvent(
        bookingId,
        caregiverUserId,
        parsed.data.type,
        parsed.data.description,
        parsed.data.photoUrl
    );
    res.json({ success: true, data: booking });
});

export const track = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const caregiverUserId = req.user!.userId;

    const parsed = trackLocationBodySchema.safeParse(req.body);
    if (!parsed.success) {
        throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Coordenadas inválidas', 'VALIDATION_ERROR');
    }

    await bookingService.trackServiceLocation(
        bookingId,
        caregiverUserId,
        parsed.data.lat,
        parsed.data.lng,
        parsed.data.accuracy
    );
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

    const parsed = concludeServiceBodySchema.safeParse(req.body);
    if (!parsed.success) {
        throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
    }

    const booking = await bookingService.concludeService(
        bookingId,
        caregiverUserId,
        parsed.data.photo,
        parsed.data.lat ?? 0,
        parsed.data.lng ?? 0
    );
    res.json({ success: true, data: booking });
});

export const confirmReceipt = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const clientId = req.user!.userId;

    const parsed = confirmReceiptBodySchema.safeParse(req.body);
    if (!parsed.success) {
        throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
    }

    const booking = await bookingService.confirmReceiptByClient(
        bookingId,
        clientId,
        parsed.data.rating,
        parsed.data.comment
    );
    res.json({ success: true, data: booking });
});

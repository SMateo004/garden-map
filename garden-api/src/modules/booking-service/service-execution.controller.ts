import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as bookingService from './booking.service.js';
import { uploadImage, uploadRawFile } from '../../services/storage.service.js';
import { assertImageBuffer } from '../../shared/mime-validation.js';
import { validarFoto, type CategoriaFoto } from '../../agents/foto-validacion.agent.js';
import prisma from '../../config/database.js';
import { AppError } from '../../shared/errors.js';
import {
  startServiceBodySchema,
  trackLocationBodySchema,
  concludeServiceBodySchema,
  confirmReceiptBodySchema,
  rateOwnerBodySchema,
  addEventBodySchema,
  confirmEndBodySchema,
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

    // Detect if the uploaded file is a video or image
    let uploadedPhotoUrl: string | undefined;
    let uploadedVideoUrl: string | undefined;
    if (req.file) {
        const mime = req.file.mimetype;
        if (mime.startsWith('video/')) {
            uploadedVideoUrl = await uploadRawFile(req.file.buffer, {
                folder: 'service-events',
                name: `video_${bookingId}_${Date.now()}`,
            }, mime);
        } else {
            // Magic-bytes check (el mimetype de arriba es el header del cliente,
            // no confiable) + validación de contenido: en PASEO se espera evidencia
            // de la mascota; en HOSPEDAJE/GUARDERIA, del espacio del hogar donde
            // se la cuida.
            const detectedMime = await assertImageBuffer(req.file.buffer);
            if (['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(detectedMime)) {
                const booking = await prisma.booking.findUnique({ where: { id: bookingId }, select: { serviceType: true } });
                const categoria: CategoriaFoto = booking?.serviceType === 'PASEO' ? 'MASCOTA' : 'ESPACIO_HOGAR';
                const resultado = await validarFoto({
                    imageBuffer: req.file.buffer,
                    mediaType: detectedMime as 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif',
                    categoria,
                    userId: caregiverUserId,
                    contexto: 'service-event',
                });
                if (!resultado.valida) {
                    throw new AppError(resultado.razon, 422, 'FOTO_NO_VALIDA');
                }
            }
            uploadedPhotoUrl = await uploadImage(req.file.buffer, {
                folder: 'service-events',
                name: `event_${bookingId}_${Date.now()}`,
            });
        }
    }

    const bodyToValidate = {
        type: req.body.type,
        description: req.body.description,
        photoUrl: uploadedPhotoUrl ?? req.body.photoUrl,
        videoUrl: uploadedVideoUrl ?? req.body.videoUrl,
        incidentType: req.body.incidentType,
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
        parsed.data.photoUrl,
        parsed.data.videoUrl,
        parsed.data.incidentType,
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
        parsed.data.lat ?? null,
        parsed.data.lng ?? null
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
        parsed.data.comment,
        parsed.data.skillTags
    );
    res.json({ success: true, data: booking });
});

export const markEndedByClient = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const clientId = req.user!.userId;

    const booking = await bookingService.markServiceEndedByClient(bookingId, clientId);
    res.json({ success: true, data: booking });
});

export const confirmEnd = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const caregiverUserId = req.user!.userId;

    const parsed = confirmEndBodySchema.safeParse(req.body);
    if (!parsed.success) {
        throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
    }

    const booking = await bookingService.confirmServiceEndByCaregiver(
        bookingId,
        caregiverUserId,
        parsed.data.accepted
    );
    res.json({ success: true, data: booking });
});

export const rateOwner = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const caregiverUserId = req.user!.userId;

    const parsed = rateOwnerBodySchema.safeParse(req.body);
    if (!parsed.success) {
        throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
    }

    const booking = await bookingService.rateOwner(
        bookingId,
        caregiverUserId,
        parsed.data.rating,
        parsed.data.comment
    );
    res.json({ success: true, data: booking });
});

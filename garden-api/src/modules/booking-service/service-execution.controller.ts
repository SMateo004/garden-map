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
    const booking = await bookingService.addServiceEvent(bookingId, caregiverUserId, type, description);
    res.json({ success: true, data: booking });
});

export const track = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const caregiverUserId = req.user!.userId;
    const { lat, lng } = req.body;
    await bookingService.trackServiceLocation(bookingId, caregiverUserId, lat, lng);
    res.json({ success: true });
});

export const conclude = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const caregiverUserId = req.user!.userId;
    const { photo, rating, lat, lng } = req.body;
    const booking = await bookingService.concludeService(bookingId, caregiverUserId, photo, Number(rating), lat, lng);
    res.json({ success: true, data: booking });
});

export const confirmReceipt = asyncHandler(async (req: Request, res: Response) => {
    const bookingId = req.params.id!;
    const clientId = req.user!.userId;
    const booking = await bookingService.confirmReceiptByClient(bookingId, clientId);
    res.json({ success: true, data: booking });
});

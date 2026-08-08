import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as recurringBookingService from './recurring-booking.service.js';
import { createRecurringSeriesSchema } from './recurring-booking.validation.js';

/** POST /api/recurring-bookings — crear serie de paseos recurrentes. */
export const create = asyncHandler(async (req: Request, res: Response) => {
  const clientId = req.user!.userId;
  const body = createRecurringSeriesSchema.parse(req.body);
  const series = await recurringBookingService.createSeries(clientId, body);
  res.status(201).json({ success: true, data: series });
});

/** GET /api/recurring-bookings/my — series activas/pausadas del cliente. */
export const getMy = asyncHandler(async (req: Request, res: Response) => {
  const clientId = req.user!.userId;
  const series = await recurringBookingService.listMySeries(clientId);
  res.json({ success: true, data: series });
});

/** PATCH /api/recurring-bookings/:id/pause */
export const pause = asyncHandler(async (req: Request, res: Response) => {
  const clientId = req.user!.userId;
  const series = await recurringBookingService.pauseSeries(clientId, req.params.id!);
  res.json({ success: true, data: series });
});

/** PATCH /api/recurring-bookings/:id/resume */
export const resume = asyncHandler(async (req: Request, res: Response) => {
  const clientId = req.user!.userId;
  const series = await recurringBookingService.resumeSeries(clientId, req.params.id!);
  res.json({ success: true, data: series });
});

/** DELETE /api/recurring-bookings/:id — cancela la serie (no borra el historial de reservas ya generadas). */
export const cancel = asyncHandler(async (req: Request, res: Response) => {
  const clientId = req.user!.userId;
  const series = await recurringBookingService.cancelSeries(clientId, req.params.id!);
  res.json({ success: true, data: series });
});

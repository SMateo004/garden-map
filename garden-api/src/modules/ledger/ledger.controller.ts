import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as ledgerService from './ledger.service.js';
import { streamMonthlyLedgerPdf } from './ledger.pdf.js';
import { createManualEntrySchema, monthParamsSchema } from './ledger.validation.js';

/** GET /api/admin/ledger/accounts — plan de cuentas (para el selector del form manual). */
export const getAccounts = asyncHandler(async (_req: Request, res: Response) => {
  const data = await ledgerService.getAccounts();
  res.json({ success: true, data });
});

/** GET /api/admin/ledger/:year/:month — libro diario del mes + estado de resultados. */
export const getMonthly = asyncHandler(async (req: Request, res: Response) => {
  const { year, month } = monthParamsSchema.parse(req.params);
  const data = await ledgerService.getMonthlyLedger(year, month);
  res.json({ success: true, data });
});

/** GET /api/admin/ledger/:year/:month/pdf — descarga el reporte del mes en PDF. */
export const getMonthlyPdf = asyncHandler(async (req: Request, res: Response) => {
  const { year, month } = monthParamsSchema.parse(req.params);
  const data = await ledgerService.getMonthlyLedger(year, month);
  streamMonthlyLedgerPdf(res, data);
});

/** POST /api/admin/ledger/manual-entry — cargar aporte de capital / gasto operativo / etc. */
export const createManualEntry = asyncHandler(async (req: Request, res: Response) => {
  const adminUserId = req.user!.userId;
  const body = createManualEntrySchema.parse(req.body);
  const data = await ledgerService.addManualEntry(adminUserId, body);
  res.status(201).json({ success: true, data });
});

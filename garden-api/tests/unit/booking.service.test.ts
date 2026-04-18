import { describe, it, expect } from '@jest/globals';
import { ServiceType, RefundStatus } from '@prisma/client';
import type { Booking } from '@prisma/client';

/**
 * Mock settings-cache so calculateRefund uses the built-in default values
 * without touching the database.
 * Defaults: hospedaje 100%>48h | 50%>24h | fee=10 bs; paseo 100%>12h | 50%>6h.
 */
jest.mock('../../src/utils/settings-cache.js', () => ({
  getNumericSetting: jest.fn((_key: string, defaultValue: number) =>
    Promise.resolve(defaultValue)
  ),
  getBoolSetting: jest.fn((_key: string, defaultValue: boolean) =>
    Promise.resolve(defaultValue)
  ),
  getStringSetting: jest.fn((_key: string, defaultValue: string) =>
    Promise.resolve(defaultValue)
  ),
  invalidateSetting: jest.fn(),
}));

import { calculateRefund } from '../../src/modules/booking-service/booking.service.js';

/**
 * All date arithmetic below uses LOCAL-time methods (.setHours, .setDate, etc.)
 * to match the service's own normalization (it calls getFullYear/getMonth/getDate
 * + new Date(y, m, d, ...) which are local-time operations).
 */

/** Returns a Date set to LOCAL midnight of the given date object */
function localMidnight(d: Date): Date {
  const r = new Date(d);
  r.setHours(0, 0, 0, 0);
  return r;
}

/** Returns a Date set to LOCAL noon of the given date object */
function localNoon(d: Date): Date {
  const r = new Date(d);
  r.setHours(12, 0, 0, 0);
  return r;
}

/** Returns a new Date whose local calendar day is `offsetDays` from today */
function daysFromNow(offsetDays: number): Date {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  return d;
}

describe('calculateRefund', () => {
  /** Mimics Prisma's Decimal: Number(d) uses valueOf(), d.toNumber() also works */
  const decimal = (n: number) => ({ valueOf: () => n, toNumber: () => n });

  const baseBooking: Pick<
    Booking,
    'serviceType' | 'startDate' | 'endDate' | 'walkDate' | 'timeSlot' | 'totalAmount'
  > = {
    serviceType: ServiceType.HOSPEDAJE,
    totalAmount: decimal(300) as any,
    startDate: null,
    endDate: null,
    walkDate: null,
    timeSlot: null,
  };

  // ─── HOSPEDAJE ───────────────────────────────────────────────────────────
  //
  // The service normalises startDate → local midnight of that calendar day.
  // hoursUntil = (localMidnight(startDate) - cancellationDate) / 1h
  //   >48h → 100%; >24h → 50%; else → 0%

  describe('Hospedaje', () => {
    it('retorna 100% (menos Bs 10 admin) si se cancela >48h antes', async () => {
      // midnight 5 days from now - now ≈ (5*24 - hour_of_day) ≥ 96h → always > 48h ✓
      const startDate = daysFromNow(5);
      const cancellationDate = new Date();
      const booking = { ...baseBooking, serviceType: ServiceType.HOSPEDAJE, startDate };

      const result = await calculateRefund(booking, cancellationDate);

      expect(result.refundStatus).toBe(RefundStatus.APPROVED);
      expect(result.refundPercent).toBe(100);
      expect(result.refundAmount).toBe(290); // 300 - 10 admin fee
    });

    it('retorna 50% si se cancela entre 24-48h antes', async () => {
      // midnight 2 days from now - (midnight today + 1 min) ≈ 47h59m → > 24, < 48 ✓
      const startDate = daysFromNow(2);
      const cancellationDate = new Date(localMidnight(new Date()).getTime() + 60_000); // +1 min
      const booking = { ...baseBooking, serviceType: ServiceType.HOSPEDAJE, startDate };

      const result = await calculateRefund(booking, cancellationDate);

      expect(result.refundStatus).toBe(RefundStatus.APPROVED);
      expect(result.refundPercent).toBe(50);
      expect(result.refundAmount).toBe(150);
    });

    it('retorna 0% si se cancela <24h antes', async () => {
      // midnight TODAY - now = negative (already past midnight) → 0% ✓
      const startDate = new Date(); // today
      startDate.setHours(8, 0, 0, 0); // 8 AM today local
      const cancellationDate = new Date();
      cancellationDate.setHours(10, 0, 0, 0); // 10 AM today (after midnight ref)
      const booking = { ...baseBooking, serviceType: ServiceType.HOSPEDAJE, startDate };

      const result = await calculateRefund(booking, cancellationDate);

      expect(result.refundStatus).toBe(RefundStatus.REJECTED);
      expect(result.refundPercent).toBe(0);
      expect(result.refundAmount).toBe(0);
    });

    it('retorna 0% si no hay startDate', async () => {
      const booking = { ...baseBooking, serviceType: ServiceType.HOSPEDAJE, startDate: null };
      const result = await calculateRefund(booking, new Date());

      expect(result.refundStatus).toBe(RefundStatus.REJECTED);
      expect(result.refundAmount).toBe(0);
    });
  });

  // ─── PASEO ───────────────────────────────────────────────────────────────
  //
  // The service normalises walkDate → local NOON of that calendar day.
  // hoursUntil = (localNoon(walkDate) - cancellationDate) / 1h
  //   >12h → 100%; >6h → 50%; else → 0%
  //
  // We pick a fixed cancellationDate = local noon today - 9h = 3 AM today.
  // Then:
  //   - walkDate whose local noon is 2+ days away → 100% (>> 12h)
  //   - walkDate whose local noon is today        → 9h away → 50%  (6 < 9 < 12)
  //   - walkDate whose local noon has already passed (yesterday) → negative → 0%

  describe('Paseo', () => {
    // Fix cancellationDate = 3 AM LOCAL today so hoursUntil = noon - 3 AM = 9h (PASEO 50%)
    const noonToday = localNoon(new Date());
    const at3amToday = new Date(noonToday.getTime() - 9 * 3600 * 1000);

    it('retorna 100% si se cancela >12h antes', async () => {
      // local noon 3 days from now − at3amToday ≫ 12h ✓
      const walkDate = daysFromNow(3);
      const booking = {
        ...baseBooking,
        serviceType: ServiceType.PASEO,
        walkDate,
        totalAmount: decimal(50) as any,
      };

      const result = await calculateRefund(booking, at3amToday);

      expect(result.refundStatus).toBe(RefundStatus.APPROVED);
      expect(result.refundPercent).toBe(100);
      expect(result.refundAmount).toBe(50);
    });

    it('retorna 50% si se cancela entre 6-12h antes', async () => {
      // local noon today − at3amToday = 9h → 6 < 9 < 12 ✓
      const walkDate = new Date(); // today (any local time, noon is what matters)
      const booking = {
        ...baseBooking,
        serviceType: ServiceType.PASEO,
        walkDate,
        totalAmount: decimal(50) as any,
      };

      const result = await calculateRefund(booking, at3amToday);

      expect(result.refundStatus).toBe(RefundStatus.APPROVED);
      expect(result.refundPercent).toBe(50);
      expect(result.refundAmount).toBe(25);
    });

    it('retorna 0% si el paseo ya pasó (noon < cancellationDate)', async () => {
      // local noon yesterday − at3amToday = negative → REJECTED ✓
      const walkDate = daysFromNow(-1); // yesterday
      const booking = {
        ...baseBooking,
        serviceType: ServiceType.PASEO,
        walkDate,
        totalAmount: decimal(50) as any,
      };

      const result = await calculateRefund(booking, at3amToday);

      expect(result.refundStatus).toBe(RefundStatus.REJECTED);
      expect(result.refundPercent).toBe(0);
      expect(result.refundAmount).toBe(0);
    });

    it('retorna 0% si no hay walkDate', async () => {
      const booking = {
        ...baseBooking,
        serviceType: ServiceType.PASEO,
        walkDate: null,
        totalAmount: decimal(50) as any,
      };

      const result = await calculateRefund(booking, new Date());

      expect(result.refundStatus).toBe(RefundStatus.REJECTED);
      expect(result.refundAmount).toBe(0);
    });
  });
});

import { describe, it, expect } from '@jest/globals';
import { ServiceType, RefundStatus } from '@prisma/client';
import { calculateRefund } from '../../src/modules/booking-service/booking.service.js';
import type { Booking } from '@prisma/client';

describe('calculateRefund', () => {
  const baseBooking: Pick<Booking, 'serviceType' | 'startDate' | 'endDate' | 'walkDate' | 'timeSlot' | 'totalAmount'> = {
    serviceType: ServiceType.HOSPEDAJE,
    totalAmount: { toNumber: () => 300 } as any,
    startDate: null,
    endDate: null,
    walkDate: null,
    timeSlot: null,
  };

  describe('Hospedaje', () => {
    it('debe retornar 100% de reembolso (menos Bs 10 admin) si se cancela >48h antes', () => {
      const startDate = new Date();
      startDate.setDate(startDate.getDate() + 3); // 3 días = 72h
      const cancellationDate = new Date();

      const booking = {
        ...baseBooking,
        serviceType: ServiceType.HOSPEDAJE,
        startDate,
        totalAmount: { toNumber: () => 300 } as any,
      };

      const result = calculateRefund(booking, cancellationDate);

      expect(result.refundStatus).toBe(RefundStatus.APPROVED);
      expect(result.refundPercent).toBe(100);
      expect(result.refundAmount).toBe(290); // 300 - 10 admin fee
    });

    it('debe retornar 50% de reembolso si se cancela entre 24-48h antes', () => {
      const startDate = new Date();
      startDate.setHours(startDate.getHours() + 36); // 36h
      const cancellationDate = new Date();

      const booking = {
        ...baseBooking,
        serviceType: ServiceType.HOSPEDAJE,
        startDate,
        totalAmount: { toNumber: () => 300 } as any,
      };

      const result = calculateRefund(booking, cancellationDate);

      expect(result.refundStatus).toBe(RefundStatus.APPROVED);
      expect(result.refundPercent).toBe(50);
      expect(result.refundAmount).toBe(150);
    });

    it('debe retornar 0% de reembolso si se cancela <24h antes', () => {
      const startDate = new Date();
      startDate.setHours(startDate.getHours() + 12); // 12h
      const cancellationDate = new Date();

      const booking = {
        ...baseBooking,
        serviceType: ServiceType.HOSPEDAJE,
        startDate,
        totalAmount: { toNumber: () => 300 } as any,
      };

      const result = calculateRefund(booking, cancellationDate);

      expect(result.refundStatus).toBe(RefundStatus.REJECTED);
      expect(result.refundPercent).toBe(0);
      expect(result.refundAmount).toBe(0);
    });

    it('debe retornar 0% si no hay startDate', () => {
      const booking = {
        ...baseBooking,
        serviceType: ServiceType.HOSPEDAJE,
        startDate: null,
        totalAmount: { toNumber: () => 300 } as any,
      };

      const result = calculateRefund(booking, new Date());

      expect(result.refundStatus).toBe(RefundStatus.REJECTED);
      expect(result.refundAmount).toBe(0);
    });
  });

  describe('Paseo', () => {
    it('debe retornar 100% de reembolso si se cancela >12h antes', () => {
      const walkDate = new Date();
      walkDate.setHours(walkDate.getHours() + 18); // 18h
      const cancellationDate = new Date();

      const booking = {
        ...baseBooking,
        serviceType: ServiceType.PASEO,
        walkDate,
        totalAmount: { toNumber: () => 50 } as any,
      };

      const result = calculateRefund(booking, cancellationDate);

      expect(result.refundStatus).toBe(RefundStatus.APPROVED);
      expect(result.refundPercent).toBe(100);
      expect(result.refundAmount).toBe(50);
    });

    it('debe retornar 50% de reembolso si se cancela entre 6-12h antes', () => {
      const walkDate = new Date();
      walkDate.setHours(walkDate.getHours() + 9); // 9h
      const cancellationDate = new Date();

      const booking = {
        ...baseBooking,
        serviceType: ServiceType.PASEO,
        walkDate,
        totalAmount: { toNumber: () => 50 } as any,
      };

      const result = calculateRefund(booking, cancellationDate);

      expect(result.refundStatus).toBe(RefundStatus.APPROVED);
      expect(result.refundPercent).toBe(50);
      expect(result.refundAmount).toBe(25);
    });

    it('debe retornar 0% de reembolso si se cancela <6h antes', () => {
      const walkDate = new Date();
      walkDate.setHours(walkDate.getHours() + 3); // 3h
      const cancellationDate = new Date();

      const booking = {
        ...baseBooking,
        serviceType: ServiceType.PASEO,
        walkDate,
        totalAmount: { toNumber: () => 50 } as any,
      };

      const result = calculateRefund(booking, cancellationDate);

      expect(result.refundStatus).toBe(RefundStatus.REJECTED);
      expect(result.refundPercent).toBe(0);
      expect(result.refundAmount).toBe(0);
    });

    it('debe retornar 0% si no hay walkDate', () => {
      const booking = {
        ...baseBooking,
        serviceType: ServiceType.PASEO,
        walkDate: null,
        totalAmount: { toNumber: () => 50 } as any,
      };

      const result = calculateRefund(booking, new Date());

      expect(result.refundStatus).toBe(RefundStatus.REJECTED);
      expect(result.refundAmount).toBe(0);
    });
  });
});

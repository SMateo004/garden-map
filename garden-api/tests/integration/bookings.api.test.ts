/**
 * Integration tests: bookings API (POST create, POST cancel, POST extend, POST change-dates).
 * Prisma is mocked; no real DB required.
 */

import request from 'supertest';
import prisma from '../../src/config/database';
import { BookingStatus, ServiceType, RefundStatus } from '@prisma/client';

jest.mock('../../src/config/database', () => {
  const booking = {
    findFirst: jest.fn(),
    findUnique: jest.fn(),
    findMany: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
    count: jest.fn(),
  };
  const caregiverData = {
    id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    userId: 'caregiver-user-id',
    status: 'APPROVED',
    verified: true,
    suspended: false,
    servicesOffered: ['HOSPEDAJE', 'PASEO'],
    pricePerDay: 100,
    pricePerWalk30: 50,
    pricePerWalk60: 80,
  };
  const caregiverProfile = {
    findUnique: jest.fn().mockResolvedValue(caregiverData),
    findFirst: jest.fn().mockResolvedValue(caregiverData),
  };
  const availability = { findMany: jest.fn() };
  const user = { findUnique: jest.fn() };
  const notification = { create: jest.fn().mockResolvedValue({}) };
  const walletTransaction = { create: jest.fn().mockResolvedValue({}) };
  const petData = { id: 'b2c3d4e5-f6a7-8901-bcde-f12345678901', name: 'Max', ownerId: 'user-client-1', species: 'DOG', breed: 'Labrador' };
  const pet = {
    findUnique: jest.fn().mockResolvedValue(petData),
    findFirst: jest.fn().mockResolvedValue(petData),
  };
  const clientProfile = {
    findUnique: jest.fn().mockResolvedValue({
      id: 'cp-1', userId: 'user-client-1', isComplete: true,
      pets: [{ id: 'b2c3d4e5-f6a7-8901-bcde-f12345678901' }],
    }),
  };
  const appSettings = { findUnique: jest.fn().mockResolvedValue(null) };
  const txModels = { booking, caregiverProfile, availability, user, notification, walletTransaction, pet, clientProfile, appSettings };
  const db = {
    booking,
    caregiverProfile,
    availability,
    user,
    notification,
    walletTransaction,
    pet,
    clientProfile,
    appSettings,
    $queryRaw: jest.fn().mockResolvedValue([]),
    $executeRaw: jest.fn().mockResolvedValue(0),
    $transaction: jest.fn((fn: (tx: unknown) => Promise<unknown>) => fn(txModels)),
  };
  return { __esModule: true, default: db };
});

// Bypass maintenance mode + service-enabled checks in tests (no real DB)
// Mock all three possible import paths Jest may resolve:
const settingsCacheMock = {
  // maintenanceMode → false (app open), *Enabled flags → true (services on)
  getBoolSetting: jest.fn().mockImplementation((key: string, defaultValue: boolean) =>
    Promise.resolve(key === 'maintenanceMode' ? false : defaultValue !== false ? true : false)
  ),
  getNumericSetting: jest.fn().mockResolvedValue(0),
  getStringSetting: jest.fn().mockResolvedValue(''),
  invalidateSetting: jest.fn(),
};
jest.mock('../../src/utils/settings-cache', () => settingsCacheMock);

jest.mock('../../src/middleware/maintenance.middleware', () => ({
  maintenanceMiddleware: (_req: unknown, _res: unknown, next: () => void) => next(),
}));

jest.mock('../../src/shared/cache', () => ({
  getCache: () => ({
    get: jest.fn().mockResolvedValue(null),
    set: jest.fn().mockResolvedValue(undefined),
    del: jest.fn().mockResolvedValue(undefined),
  }),
  caregiverListCacheKey: () => 'caregivers:list',
  caregiverDetailCacheKey: () => 'caregivers:detail',
}));

jest.mock('../../src/config/stripe', () => ({
  stripe: null,
  STRIPE_WEBHOOK_SECRET: '',
}));

jest.mock('../../src/middleware/auth.middleware', () => ({
  authMiddleware: (req: { user?: { id: string; role: string } }, _res: unknown, next: () => void) => {
    req.user = { id: 'user-client-1', role: 'CLIENT' } as { id: string; email: string; role: string };
    next();
  },
  requireRole: () => (_req: unknown, _res: unknown, next: () => void) => next(),
}));

import app from '../../src/app';

const mockPrisma = prisma as jest.Mocked<typeof prisma>;

describe('POST /api/bookings', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('debe crear una reserva de hospedaje exitosamente', async () => {
    const caregiverId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
    const startDate = new Date();
    startDate.setDate(startDate.getDate() + 3);
    const endDate = new Date(startDate);
    endDate.setDate(endDate.getDate() + 3);

    (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue({
      id: caregiverId,
      status: 'APPROVED',
      verified: true,
      services: ['HOSPEDAJE'],
      pricePerDay: 100,
    });

    (mockPrisma.availability.findMany as jest.Mock).mockResolvedValue([
      { date: startDate, isAvailable: true },
      { date: new Date(startDate.getTime() + 24 * 60 * 60 * 1000), isAvailable: true },
      { date: endDate, isAvailable: true },
    ]);

    (mockPrisma.booking.count as jest.Mock).mockResolvedValue(0);
    (mockPrisma.booking.create as jest.Mock).mockResolvedValue({
      id: 'booking-1',
      serviceType: ServiceType.HOSPEDAJE,
      status: BookingStatus.PENDING_PAYMENT,
      startDate,
      endDate,
      totalDays: 3,
      totalAmount: { toNumber: () => 300 },
      pricePerUnit: { toNumber: () => 100 },
      commissionAmount: { toNumber: () => 30 },
      qrId: 'QR-123',
      qrImageUrl: 'https://example.com/qr.png',
      qrExpiresAt: new Date(),
      petName: 'Max',
      caregiverId,
      clientId: 'user-client-1',
      createdAt: new Date(),
    });

    const response = await request(app)
      .post('/api/bookings')
      .send({
        serviceType: 'HOSPEDAJE',
        caregiverId,
        petId: 'b2c3d4e5-f6a7-8901-bcde-f12345678901',
        startDate: startDate.toISOString().slice(0, 10),
        endDate: endDate.toISOString().slice(0, 10),
        totalDays: 3,
        petName: 'Max',
      });

    expect(response.status).toBe(201);
    expect(response.body.success).toBe(true);
    expect(response.body.data.serviceType).toBe('HOSPEDAJE');
  });

  it('debe rechazar crear reserva si el cuidador no está APPROVED', async () => {
    // The service uses findFirst to check caregiver status — return null to simulate not-APPROVED
    (mockPrisma.caregiverProfile.findFirst as jest.Mock).mockResolvedValue(null);
    (mockPrisma.caregiverProfile.findUnique as jest.Mock).mockResolvedValue(null);

    const response = await request(app).post('/api/bookings').send({
      serviceType: 'HOSPEDAJE',
      caregiverId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      petId: 'b2c3d4e5-f6a7-8901-bcde-f12345678901',
      startDate: '2026-06-15',  // future date to pass date validation
      endDate: '2026-06-18',
      totalDays: 3,
      petName: 'Max',
    });

    // Caregiver not found → 400 (BAD_REQUEST)
    expect(response.status).toBe(400);
  });
});

describe('POST /api/bookings/:id/cancel', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('debe cancelar una reserva y calcular reembolso correctamente', async () => {
    const bookingId = 'booking-1';
    const startDate = new Date();
    startDate.setDate(startDate.getDate() + 3); // >48h

    (mockPrisma.booking.findFirst as jest.Mock).mockResolvedValue({
      id: bookingId,
      clientId: 'user-client-1',
      status: BookingStatus.CONFIRMED,
      serviceType: ServiceType.HOSPEDAJE,
      startDate,
      totalAmount: { toNumber: () => 300 },
    });

    (mockPrisma.booking.update as jest.Mock).mockResolvedValue({
      id: bookingId,
      status: BookingStatus.CANCELLED,
      refundAmount: { toNumber: () => 290 },
      refundStatus: RefundStatus.APPROVED,
      cancelledAt: new Date(),
    });

    const response = await request(app).post(`/api/bookings/${bookingId}/cancel`).send({
      reason: 'Cambio de planes',
    });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(response.body.data.status).toBe('CANCELLED');
  });
});

describe('GET /api/bookings/my', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('debe retornar las reservas del cliente', async () => {
    (mockPrisma.booking.findMany as jest.Mock).mockResolvedValue([
      {
        id: 'booking-1',
        serviceType: ServiceType.HOSPEDAJE,
        status: BookingStatus.CONFIRMED,
        totalAmount: { toNumber: () => 300 },
        caregiver: {
          user: { firstName: 'Juan', lastName: 'Pérez' },
        },
      },
    ]);

    const response = await request(app).get('/api/bookings/my');

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(Array.isArray(response.body.data)).toBe(true);
  });
});

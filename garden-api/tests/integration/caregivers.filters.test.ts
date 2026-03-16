/**
 * Integration tests: caregivers filters (GET /api/caregivers with filters).
 * Verifica que los filtros funcionen correctamente y solo retornen APPROVED.
 */

import request from 'supertest';
import prisma from '../../src/config/database';
import { CaregiverStatus } from '@prisma/client';

jest.mock('../../src/config/database', () => {
  const caregiverProfile = {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    count: jest.fn(),
  };
  const user = { findUnique: jest.fn() };
  const availability = { findMany: jest.fn() };
  const db = {
    caregiverProfile,
    user,
    availability,
  };
  return { __esModule: true, default: db };
});

jest.mock('../../src/shared/cache', () => ({
  getCache: () => ({
    get: jest.fn().mockResolvedValue(null),
    set: jest.fn().mockResolvedValue(undefined),
    del: jest.fn().mockResolvedValue(undefined),
  }),
  caregiverListCacheKey: () => 'caregivers:list',
  caregiverDetailCacheKey: () => 'caregivers:detail',
}));

import app from '../../src/app';

const mockPrisma = prisma as jest.Mocked<typeof prisma>;

describe('GET /api/caregivers con filtros', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('debe filtrar solo cuidadores APPROVED', async () => {
    (mockPrisma.caregiverProfile.findMany as jest.Mock).mockResolvedValue([
      {
        id: 'cp-1',
        status: CaregiverStatus.APPROVED,
        verified: true,
        services: ['HOSPEDAJE'],
        zone: 'NORTE',
        pricePerDay: 100,
      },
    ]);

    const response = await request(app).get('/api/caregivers');

    expect(response.status).toBe(200);
    expect(mockPrisma.caregiverProfile.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          status: CaregiverStatus.APPROVED,
          verified: true,
        }),
      })
    );
  });

  it('debe aplicar filtro de servicio (HOSPEDAJE)', async () => {
    (mockPrisma.caregiverProfile.findMany as jest.Mock).mockResolvedValue([]);

    await request(app).get('/api/caregivers?service=HOSPEDAJE');

    expect(mockPrisma.caregiverProfile.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          services: { has: 'HOSPEDAJE' },
        }),
      })
    );
  });

  it('debe aplicar filtro de zona', async () => {
    (mockPrisma.caregiverProfile.findMany as jest.Mock).mockResolvedValue([]);

    await request(app).get('/api/caregivers?zone=NORTE');

    expect(mockPrisma.caregiverProfile.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          zone: 'NORTE',
        }),
      })
    );
  });

  it('debe aplicar filtro de rango de precio', async () => {
    (mockPrisma.caregiverProfile.findMany as jest.Mock).mockResolvedValue([]);

    await request(app).get('/api/caregivers?priceRange=economico');

    expect(mockPrisma.caregiverProfile.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          pricePerDay: expect.objectContaining({
            lte: expect.any(Number),
          }),
        }),
      })
    );
  });

  it('debe combinar múltiples filtros', async () => {
    (mockPrisma.caregiverProfile.findMany as jest.Mock).mockResolvedValue([]);

    await request(app).get('/api/caregivers?service=HOSPEDAJE&zone=NORTE&priceRange=estandar');

    const call = (mockPrisma.caregiverProfile.findMany as jest.Mock).mock.calls[0]?.[0];
    expect(call?.where).toMatchObject({
      status: CaregiverStatus.APPROVED,
      verified: true,
      services: { has: 'HOSPEDAJE' },
      zone: 'NORTE',
    });
  });
});

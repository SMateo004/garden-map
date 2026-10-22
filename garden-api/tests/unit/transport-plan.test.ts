import { describe, it, expect } from '@jest/globals';
import { ServiceType, RefundStatus } from '@prisma/client';

jest.mock('../../src/utils/settings-cache.js', () => ({
  getNumericSetting: jest.fn((_key: string, d: number) => Promise.resolve(d)),
  getBoolSetting: jest.fn((_key: string, d: boolean) => Promise.resolve(d)),
  getStringSetting: jest.fn((_key: string, d: string) => Promise.resolve(d)),
  invalidateSetting: jest.fn(),
}));

import {
  planTransport,
  haversineKm,
  publicTransportOf,
  legScheduledMs,
  transportGrossOf,
} from '../../src/modules/transport/transport.service.js';
import { calculateRefund } from '../../src/modules/booking-service/booking.service.js';

// Santa Cruz: Plaza 24 de Septiembre y un punto ~3 km al norte.
const PLAZA = { lat: -17.7838, lng: -63.1821 };
const NORTE = { lat: -17.757, lng: -63.1821 };
const LEJOS = { lat: -17.6, lng: -63.18 }; // ~20 km

const caregiver = (over: Record<string, unknown> = {}) => ({
  id: 'cg1',
  servicesOffered: [ServiceType.GUARDERIA, ServiceType.HOSPEDAJE, ServiceType.PASEO],
  addressLat: PLAZA.lat,
  addressLng: PLAZA.lng,
  transportEnabled: true,
  transportPickupFee: 15,
  transportDropoffFee: 10,
  transportMaxKm: 5,
  ...over,
});
const client = (pos = NORTE) => ({
  address: 'Av. Banzer', addressLat: pos.lat, addressLng: pos.lng, addressReference: 'Portón verde',
  addressStreet: 'Av. Banzer', addressNumber: '123', addressApartment: null, addressCondominio: null,
});
const day = (iso: string) => new Date(`${iso}T00:00:00.000Z`);
// "Ahora" fijo: 1 de diciembre 2030 08:00 Bolivia (12:00 UTC).
const NOW = Date.UTC(2030, 11, 1, 12, 0);
const hospedaje = { serviceType: ServiceType.HOSPEDAJE, startDate: day('2030-12-05'), endDate: day('2030-12-08'), walkDate: null, startTime: null, timeSlot: null, duration: null };
const guarderia = { serviceType: ServiceType.GUARDERIA, startDate: null, endDate: null, walkDate: day('2030-12-05'), startTime: '08:30', timeSlot: 'MANANA', duration: 480 };

describe('distancia y datos públicos', () => {
  it('haversine da ~3 km entre la plaza y el norte', () => {
    expect(haversineKm(PLAZA, NORTE)).toBeGreaterThan(2.8);
    expect(haversineKm(PLAZA, NORTE)).toBeLessThan(3.3);
  });
  it('solo se muestra si está activo, tiene ubicación y ofrece guardería u hospedaje', () => {
    expect(publicTransportOf(caregiver())).toMatchObject({ pickupFee: 15, dropoffFee: 10, maxKm: 5 });
    expect(publicTransportOf(caregiver({ transportEnabled: false }))).toBeNull();
    expect(publicTransportOf(caregiver({ addressLat: null }))).toBeNull();
    expect(publicTransportOf(caregiver({ servicesOffered: [ServiceType.PASEO] }))).toBeNull();
    expect(publicTransportOf(caregiver())!.services).not.toContain(ServiceType.PASEO);
  });
});

describe('hora de cada viaje (derivada de la reserva)', () => {
  it('hospedaje: recojo el día de entrada, entrega el de salida, a la hora elegida (Bolivia = UTC-4)', () => {
    expect(new Date(legScheduledMs(hospedaje, { kind: 'PICKUP', time: '09:00' })!).toISOString()).toBe('2030-12-05T13:00:00.000Z');
    expect(new Date(legScheduledMs(hospedaje, { kind: 'DROPOFF', time: '18:30' })!).toISOString()).toBe('2030-12-08T22:30:00.000Z');
  });
  it('si se extiende el hospedaje, la entrega se mueve sola', () => {
    const extended = { ...hospedaje, endDate: day('2030-12-10') };
    expect(new Date(legScheduledMs(extended, { kind: 'DROPOFF', time: '18:30' })!).toISOString()).toBe('2030-12-10T22:30:00.000Z');
  });
  it('guardería: recojo al inicio, entrega al terminar (y sigue a una extensión de horas)', () => {
    expect(new Date(legScheduledMs(guarderia, { kind: 'PICKUP', time: null })!).toISOString()).toBe('2030-12-05T12:30:00.000Z');
    expect(new Date(legScheduledMs(guarderia, { kind: 'DROPOFF', time: null })!).toISOString()).toBe('2030-12-05T20:30:00.000Z');
    expect(new Date(legScheduledMs({ ...guarderia, duration: 600 }, { kind: 'DROPOFF', time: null })!).toISOString()).toBe('2030-12-05T22:30:00.000Z');
    // sin hora exacta usa el turno
    expect(new Date(legScheduledMs({ ...guarderia, startTime: null }, { kind: 'PICKUP', time: null })!).toISOString()).toBe('2030-12-05T12:00:00.000Z');
  });
});

describe('planTransport — lo que se puede pedir al reservar', () => {
  const ctx = (over: Record<string, unknown> = {}) => ({ caregiver: caregiver(), client: client(), booking: hospedaje, nowMs: NOW, ...over }) as any;

  it('sin pedido no hay viajes ni monto', () => {
    expect(planTransport(undefined, ctx())).toEqual({ legs: [], amount: 0, tax: 0 });
    expect(planTransport({ pickup: null, dropoff: null }, ctx())).toEqual({ legs: [], amount: 0, tax: 0 });
  });

  it('recojo y entrega: suma los dos precios con copia de la dirección y la distancia', () => {
    const r = planTransport({ pickup: { time: '09:00' }, dropoff: { time: '18:00' } }, ctx());
    expect(r.amount).toBe(25);
    expect(r.tax).toBe(0);
    expect(r.legs.map((l) => l.kind)).toEqual(['PICKUP', 'DROPOFF']);
    expect(r.legs[0]).toMatchObject({ fee: 15, time: '09:00', addressReference: 'Portón verde', address: 'Av. Banzer #123' });
    expect(r.legs[0]!.distanceKm).toBeCloseTo(3, 0);
  });

  it('solo el recojo (el dueño lo busca después) o solo la entrega', () => {
    expect(planTransport({ pickup: { time: '09:00' } }, ctx()).amount).toBe(15);
    expect(planTransport({ dropoff: { time: '18:00' } }, ctx()).amount).toBe(10);
  });

  it('gratis (precio 0) es válido', () => {
    const r = planTransport({ pickup: { time: '09:00' } }, ctx({ caregiver: caregiver({ transportPickupFee: 0 }) }));
    expect(r.amount).toBe(0);
    expect(r.legs).toHaveLength(1);
  });

  it('impuesto por viaje, redondeado igual que el de la reserva', () => {
    const r = planTransport({ pickup: { time: '09:00' }, dropoff: { time: '18:00' } }, ctx({ taxRate: 0.16 }));
    expect(r.legs.map((l) => l.tax)).toEqual([2, 2]); // 15·0.16=2.4→2 · 10·0.16=1.6→2
    expect(r.tax).toBe(4);
  });

  it('guardería: no pide horas (salen de la reserva) e ignora las que mande la app', () => {
    const r = planTransport({ pickup: { time: '03:00' }, dropoff: {} }, ctx({ booking: guarderia }));
    expect(r.legs.map((l) => l.time)).toEqual([null, null]);
  });

  it.each([
    ['cuidador sin transporte', { caregiver: caregiver({ transportEnabled: false }) }, /no ofrece/],
    ['paseo', { booking: { ...guarderia, serviceType: ServiceType.PASEO } }, /solo para guardería u hospedaje/],
    ['dueño sin dirección en el mapa', { client: { ...client(), addressLat: null } }, /dirección/],
    ['dueño sin perfil', { client: null }, /dirección/],
    ['fuera del radio (sin revelar la distancia exacta)', { client: client(LEJOS) }, /fuera del área donde este cuidador recoge \(hasta 5 km\)/],
  ])('rechaza: %s', (_n, over, msg) => {
    expect(() => planTransport({ pickup: { time: '09:00' } }, ctx(over))).toThrow(msg as RegExp);
  });

  it.each([
    [{ pickup: {} }, /Elige la hora de recojo/],
    [{ pickup: { time: '9:00' } }, /Elige la hora/],
    [{ pickup: { time: '25:00' } }, /Elige la hora/],
    [{ pickup: { time: '05:30' } }, /entre las 06:00 y las 21:00/],
    [{ dropoff: { time: '22:00' } }, /entre las 06:00 y las 21:00/],
    [{ pickup: { time: 'mañana' } }, /Elige la hora/],
  ])('hospedaje: horas inválidas %#', (req, msg) => {
    expect(() => planTransport(req as any, ctx())).toThrow(msg);
  });

  it('el recojo tiene que quedar al menos 45 min en el futuro', () => {
    const today = { ...hospedaje, startDate: day('2030-12-01') };
    expect(() => planTransport({ pickup: { time: '08:30' } }, ctx({ booking: today }))).toThrow(/al menos 45 minutos/);
    expect(planTransport({ pickup: { time: '09:00' } }, ctx({ booking: today })).legs).toHaveLength(1);
    // la entrega no tiene ese límite (se pide para el día de salida)
    expect(planTransport({ dropoff: { time: '07:00' } }, ctx()).legs).toHaveLength(1);
  });
});

describe('reembolso al cancelar la reserva: el transporte se devuelve completo', () => {
  const decimal = (n: number) => ({ valueOf: () => n, toNumber: () => n }) as any;
  const inHours = (h: number) => new Date(Date.now() + h * 3600_000);
  const startIn = (h: number) => {
    const d = inHours(h);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
  };

  it('hospedaje cancelado tarde (0% del servicio): igual se devuelve el recojo y la entrega', async () => {
    const r = await calculateRefund(
      { serviceType: ServiceType.HOSPEDAJE, totalAmount: decimal(325), transportAmount: decimal(25), transportTaxAmount: decimal(0), startDate: startIn(2), endDate: null, walkDate: null, timeSlot: null } as any,
      new Date()
    );
    expect(r.refundAmount).toBe(25);
    expect(r.refundStatus).toBe(RefundStatus.APPROVED);
    expect(r.refundPercent).toBe(0);
  });

  it('con mucha anticipación: servicio menos el cargo administrativo + transporte entero', async () => {
    const r = await calculateRefund(
      { serviceType: ServiceType.HOSPEDAJE, totalAmount: decimal(329), transportAmount: decimal(25), transportTaxAmount: decimal(4), startDate: startIn(24 * 6), endDate: null, walkDate: null, timeSlot: null } as any,
      new Date()
    );
    // servicio 300 − 10 de cargo administrativo + 29 de transporte (con impuesto)
    expect(r.refundAmount).toBe(319);
    expect(r.refundPercent).toBe(100);
  });

  it('sin transporte el cálculo es el de siempre', async () => {
    const r = await calculateRefund(
      { serviceType: ServiceType.HOSPEDAJE, totalAmount: decimal(300), startDate: startIn(24 * 6), endDate: null, walkDate: null, timeSlot: null } as any,
      new Date()
    );
    expect(r.refundAmount).toBe(290);
  });

  it('si el cuidador ya salió a recogerlo, ese viaje NO se devuelve (se le paga a él)', async () => {
    const r = await calculateRefund(
      {
        serviceType: ServiceType.HOSPEDAJE, totalAmount: decimal(325), transportAmount: decimal(25), transportTaxAmount: decimal(0),
        startDate: startIn(2), endDate: null, walkDate: null, timeSlot: null,
        transportLegs: [{ status: 'EN_ROUTE', fee: 15, tax: 0, trackingData: [{ lat: 1, lng: 1 }] }, { status: 'SCHEDULED', fee: 10, tax: 0 }],
      } as any,
      new Date()
    );
    expect(r.refundAmount).toBe(10); // solo la entrega, que no empezó
  });

  it('sin nada que devolver queda rechazado (no "aprobado por 0")', async () => {
    const r = await calculateRefund(
      {
        serviceType: ServiceType.HOSPEDAJE, totalAmount: decimal(315), transportAmount: decimal(15), transportTaxAmount: decimal(0),
        startDate: startIn(2), endDate: null, walkDate: null, timeSlot: null,
        transportLegs: [{ status: 'ARRIVED', fee: 15, tax: 0, trackingData: [{ lat: 1, lng: 1 }] }],
      } as any,
      new Date()
    );
    expect(r.refundAmount).toBe(0);
    expect(r.refundStatus).toBe(RefundStatus.REJECTED);
  });

  it('"en camino" sin ningún GPS del viaje no cuenta: se le devuelve al dueño', async () => {
    const r = await calculateRefund(
      {
        serviceType: ServiceType.HOSPEDAJE, totalAmount: decimal(325), transportAmount: decimal(25), transportTaxAmount: decimal(0),
        startDate: startIn(2), endDate: null, walkDate: null, timeSlot: null,
        transportLegs: [{ status: 'EN_ROUTE', fee: 15, tax: 0, trackingData: [] }, { status: 'ARRIVED', fee: 10, tax: 0 }],
      } as any,
      new Date()
    );
    expect(r.refundAmount).toBe(25);
  });

  it('nunca devuelve más que el total pagado', async () => {
    const r = await calculateRefund(
      { serviceType: ServiceType.HOSPEDAJE, totalAmount: decimal(20), transportAmount: decimal(25), transportTaxAmount: decimal(0), startDate: startIn(24 * 6), endDate: null, walkDate: null, timeSlot: null } as any,
      new Date()
    );
    expect(r.refundAmount).toBeLessThanOrEqual(20);
  });

  it('transportGrossOf = precios + su impuesto', () => {
    expect(transportGrossOf({ transportAmount: 25, transportTaxAmount: 4 })).toBe(29);
    expect(transportGrossOf({})).toBe(0);
  });
});

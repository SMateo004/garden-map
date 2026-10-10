import { walkInPetsByDay, combinedOccupancyByDay, firstFullDay, daysBetween } from '../../src/modules/caregiver-crm/walk-in-capacity';

const d = (s: string) => new Date(s + 'T00:00:00.000Z');

function tx(opts: { openVisits?: number; reservations?: any[]; hospedaje?: any[]; guarderia?: any[]; max?: number }) {
  return {
    walkInVisit: { count: jest.fn().mockResolvedValue(opts.openVisits ?? 0) },
    walkInReservation: { findMany: jest.fn().mockResolvedValue(opts.reservations ?? []) },
    caregiverProfile: { findUnique: jest.fn().mockResolvedValue({ maxPetsHospedaje: opts.max ?? 3 }) },
    booking: {
      findMany: jest.fn().mockImplementation(({ where }: any) =>
        Promise.resolve(where.serviceType === 'HOSPEDAJE' ? opts.hospedaje ?? [] : opts.guarderia ?? [])
      ),
    },
  } as any;
}

describe('walkInPetsByDay', () => {
  const today = '2026-10-10';

  it('las visitas abiertas cuentan solo hoy', async () => {
    const m = await walkInPetsByDay(tx({ openVisits: 2 }), 'p', d('2026-10-10'), d('2026-10-13'), today);
    expect(Object.fromEntries(m)).toEqual({ '2026-10-10': 2 });
  });

  it('una reserva futura ocupa cada día que cubre (salida exclusiva)', async () => {
    const t = tx({ reservations: [{ startDate: d('2026-10-12'), endDate: d('2026-10-15'), status: 'RESERVED' }] });
    const m = await walkInPetsByDay(t, 'p', d('2026-10-10'), d('2026-10-20'), today);
    expect(Object.fromEntries(m)).toEqual({ '2026-10-12': 1, '2026-10-13': 1, '2026-10-14': 1 });
  });

  it('ya adentro: hoy lo cuenta la visita, la reserva cuenta los días siguientes', async () => {
    const t = tx({ openVisits: 1, reservations: [{ startDate: d('2026-10-09'), endDate: d('2026-10-12'), status: 'CHECKED_IN' }] });
    const m = await walkInPetsByDay(t, 'p', d('2026-10-10'), d('2026-10-15'), today);
    expect(Object.fromEntries(m)).toEqual({ '2026-10-10': 1, '2026-10-11': 1 });
  });

  it('fuera del rango pedido no cuenta (ni consulta visitas si hoy no está en el rango)', async () => {
    const t = tx({ openVisits: 5, reservations: [{ startDate: d('2026-10-01'), endDate: d('2026-10-30'), status: 'RESERVED' }] });
    const m = await walkInPetsByDay(t, 'p', d('2026-10-20'), d('2026-10-22'), today);
    expect(Object.fromEntries(m)).toEqual({ '2026-10-20': 1, '2026-10-21': 1 });
    expect(t.walkInVisit.count).not.toHaveBeenCalled();
  });
});

describe('combinedOccupancyByDay + firstFullDay', () => {
  it('suma reservas de la app (por mascota) y de mostrador en el mismo cupo', async () => {
    const t = tx({
      max: 3,
      hospedaje: [{ startDate: d('2026-10-20'), endDate: d('2026-10-22'), petCount: 2 }],
      guarderia: [{ walkDate: d('2026-10-21'), petCount: 1 }],
      reservations: [{ startDate: d('2026-10-21'), endDate: d('2026-10-22'), status: 'RESERVED' }],
    });
    const occ = await combinedOccupancyByDay(t, 'p', d('2026-10-20'), d('2026-10-23'));
    expect(Object.fromEntries(occ.byDay)).toEqual({ '2026-10-20': 2, '2026-10-21': 4 });
    expect(firstFullDay(occ, d('2026-10-20'), d('2026-10-23'))).toEqual({ day: '2026-10-21', occupied: 4 });
    expect(firstFullDay(occ, d('2026-10-22'), d('2026-10-23'))).toBeNull();
  });

  it('daysBetween excluye la salida', () => {
    expect(daysBetween(d('2026-12-30'), d('2027-01-02'))).toEqual(['2026-12-30', '2026-12-31', '2027-01-01']);
  });
});

/**
 * Tareas programadas con turno (jobs/job-lease.ts): con dos instancias de la API, cada
 * ejecución corre en una sola. Si la tabla de turnos falla, la tarea corre igual (como antes).
 */
import prisma from '../../src/config/database';
import { claimJobLease, scheduleExclusive } from '../../src/jobs/job-lease';
import cron from 'node-cron';

jest.mock('../../src/config/database', () => ({ __esModule: true, default: { $queryRaw: jest.fn() } }));
jest.mock('node-cron', () => ({ __esModule: true, default: { schedule: jest.fn() } }));

const db = prisma as unknown as { $queryRaw: jest.Mock };
beforeEach(() => jest.clearAllMocks());

it('toma el turno si nadie lo tiene', async () => {
  db.$queryRaw.mockResolvedValue([{ name: 'qr-expiry' }]);
  await expect(claimJobLease('qr-expiry', 50_000)).resolves.toBe(true);
});

it('otra instancia ya lo tiene: se salta la vuelta', async () => {
  db.$queryRaw.mockResolvedValue([]);
  await expect(claimJobLease('qr-expiry', 50_000)).resolves.toBe(false);
});

it('si la base falla, corre igual (nunca peor que antes)', async () => {
  db.$queryRaw.mockRejectedValue(new Error('relation "job_leases" does not exist'));
  await expect(claimJobLease('qr-expiry', 50_000)).resolves.toBe(true);
});

it('scheduleExclusive solo ejecuta la tarea con el turno tomado', async () => {
  const fn = jest.fn();
  scheduleExclusive('demo', '* * * * *', fn);
  const tick = (cron.schedule as jest.Mock).mock.calls[0][1] as () => Promise<void>;
  db.$queryRaw.mockResolvedValueOnce([]);
  await tick();
  expect(fn).not.toHaveBeenCalled();
  db.$queryRaw.mockResolvedValueOnce([{ name: 'demo' }]);
  await tick();
  expect(fn).toHaveBeenCalledTimes(1);
});

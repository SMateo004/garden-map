/**
 * Tareas programadas que corren en UNA sola instancia de la API.
 *
 * Las ~30 tareas (cron.schedule / setInterval) viven dentro del proceso web. Con una sola
 * instancia está bien, pero si Render levanta dos (escalado, o un deploy que se solapa con la
 * instancia vieja) cada tarea corría dos veces: las que mueven plata ya tienen reclamos atómicos,
 * pero avisos, recordatorios y push salían duplicados. Ahora cada ejecución pide un "turno" en la
 * tabla job_leases con un UPDATE condicional: la primera instancia que llega lo toma y las demás
 * se saltan esa vuelta.
 *
 * Si la tabla todavía no existe (primer arranque antes del db push) o la base falla, la tarea
 * corre igual — mismo comportamiento que antes, nunca peor.
 */
import os from 'node:os';
import cron from 'node-cron';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';

const OWNER = `${process.env.RENDER_INSTANCE_ID ?? os.hostname()}:${process.pid}`;

/** Las ejecuciones de cron se disparan a la misma hora de reloj en todas las instancias. */
const CRON_LEASE_MS = 50_000;

let warnedFailOpen = false;

/** Intenta tomar el turno de `name` por `ttlMs`. true = esta instancia corre la tarea. */
export async function claimJobLease(name: string, ttlMs: number): Promise<boolean> {
  try {
    const rows = await prisma.$queryRaw<Array<{ name: string }>>`
      INSERT INTO "job_leases" ("name", "lockedUntil", "owner", "updatedAt")
      VALUES (${name}, now() + (${ttlMs} * interval '1 millisecond'), ${OWNER}, now())
      ON CONFLICT ("name") DO UPDATE
        SET "lockedUntil" = EXCLUDED."lockedUntil", "owner" = EXCLUDED."owner", "updatedAt" = now()
        WHERE "job_leases"."lockedUntil" < now()
      RETURNING "name"`;
    return rows.length > 0;
  } catch (err) {
    if (!warnedFailOpen) {
      warnedFailOpen = true;
      logger.warn('[JOB-LEASE] no se pudo tomar el turno — la tarea corre sin exclusión', { name, err: (err as Error)?.message });
    }
    return true;
  }
}

/** cron.schedule con exclusión entre instancias. `name` tiene que ser único por tarea. */
export function scheduleExclusive(name: string, expression: string, fn: () => unknown): void {
  cron.schedule(expression, async () => {
    if (!(await claimJobLease(name, CRON_LEASE_MS))) return;
    await fn();
  });
}

/**
 * setInterval con exclusión. Los intervalos no están alineados al reloj entre instancias, así que
 * el turno dura casi todo el intervalo: en cada período corre una sola instancia.
 */
export function intervalExclusive(name: string, everyMs: number, fn: () => unknown): ReturnType<typeof setInterval> {
  const ttl = Math.max(everyMs - Math.min(60_000, everyMs * 0.1), 1_000);
  return setInterval(async () => {
    if (!(await claimJobLease(name, ttl))) return;
    await fn();
  }, everyMs);
}

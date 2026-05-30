import { prisma } from '../config/database.js';
import logger from '../shared/logger.js';

export interface AuditParams {
  userId?: string;
  action: string;
  entity: string;
  entityId?: string;
  details?: Record<string, unknown>;
  ip?: string;
}

/**
 * Fire-and-forget audit log write.
 * Never throws — failures are logged but never block the caller.
 */
export function auditLog(params: AuditParams): void {
  prisma.auditLog.create({
    data: {
      userId: params.userId ?? null,
      action: params.action,
      entity: params.entity,
      entityId: params.entityId ?? null,
      details: params.details ? JSON.stringify(params.details) : null,
      ip: params.ip ?? null,
    },
  }).catch((err) => {
    logger.error('auditLog write failed', { err, params });
  });
}

/**
 * Return all audit logs for a given month as a formatted TXT string.
 * month format: "YYYY-MM"
 */
export async function exportMonthAsTxt(month: string): Promise<string> {
  const parts = month.split('-').map(Number);
  const year = parts[0]!;
  const mon = parts[1]!;
  const from = new Date(year, mon - 1, 1);
  const to   = new Date(year, mon, 1);

  const rows = await prisma.auditLog.findMany({
    where: { createdAt: { gte: from, lt: to } },
    orderBy: { createdAt: 'asc' },
  });

  const header = [
    `GARDEN - REGISTRO DE AUDITORÍA`,
    `Mes: ${month}`,
    `Generado: ${new Date().toISOString()}`,
    `Total registros: ${rows.length}`,
    '='.repeat(80),
    '',
  ].join('\n');

  const lines = rows.map((r) => {
    const ts  = r.createdAt.toISOString();
    const uid = r.userId ?? 'SISTEMA';
    const det = r.details ? ` | ${r.details}` : '';
    const eid = r.entityId ? ` [${r.entityId}]` : '';
    return `[${ts}] ${r.action.padEnd(35)} ${r.entity}${eid} | usuario:${uid}${det}`;
  });

  return header + lines.join('\n') + '\n';
}

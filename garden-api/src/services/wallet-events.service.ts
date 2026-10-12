/**
 * Aviso `wallet_updated` a la app cada vez que cambia algo de la billetera de
 * un usuario: saldo, un movimiento (pago, reembolso, ganancia, retiro…) o una
 * donación.
 *
 * Antes cada flujo tenía que acordarse de llamar a emitWalletUpdated() y la
 * mayoría no lo hacía (pagos, reembolsos, disputas, referidos, donaciones,
 * vencimientos, aprobaciones del admin): la billetera abierta quedaba
 * desactualizada hasta salir y volver a entrar. Ahora un middleware de Prisma
 * (ver config/database.ts) detecta esas escrituras en un solo lugar, así
 * también cubre los flujos nuevos.
 *
 * El aviso sale [WALLET_EVENT_DELAY_MS] después de la última escritura de ese
 * usuario: si la escritura fue dentro de una transacción, para entonces ya se
 * confirmó y la app lee el dato nuevo (y varias escrituras seguidas de un
 * mismo flujo salen como un solo aviso).
 */
import logger from '../shared/logger.js';

export const WALLET_EVENT_DELAY_MS = 1000;

const pending = new Map<string, NodeJS.Timeout>();

export function scheduleWalletUpdated(userId: string | null | undefined): void {
  if (!userId) return;
  const prev = pending.get(userId);
  if (prev) clearTimeout(prev);
  const timer = setTimeout(() => {
    pending.delete(userId);
    import('./socket.service.js')
      .then((m) => m.emitWalletUpdated(userId))
      .catch((err) => logger.warn('[WALLET-EVENTS] no se pudo avisar', { userId, error: (err as Error).message }));
  }, WALLET_EVENT_DELAY_MS);
  timer.unref?.();
  pending.set(userId, timer);
}

type QueryParams = { model?: string; action: string; args?: any };

/** IDs de usuario de un valor `where.id` (string o `{ in: [...] }`). */
function idsFromWhere(where: any): string[] {
  const id = where?.id;
  if (typeof id === 'string') return [id];
  if (Array.isArray(id?.in)) return id.in.filter((x: unknown): x is string => typeof x === 'string');
  return [];
}

/**
 * Usuarios cuya billetera cambió con esta consulta (ya ejecutada). Usa el
 * resultado cuando lo trae (create/update/upsert devuelven el registro) y los
 * argumentos cuando no (createMany/updateMany devuelven solo un conteo).
 * Devuelve [] para todo lo demás.
 */
export function walletUsersOf(params: QueryParams, result: any): string[] {
  const { model, action, args } = params;
  const writes = ['create', 'createMany', 'update', 'updateMany', 'upsert'];
  if (!model || !writes.includes(action)) return [];

  if (model === 'WalletTransaction') {
    if (result && typeof result.userId === 'string') return [result.userId];
    const data = args?.data;
    if (Array.isArray(data)) return data.map((d: any) => d?.userId).filter(Boolean);
    if (typeof data?.userId === 'string') return [data.userId];
    return [];
  }

  if (model === 'Donation') {
    if (result && typeof result.clientId === 'string') return [result.clientId];
    const data = args?.data ?? args?.create;
    if (Array.isArray(data)) return data.map((d: any) => d?.clientId).filter(Boolean);
    return typeof data?.clientId === 'string' ? [data.clientId] : [];
  }

  if (model === 'User') {
    const data = action === 'upsert' ? { ...args?.create, ...args?.update } : args?.data;
    if (!data || !('balance' in data)) return [];
    if (result && typeof result.id === 'string') return [result.id];
    return idsFromWhere(args?.where);
  }

  return [];
}

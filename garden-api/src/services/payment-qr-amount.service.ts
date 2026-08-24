/**
 * QR de pago provisional por MONTO EXACTO (Bs 15 a Bs 1000, uno por cada
 * boliviano) — igual concepto que payment-qr.service.ts (imagen real subida
 * por un admin, mostrada mientras SIP_ENABLED=false), pero indexado por el
 * total exacto de la reserva en vez de por tipo de servicio. Más preciso:
 * el cliente ve un QR con el monto correcto ya "impreso" en vez de tener
 * que escribirlo a mano.
 *
 * Si una reserva cae en un monto sin QR subido (o fuera de este rango),
 * booking.service.ts cae al QR genérico por tipo de servicio (payment-qr.service.ts)
 * y de ahí al placeholder — ver generateQR().
 *
 * Se guarda como un único JSON disperso {monto: url} en una fila de
 * AppSettings en vez de 986 filas sueltas — el rango es fijo y acotado,
 * así que no hace falta una tabla nueva.
 */
import prisma from '../config/database.js';

export const MIN_AMOUNT = 15;
export const MAX_AMOUNT = 1000;

const SETTING_KEY = 'payment_qr_by_amount';
const TTL_MS = 30_000;

// Cache local en vez de utils/settings-cache.js: ese helper solo sabe leer
// valores string/number/boolean simples (hace JSON.parse y exige que el
// resultado sea del tipo esperado) — acá guardamos un objeto {monto: url}
// completo, así que necesitamos nuestro propio cache.
let _cache: { map: Record<string, string>; ts: number } | null = null;

function isValidAmount(amount: number): boolean {
  return Number.isInteger(amount) && amount >= MIN_AMOUNT && amount <= MAX_AMOUNT;
}

async function readMap(): Promise<Record<string, string>> {
  if (_cache && Date.now() - _cache.ts < TTL_MS) return _cache.map;
  const setting = await prisma.appSettings.findUnique({ where: { key: SETTING_KEY } });
  let map: Record<string, string> = {};
  if (setting) {
    try {
      const parsed = JSON.parse(setting.value);
      if (parsed && typeof parsed === 'object') map = parsed;
    } catch {
      map = {};
    }
  }
  _cache = { map, ts: Date.now() };
  return map;
}

async function writeMap(map: Record<string, string>, adminUserId: string): Promise<void> {
  await prisma.appSettings.upsert({
    where: { key: SETTING_KEY },
    update: { value: JSON.stringify(map), updatedBy: adminUserId },
    create: { key: SETTING_KEY, value: JSON.stringify(map), updatedBy: adminUserId },
  });
  _cache = { map, ts: Date.now() };
}

/** Redondea al boliviano más cercano (los totales de reserva ya vienen redondeados,
 *  esto es solo defensivo) y busca su QR exacto. null si no hay uno subido. */
export async function getPaymentQrImageUrlForAmount(amount: number): Promise<string | null> {
  const rounded = Math.round(amount);
  if (!isValidAmount(rounded)) return null;
  const map = await readMap();
  const url = map[String(rounded)];
  return url && url.length > 0 ? url : null;
}

/** Mapa disperso {monto: url} — solo los montos que ya tienen QR subido. */
export async function getAllPaymentQrByAmount(): Promise<Record<number, string>> {
  const map = await readMap();
  const result: Record<number, string> = {};
  for (const [key, url] of Object.entries(map)) {
    const amount = Number(key);
    if (isValidAmount(amount) && url) result[amount] = url;
  }
  return result;
}

export async function setPaymentQrImageUrlForAmount(
  amount: number,
  url: string,
  adminUserId: string
): Promise<void> {
  if (!isValidAmount(amount)) {
    throw new Error(`Monto inválido: debe ser un entero entre ${MIN_AMOUNT} y ${MAX_AMOUNT}`);
  }
  const map = await readMap();
  map[String(amount)] = url;
  await writeMap(map, adminUserId);
}

export async function deletePaymentQrImageUrlForAmount(amount: number, adminUserId: string): Promise<void> {
  const map = await readMap();
  delete map[String(amount)];
  await writeMap(map, adminUserId);
}

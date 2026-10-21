/**
 * Precio de Premium ("Destacado") según la duración, en semanas (1 a 52).
 *
 * El admin define una tabla de puntos — ej. 1 sem = Bs 50, 4 sem = Bs 150,
 * 52 sem = Bs 1.400 — y entre dos puntos el precio se interpola en línea recta
 * (redondeado al boliviano). La duración máxima que se puede comprar es la del
 * último punto. Funciones puras: las usan el backend (cobro) y la validación del
 * formulario del admin; la app recibe la tabla y calcula igual para el deslizador,
 * pero el precio que se cobra SIEMPRE lo calcula el servidor.
 */

export const PREMIUM_MIN_WEEKS = 1;
export const PREMIUM_MAX_WEEKS = 52;
export const PREMIUM_MAX_POINTS = 20;
export const PREMIUM_MAX_PRICE = 100_000;

export interface PremiumPricePoint {
  weeks: number;
  price: number;
}

/** Error de validación con mensaje para mostrarle al admin tal cual. */
export class PremiumTableError extends Error {}

/**
 * Valida y normaliza la tabla que manda el admin. Reglas (pensadas para que un
 * error de tipeo no deje precios absurdos):
 *  - 1 a 20 puntos; semanas enteras de 1 a 52, sin repetir; debe existir 1 semana.
 *  - Precios enteros de Bs 1 a Bs 100.000.
 *  - Más semanas nunca cuestan menos: el precio no baja al aumentar la duración.
 */
export function validatePriceTable(raw: unknown): PremiumPricePoint[] {
  if (!Array.isArray(raw)) throw new PremiumTableError('La tabla de precios debe ser una lista.');
  if (raw.length === 0) throw new PremiumTableError('Agrega al menos un precio (el de 1 semana).');
  if (raw.length > PREMIUM_MAX_POINTS) {
    throw new PremiumTableError(`Máximo ${PREMIUM_MAX_POINTS} puntos de precio.`);
  }
  const points: PremiumPricePoint[] = raw.map((p, i) => {
    const weeks = Number((p as any)?.weeks);
    const price = Number((p as any)?.price);
    if (!Number.isInteger(weeks) || weeks < PREMIUM_MIN_WEEKS || weeks > PREMIUM_MAX_WEEKS) {
      throw new PremiumTableError(`Fila ${i + 1}: las semanas deben ser un número entero de 1 a 52.`);
    }
    if (!Number.isInteger(price) || price < 1 || price > PREMIUM_MAX_PRICE) {
      throw new PremiumTableError(`Fila ${i + 1}: el precio debe ser un monto entero de Bs 1 a Bs 100.000.`);
    }
    return { weeks, price };
  });
  points.sort((a, b) => a.weeks - b.weeks);
  for (let i = 1; i < points.length; i++) {
    if (points[i]!.weeks === points[i - 1]!.weeks) {
      throw new PremiumTableError(`Hay dos precios para ${points[i]!.weeks} semana(s).`);
    }
    if (points[i]!.price < points[i - 1]!.price) {
      throw new PremiumTableError(
        `${points[i]!.weeks} semanas (Bs ${points[i]!.price}) no puede costar menos que ${points[i - 1]!.weeks} (Bs ${points[i - 1]!.price}).`
      );
    }
  }
  if (points[0]!.weeks !== 1) throw new PremiumTableError('La tabla debe incluir el precio de 1 semana.');
  return points;
}

/** Duración máxima comprable con esta tabla (semanas del último punto). */
export function maxWeeksOf(table: PremiumPricePoint[]): number {
  return table.length ? table[table.length - 1]!.weeks : 0;
}

/**
 * Precio para [weeks] semanas, o null si la duración no se puede comprar con esta
 * tabla (fuera de 1..máximo, no entera, o tabla vacía).
 */
export function priceForWeeks(table: PremiumPricePoint[], weeks: number): number | null {
  if (!Number.isInteger(weeks) || weeks < PREMIUM_MIN_WEEKS || table.length === 0) return null;
  if (weeks > maxWeeksOf(table)) return null;
  for (let i = 0; i < table.length; i++) {
    const p = table[i]!;
    if (p.weeks === weeks) return p.price;
    if (p.weeks > weeks) {
      const a = table[i - 1]!; // existe: la tabla empieza en 1 semana
      return Math.round(a.price + ((p.price - a.price) * (weeks - a.weeks)) / (p.weeks - a.weeks));
    }
  }
  return null;
}

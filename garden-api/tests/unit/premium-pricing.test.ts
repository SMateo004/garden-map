/**
 * Tabla de precios de Premium: puntos que define el admin + interpolación lineal.
 * La validación tiene que frenar los errores de tipeo típicos de un admin apurado.
 */
import { validatePriceTable, priceForWeeks, maxWeeksOf, PremiumTableError } from '../../src/modules/premium/premium.pricing';

const table = validatePriceTable([
  { weeks: 4, price: 150 },
  { weeks: 1, price: 50 },
  { weeks: 52, price: 1400 },
]);

describe('validatePriceTable', () => {
  it('ordena los puntos y acepta números como texto', () => {
    expect(table).toEqual([{ weeks: 1, price: 50 }, { weeks: 4, price: 150 }, { weeks: 52, price: 1400 }]);
    expect(validatePriceTable([{ weeks: '1', price: '60' }])).toEqual([{ weeks: 1, price: 60 }]);
  });

  it.each([
    ['no es lista', { weeks: 1, price: 50 }],
    ['vacía', []],
    ['sin 1 semana', [{ weeks: 2, price: 50 }]],
    ['semanas 0', [{ weeks: 0, price: 50 }]],
    ['semanas 53', [{ weeks: 1, price: 50 }, { weeks: 53, price: 900 }]],
    ['semanas con decimales', [{ weeks: 1.5, price: 50 }]],
    ['precio 0', [{ weeks: 1, price: 0 }]],
    ['precio negativo', [{ weeks: 1, price: -10 }]],
    ['precio con decimales', [{ weeks: 1, price: 49.9 }]],
    ['precio gigante', [{ weeks: 1, price: 1_000_000 }]],
    ['texto', [{ weeks: 'una', price: 'cincuenta' }]],
    ['semanas repetidas', [{ weeks: 1, price: 50 }, { weeks: 1, price: 60 }]],
    ['más semanas más baratas', [{ weeks: 1, price: 50 }, { weeks: 4, price: 40 }]],
    ['null', null],
    ['demasiados puntos', Array.from({ length: 21 }, (_, i) => ({ weeks: i + 1, price: 10 + i }))],
  ])('rechaza: %s', (_label, raw) => {
    expect(() => validatePriceTable(raw)).toThrow(PremiumTableError);
  });
});

describe('priceForWeeks', () => {
  it('usa el precio exacto de cada punto', () => {
    expect(priceForWeeks(table, 1)).toBe(50);
    expect(priceForWeeks(table, 4)).toBe(150);
    expect(priceForWeeks(table, 52)).toBe(1400);
  });

  it('interpola entre puntos y redondea al boliviano', () => {
    expect(priceForWeeks(table, 2)).toBe(83); // 50 + 100/3
    expect(priceForWeeks(table, 3)).toBe(117);
    expect(priceForWeeks(table, 28)).toBe(775); // 150 + 1250 × 24/48
  });

  it('el precio nunca baja al agregar semanas', () => {
    let prev = 0;
    for (let w = 1; w <= 52; w++) {
      const p = priceForWeeks(table, w)!;
      expect(p).toBeGreaterThanOrEqual(prev);
      prev = p;
    }
  });

  it.each([0, -1, 53, 2.5, NaN])('fuera de rango o inválido: %p', (w) => {
    expect(priceForWeeks(table, w as number)).toBeNull();
  });

  it('la duración máxima es la del último punto', () => {
    const short = validatePriceTable([{ weeks: 1, price: 50 }, { weeks: 8, price: 300 }]);
    expect(maxWeeksOf(short)).toBe(8);
    expect(priceForWeeks(short, 8)).toBe(300);
    expect(priceForWeeks(short, 9)).toBeNull();
    expect(priceForWeeks([], 1)).toBeNull();
  });
});

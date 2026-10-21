import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/utils/premium_price.dart';

// Debe dar exactamente lo mismo que garden-api/src/modules/premium/premium.pricing.ts
// (tests/unit/premium-pricing.test.ts): el deslizador muestra el precio que el servidor cobra.
void main() {
  final table = PremiumPricePoint.listFrom([
    {'weeks': 4, 'price': 100},
    {'weeks': 1, 'price': 30},
    {'weeks': 52, 'price': 900},
  ]);

  test('ordena los puntos y descarta basura', () {
    expect(table.map((p) => p.weeks), [1, 4, 52]);
    expect(PremiumPricePoint.listFrom('x'), isEmpty);
    expect(PremiumPricePoint.listFrom([{'weeks': 0, 'price': 5}, {'weeks': 2}, 3]), isEmpty);
  });

  test('puntos exactos e interpolación redondeada como Math.round', () {
    expect(premiumPriceForWeeks(table, 1), 30);
    expect(premiumPriceForWeeks(table, 4), 100);
    expect(premiumPriceForWeeks(table, 52), 900);
    expect(premiumPriceForWeeks(table, 2), 53); // 30 + 70/3 = 53.33
    expect(premiumPriceForWeeks(table, 3), 77); // 76.67
    expect(premiumPriceForWeeks(table, 28), 500); // 100 + 800·24/48
    expect(premiumPriceForWeeks(PremiumPricePoint.listFrom([{'weeks': 1, 'price': 10}, {'weeks': 3, 'price': 11}]), 2), 11); // 10.5 → 11
  });

  test('fuera de rango no tiene precio', () {
    expect(premiumPriceForWeeks(table, 0), isNull);
    expect(premiumPriceForWeeks(table, 53), isNull);
    expect(premiumPriceForWeeks(const [], 1), isNull);
    expect(maxPremiumWeeks(table), 52);
  });

  test('nunca baja de precio al alargar la duración', () {
    int prev = 0;
    for (var w = 1; w <= 52; w++) {
      final p = premiumPriceForWeeks(table, w)!;
      expect(p >= prev, isTrue, reason: 'semana $w');
      prev = p;
    }
  });

  test('etiquetas', () {
    expect(premiumDurationLabel(1), '1 semana');
    expect(premiumDurationLabel(3), '3 semanas');
    expect(premiumDurationLabel(52), '1 año');
    expect(premiumDurationLabel(13), '13 semanas (≈ 3 meses)');
  });
}

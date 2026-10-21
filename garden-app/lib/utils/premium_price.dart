/// Precio de Premium para una duración en semanas — mismo cálculo que
/// garden-api/src/modules/premium/premium.pricing.ts (puntos del admin +
/// interpolación lineal, redondeado al boliviano). Solo para mostrar el precio
/// mientras se mueve el deslizador: el monto que se cobra lo calcula el servidor.
class PremiumPricePoint {
  final int weeks;
  final int price;
  const PremiumPricePoint(this.weeks, this.price);

  static List<PremiumPricePoint> listFrom(Object? raw) {
    if (raw is! List) return const [];
    final out = <PremiumPricePoint>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final w = (e['weeks'] as num?)?.toInt();
      final p = (e['price'] as num?)?.toInt();
      if (w != null && p != null && w > 0 && p > 0) out.add(PremiumPricePoint(w, p));
    }
    out.sort((a, b) => a.weeks.compareTo(b.weeks));
    return out;
  }
}

int maxPremiumWeeks(List<PremiumPricePoint> table) => table.isEmpty ? 0 : table.last.weeks;

/// null si esa duración no se puede comprar con la tabla.
int? premiumPriceForWeeks(List<PremiumPricePoint> table, int weeks) {
  if (table.isEmpty || weeks < 1 || weeks > maxPremiumWeeks(table)) return null;
  for (var i = 0; i < table.length; i++) {
    final p = table[i];
    if (p.weeks == weeks) return p.price;
    if (p.weeks > weeks) {
      if (i == 0) return null; // la tabla del servidor siempre empieza en 1 semana
      final a = table[i - 1];
      // Igual que Math.round de JS (mitades hacia arriba).
      return (a.price + (p.price - a.price) * (weeks - a.weeks) / (p.weeks - a.weeks) + 0.5).floor();
    }
  }
  return null;
}

/// "1 semana", "3 semanas", "≈ 2 meses", "1 año".
String premiumDurationLabel(int weeks) {
  if (weeks == 52) return '1 año';
  final base = weeks == 1 ? '1 semana' : '$weeks semanas';
  if (weeks >= 8) {
    final months = (weeks / 4.345).round();
    return '$base (≈ $months ${months == 1 ? 'mes' : 'meses'})';
  }
  return base;
}

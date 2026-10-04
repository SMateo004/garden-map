/// Lo que cobra el cuidador por una reserva: total − comisión − impuestos.
///
/// Mismo cálculo que `caregiverNetOf()` en garden-api/src/modules/pricing/
/// pricing.service.ts. `totalAmount` es lo que pagó el dueño (incluye comisión
/// e impuestos), así que nunca se le muestra al cuidador como "su" monto.
/// Null si la reserva no trae los montos (ej. una respuesta para un CLIENT, a
/// la que la API le quita la comisión).
double? caregiverNetOf(Map<String, dynamic>? booking) {
  if (booking == null) return null;
  double? n(Object? v) => v == null ? null : double.tryParse(v.toString());
  final total = n(booking['totalAmount']);
  final commission = n(booking['commissionAmount']);
  if (total == null || commission == null) return null;
  final tax = n(booking['taxAmount']) ?? 0;
  final net = total - commission - tax;
  return net >= 0 ? net : null;
}

/// "Bs 120" o "—" si no se puede calcular.
String caregiverNetLabel(Map<String, dynamic>? booking) {
  final net = caregiverNetOf(booking);
  return net == null ? '—' : 'Bs ${net.toStringAsFixed(0)}';
}

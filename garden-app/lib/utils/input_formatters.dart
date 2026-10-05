import 'package:flutter/services.dart';

/// Bloquea dígitos a nivel de tecleo — para campos de Nombre/Apellido, donde
/// un número nunca es un valor válido (a diferencia de un validador post-submit,
/// esto impide que se escriba desde el principio).
final noDigitsFormatter = FilteringTextInputFormatter.deny(RegExp(r'[0-9]'));

/// Solo números y separador decimal (coma o punto) — montos, precios, pesos.
final decimalInputFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

/// Lee un número escrito por una persona: acepta "4,5" y "4.5" (en Bolivia se
/// usa coma). Devuelve null si no es un número válido — antes
/// `double.tryParse("4,5")` daba null y el dato se perdía en silencio o el
/// monto quedaba en 0.
double? parseDecimal(String raw) {
  final t = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty || '.'.allMatches(t).length > 1) return null;
  return double.tryParse(t);
}

import 'package:flutter/services.dart';

/// Bloquea dígitos a nivel de tecleo — para campos de Nombre/Apellido, donde
/// un número nunca es un valor válido (a diferencia de un validador post-submit,
/// esto impide que se escriba desde el principio).
final noDigitsFormatter = FilteringTextInputFormatter.deny(RegExp(r'[0-9]'));

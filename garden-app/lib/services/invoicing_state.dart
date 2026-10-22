import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// ¿GARDEN ya emite facturas con NIT? Lo decide el admin con el switch de Admin > Comisiones /
/// Finanzas (`invoicingActive` en GET /settings, invoicing.service.ts del backend).
///
/// Mientras sea false, "Datos de facturación" aparece como "Pronto" antes de pagar y la app no
/// pide ni envía NIT. Arranca en false: si la carga falla, no se promete una factura que todavía
/// no se emite.
class InvoicingState {
  InvoicingState._();

  static const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// Lee `invoicingActive` de una respuesta de GET /settings ya obtenida.
  static void applySettings(Map<String, dynamic>? data) {
    active.value = data?['invoicingActive'] == true;
  }

  static Future<void> refresh() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/settings')).timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) {
        applySettings((body['data'] as Map?)?.cast<String, dynamic>());
      }
    } catch (_) {
      // Sin red: se queda como estaba (por defecto, "Pronto").
    }
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// ¿GARDEN cobra impuestos hoy? Lo decide el backend (`taxesActive` en GET /settings): el
/// admin los aprobó con el switch de Admin > Comisiones / Finanzas (pricing.service.ts).
/// Mientras sea false la app no menciona impuestos en ningún lado.
///
/// Arranca en false a propósito: si la carga falla, lo seguro es no hablar de un cobro
/// que quizá no existe. Los montos reales siempre vienen de la reserva (taxAmount), así
/// que este estado solo decide textos y desgloses previos al pago.
class TaxesState {
  TaxesState._();

  static const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// Lee `taxesActive` de una respuesta de GET /settings ya obtenida.
  static void applySettings(Map<String, dynamic>? data) {
    active.value = data?['taxesActive'] == true;
  }

  static Future<void> refresh() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/settings')).timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) {
        applySettings((body['data'] as Map?)?.cast<String, dynamic>());
      }
    } catch (_) {
      // Sin red: se queda como estaba (por defecto, sin mencionar impuestos).
    }
  }

  /// Frases de los Términos que hablan de impuestos y su versión sin ellos. Mismo
  /// reemplazo que garden-api/src/modules/legal/tax-clauses.ts.
  static const List<(String, String)> termsReplacements = [
    (
      ' y al pagar se suman los impuestos de ley (16%: Bs. 18), para un total de Bs. 128.',
      ', que es el total a pagar.',
    ),
    (
      ' y al pagar se suman los impuestos de ley (ej.: Bs. 18), para un total de Bs. 128.',
      ', que es el total que paga.',
    ),
    (
      ' y destina los impuestos cobrados al pago de sus obligaciones tributarias (ej.: Bs. 18).',
      '.',
    ),
    (
      'IVA E IMPUESTOS: Los impuestos de ley (IVA 13% e IT 3%, 16% en total) se muestran por separado en el detalle de pago y se suman al precio del servicio; no se descuentan al Cuidador. Garden emite las facturas electrónicas que correspondan al amparo de la Ley N° 812 (Factura Electrónica) y las disposiciones del Servicio de Impuestos Nacionales (SIN).',
      'PRECIO TOTAL Y FACTURACIÓN: El precio que el Cliente ve antes de pagar es el total final del servicio; no se suman otros cargos al pagar. Garden emite las facturas electrónicas que correspondan conforme a la Ley N° 812 (Factura Electrónica).',
    ),
  ];

  static String withoutTaxMentions(String text) {
    var out = text;
    for (final (from, to) in termsReplacements) {
      out = out.replaceAll(from, to);
    }
    return out;
  }

  /// Texto de los Términos según el estado actual.
  static String terms(String text) => active.value ? text : withoutTaxMentions(text);
}

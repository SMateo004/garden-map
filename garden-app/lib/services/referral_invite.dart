import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_state.dart';

/// Invitación de un amigo que llega por enlace (gardenbo.com/register?ref=CODIGO).
///
/// El registro no tiene campo de código (y tiene 4 flujos sensibles que no
/// conviene tocar), así que el código se guarda al abrir el enlace y se aplica
/// solo en cuanto hay sesión. Antes el mensaje de WhatsApp decía "usa mi
/// código al registrarte", pero no había dónde: había que encontrar después
/// la pantalla "Invita y gana" y escribirlo a mano.
class ReferralInvite {
  static const _key = 'pending_referral_code';
  static final _valid = RegExp(r'^[A-Z0-9]{4,12}$');

  static String? normalize(String? code) {
    final c = code?.trim().toUpperCase();
    return c != null && _valid.hasMatch(c) ? c : null;
  }

  static Future<void> remember(String? code) async {
    final c = normalize(code);
    if (c == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, c);
  }

  static Future<String?> pending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Aplica el código guardado si hay sesión. Devuelve el texto para avisar
  /// al usuario, o null si no había nada que aplicar. Si el servidor lo
  /// rechaza (código inexistente, propio, ya aplicado o ya hizo un servicio)
  /// se descarta; si es un error de red, queda guardado para la próxima.
  static Future<String?> applyPending(String baseUrl) async {
    if (!AuthState.hasSession) return null;
    final code = await pending();
    if (code == null) return null;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/referral/apply'),
        headers: {'Authorization': 'Bearer ${AuthState.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );
      if (res.statusCode >= 500) return null;
      await clear();
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        return 'Aplicamos el código de invitación $code: cuando completes tu primer servicio, los dos ganan un bono.';
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

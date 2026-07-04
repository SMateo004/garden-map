import 'dart:convert';
import 'package:http/http.dart' as http;

/// Zonas que un admin deshabilitó temporalmente (AppSettings.blockedZones).
///
/// Cuando una zona está bloqueada, ningún cuidador nuevo o existente debería
/// poder seleccionarla como su zona de servicio, y no debería aparecer como
/// opción activa en el mapa ni en los filtros del marketplace.
///
/// Cachea el resultado en memoria por 60s para no golpear el endpoint en
/// cada pantalla que lo usa (registro, edición de perfil, marketplace).
class ZonesService {
  static Set<String>? _cache;
  static DateTime? _cachedAt;
  static const _ttl = Duration(seconds: 60);

  static String get _baseUrl =>
      const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  static Future<Set<String>> getBlockedZones({bool forceRefresh = false}) async {
    final cached = _cache;
    final cachedAt = _cachedAt;
    if (!forceRefresh && cached != null && cachedAt != null && DateTime.now().difference(cachedAt) < _ttl) {
      return cached;
    }
    try {
      final res = await http.get(Uri.parse('$_baseUrl/settings/blocked-zones'));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final list = (data['data']?['blockedZones'] as List?)?.cast<String>() ?? [];
        _cache = list.toSet();
        _cachedAt = DateTime.now();
        return _cache!;
      }
    } catch (_) {
      // Si falla, no bloqueamos ninguna zona — mejor mostrar todas que
      // dejar al usuario sin poder registrarse por un error de red.
    }
    return _cache ?? <String>{};
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Aplica el icono de app "estacional" que el admin configuró en el panel
/// (ver `_IconScheduleTab` en admin_general_screen.dart / GET /api/app/active-icon).
///
/// LÍMITE REAL DE PLATAFORMA — leer antes de tocar este archivo:
/// Esta clase NUNCA puede hacer que aparezca un icono con arte que no estaba ya
/// empaquetado en el build actual de la app. En iOS, `UIApplication.setAlternateIconName`
/// solo puede elegir entre los `CFBundleAlternateIcons` declarados en Info.plist de
/// ESTE build. En Android, el switch es vía `activity-alias` ya declarados en
/// AndroidManifest.xml de ESTE build. Si el backend devuelve una variante que esta
/// versión de la app no conoce (porque el admin creó la regla pensando en una variante
/// que se agregará en un build futuro), el cliente debe ignorarla seguro y quedarse en el
/// icono actual — nunca puede "inventar" el icono. Ver `_knownVariants` abajo.
///
/// Aplica una sola vez por sesión relevante: guarda en SharedPreferences la última
/// variante aplicada para evitar llamadas nativas redundantes en cada apertura de la
/// app (en iOS, además, cada cambio real le muestra al usuario un diálogo de
/// confirmación del sistema — no queremos dispararlo si la variante no cambió).
class IconScheduleService {
  IconScheduleService._();
  static final IconScheduleService instance = IconScheduleService._();

  static const _channel = MethodChannel('com.gardenbo.app/icon_switcher');
  static const _prefsKey = 'lastAppliedIconVariant';

  /// Variantes que ESTE build sabe aplicar — deben coincidir 1:1 con:
  ///  - iOS: CFBundleAlternateIcons en ios/Runner/Info.plist
  ///  - Android: activity-alias en android/app/src/main/AndroidManifest.xml
  /// "variantB" es hoy un PLACEHOLDER (mismo arte que "default", duplicado solo para
  /// probar el pipeline end-to-end) — no es una variante estacional real todavía.
  static const _knownVariants = {'default', 'variantB'};

  static String get _baseUrl => const String.fromEnvironment(
        'API_URL',
        defaultValue: 'https://api.gardenbo.com/api',
      );

  /// Llamar una vez al arrancar la app (no bloqueante — ver _bootstrap en main.dart).
  /// Web no soporta iconos alternativos de app — no-op ahí.
  Future<void> checkAndApplyOnLaunch() async {
    if (kIsWeb) return;
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/app/active-icon'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] != true) return;
      final variant = (body['data']?['variant'] as String?) ?? 'default';
      await _applyIfNeeded(variant);
    } catch (e) {
      // Fallo de red / servidor no debe afectar el arranque de la app — el icono
      // simplemente se queda como estaba hasta el próximo chequeo.
      debugPrint('IconScheduleService.checkAndApplyOnLaunch failed: $e');
    }
  }

  Future<void> _applyIfNeeded(String variant) async {
    if (!_knownVariants.contains(variant)) {
      // El backend pide una variante que este build no conoce todavía (ver nota de
      // clase) — no hacemos nada, nos quedamos en el icono actual.
      debugPrint('IconScheduleService: variante desconocida "$variant" para este build, se ignora');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_prefsKey);
    if (last == variant) return; // ya aplicado, evita llamada nativa + diálogo redundante en iOS

    try {
      final ok = await _channel.invokeMethod<bool>('setIcon', {'variant': variant});
      if (ok == true) {
        await prefs.setString(_prefsKey, variant);
      }
    } on PlatformException catch (e) {
      // "UNSUPPORTED" (iOS < ciertas versiones / dispositivo sin soporte) o
      // "UNKNOWN_VARIANT" (desalineación entre backend y build) — no fatal.
      debugPrint('IconScheduleService.setIcon failed: ${e.code} ${e.message}');
    } on MissingPluginException {
      // Build sin el canal nativo registrado (ej. corriendo en un simulador/entorno
      // viejo antes de este cambio) — no debe tumbar el arranque de la app.
      debugPrint('IconScheduleService: native icon_switcher channel not available');
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'auth_state.dart';

/// Maneja los toques en los widgets nativos del home screen (Android Glance
/// + el Live Activity de iOS) — ambos abren la app directo en la pantalla
/// correcta en vez de solo traerla al frente.
///
/// - Android: `MainActivity` captura el Intent (extras `deepLinkRoute`/
///   `deepLinkRole`) y lo manda acá por `com.gardenbo.app/deep_link` — una
///   sola llamada a [init] cubre tanto el caso de "la app estaba cerrada"
///   (`getInitialRoute`) como "la app ya estaba abierta" (evento
///   `onDeepLink`, ver `onNewIntent` en MainActivity.kt).
/// - iOS: el Live Activity usa `widgetURL`/`Link` con el esquema `garden://`
///   (ver AppDelegate.swift) — mismo canal y mismo formato de ruta
///   (`/service/<bookingId>`) para no duplicar la lógica de navegación.
class DeepLinkService {
  DeepLinkService._();

  static const _channel = MethodChannel('com.gardenbo.app/deep_link');
  static bool _initialized = false;

  static Future<void> init(GoRouter router) async {
    if (kIsWeb || _initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final args = call.arguments as Map?;
        final route = args?['route'] as String?;
        final role = args?['role'] as String?;
        if (route != null) _navigate(router, route, role);
      }
    });

    try {
      final initial = await _channel.invokeMethod<Map>('getInitialRoute');
      final route = initial?['route'] as String?;
      final role = initial?['role'] as String?;
      if (route != null) _navigate(router, route, role);
    } catch (e) {
      debugPrint('[DeepLink] getInitialRoute error: $e');
    }
  }

  static void _navigate(GoRouter router, String route, String? role) {
    // El widget solo tiene sentido para un usuario con sesión activa — si por
    // lo que sea no la hay (logout mientras el widget quedó pegado con datos
    // viejos, etc.), el router ya redirige solo a /login para rutas privadas.
    if (route.startsWith('/service/')) {
      if (!AuthState.hasSession) return;
      final bookingId = route.substring('/service/'.length);
      router.push('/service/$bookingId', extra: {
        'role': role ?? AuthState.effectiveRole,
        'token': AuthState.token,
      });
      return;
    }
    router.push(route);
  }
}

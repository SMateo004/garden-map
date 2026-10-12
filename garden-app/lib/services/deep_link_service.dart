import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
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
        if (route != null) _navigateWhenReady(router, route, role);
      }
    });

    try {
      final initial = await _channel.invokeMethod<Map>('getInitialRoute');
      final route = initial?['route'] as String?;
      final role = initial?['role'] as String?;
      if (route != null) _navigateWhenReady(router, route, role);
    } catch (e) {
      debugPrint('[DeepLink] getInitialRoute error: $e');
    }
  }

  // ── Esperar a que la app termine de arrancar ──────────────────────────────
  // Con la app cerrada, el toque en el widget llega mientras todavía se muestra el arranque
  // (/ → /splash → inicio según la sesión). Ese arranque navega con `go`, que reemplaza la pila:
  // si el destino del widget se empujaba antes, se perdía y la persona caía en el inicio. Ahora
  // se guarda y se abre recién cuando la app ya está en una pantalla real (o después del login).
  static const _bootLocations = {'', '/', '/splash', '/onboarding', '/login', '/maintenance', '/update-required'};
  static String? _pendingRoute;
  static String? _pendingRole;
  static GoRouter? _router;

  static bool _isReady(GoRouter router) {
    final path = router.routerDelegate.currentConfiguration.uri.path;
    return !_bootLocations.contains(path);
  }

  @visibleForTesting
  static void handleForTest(GoRouter router, String route, String? role) => _navigateWhenReady(router, route, role);

  static void _navigateWhenReady(GoRouter router, String route, String? role) {
    if (_isReady(router)) {
      _navigate(router, route, role);
      return;
    }
    _pendingRoute = route;
    _pendingRole = role;
    if (_router == null) {
      _router = router;
      router.routerDelegate.addListener(_flushPending);
    }
  }

  static void _flushPending() {
    final router = _router;
    final route = _pendingRoute;
    if (router == null || route == null || !_isReady(router)) return;
    final role = _pendingRole;
    _pendingRoute = null;
    _pendingRole = null;
    router.routerDelegate.removeListener(_flushPending);
    _router = null;
    // Fuera del frame de navegación que disparó el aviso.
    WidgetsBinding.instance.addPostFrameCallback((_) => _navigate(router, route, role));
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

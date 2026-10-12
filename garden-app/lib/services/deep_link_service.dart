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

  /// Destino real de un toque en un widget según quién tiene la sesión. Los widgets (Android e
  /// iOS) mandan rutas neutras —`/service/<id>`, `/marketplace`, `/my-bookings-tab`— y acá se
  /// traducen a la pantalla correcta para cada rol: el cuidador no tiene marketplace ni "mis
  /// reservas" de dueño (esas rutas son solo de cliente y el router lo devolvía a su inicio, en la
  /// pestaña equivocada). Devuelve null si el toque no tiene destino válido.
  @visibleForTesting
  static ({String location, bool push})? resolve(String route, {required bool hasSession, required String effectiveRole, required bool isStaff}) {
    final path = route.trim();
    final caregiverHome = isStaff ? '/caregiver-staff/home' : '/caregiver/home';
    final isCaregiver = hasSession && effectiveRole == 'CAREGIVER';

    // iOS arma la ruta como "/<host><path>": sin id llega "/service" (sin barra final).
    if (path == '/service' || path.startsWith('/service/')) {
      final bookingId = path.length > '/service/'.length
          ? path.substring('/service/'.length).split(RegExp(r'[/?#]')).first
          : '';
      // Sin sesión no se puede ver un servicio; sin id (dato viejo del widget), no hay qué abrir:
      // en vez de una pantalla rota se va a las reservas de quien tocó.
      if (!hasSession) return null;
      if (bookingId.isEmpty) {
        return (location: isCaregiver ? '$caregiverHome${isStaff ? '' : '?tab=reservas'}' : '/my-bookings-tab', push: false);
      }
      return (location: '/service/$bookingId', push: true);
    }
    if (path == '/my-bookings-tab' || path == '/my-bookings') {
      if (!hasSession) return (location: '/login', push: false);
      return (location: isCaregiver ? '$caregiverHome${isStaff ? '' : '?tab=reservas'}' : '/my-bookings-tab', push: false);
    }
    if (path == '/marketplace' || path.isEmpty || path == '/') {
      return (location: isCaregiver ? caregiverHome : '/marketplace', push: false);
    }
    // Cualquier otra ruta conocida se abre tal cual (el router valida rol y sesión, y una ruta
    // inexistente vuelve al inicio — ver onException en main.dart).
    return (location: path.startsWith('/') ? path : '/$path', push: true);
  }

  static void _navigate(GoRouter router, String route, String? role) {
    final target = resolve(
      route,
      hasSession: AuthState.hasSession,
      effectiveRole: AuthState.effectiveRole,
      isStaff: AuthState.isCaregiverStaff,
    );
    if (target == null) return;
    if (target.location.startsWith('/service/')) {
      router.push(target.location, extra: {
        'role': role ?? AuthState.effectiveRole,
        'token': AuthState.token,
      });
      return;
    }
    // Las pantallas principales (marketplace, mis reservas, inicio del cuidador) se abren con
    // `go`: con `push` quedaban apiladas sobre sí mismas y "atrás" volvía a la misma pantalla.
    if (target.push) {
      router.push(target.location);
    } else {
      router.go(target.location);
    }
  }
}

/// Analytics — uso de la app de forma liviana y anónima.
///
/// Qué mide: sesiones (duración), pantallas vistas y tiempo en cada una,
/// pasos del embudo de reserva (con cuánto tardó el usuario) y los filtros
/// que usa en el marketplace. Todo se manda en lotes chicos (cada 30 s, al
/// llegar a 20 eventos o al pasar a segundo plano) a `POST /analytics/batch`.
///
/// Qué NO mide, a propósito: texto que escribe el usuario, ubicación,
/// contenido de chats, datos de mascotas ni ningún dato personal. Solo ids
/// aleatorios, nombres de pantalla "genéricos" (`/caregiver/:id`, nunca el id
/// real ni tokens) y propiedades chicas tipo `zone=equipetrol`.
///
/// Falla en silencio siempre: la analítica jamás debe romper ni demorar la
/// app. El usuario puede apagarla con [setEnabled] (se respeta de inmediato).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint, visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_state.dart';

const String _kApiBase = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
const _kOptOutKey = 'analytics_opt_out';
const _kDeviceKey = 'analytics_device_id';
const _kSessionGap = Duration(minutes: 30);
const _kMaxQueue = 200;

/// Convierte una ruta concreta en su patrón anónimo: cualquier segmento que
/// parezca un id/token (uuid, hex largo, con dígitos y ≥ 8 caracteres) → `:id`.
@visibleForTesting
String sanitizeRoute(String raw) {
  final path = raw.split('?').first.split('#').first;
  if (path.isEmpty) return '/';
  final parts = path.split('/').map((s) {
    if (s.isEmpty || s.startsWith(':')) return s;
    final looksId = s.length >= 8 && RegExp(r'\d').hasMatch(s);
    return looksId ? ':id' : s;
  });
  final out = parts.join('/');
  return out.length > 60 ? out.substring(0, 60) : out;
}

class Analytics {
  Analytics._();
  static final Analytics instance = Analytics._();

  final List<Map<String, dynamic>> _queue = [];
  final Map<String, DateTime> _marks = {};
  bool _enabled = true;
  bool _initialized = false;
  bool _flushing = false;

  String _deviceId = '';
  String _sessionId = '';
  String _appVersion = '';
  DateTime _sessionStart = DateTime.now();
  DateTime? _pausedAt;
  Duration _backgroundTotal = Duration.zero;
  int _screenCount = 0;

  String? _screen;
  DateTime? _screenStart;

  bool get enabled => _enabled;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = !(prefs.getBool(_kOptOutKey) ?? false);
      var id = prefs.getString(_kDeviceKey);
      if (id == null || id.length < 8) {
        id = _randomId();
        await prefs.setString(_kDeviceKey, id);
      }
      _deviceId = id;
      try {
        _appVersion = (await PackageInfo.fromPlatform()).version;
      } catch (_) {}
    } catch (_) {
      _enabled = false;
      return;
    }
    _startSession();
    Timer.periodic(const Duration(seconds: 30), (_) => flush());
  }

  /// Permite al usuario apagar/prender la analítica (ej. desde Ajustes).
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) _queue.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kOptOutKey, !value);
    } catch (_) {}
  }

  // ── Sesión ────────────────────────────────────────────────────────────

  void _startSession() {
    _sessionId = _randomId();
    _sessionStart = DateTime.now();
    _backgroundTotal = Duration.zero;
    _pausedAt = null;
    _screenCount = 0;
  }

  /// Llamar desde `didChangeAppLifecycleState`.
  void onLifecycle(AppLifecycleState state) {
    if (!_initialized || !_enabled) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (_pausedAt != null) return;
      _closeScreen();
      _pausedAt = DateTime.now();
      flush();
    } else if (state == AppLifecycleState.resumed) {
      final paused = _pausedAt;
      if (paused == null) return;
      final gap = DateTime.now().difference(paused);
      if (gap > _kSessionGap) {
        _startSession(); // volvió después de mucho: es otra sesión
      } else {
        _backgroundTotal += gap;
        _pausedAt = null;
      }
      final s = _screen;
      if (s != null) {
        _screenStart = DateTime.now(); // retoma el cronómetro sin contar otra vista
      }
    }
  }

  int get _activeSeconds {
    final end = _pausedAt ?? DateTime.now();
    final s = end.difference(_sessionStart) - _backgroundTotal;
    return s.isNegative ? 0 : s.inSeconds;
  }

  // ── Pantallas ─────────────────────────────────────────────────────────

  /// Llamado por [AnalyticsRouteObserver] cuando cambia la pantalla visible.
  void screenChanged(String rawRoute, {String? currentPath}) {
    if (!_initialized || !_enabled) return;
    final screen = sanitizeRoute(rawRoute);
    if (screen == _screen) return;
    _closeScreen();
    _screen = screen;
    _screenStart = DateTime.now();
    _screenCount++;
    _milestone(screen, currentPath);
  }

  void _closeScreen() {
    final s = _screen;
    final start = _screenStart;
    if (s == null || start == null) return;
    final ms = DateTime.now().difference(start).inMilliseconds;
    _screenStart = null;
    if (ms < 300) return; // rebotes de navegación, no son vistas reales
    _add('screen_view', screen: s, durationMs: ms.clamp(0, 30 * 60 * 1000));
  }

  /// Pasos del embudo que se derivan de la ruta — sin tocar cada pantalla.
  void _milestone(String screen, String? path) {
    switch (screen) {
      case '/marketplace':
        _add('marketplace_view');
      case '/caregiver/:id':
        final cid = RegExp(r'^/caregiver/([A-Za-z0-9-]{8,40})').firstMatch(path ?? '')?.group(1);
        _add('caregiver_open', props: cid == null ? null : {'cid': cid});
      case '/booking/:id':
      case '/recurring-booking/:id':
        _marks['booking_start'] = DateTime.now();
        _add('booking_start');
      case '/payment/:id':
      case '/payment-new':
        _marks['payment_view'] = DateTime.now();
        _add('payment_view');
    }
  }

  // ── Eventos explícitos ────────────────────────────────────────────────

  /// Evento suelto. [props]: solo valores cortos y NO personales.
  void track(String name, {Map<String, Object>? props, String? sinceMark}) {
    if (!_initialized || !_enabled) return;
    int? ms;
    final mark = sinceMark == null ? null : _marks[sinceMark];
    if (mark != null) ms = DateTime.now().difference(mark).inMilliseconds;
    _add(name, props: props, durationMs: ms);
  }

  /// Filtro/orden aplicado en el marketplace (alimenta "preferencias").
  void filter(String key, Object value) =>
      track('filter_applied', props: {'k': key, 'v': value.toString()});

  // ── Cola y envío ──────────────────────────────────────────────────────

  void _add(String name, {String? screen, int? durationMs, Map<String, Object>? props}) {
    if (_queue.length >= _kMaxQueue) _queue.removeAt(0);
    _queue.add({
      'name': name,
      if ((screen ?? _screen) != null) 'screen': screen ?? _screen,
      if (durationMs != null) 'durationMs': durationMs,
      if (props != null) 'props': props,
      't': DateTime.now().millisecondsSinceEpoch,
    });
    if (_queue.length >= 20) flush();
  }

  Future<void> flush() async {
    if (!_initialized || !_enabled || _flushing || _sessionId.isEmpty) return;
    _flushing = true;
    final batch = _queue.take(60).toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final body = jsonEncode({
        'deviceId': _deviceId,
        'session': {
          'id': _sessionId,
          'platform': kIsWeb
              ? 'web'
              : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'),
          if (_appVersion.isNotEmpty) 'appVersion': _appVersion,
          'locale': WidgetsBinding.instance.platformDispatcher.locale.languageCode,
          if (AuthState.hasSession) 'role': AuthState.effectiveRole,
          'durationSec': _activeSeconds.clamp(0, 4 * 3600),
          'screenCount': _screenCount.clamp(0, 5000),
        },
        'events': [
          for (final e in batch)
            {
              for (final k in e.keys)
                if (k != 't') k: e[k],
              'ago': (now - (e['t'] as int)).clamp(0, 24 * 3600 * 1000),
            },
        ],
      });
      final res = await http
          .post(
            Uri.parse('$_kApiBase/analytics/batch'),
            headers: {
              'Content-Type': 'application/json',
              if (AuthState.hasSession) 'Authorization': 'Bearer ${AuthState.token}',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode < 300 || res.statusCode == 400) {
        _queue.removeRange(0, batch.length.clamp(0, _queue.length));
      }
    } catch (e) {
      debugPrint('Analytics: flush failed (se reintenta): $e');
    } finally {
      _flushing = false;
    }
  }

  static String _randomId() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }
}

/// Observer para GoRouter (`observers: [AnalyticsRouteObserver(...)]`).
class AnalyticsRouteObserver extends NavigatorObserver {
  /// Devuelve la ruta concreta actual (para sacar el id del cuidador).
  final String Function() currentPath;
  AnalyticsRouteObserver(this.currentPath);

  void _report(Route<dynamic>? route) {
    if (route == null || route is PopupRoute) return; // diálogos y bottom sheets no son pantallas
    final name = route.settings.name;
    final path = currentPath();
    Analytics.instance.screenChanged(name == null || name.isEmpty ? path : name, currentPath: path);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _report(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _report(newRoute);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _report(previousRoute);
}

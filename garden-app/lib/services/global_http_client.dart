/// GlobalHttpClient — wraps every `http.get/post/...` call made through
/// `package:http`'s top-level functions, via `http.runWithClient` in main.dart.
///
/// This lets the app react globally to two situations without touching any
/// of the 200+ individual call sites scattered across screens:
///   1. The backend returns 503 MAINTENANCE_MODE while the user is already
///      inside the app (not just at splash) → [maintenanceNotifier] fires.
///   2. A request fails at the transport level (no connection, timeout,
///      DNS failure, etc.) → [networkErrorNotifier] holds a user-facing
///      message until the next successful request clears it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;

/// Fires when the backend reports MAINTENANCE_MODE mid-session.
/// GardenApp listens to this and redirects to /maintenance from any screen.
final maintenanceNotifier = ValueNotifier<bool>(false);

/// Holds a short user-facing message when a request fails at the transport
/// level (no connection, timeout, DNS). Null means no active network issue.
final networkErrorNotifier = ValueNotifier<String?>(null);

const String _kApiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://api.gardenbo.com/api',
);

/// Root domain (no `/api` suffix) — `/health` is mounted at the root, not
/// under `/api`. See garden-api/src/app.ts.
Uri get _healthCheckUri => Uri.parse(
      '${_kApiBaseUrl.replaceFirst(RegExp(r'/api/?$'), '')}/health',
    );

/// ConnectivityMonitor — while [networkErrorNotifier] is non-null (i.e. we
/// believe we're offline), pings the lightweight `/health` endpoint every 3s
/// to detect recovery automatically, so any offline UI (dialog, etc.) can
/// auto-dismiss without the user having to do anything.
///
/// Deliberately only *clears* the notifier on success — it never sets a new
/// error message on failure. That keeps this purely a "did we recover?"
/// probe: it can't itself cause the "no connection" dialog to (re)appear,
/// only real app traffic (an actual user-triggered request failing) does
/// that. This is what lets the UI layer show the dialog once automatically
/// per offline episode while still allowing a genuine failed user action to
/// surface it again.
class ConnectivityMonitor {
  ConnectivityMonitor._();
  static final ConnectivityMonitor instance = ConnectivityMonitor._();

  Timer? _recheckTimer;
  bool _checking = false;
  bool _started = false;

  void start() {
    if (_started) return; // idempotent — safe to call again (e.g. hot restart)
    _started = true;
    networkErrorNotifier.addListener(_onNetworkStateChanged);
    _onNetworkStateChanged(); // in case we start already offline
  }

  void _onNetworkStateChanged() {
    if (networkErrorNotifier.value == null) {
      _recheckTimer?.cancel();
      _recheckTimer = null;
      return;
    }
    _recheckTimer ??= Timer.periodic(const Duration(seconds: 3), (_) => _pingOnce());
  }

  /// Single connectivity probe — used both by the 3s loop and by a manual
  /// "retry" button so the user gets an immediate answer instead of waiting
  /// for the next tick.
  Future<bool> _pingOnce() async {
    if (_checking) return networkErrorNotifier.value == null;
    _checking = true;
    try {
      final response = await http
          .get(_healthCheckUri)
          .timeout(const Duration(seconds: 4));
      // Any response at all (even a non-200) proves the network path is up.
      if (response.statusCode >= 200) {
        networkErrorNotifier.value = null;
        return true;
      }
      return false;
    } catch (_) {
      // Still offline — leave networkErrorNotifier as-is, do not overwrite.
      return false;
    } finally {
      _checking = false;
    }
  }

  /// Manual retry entry point (e.g. a "Reintentar" button in the offline
  /// dialog). Returns true if connectivity was confirmed restored.
  Future<bool> checkNow() => _pingOnce();
}

class GlobalHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await _inner.send(request);

      // Any response that actually reaches us — including a 503 — proves the
      // network itself is fine, so clear a stale "no connection" banner.
      if (networkErrorNotifier.value != null) {
        networkErrorNotifier.value = null;
      }

      if (response.statusCode == 503) {
        final bytes = await response.stream.toBytes();
        final bodyStr = utf8.decode(bytes, allowMalformed: true);
        if (bodyStr.contains('MAINTENANCE_MODE')) {
          maintenanceNotifier.value = true;
        }
        // Re-wrap: the original stream was consumed above, so callers that
        // read response.stream/.body still get the same bytes.
        return http.StreamedResponse(
          Stream.value(bytes),
          response.statusCode,
          contentLength: bytes.length,
          request: response.request,
          headers: response.headers,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection,
          reasonPhrase: response.reasonPhrase,
        );
      }

      return response;
    } on TimeoutException {
      networkErrorNotifier.value = 'El servidor no responde. Intenta de nuevo.';
      rethrow;
    } on http.ClientException {
      // Covers SocketException (no connection) wrapped by IOClient, and
      // BrowserClient's XMLHttpRequest errors on web.
      networkErrorNotifier.value = 'No pudimos conectar con el servidor. Verifica tu conexión.';
      rethrow;
    }
  }
}

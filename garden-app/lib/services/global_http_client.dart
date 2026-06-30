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

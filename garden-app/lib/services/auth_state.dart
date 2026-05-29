/// AuthState — Single source of truth for the current session token.
///
/// Problem solved:
///   35+ screens were reading `access_token` directly from SharedPreferences.
///   After migrating to flutter_secure_storage, those reads always returned ''
///   (empty) because SharedPreferences no longer holds the token, causing the
///   app to behave as if the session had ended mid-navigation.
///
/// Solution:
///   AuthState keeps a synchronous in-memory copy of the token that is
///   initialised once at app start from SecureStorageService. Every screen
///   uses `AuthState.token` instead of touching SharedPreferences directly.
///
/// Session expiry:
///   Any screen or service that receives a 401 should call
///   `AuthState.handleUnauthorized()`. This fires [sessionExpiredNotifier]
///   which is already wired in GardenApp to redirect to /login.
///
library;

import 'package:flutter/foundation.dart' show ValueNotifier, kDebugMode, debugPrint;
import 'secure_storage_service.dart';

/// Se emite cuando el servidor devuelve 401 y el refresh token también es inválido.
/// La app escucha esto en GardenApp para redirigir al login de forma global.
/// Definido aquí (no en auth_service) para evitar dependencias circulares.
final sessionExpiredNotifier = ValueNotifier<bool>(false);

class AuthState {
  AuthState._(); // non-instantiable

  static String _token = '';

  // ── Synchronous read ───────────────────────────────────────────────────────

  /// The current access token. Empty string means no active session.
  static String get token => _token;

  /// True when there is an active session token in memory.
  static bool get hasSession => _token.isNotEmpty;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Call once at app start (after WidgetsFlutterBinding.ensureInitialized).
  /// Loads the token from SecureStorageService into the in-memory cache so
  /// all subsequent reads via [token] are synchronous.
  static Future<void> initialize() async {
    _token = await SecureStorageService.getAccessToken() ?? '';
    if (kDebugMode) {
      debugPrint('[AuthState] initialized — session: ${_token.isNotEmpty ? "present" : "none"}');
    }
  }

  /// Update the in-memory token AND persist to SecureStorageService.
  /// Call after a successful login or token refresh.
  static Future<void> update(String newToken) async {
    _token = newToken;
    await SecureStorageService.saveAccessToken(newToken);
  }

  /// Clear the in-memory token AND all persisted session data.
  /// Call on explicit logout.
  static Future<void> clear() async {
    _token = '';
    await SecureStorageService.clearAll();
  }

  // ── 401 guard ─────────────────────────────────────────────────────────────

  /// Call whenever an HTTP response comes back with status 401.
  ///
  /// Clears the in-memory token and fires [sessionExpiredNotifier] so the
  /// global listener in GardenApp redirects to /login with a SnackBar.
  /// Safe to call multiple times (no-op if already logged out).
  static void handleUnauthorized() {
    if (_token.isEmpty) return; // already logged out — avoid duplicate redirect
    if (kDebugMode) debugPrint('[AuthState] 401 received — session expired');
    _token = '';
    // Fire the global notifier. GardenApp._onSessionExpired handles the
    // redirect to /login and the SnackBar.
    sessionExpiredNotifier.value = true;
  }

  /// Convenience: if [response] has status 401, call [handleUnauthorized] and
  /// return true. Screens can do: `if (AuthState.check401(res)) return;`
  static bool check401(int statusCode) {
    if (statusCode == 401) {
      handleUnauthorized();
      return true;
    }
    return false;
  }
}

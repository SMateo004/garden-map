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
import 'package:shared_preferences/shared_preferences.dart';
import 'secure_storage_service.dart';
import 'presence_service.dart';

/// Se emite cuando el servidor devuelve 401 y el refresh token también es inválido.
/// La app escucha esto en GardenApp para redirigir al login de forma global.
/// Definido aquí (no en auth_service) para evitar dependencias circulares.
final sessionExpiredNotifier = ValueNotifier<bool>(false);

class AuthState {
  AuthState._(); // non-instantiable

  static String _token = '';
  static String _role = '';
  static String _activeRole = '';

  // ── Synchronous read ───────────────────────────────────────────────────────

  /// The current access token. Empty string means no active session.
  static String get token => _token;

  /// True when there is an active session token in memory.
  static bool get hasSession => _token.isNotEmpty;

  /// El rol permanente del usuario ('CLIENT', 'CAREGIVER', 'ADMIN').
  static String get role => _role;

  /// El rol activo temporal (sobre-escribe [role] mientras no esté vacío).
  static String get activeRole => _activeRole;

  /// El rol "efectivo" actual: [activeRole] si no está vacío, si no [role].
  /// Mismo patrón usado en login_screen.dart, profile_screen.dart y
  /// mobile_splash_screen.dart.
  static String get effectiveRole => _activeRole.isNotEmpty ? _activeRole : _role;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Call once at app start (after WidgetsFlutterBinding.ensureInitialized).
  /// Loads the token from SecureStorageService and the role/activeRole from
  /// SharedPreferences into the in-memory cache so all subsequent reads via
  /// [token]/[role]/[activeRole]/[effectiveRole] are synchronous.
  static Future<void> initialize() async {
    _token = await SecureStorageService.getAccessToken() ?? '';
    final prefs = await SharedPreferences.getInstance();
    _role = prefs.getString('user_role') ?? '';
    _activeRole = prefs.getString('active_role') ?? '';
    if (kDebugMode) {
      debugPrint('[AuthState] initialized — session: ${_token.isNotEmpty ? "present" : "none"}, '
          'role: $_role, activeRole: $_activeRole');
    }
    if (hasSession) PresenceService.instance.connect();
  }

  /// Update the in-memory token AND persist to SecureStorageService.
  /// Call after a successful login or token refresh.
  static Future<void> update(String newToken) async {
    _token = newToken;
    await SecureStorageService.saveAccessToken(newToken);
    PresenceService.instance.connect();
  }

  /// Update the in-memory role cache. Call alongside every write to
  /// `user_role`/`active_role` in SharedPreferences so this cache stays in
  /// sync with persisted storage. Pass only the field(s) that changed;
  /// omitted fields are left untouched. Pass an empty string to clear a role.
  static void updateRole({String? role, String? activeRole}) {
    if (role != null) _role = role;
    if (activeRole != null) _activeRole = activeRole;
  }

  /// Clear the in-memory token AND all persisted session data.
  /// Call on explicit logout.
  static Future<void> clear() async {
    _token = '';
    _role = '';
    _activeRole = '';
    await SecureStorageService.clearAll();
    PresenceService.instance.disconnect();
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

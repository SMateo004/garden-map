/// SecureStorageService
///
/// Wraps [flutter_secure_storage] to store sensitive tokens (access_token,
/// refresh_token) in the device's secure enclave (iOS Keychain / Android
/// EncryptedSharedPreferences).
///
/// Resilience strategy:
///   - If secure storage throws (e.g. iOS Keychain entitlement missing in dev,
///     or first-run before entitlement propagates), falls back to
///     SharedPreferences so the app NEVER freezes.
///   - On every successful secure-storage write, any legacy plaintext copy in
///     SharedPreferences is removed (one-way migration).
///   - On every successful secure-storage read, we attempt to migrate a legacy
///     token from SharedPreferences and then delete it there.
///
/// Non-sensitive user data (name, role, photo URL) stays in SharedPreferences.
library;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAccessToken  = 'access_token';
const _kRefreshToken = 'refresh_token';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true, // AES-256 via Jetpack Security
    ),
    iOptions: IOSOptions(
      // first_unlock (not _this_device) works on Simulator and device equally.
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // ── Access token ───────────────────────────────────────────────────────────

  static Future<void> saveAccessToken(String token) async {
    try {
      await _storage.write(key: _kAccessToken, value: token);
      // Remove legacy plaintext copy if present
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAccessToken);
    } catch (e) {
      if (kDebugMode) debugPrint('[SecureStorage] write failed, using SharedPreferences: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAccessToken, token);
    }
  }

  static Future<String?> getAccessToken() async {
    try {
      final token = await _storage.read(key: _kAccessToken);
      if (token != null) return token;
      // Migrate legacy token from SharedPreferences if it exists
      return await _migrateFromPrefs(_kAccessToken);
    } catch (e) {
      if (kDebugMode) debugPrint('[SecureStorage] read failed, falling back: $e');
      return await _fallbackRead(_kAccessToken);
    }
  }

  static Future<void> deleteAccessToken() async {
    try {
      await _storage.delete(key: _kAccessToken);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
  }

  // ── Refresh token ──────────────────────────────────────────────────────────

  static Future<void> saveRefreshToken(String token) async {
    try {
      await _storage.write(key: _kRefreshToken, value: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kRefreshToken);
    } catch (e) {
      if (kDebugMode) debugPrint('[SecureStorage] write failed, using SharedPreferences: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRefreshToken, token);
    }
  }

  static Future<String?> getRefreshToken() async {
    try {
      final token = await _storage.read(key: _kRefreshToken);
      if (token != null) return token;
      return await _migrateFromPrefs(_kRefreshToken);
    } catch (e) {
      if (kDebugMode) debugPrint('[SecureStorage] read failed, falling back: $e');
      return await _fallbackRead(_kRefreshToken);
    }
  }

  static Future<void> deleteRefreshToken() async {
    try {
      await _storage.delete(key: _kRefreshToken);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRefreshToken);
  }

  // ── Clear all ──────────────────────────────────────────────────────────────

  static Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Reads a legacy token from SharedPreferences, migrates it to secure
  /// storage, then deletes the plaintext copy.
  static Future<String?> _migrateFromPrefs(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(key);
      if (legacy == null || legacy.isEmpty) return null;
      // Migrate: write to secure storage and erase plaintext
      await _storage.write(key: key, value: legacy);
      await prefs.remove(key);
      if (kDebugMode) debugPrint('[SecureStorage] Migrated $key from SharedPreferences');
      return legacy;
    } catch (_) {
      return null;
    }
  }

  /// Last-resort plaintext read (used when secure storage itself throws).
  static Future<String?> _fallbackRead(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }
}

/// SecureStorageService
///
/// Wraps [flutter_secure_storage] to store sensitive tokens (access_token,
/// refresh_token) in the device's secure enclave (iOS Keychain / Android
/// EncryptedSharedPreferences).
///
/// Non-sensitive user data (name, role, photo URL) stays in SharedPreferences.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kAccessToken  = 'access_token';
const _kRefreshToken = 'refresh_token';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true, // AES-256 via Jetpack Security
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // ── Access token ───────────────────────────────────────────────────────────

  static Future<void> saveAccessToken(String token) =>
      _storage.write(key: _kAccessToken, value: token);

  static Future<String?> getAccessToken() =>
      _storage.read(key: _kAccessToken);

  static Future<void> deleteAccessToken() =>
      _storage.delete(key: _kAccessToken);

  // ── Refresh token ──────────────────────────────────────────────────────────

  static Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _kRefreshToken, value: token);

  static Future<String?> getRefreshToken() =>
      _storage.read(key: _kRefreshToken);

  static Future<void> deleteRefreshToken() =>
      _storage.delete(key: _kRefreshToken);

  // ── Clear all secure keys ──────────────────────────────────────────────────

  static Future<void> clearAll() => _storage.deleteAll();
}

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'secure_storage_service.dart';
import 'auth_state.dart'; // sessionExpiredNotifier + AuthState cache

// sessionExpiredNotifier is defined in auth_state.dart and re-exported for
// backward compatibility with any code that imports it from here.
export 'auth_state.dart' show sessionExpiredNotifier;

class AuthService {
  final String baseUrl = const String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.gardenbo.com/api',
  );

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
  };

  Map<String, String> authHeaders(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  // ── Token storage (backed by flutter_secure_storage) ───────────────────────
  // Tokens are stored in iOS Keychain / Android EncryptedSharedPreferences so
  // they cannot be extracted from a non-rooted device.

  Future<void> saveToken(String token) async {
    await SecureStorageService.saveAccessToken(token);
    await AuthState.update(token); // keep in-memory cache in sync
  }

  Future<String?> getToken() async {
    // Prefer in-memory cache (synchronous); fall back to SecureStorage
    if (AuthState.hasSession) return AuthState.token;
    return SecureStorageService.getAccessToken();
  }

  Future<void> saveRefreshToken(String token) =>
      SecureStorageService.saveRefreshToken(token);

  Future<String?> getRefreshToken() =>
      SecureStorageService.getRefreshToken();

  /// Guarda access + refresh tokens de una respuesta de la API.
  Future<void> _saveTokens(Map<String, dynamic> data) async {
    if (data['accessToken'] != null) await saveToken(data['accessToken'] as String);
    if (data['refreshToken'] != null) await saveRefreshToken(data['refreshToken'] as String);
  }

  Future<void> saveActiveRole(String activeRole) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_role', activeRole);
  }

  Future<String> getActiveRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('active_role') ?? '';
  }

  Future<void> clearToken() async {
    // Clear in-memory token cache immediately
    await AuthState.clear();
    // Clear sensitive tokens from secure storage
    await SecureStorageService.clearAll();
    // Clear non-sensitive user data from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_role');
    await prefs.remove('active_role');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_photo');
  }

  // ── User data storage ───────────────────────────────────────────────────────

  Future<void> saveUserData(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    final permanentRole = user['role'] as String? ?? '';
    final activeRole = user['activeRole'] as String?;
    await prefs.setString('user_role', permanentRole);
    await prefs.setString('user_id', user['id'] as String? ?? '');
    await prefs.setString(
      'user_name',
      user['fullName'] as String? ?? '${user['firstName']} ${user['lastName']}',
    );
    await prefs.setString('user_photo', user['profilePicture'] as String? ?? '');
    // Persist active_role from the server; clear if null or same as permanent role
    if (activeRole != null && activeRole.isNotEmpty && activeRole != permanentRole) {
      await prefs.setString('active_role', activeRole);
    } else {
      await prefs.remove('active_role');
    }
  }

  // ── Session refresh ─────────────────────────────────────────────────────────

  /// Renueva el access token usando el refresh token almacenado.
  /// Devuelve el nuevo access token o null si la sesión expiró.
  Future<String?> renewAccessToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) return null;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: _headers,
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          final tokens = data['data'] as Map<String, dynamic>;
          final newAccess = tokens['accessToken'] as String;
          await SecureStorageService.saveAccessToken(newAccess);
          await SecureStorageService.saveRefreshToken(tokens['refreshToken'] as String);
          // Keep AuthState in-memory cache in sync
          await AuthState.update(newAccess);
          return newAccess;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Ejecuta una petición HTTP autenticada con auto-renovación de token.
  /// Si recibe 401, intenta renovar el token una vez y reintenta.
  /// Si el refresh también falla, dispara [sessionExpiredNotifier] para
  /// que la app redirija al login globalmente.
  Future<http.Response> authenticatedRequest(
    Future<http.Response> Function(String token) request,
  ) async {
    final token = await getToken() ?? '';
    var response = await request(token);

    if (response.statusCode == 401) {
      final newToken = await renewAccessToken();
      if (newToken != null) {
        response = await request(newToken);
      } else {
        // Refresh falló — sesión definitivamente expirada
        await clearToken();
        sessionExpiredNotifier.value = true;
      }
    }
    return response;
  }

  // ── Auth endpoints ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: _headers,
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw Exception('No se pudo conectar con el servidor. Verifica tu internet e intenta de nuevo.');
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('El servidor no respondió correctamente (${response.statusCode}). Intenta de nuevo en unos segundos.');
    }

    if (response.statusCode == 200 && data['success'] == true) {
      final result = data['data'] as Map<String, dynamic>;
      await _saveTokens(result);
      await saveUserData(result['user'] as Map<String, dynamic>);
      return result;
    }
    throw Exception(
      (data['error'] as Map<String, dynamic>?)?['message'] ??
          data['message'] ??
          'Error al iniciar sesión',
    );
  }

  Future<Map<String, dynamic>> registerClient({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String phone,
    String? address,
    DateTime? dateOfBirth,
    String? bio,
    double? addressLat,
    double? addressLng,
    String? addressStreet,
    String? addressNumber,
    String? addressApartment,
    String? addressCondominio,
    String? addressReference,
    String? addressZone,
  }) async {
    final body = {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'password': password,
      'phone': phone,
      if (address != null && address.isNotEmpty) 'address': address,
      if (dateOfBirth != null) 'dateOfBirth': dateOfBirth.toIso8601String(),
      if (bio != null && bio.isNotEmpty) 'bio': bio,
      if (addressLat != null) 'addressLat': addressLat,
      if (addressLng != null) 'addressLng': addressLng,
      if (addressStreet != null && addressStreet.isNotEmpty) 'addressStreet': addressStreet,
      if (addressNumber != null && addressNumber.isNotEmpty) 'addressNumber': addressNumber,
      if (addressApartment != null && addressApartment.isNotEmpty) 'addressApartment': addressApartment,
      if (addressCondominio != null && addressCondominio.isNotEmpty) 'addressCondominio': addressCondominio,
      if (addressReference != null && addressReference.isNotEmpty) 'addressReference': addressReference,
      if (addressZone != null && addressZone.isNotEmpty) 'addressZone': addressZone,
    };
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/auth/client/register'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw Exception('No se pudo conectar con el servidor. Verifica tu internet e intenta de nuevo.');
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('El servidor no respondió correctamente (${response.statusCode}). Intenta de nuevo en unos segundos.');
    }
    if (response.statusCode == 201 && data['success'] == true) {
      final result = data['data'] as Map<String, dynamic>;
      await _saveTokens(result);
      await saveUserData(result['user'] as Map<String, dynamic>);
      return result;
    }
    if (data['errors'] != null) {
      final errors = (data['errors'] as List)
          .map((e) => (e as Map<String, dynamic>)['message'] as String)
          .join(', ');
      throw Exception(errors);
    }
    throw Exception(
      (data['error'] as Map<String, dynamic>?)?['message'] ??
          data['message'] ??
          'Error al registrarse',
    );
  }

  /// Llama a POST /api/auth/switch-role.
  /// Guarda los nuevos tokens y el active_role en SharedPreferences.
  /// Devuelve el effectiveRole resultante ('CLIENT' o 'CAREGIVER').
  Future<String> switchRole({required String token, required String targetRole}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/switch-role'),
      headers: authHeaders(token),
      body: jsonEncode({'targetRole': targetRole}),
    ).timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 && data['success'] == true) {
      final result = data['data'] as Map<String, dynamic>;
      await _saveTokens(result);
      final effectiveRole = result['activeRole'] as String? ?? targetRole;
      // Si el activeRole coincide con el rol permanente, limpiar active_role
      final prefs = await SharedPreferences.getInstance();
      final permanentRole = prefs.getString('user_role') ?? '';
      if (effectiveRole == permanentRole) {
        await prefs.remove('active_role');
      } else {
        await saveActiveRole(effectiveRole);
      }
      return effectiveRole;
    }
    throw Exception(
      (data['error'] as Map<String, dynamic>?)?['message'] ?? 'Error al cambiar de rol',
    );
  }

  Future<void> logout() async {
    try {
      final token = await getToken();
      if (token != null) {
        await http.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: authHeaders(token),
        );
      }
    } catch (_) {
      // Continuar con limpieza local aunque el request falle
    } finally {
      await clearToken();
    }
  }

  Future<Map<String, dynamic>> getMe(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: authHeaders(token),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 && data['success'] == true) {
      return data['data'] as Map<String, dynamic>;
    }
    throw Exception('Sesión expirada');
  }
}

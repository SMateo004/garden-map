import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final String baseUrl = const String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://garden-api-1ldd.onrender.com/api',
  );

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
  };

  Map<String, String> authHeaders(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  // ── Token storage ───────────────────────────────────────────────────────────

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', token);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<void> saveRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('refresh_token', token);
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('refresh_token');
  }

  /// Guarda access + refresh tokens de una respuesta de la API.
  Future<void> _saveTokens(Map<String, dynamic> data) async {
    if (data['accessToken'] != null) await saveToken(data['accessToken'] as String);
    if (data['refreshToken'] != null) await saveRefreshToken(data['refreshToken'] as String);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_role');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_photo');
  }

  // ── User data storage ───────────────────────────────────────────────────────

  Future<void> saveUserData(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', user['role'] as String? ?? '');
    await prefs.setString('user_id', user['id'] as String? ?? '');
    await prefs.setString(
      'user_name',
      user['fullName'] as String? ?? '${user['firstName']} ${user['lastName']}',
    );
    await prefs.setString('user_photo', user['profilePicture'] as String? ?? '');
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
          await saveToken(tokens['accessToken'] as String);
          await saveRefreshToken(tokens['refreshToken'] as String);
          return tokens['accessToken'] as String;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Ejecuta una petición HTTP autenticada con auto-renovación de token.
  /// Si recibe 401, intenta renovar el token una vez y reintenta.
  Future<http.Response> authenticatedRequest(
    Future<http.Response> Function(String token) request,
  ) async {
    final token = await getToken() ?? '';
    var response = await request(token);

    if (response.statusCode == 401) {
      final newToken = await renewAccessToken();
      if (newToken != null) {
        response = await request(newToken);
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
  }) async {
    final body = {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'password': password,
      'phone': phone,
      if (address != null && address.isNotEmpty) 'address': address,
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

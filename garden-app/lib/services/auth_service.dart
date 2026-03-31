import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final String baseUrl = const String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:3000/api',
  );

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
  };

  Map<String, String> authHeaders(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  // Guardar token en SharedPreferences
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', token);
  }

  // Leer token guardado
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  // Eliminar token (logout)
  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('user_role');
    await prefs.remove('user_id');
  }

  // Guardar datos del usuario
  Future<void> saveUserData(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', user['role'] ?? '');
    await prefs.setString('user_id', user['id'] ?? '');
    await prefs.setString('user_name', user['fullName'] ?? '${user['firstName']} ${user['lastName']}');
    await prefs.setString('user_photo', user['profilePicture'] ?? '');
  }

  // LOGIN
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      await saveToken(data['data']['accessToken']);
      await saveUserData(data['data']['user']);
      return data['data'];
    }
    throw Exception(
      data['error']?['message'] ?? data['message'] ?? 'Error al iniciar sesión',
    );
  }

  // REGISTRO CLIENTE (dueño)
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
    final response = await http.post(
      Uri.parse('$baseUrl/auth/client/register'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201 && data['success'] == true) {
      await saveToken(data['data']['accessToken']);
      await saveUserData(data['data']['user']);
      return data['data'];
    }
    // Manejo de errores de validación del backend
    if (data['errors'] != null) {
      final errors = (data['errors'] as List)
          .map((e) => e['message'] as String)
          .join(', ');
      throw Exception(errors);
    }
    throw Exception(
      data['error']?['message'] ?? data['message'] ?? 'Error al registrarse',
    );
  }

  // OBTENER USUARIO ACTUAL
  Future<Map<String, dynamic>> getMe(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: authHeaders(token),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return data['data'];
    }
    throw Exception('Sesión expirada');
  }
}

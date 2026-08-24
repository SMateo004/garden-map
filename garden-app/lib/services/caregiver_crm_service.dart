import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_state.dart';

/// Cliente HTTP del CRM de mascotas walk-in + dashboard de ocupación.
/// Una sola clase parametrizada por prefijo — el dueño y el staff pegan a
/// los MISMOS endpoints del backend, solo cambia el prefijo de la URL
/// ('caregiver' para el dueño → /api/caregiver/crm/*, 'caregiver-staff'
/// para el empleado → /api/caregiver-staff/crm/*). Mismas convenciones que
/// caregiver_staff_service.dart.
class CaregiverCrmService {
  final String baseUrl = const String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.gardenbo.com/api',
  );

  /// 'caregiver' (dueño) o 'caregiver-staff' (empleado).
  final String prefix;
  CaregiverCrmService({required this.prefix});

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AuthState.token}',
      };

  Future<Map<String, dynamic>> _decode(http.Response res) async {
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception((data['error'] as Map<String, dynamic>?)?['message'] as String? ?? 'Error inesperado');
    }
    return data;
  }

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl/$prefix/crm$path').replace(queryParameters: query);

  // ── Clientes walk-in ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listClients({String? search}) async {
    final res = await http.get(
      _u('/clients', search != null && search.isNotEmpty ? {'search': search} : null),
      headers: _authHeaders,
    );
    final data = await _decode(res);
    return (data['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getClient(String id) async {
    final res = await http.get(_u('/clients/$id'), headers: _authHeaders);
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createClient({required String name, String? phone, String? email, String? notes}) async {
    final res = await http.post(
      _u('/clients'),
      headers: _authHeaders,
      body: jsonEncode({
        'name': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      }),
    );
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<void> deleteClient(String id) async {
    final res = await http.delete(_u('/clients/$id'), headers: _authHeaders);
    await _decode(res);
  }

  // ── Mascotas walk-in ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createPet(String clientId, Map<String, dynamic> body) async {
    final res = await http.post(_u('/clients/$clientId/pets'), headers: _authHeaders, body: jsonEncode(body));
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<void> deletePet(String petId) async {
    final res = await http.delete(_u('/pets/$petId'), headers: _authHeaders);
    await _decode(res);
  }

  // ── Check-in / check-out ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> checkIn(String petId, {required String serviceType, String? notes}) async {
    final res = await http.post(
      _u('/pets/$petId/check-in'),
      headers: _authHeaders,
      body: jsonEncode({'serviceType': serviceType, if (notes != null && notes.isNotEmpty) 'notes': notes}),
    );
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> checkOut(String visitId) async {
    final res = await http.post(_u('/visits/$visitId/check-out'), headers: _authHeaders);
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  // ── Dashboard de ocupación ────────────────────────────────────────────────

  Future<Map<String, dynamic>> getOccupancy() async {
    final res = await http.get(_u('/occupancy'), headers: _authHeaders);
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }
}

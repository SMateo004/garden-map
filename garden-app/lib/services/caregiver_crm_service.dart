import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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

  Future<Map<String, dynamic>> updateClient(String id, Map<String, dynamic> body) async {
    final res = await http.patch(_u('/clients/$id'), headers: _authHeaders, body: jsonEncode(body));
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<void> deleteClient(String id) async {
    final res = await http.delete(_u('/clients/$id'), headers: _authHeaders);
    await _decode(res);
  }

  // ── Mascotas walk-in ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getPet(String petId) async {
    final res = await http.get(_u('/pets/$petId'), headers: _authHeaders);
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createPet(String clientId, Map<String, dynamic> body) async {
    final res = await http.post(_u('/clients/$clientId/pets'), headers: _authHeaders, body: jsonEncode(body));
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updatePet(String petId, Map<String, dynamic> body) async {
    final res = await http.patch(_u('/pets/$petId'), headers: _authHeaders, body: jsonEncode(body));
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<void> deletePet(String petId) async {
    final res = await http.delete(_u('/pets/$petId'), headers: _authHeaders);
    await _decode(res);
  }

  /// Sube una foto de mascota walk-in vía /upload/service-photo — a
  /// diferencia de /upload/pet-photo (pensado para ClientProfile.petPhoto),
  /// este endpoint es CAREGIVER-only y no tiene efectos secundarios en la
  /// base de datos: solo valida la foto (categoría MASCOTA) y devuelve la URL.
  Future<String> uploadPetPhoto(Uint8List bytes, String fileName) async {
    final uri = Uri.parse('$baseUrl/upload/service-photo');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer ${AuthState.token}';
    request.files.add(http.MultipartFile.fromBytes(
      'photo', bytes, filename: fileName,
      contentType: MediaType('image', 'jpeg'),
    ));
    final streamedRes = await request.send();
    final res = await http.Response.fromStream(streamedRes);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 200 && data['success'] == true) {
      return data['data']['url'] as String;
    }
    final errMsg = (data['error'] as Map<String, dynamic>?)?['message'] as String? ?? 'Error al subir la foto';
    throw Exception(errMsg);
  }

  Future<Map<String, dynamic>> getVisit(String visitId) async {
    final res = await http.get(_u('/visits/$visitId'), headers: _authHeaders);
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  // ── Check-in / check-out ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> checkIn(String petId, {required String serviceType, String? notes, String? spaceLabel}) async {
    final res = await http.post(
      _u('/pets/$petId/check-in'),
      headers: _authHeaders,
      body: jsonEncode({
        'serviceType': serviceType,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (spaceLabel != null && spaceLabel.isNotEmpty) 'spaceLabel': spaceLabel,
      }),
    );
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> checkOut(String visitId, {double? amountCollected}) async {
    final res = await http.post(
      _u('/visits/$visitId/check-out'),
      headers: _authHeaders,
      body: jsonEncode({if (amountCollected != null) 'amountCollected': amountCollected}),
    );
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateVisit(String visitId, Map<String, dynamic> body) async {
    final res = await http.patch(_u('/visits/$visitId'), headers: _authHeaders, body: jsonEncode(body));
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  /// Agrega una entrada a la bitácora de una visita abierta — type es uno de
  /// FEEDING/WALK/MEDICATION/BATH/NOTE (nunca notifican al dueño) o
  /// PHOTO/INCIDENT/INCIDENT_RESOLVED (sí, si el cliente walk-in tiene email).
  Future<Map<String, dynamic>> addVisitEvent(String visitId, {required String type, String? note, String? photoUrl}) async {
    final res = await http.post(
      _u('/visits/$visitId/events'),
      headers: _authHeaders,
      body: jsonEncode({
        'type': type,
        if (note != null && note.isNotEmpty) 'note': note,
        if (photoUrl != null) 'photoUrl': photoUrl,
      }),
    );
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  // ── Dashboard de ocupación ────────────────────────────────────────────────

  Future<Map<String, dynamic>> getOccupancy() async {
    final res = await http.get(_u('/occupancy'), headers: _authHeaders);
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  // ── Reportes (solo dueño) ───────────────────────────────────────────────

  Future<Map<String, dynamic>> getOccupancyReport({String? from, String? to}) async {
    final query = <String, String>{if (from != null) 'from': from, if (to != null) 'to': to};
    final res = await http.get(_u('/reports/occupancy', query.isEmpty ? null : query), headers: _authHeaders);
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCashReport({String? from, String? to}) async {
    final query = <String, String>{if (from != null) 'from': from, if (to != null) 'to': to};
    final res = await http.get(_u('/reports/cash', query.isEmpty ? null : query), headers: _authHeaders);
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }
}

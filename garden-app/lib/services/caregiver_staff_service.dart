import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'auth_state.dart';

/// Cliente HTTP para el staff multiusuario de cuentas empresa — invitar/listar/
/// quitar empleados (dueño) y ver/atender reservas (empleado). Mismas
/// convenciones que auth_service.dart (baseUrl, authHeaders).
class CaregiverStaffService {
  final String baseUrl = const String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.gardenbo.com/api',
  );

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

  // ── Gestión del dueño ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createInvite({String? label}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/caregiver-staff/invites'),
      headers: _authHeaders,
      body: jsonEncode({if (label != null && label.isNotEmpty) 'label': label}),
    );
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listInvites() async {
    final res = await http.get(Uri.parse('$baseUrl/caregiver-staff/invites'), headers: _authHeaders);
    final data = await _decode(res);
    return (data['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> revokeInvite(String inviteId) async {
    final res = await http.delete(Uri.parse('$baseUrl/caregiver-staff/invites/$inviteId'), headers: _authHeaders);
    await _decode(res);
  }

  Future<List<Map<String, dynamic>>> listStaffMembers() async {
    final res = await http.get(Uri.parse('$baseUrl/caregiver-staff/members'), headers: _authHeaders);
    final data = await _decode(res);
    return (data['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> removeStaffMember(String memberId, {String? reason}) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/caregiver-staff/members/$memberId'),
      headers: _authHeaders,
      body: jsonEncode({if (reason != null && reason.isNotEmpty) 'reason': reason}),
    );
    await _decode(res);
  }

  Future<void> suspendStaffMember(String memberId) async {
    final res = await http.patch(Uri.parse('$baseUrl/caregiver-staff/members/$memberId/suspend'), headers: _authHeaders);
    await _decode(res);
  }

  Future<void> reactivateStaffMember(String memberId) async {
    final res = await http.patch(Uri.parse('$baseUrl/caregiver-staff/members/$memberId/reactivate'), headers: _authHeaders);
    await _decode(res);
  }

  // ── Autoservicio del empleado (sin auth) ─────────────────────────────────

  Future<Map<String, dynamic>> previewInvite(String code) async {
    final res = await http.get(Uri.parse('$baseUrl/caregiver-staff/invites/$code/preview'));
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  /// Registra al empleado y ya deja la sesión guardada (mismo flujo que login).
  Future<Map<String, dynamic>> registerStaff({
    required String code,
    required String email,
    required String password,
    required String phone,
    required String firstName,
    required String lastName,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/caregiver-staff/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code, 'email': email, 'password': password,
        'phone': phone, 'firstName': firstName, 'lastName': lastName,
      }),
    );
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  // ── Operativo del empleado ───────────────────────────────────────────────

  Future<Map<String, dynamic>> whoami() async {
    final res = await http.get(Uri.parse('$baseUrl/caregiver-staff/whoami'), headers: _authHeaders);
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getBookings({int page = 1, int limit = 20}) async {
    final res = await http.get(
      Uri.parse('$baseUrl/caregiver-staff/bookings?page=$page&limit=$limit'),
      headers: _authHeaders,
    );
    final data = await _decode(res);
    return (data['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getBookingById(String bookingId) async {
    final res = await http.get(Uri.parse('$baseUrl/caregiver-staff/bookings/$bookingId'), headers: _authHeaders);
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  /// Sube una foto al mismo endpoint genérico que usa la app del dueño
  /// (upload/service-photo) — reusado tal cual, no hay una versión "staff".
  Future<String> uploadServicePhoto(List<int> bytes, String fileName) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload/service-photo'));
    request.headers['Authorization'] = 'Bearer ${AuthState.token}';
    request.files.add(http.MultipartFile.fromBytes('photo', bytes, filename: fileName, contentType: MediaType('image', 'jpeg')));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final data = await _decode(res);
    return (data['data'] as Map<String, dynamic>)['url'] as String;
  }

  Future<Map<String, dynamic>> startService(String bookingId, String photoUrl) async {
    final res = await http.post(
      Uri.parse('$baseUrl/caregiver-staff/bookings/$bookingId/start'),
      headers: _authHeaders,
      body: jsonEncode({'photo': photoUrl}),
    );
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> markEnRoute(String bookingId) async {
    final res = await http.post(Uri.parse('$baseUrl/caregiver-staff/bookings/$bookingId/en-route'), headers: _authHeaders);
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> markArrived(String bookingId) async {
    final res = await http.post(Uri.parse('$baseUrl/caregiver-staff/bookings/$bookingId/arrive'), headers: _authHeaders);
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> addEvent(String bookingId, List<int> photoBytes, String fileName, {String type = 'PHOTO', String? description}) async {
    final uri = Uri.parse('$baseUrl/caregiver-staff/bookings/$bookingId/event');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer ${AuthState.token}';
    request.fields['type'] = type;
    if (description != null) request.fields['description'] = description;
    request.files.add(http.MultipartFile.fromBytes('photo', photoBytes, filename: fileName, contentType: MediaType('image', 'jpeg')));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  /// Sin foto — las fotos del servicio se registran antes vía [addEvent];
  /// concluir solo necesita la ubicación final (best-effort) y opcionalmente
  /// el estado de ánimo de la mascota. Mismo patrón que
  /// service_execution_screen.dart _concludeService().
  Future<Map<String, dynamic>> concludeService(String bookingId, {double? lat, double? lng, String? petMood}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/caregiver-staff/bookings/$bookingId/conclude'),
      headers: _authHeaders,
      body: jsonEncode({
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (petMood != null) 'petMood': petMood,
      }),
    );
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> confirmEnd(String bookingId, bool accepted) async {
    final res = await http.post(
      Uri.parse('$baseUrl/caregiver-staff/bookings/$bookingId/confirm-end'),
      headers: _authHeaders,
      body: jsonEncode({'accepted': accepted}),
    );
    final data = await _decode(res);
    return data['data'] as Map<String, dynamic>;
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;

class AgentesService {
  final String baseUrl = const String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://garden-api-1ldd.onrender.com/api',
  );
  final String authToken;

  AgentesService({required this.authToken});

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $authToken',
  };

  // AGENTE 2: Sugerir precio en onboarding
  Future<Map<String, dynamic>> sugerirPrecioOnboarding({
    required String zona,
    required String servicio,
    required int experienciaMeses,
    required int trustScore,
    required double precioPromedioZona,
    required double precioMinZona,
    required double precioMaxZona,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/agentes/precio/onboarding'),
        headers: _headers,
        body: jsonEncode({
          'zona': zona,
          'servicio': servicio,
          'experienciaMeses': experienciaMeses,
          'trustScore': trustScore,
          'precioPromedioZona': precioPromedioZona,
          'precioMinZona': precioMinZona,
          'precioMaxZona': precioMaxZona,
        }),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Error ${response.statusCode}: ${response.body}');
    } catch (e) {
      throw Exception('sugerirPrecioOnboarding falló: $e');
    }
  }

  // AGENTE 2: Calcular ajuste dinámico por zona
  Future<Map<String, dynamic>> calcularAjusteDinamico({
    required String zona,
    required String servicio,
    required double ocupacionUltimos30Dias,
    required int reservasUltimos7Dias,
    required int reservasMismoPeriodoMesAnterior,
    required List<String> eventosProximos,
    required String fechaConsulta,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/agentes/precio/ajuste-dinamico'),
        headers: _headers,
        body: jsonEncode({
          'zona': zona,
          'servicio': servicio,
          'ocupacionUltimos30Dias': ocupacionUltimos30Dias,
          'reservasUltimos7Dias': reservasUltimos7Dias,
          'reservasMismoPeriodoMesAnterior': reservasMismoPeriodoMesAnterior,
          'eventosProximos': eventosProximos,
          'fechaConsulta': fechaConsulta,
        }),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Error ${response.statusCode}: ${response.body}');
    } catch (e) {
      throw Exception('calcularAjusteDinamico falló: $e');
    }
  }

  // AGENTE 2: Explicar badge de temporada alta al dueño
  Future<Map<String, dynamic>> explicarBadgeTemporadaAlta({
    required String zona,
    required int porcentajeAjuste,
    required String motivo,
    required String fechaVueltaNormal,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/agentes/precio/explicar-badge'),
        headers: _headers,
        body: jsonEncode({
          'zona': zona,
          'porcentajeAjuste': porcentajeAjuste,
          'motivo': motivo,
          'fechaVueltaNormal': fechaVueltaNormal,
        }),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Error ${response.statusCode}: ${response.body}');
    } catch (e) {
      throw Exception('explicarBadgeTemporadaAlta falló: $e');
    }
  }

  // AGENTE 1: Analizar si una calificación es válida o sospechosa
  Future<Map<String, dynamic>> analizarCalificacion({
    required int calificacionNueva,
    required String cuidadorId,
    required List<int> historialCalificaciones,
    required double calificacionPromedio,
    required int totalResenas,
    required String tiempoEnPlataforma,
    required List<int> duenoHistorial,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/agentes/calificacion/analizar'),
        headers: _headers,
        body: jsonEncode({
          'calificacionNueva': calificacionNueva,
          'cuidadorId': cuidadorId,
          'historialCalificaciones': historialCalificaciones,
          'calificacionPromedio': calificacionPromedio,
          'totalResenas': totalResenas,
          'tiempoEnPlataforma': tiempoEnPlataforma,
          'duenoHistorial': duenoHistorial,
        }),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Error ${response.statusCode}: ${response.body}');
    } catch (e) {
      throw Exception('analizarCalificacion falló: $e');
    }
  }

  // AGENTE 1: Analizar disputa y recomendar resolución
  Future<Map<String, dynamic>> analizarDisputa({
    required Map<String, dynamic> reserva,
    required Map<String, dynamic> cuidador,
    required Map<String, dynamic> dueno,
    required Map<String, dynamic> mascota,
    required String motivoDisputa,
    List<String>? mensajesRelevantes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/agentes/disputa/analizar'),
        headers: _headers,
        body: jsonEncode({
          'reserva': reserva,
          'cuidador': cuidador,
          'dueno': dueno,
          'mascota': mascota,
          'motivoDisputa': motivoDisputa,
          if (mensajesRelevantes != null)
            'mensajesRelevantes': mensajesRelevantes,
        }),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Error ${response.statusCode}: ${response.body}');
    } catch (e) {
      throw Exception('analizarDisputa falló: $e');
    }
  }
}

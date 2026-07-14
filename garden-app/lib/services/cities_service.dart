import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Ciudad donde Garden opera (multi-ciudad — reemplaza el supuesto implícito
/// de "todo es Santa Cruz"). Datos reales desde el backend, editables por
/// el admin sin necesitar un release de la app.
class GardenCity {
  final String id;
  final String name;
  final String slug;
  final double centerLat;
  final double centerLng;
  final double defaultZoom;

  const GardenCity({
    required this.id,
    required this.name,
    required this.slug,
    required this.centerLat,
    required this.centerLng,
    required this.defaultZoom,
  });

  factory GardenCity.fromJson(Map<String, dynamic> json) => GardenCity(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        centerLat: (json['centerLat'] as num).toDouble(),
        centerLng: (json['centerLng'] as num).toDouble(),
        defaultZoom: (json['defaultZoom'] as num).toDouble(),
      );
}

/// Zona dentro de una ciudad (ej. Equipetrol en Santa Cruz, Parque Fidel
/// Anzoátegui en Cochabamba). Reemplaza el enum fijo `Zone` y los mapas
/// hardcodeados en `constants/zones.dart` — el admin agrega/edita zonas
/// desde el panel sin tocar código.
class GardenZone {
  final String id;
  final String key;
  final String label;
  final Color color;
  final double lat;
  final double lng;

  const GardenZone({
    required this.id,
    required this.key,
    required this.label,
    required this.color,
    required this.lat,
    required this.lng,
  });

  factory GardenZone.fromJson(Map<String, dynamic> json) => GardenZone(
        id: json['id'] as String,
        key: json['key'] as String,
        label: json['label'] as String,
        color: _parseHexColor(json['color'] as String),
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );

  static Color _parseHexColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    final value = int.tryParse(clean, radix: 16) ?? 0x4CAF50;
    return Color(0xFF000000 | value);
  }
}

/// Cachea ciudades/zonas en memoria por 5 minutos — cambian poco (el admin
/// las edita ocasionalmente), no hace falta pedirlas en cada pantalla.
class CitiesService {
  static List<GardenCity>? _citiesCache;
  static DateTime? _citiesCachedAt;
  static final Map<String, List<GardenZone>> _zonesCache = {};
  static final Map<String, DateTime> _zonesCachedAt = {};
  static const _ttl = Duration(minutes: 5);

  static String get _baseUrl =>
      const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  static Future<List<GardenCity>> getCities({bool forceRefresh = false}) async {
    final cached = _citiesCache;
    final cachedAt = _citiesCachedAt;
    if (!forceRefresh && cached != null && cachedAt != null && DateTime.now().difference(cachedAt) < _ttl) {
      return cached;
    }
    try {
      final res = await http.get(Uri.parse('$_baseUrl/cities'));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final list = (data['data'] as List)
            .map((e) => GardenCity.fromJson(e as Map<String, dynamic>))
            .toList();
        _citiesCache = list;
        _citiesCachedAt = DateTime.now();
        return list;
      }
    } catch (_) {
      // Sin conexión — devolvemos lo que haya en caché, aunque esté vencido.
    }
    return _citiesCache ?? [];
  }

  static Future<List<GardenZone>> getZones(String cityId, {bool forceRefresh = false}) async {
    final cached = _zonesCache[cityId];
    final cachedAt = _zonesCachedAt[cityId];
    if (!forceRefresh && cached != null && cachedAt != null && DateTime.now().difference(cachedAt) < _ttl) {
      return cached;
    }
    try {
      final res = await http.get(Uri.parse('$_baseUrl/cities/$cityId/zones'));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final list = (data['data'] as List)
            .map((e) => GardenZone.fromJson(e as Map<String, dynamic>))
            .toList();
        _zonesCache[cityId] = list;
        _zonesCachedAt[cityId] = DateTime.now();
        return list;
      }
    } catch (_) {
      // Sin conexión — devolvemos lo que haya en caché para esa ciudad.
    }
    return _zonesCache[cityId] ?? [];
  }
}

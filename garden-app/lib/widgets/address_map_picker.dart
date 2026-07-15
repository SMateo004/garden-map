import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Resultado del mapa picker.
class AddressMapResult {
  final double lat;
  final double lng;
  /// Dirección legible (reverse geocoding), si se pudo calcular — usada para
  /// pre-llenar el campo "Calle / Avenida" sin que el usuario la re-escriba.
  final String? formattedAddress;

  const AddressMapResult({required this.lat, required this.lng, this.formattedAddress});
}

/// Modal fullscreen con mapa de OpenStreetMap y pin arrastrable.
/// Centrado en la ciudad del usuario (Santa Cruz si no se especifica), y
/// restringido a un radio alrededor de esa ciudad — evita que alguien marque
/// una ubicación "exacta" fuera de su ciudad real (fraude de zona/dirección).
/// Devuelve [AddressMapResult] con lat/lng confirmados, o null si cancela.
Future<AddressMapResult?> showAddressMapPicker(
  BuildContext context, {
  double? initialLat,
  double? initialLng,
  String purpose = 'Tu dirección se usa para coordinar el servicio con el cuidador.',
  double cityLat = -17.7863,
  double cityLng = -63.1812,
  String cityName = 'Santa Cruz',
  double radiusKm = 35,
}) {
  return showModalBottomSheet<AddressMapResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddressMapPicker(
      initialLat: initialLat,
      initialLng: initialLng,
      purpose: purpose,
      cityLat: cityLat,
      cityLng: cityLng,
      cityName: cityName,
      radiusKm: radiusKm,
    ),
  );
}

class _AddressMapPicker extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String purpose;
  final double cityLat;
  final double cityLng;
  final String cityName;
  final double radiusKm;

  const _AddressMapPicker({
    this.initialLat,
    this.initialLng,
    required this.purpose,
    required this.cityLat,
    required this.cityLng,
    required this.cityName,
    required this.radiusKm,
  });

  @override
  State<_AddressMapPicker> createState() => _AddressMapPickerState();
}

class _AddressMapPickerState extends State<_AddressMapPicker> {
  static const _distance = Distance();

  late final LatLng _cityCenter;
  late LatLng _pinPosition;
  late MapController _mapController;
  bool _locating = false;
  String? _reverseAddress;
  /// Solo el nombre de la calle/avenida (de `address.road` en la respuesta de
  /// Nominatim) — para prellenar el campo "Calle / Avenida", a diferencia de
  /// [_reverseAddress] que es la dirección completa mostrada como preview.
  String? _reverseStreet;
  bool _reversing = false;
  DateTime? _lastOutOfBoundsWarning;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _cityCenter = LatLng(widget.cityLat, widget.cityLng);
    _pinPosition = LatLng(
      widget.initialLat ?? widget.cityLat,
      widget.initialLng ?? widget.cityLng,
    );
    if (widget.initialLat != null) _reverseGeocode(_pinPosition);
  }

  bool _isWithinCity(LatLng point) =>
      _distance.as(LengthUnit.Kilometer, _cityCenter, point) <= widget.radiusKm;

  /// Si el usuario paneó el mapa fuera del radio permitido, revierte el pin
  /// a la última posición válida y avisa (con throttle para no spamear el
  /// SnackBar en cada pixel de un drag largo).
  void _handlePositionChanged(LatLng newCenter, double currentZoom) {
    if (_isWithinCity(newCenter)) {
      setState(() => _pinPosition = newCenter);
      return;
    }
    final now = DateTime.now();
    if (_lastOutOfBoundsWarning == null ||
        now.difference(_lastOutOfBoundsWarning!) > const Duration(seconds: 2)) {
      _lastOutOfBoundsWarning = now;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No podés marcar una ubicación fuera de ${widget.cityName}'),
        duration: const Duration(seconds: 2),
      ));
    }
    // Revertir el mapa a la última posición válida.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(_pinPosition, currentZoom);
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _locateMe() async {
    setState(() => _locating = true);
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso de ubicación denegado')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      final ll = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      if (!_isWithinCity(ll)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Tu ubicación actual está fuera de ${widget.cityName} — marcá manualmente dentro de la ciudad'),
        ));
        return;
      }
      setState(() => _pinPosition = ll);
      _mapController.move(ll, 17);
      _reverseGeocode(ll);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo obtener la ubicación')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    setState(() {
      _reversing = true;
      _reverseAddress = null;
      _reverseStreet = null;
    });
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json'
        '&lat=${pos.latitude}&lon=${pos.longitude}&zoom=18&addressdetails=1',
      );
      final res = await http
          .get(url, headers: {'Accept-Language': 'es', 'User-Agent': 'GardenApp/1.0'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final display = data['display_name'] as String?;
        final address = data['address'] as Map<String, dynamic>?;
        final road = address?['road'] as String? ?? address?['pedestrian'] as String?;
        final houseNumber = address?['house_number'] as String?;
        final street = road == null
            ? null
            : (houseNumber != null ? '$road $houseNumber' : road);
        if (mounted && display != null) {
          setState(() {
            _reverseAddress = display;
            _reverseStreet = street;
          });
        }
      }
    } catch (_) {
      // No bloquear el flujo si Nominatim falla
    } finally {
      if (mounted) setState(() => _reversing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.6,
      maxChildSize: 1.0,
      builder: (_, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Scaffold(
          backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          body: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confirma tu ubicación',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16a34a).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF16a34a).withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFF16a34a), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.purpose,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF16a34a),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Map
              Expanded(
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _pinPosition,
                        initialZoom: 16,
                        onPositionChanged: (pos, hasGesture) {
                          if (hasGesture) {
                            _handlePositionChanged(pos.center, pos.zoom);
                          }
                        },
                        onMapEvent: (event) {
                          if (event is MapEventMoveEnd) {
                            _reverseGeocode(_pinPosition);
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: isDark
                              ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                              : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                          subdomains: const ['a', 'b', 'c', 'd'],
                          userAgentPackageName: 'com.garden.bolivia',
                        ),
                      ],
                    ),

                    // Pin centrado en el mapa
                    const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_pin, color: Color(0xFF16a34a), size: 48),
                          SizedBox(height: 24),
                        ],
                      ),
                    ),

                    // Botón "Mi ubicación"
                    Positioned(
                      right: 12,
                      bottom: 16,
                      child: FloatingActionButton.small(
                        heroTag: 'locate_me',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF16a34a),
                        onPressed: _locating ? null : _locateMe,
                        child: _locating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location),
                      ),
                    ),
                  ],
                ),
              ),

              // Dirección detectada + botón confirmar
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_reversing)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Detectando dirección...', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      )
                    else if (_reverseAddress != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on, size: 16, color: Color(0xFF16a34a)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _reverseAddress!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                    Text(
                      'Mueve el mapa para ajustar el pin a tu ubicación exacta',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Confirmar ubicación'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16a34a),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(
                          AddressMapResult(
                            lat: _pinPosition.latitude,
                            lng: _pinPosition.longitude,
                            formattedAddress: _reverseStreet,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

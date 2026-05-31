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

  const AddressMapResult({required this.lat, required this.lng});
}

/// Modal fullscreen con mapa de OpenStreetMap y pin arrastrable.
/// Centrado en Santa Cruz de la Sierra por defecto.
/// Devuelve [AddressMapResult] con lat/lng confirmados, o null si cancela.
Future<AddressMapResult?> showAddressMapPicker(
  BuildContext context, {
  double? initialLat,
  double? initialLng,
  String purpose = 'Tu dirección se usa para coordinar el servicio con el cuidador.',
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
    ),
  );
}

class _AddressMapPicker extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String purpose;

  const _AddressMapPicker({
    this.initialLat,
    this.initialLng,
    required this.purpose,
  });

  @override
  State<_AddressMapPicker> createState() => _AddressMapPickerState();
}

class _AddressMapPickerState extends State<_AddressMapPicker> {
  // Santa Cruz de la Sierra, Bolivia
  static const _defaultLat = -17.7863;
  static const _defaultLng = -63.1812;

  late LatLng _pinPosition;
  late MapController _mapController;
  bool _locating = false;
  String? _reverseAddress;
  bool _reversing = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pinPosition = LatLng(
      widget.initialLat ?? _defaultLat,
      widget.initialLng ?? _defaultLng,
    );
    if (widget.initialLat != null) _reverseGeocode(_pinPosition);
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
        if (mounted && display != null) {
          setState(() => _reverseAddress = display);
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
                            setState(() => _pinPosition = pos.center);
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
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.garden.app',
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

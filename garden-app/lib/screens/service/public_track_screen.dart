import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Vista pública de solo lectura para el link de "compartir viaje en vivo"
/// (ver GardenColors/booking_screen: el dueño genera este link desde el
/// seguimiento GPS y se lo manda a un contacto de confianza). Sin login —
/// quien lo abre no tiene cuenta en Garden. El token en la URL es lo único
/// que autoriza ver estos datos (ver deriveShareToken en booking.service.ts
/// del backend); no hay nada más sensible expuesto acá (ni teléfonos ni
/// apellidos).
class PublicTrackScreen extends StatefulWidget {
  final String bookingId;
  final String token;

  const PublicTrackScreen({super.key, required this.bookingId, required this.token});

  @override
  State<PublicTrackScreen> createState() => _PublicTrackScreenState();
}

class _PublicTrackScreenState extends State<PublicTrackScreen> {
  final MapController _mapController = MapController();
  Timer? _pollTimer;
  bool _loading = true;
  bool _notFound = false;
  bool _active = false;
  String? _status;
  String? _petName;
  String? _serviceType;
  String? _caregiverFirstName;
  List<LatLng> _track = [];

  String get _baseUrl =>
      const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/bookings/track/${widget.bookingId}/${widget.token}'),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] != true) {
        setState(() {
          _notFound = true;
          _loading = false;
        });
        return;
      }
      final d = data['data'] as Map<String, dynamic>;
      final active = d['active'] == true;
      final rawTrack = (d['track'] as List?) ?? [];
      final pts = rawTrack
          .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
          .toList();
      setState(() {
        _active = active;
        _status = d['status'] as String?;
        _petName = d['petName'] as String?;
        _serviceType = d['serviceType'] as String?;
        _caregiverFirstName = d['caregiverFirstName'] as String?;
        _track = pts;
        _loading = false;
      });
      if (pts.isNotEmpty) {
        try {
          _mapController.move(pts.last, 15);
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: surface,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🐾', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text('Garden — seguimiento en vivo',
                    style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          body: _loading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : (_notFound || (!_active && _track.isEmpty))
                  ? _buildInactive(textColor, subtextColor)
                  : _active
                      ? _buildActive(textColor, subtextColor, surface)
                      : _buildInactive(textColor, subtextColor),
        );
      },
    );
  }

  Widget _buildInactive(Color textColor, Color subtextColor) {
    final finished = _status == 'COMPLETED';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              finished ? Icons.check_circle_outline_rounded : Icons.link_off_rounded,
              size: 44,
              color: subtextColor,
            ),
            const SizedBox(height: 16),
            Text(
              finished
                  ? 'Este servicio ya terminó'
                  : (_notFound ? 'Este link ya no está disponible' : 'El servicio todavía no empezó'),
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'El seguimiento en vivo solo está disponible mientras el paseo está en curso.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtextColor, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActive(Color textColor, Color subtextColor, Color surface) {
    final serviceLabel = _serviceType == 'PASEO'
        ? 'Paseo'
        : _serviceType == 'HOSPEDAJE'
            ? 'Hospedaje'
            : 'Servicio';
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          color: surface,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: GardenColors.lime, shape: BoxShape.circle),
                child: const Icon(Icons.pets_rounded, color: GardenColors.primaryDark, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$serviceLabel de ${_petName ?? 'la mascota'}',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 14.5)),
                    if (_caregiverFirstName != null)
                      Text('Con ${_caregiverFirstName!} · en curso',
                          style: TextStyle(color: subtextColor, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: GardenColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 7, color: GardenColors.success),
                  SizedBox(width: 5),
                  Text('En vivo',
                      style: TextStyle(color: GardenColors.success, fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
          ),
        ),
        Expanded(
          child: _track.isEmpty
              ? Center(
                  child: Text('Esperando la primera ubicación…',
                      style: TextStyle(color: subtextColor, fontSize: 13)),
                )
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _track.last,
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.garden.bolivia',
                    ),
                    if (_track.length > 1)
                      PolylineLayer(polylines: [
                        Polyline(points: _track, strokeWidth: 4, color: GardenColors.primary),
                      ]),
                    MarkerLayer(markers: [
                      Marker(
                        point: _track.last,
                        width: 36,
                        height: 36,
                        child: const Icon(Icons.pets_rounded, color: GardenColors.accent, size: 32),
                      ),
                    ]),
                  ],
                ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: surface,
          child: Text(
            'Link de solo lectura compartido por el dueño de la mascota — deja de mostrar ubicación en cuanto el servicio termina.',
            textAlign: TextAlign.center,
            style: TextStyle(color: subtextColor, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

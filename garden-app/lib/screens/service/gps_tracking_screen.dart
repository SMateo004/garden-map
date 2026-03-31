import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../theme/garden_theme.dart';
import 'gps_location.dart';

class GpsTrackingScreen extends StatefulWidget {
  final String bookingId;
  final String role; // 'CAREGIVER' | 'CLIENT'
  final String petName;
  final String token;
  final String? petPhoto;

  const GpsTrackingScreen({
    super.key,
    required this.bookingId,
    required this.role,
    required this.petName,
    required this.token,
    this.petPhoto,
  });

  @override
  State<GpsTrackingScreen> createState() => _GpsTrackingScreenState();
}

class _GpsTrackingScreenState extends State<GpsTrackingScreen> {
  final MapController _mapController = MapController();
  final List<LatLng> _track = [];
  LatLng? _currentPos;
  StreamSubscription<Map<String, double>>? _gpsSub;
  IO.Socket? _socket;
  bool _isSharing = true;
  bool _gpsBlocked = false;
  DateTime? _lastSent;
  double _distanceMeters = 0;

  String get _baseUrl =>
      const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');
  bool get _isCaregiver => widget.role == 'CAREGIVER';

  @override
  void initState() {
    super.initState();
    _loadTrackHistory();
    if (_isCaregiver) {
      _startGps();
    } else {
      _connectSocket();
    }
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  // ── Carga el historial de puntos GPS ─────────────────────────────────────
  Future<void> _loadTrackHistory() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/track'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final raw = data['data'] as List? ?? [];
        final pts = raw
            .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
            .toList();
        if (pts.isNotEmpty && mounted) {
          setState(() {
            _track.addAll(pts);
            _currentPos = pts.last;
            _distanceMeters = _haversineTotal(_track);
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try { _mapController.move(pts.last, 16); } catch (_) {}
          });
        }
      }
    } catch (e) {
      debugPrint('GPS: historial error: $e');
    }
  }

  // ── CUIDADOR: inicia stream GPS del navegador ─────────────────────────────
  void _startGps() {
    if (!kIsWeb) {
      setState(() => _gpsBlocked = true);
      return;
    }
    _gpsSub = watchGpsPosition().listen(
      (pos) => _onLocation(pos['lat']!, pos['lng']!, pos['accuracy'] ?? 0),
      onError: (_) { if (mounted) setState(() => _gpsBlocked = true); },
    );
  }

  Future<void> _onLocation(double lat, double lng, double accuracy) async {
    if (!_isSharing || !mounted) return;
    final pt = LatLng(lat, lng);
    setState(() {
      _track.add(pt);
      _currentPos = pt;
      _distanceMeters = _haversineTotal(_track);
    });
    try { _mapController.move(pt, _mapController.camera.zoom); } catch (_) {}

    final now = DateTime.now();
    if (_lastSent == null || now.difference(_lastSent!).inSeconds >= 10) {
      _lastSent = now;
      try {
        await http.post(
          Uri.parse('$_baseUrl/bookings/${widget.bookingId}/track'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'lat': lat, 'lng': lng, 'accuracy': accuracy}),
        );
      } catch (e) {
        debugPrint('GPS: envío error: $e');
      }
    }
  }

  // ── CLIENTE: recibe GPS via Socket.io ────────────────────────────────────
  void _connectSocket() {
    try {
      final wsUrl = _baseUrl.replaceAll('/api', '');
      _socket = IO.io(wsUrl, <String, dynamic>{
        'transports': ['polling', 'websocket'],
        'autoConnect': false,
        'auth': {'token': widget.token},
      });
      _socket!.onConnect((_) => _socket!.emit('join_booking', widget.bookingId));
      _socket!.on('gps_update', (raw) {
        if (!mounted) return;
        try {
          final map = (raw is Map) ? raw : <String, dynamic>{};
          final lat = (map['lat'] as num).toDouble();
          final lng = (map['lng'] as num).toDouble();
          final pt = LatLng(lat, lng);
          setState(() {
            _track.add(pt);
            _currentPos = pt;
            _distanceMeters = _haversineTotal(_track);
          });
          try { _mapController.move(pt, _mapController.camera.zoom); } catch (_) {}
        } catch (e) {
          debugPrint('GPS: socket parse error: $e');
        }
      });
      _socket!.connect();
    } catch (e) {
      debugPrint('GPS: socket error: $e');
    }
  }

  // ── Haversine ─────────────────────────────────────────────────────────────
  double _haversineTotal(List<LatLng> pts) {
    double total = 0;
    for (int i = 1; i < pts.length; i++) {
      const R = 6371000.0;
      final dLat = (pts[i].latitude - pts[i - 1].latitude) * math.pi / 180;
      final dLng = (pts[i].longitude - pts[i - 1].longitude) * math.pi / 180;
      final a = math.pow(math.sin(dLat / 2), 2) +
          math.cos(pts[i - 1].latitude * math.pi / 180) *
              math.cos(pts[i].latitude * math.pi / 180) *
              math.pow(math.sin(dLng / 2), 2);
      final ad = a.toDouble();
      total += R * 2 * math.atan2(math.sqrt(ad), math.sqrt(1 - ad));
    }
    return total;
  }

  String _fmtDist(double m) =>
      m < 1000 ? '${m.toStringAsFixed(0)} m' : '${(m / 1000).toStringAsFixed(2)} km';

  // ── BUILD ─────────────────────────────────────────────────────────────────
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
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        return Scaffold(
          backgroundColor: bg,
          body: Stack(
            children: [
              // ── Mapa (o pantalla de permiso denegado) ──────────────────
              _gpsBlocked
                  ? _buildBlocked(bg, textColor, subtextColor)
                  : _buildMap(isDark),

              // ── Header con gradiente ───────────────────────────────────
              Positioned(
                top: 0, left: 0, right: 0,
                child: _buildHeader(context),
              ),

              // ── Bottom card ────────────────────────────────────────────
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: _buildBottomCard(
                  context, surface, textColor, subtextColor, borderColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final headerColor = _isCaregiver ? const Color(0xFF0F7A3E) : GardenColors.secondary;
    final isActive = _isCaregiver ? _isSharing : true;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16, MediaQuery.of(context).padding.top + 12, 16, 32,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            headerColor.withValues(alpha: 0.94),
            headerColor.withValues(alpha: 0),
          ],
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36, height: 36,
              decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isCaregiver ? '📍 Compartiendo GPS' : '🐾 Siguiendo a ${widget.petName}',
                  style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                ),
                if (!_isCaregiver)
                  const Text('en tiempo real',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          // Badge activo / pausado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isActive ? Colors.white24 : Colors.black26,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulsingDotSmall(active: isActive),
                const SizedBox(width: 5),
                Text(
                  _isCaregiver ? (_isSharing ? 'GPS activo' : 'Pausado') : 'GPS activo',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCard(
    BuildContext context,
    Color surface,
    Color textColor,
    Color subtextColor,
    Color borderColor,
  ) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20, 14, 20, MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: borderColor)),
        boxShadow: GardenShadows.elevated,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: subtextColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatChip(
                icon: Icons.route_rounded,
                label: 'Recorrido',
                value: _fmtDist(_distanceMeters),
                color: GardenColors.primary,
                textColor: textColor,
                subtextColor: subtextColor,
              ),
              _StatChip(
                icon: Icons.location_on_rounded,
                label: 'Puntos GPS',
                value: '${_track.length}',
                color: GardenColors.secondary,
                textColor: textColor,
                subtextColor: subtextColor,
              ),
              _StatChip(
                icon: Icons.pets_rounded,
                label: widget.petName,
                value: _isCaregiver ? 'Cuidando' : 'En paseo',
                color: GardenColors.success,
                textColor: textColor,
                subtextColor: subtextColor,
              ),
            ],
          ),

          // Controles del cuidador
          if (_isCaregiver && !_gpsBlocked) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(
                  _isSharing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white, size: 18,
                ),
                label: Text(
                  _isSharing ? 'Pausar GPS' : 'Reanudar GPS',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                onPressed: () => setState(() => _isSharing = !_isSharing),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isSharing ? GardenColors.warning : GardenColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],

          // Nota del cliente
          if (!_isCaregiver) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 13, color: GardenColors.secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'El mapa se actualiza automáticamente cuando el cuidador se mueve.',
                    style: TextStyle(color: subtextColor, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMap(bool isDark) {
    const defaultCenter = LatLng(-17.7863, -63.1812); // Santa Cruz, Bolivia
    final center = _currentPos ?? defaultCenter;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: _track.isEmpty ? 13 : 16,
        minZoom: 10,
        maxZoom: 19,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.garden.app',
          tileBuilder: isDark ? _darkTile : null,
        ),

        // Polilínea del trayecto
        if (_track.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _track,
                strokeWidth: 4.5,
                color: GardenColors.secondary,
              ),
            ],
          ),

        // Punto de inicio (verde)
        if (_track.isNotEmpty)
          MarkerLayer(
            markers: [
              Marker(
                point: _track.first,
                width: 22, height: 22,
                child: Container(
                  decoration: const BoxDecoration(
                    color: GardenColors.success, shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                ),
              ),
            ],
          ),

        // Posición actual: avatar con foto/inicial de la mascota
        if (_currentPos != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _currentPos!,
                width: 52, height: 64,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: GardenColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: GardenColors.primary.withValues(alpha: 0.45),
                            blurRadius: 8, spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: widget.petPhoto != null && widget.petPhoto!.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                widget.petPhoto!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _petInitial(),
                              ),
                            )
                          : _petInitial(),
                    ),
                    // Triángulo apuntando hacia abajo
                    const CustomPaint(
                      size: Size(12, 7),
                      painter: _DownArrow(GardenColors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),

        const RichAttributionWidget(
          attributions: [TextSourceAttribution('© OpenStreetMap')],
        ),
      ],
    );
  }

  Widget _petInitial() => Center(
        child: Text(
          widget.petName.isNotEmpty ? widget.petName[0].toUpperCase() : '🐾',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
        ),
      );

  Widget _darkTile(BuildContext context, Widget child, TileImage tile) =>
      ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -0.2126, -0.7152, -0.0722, 0, 255,
          -0.2126, -0.7152, -0.0722, 0, 255,
          -0.2126, -0.7152, -0.0722, 0, 255,
          0, 0, 0, 1, 0,
        ]),
        child: child,
      );

  Widget _buildBlocked(Color bg, Color textColor, Color subtextColor) => Container(
        color: bg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('📍', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 24),
                Text(
                  'Permiso de ubicación requerido',
                  style: TextStyle(
                      color: textColor, fontSize: 20, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _isCaregiver
                      ? 'Necesitamos tu ubicación para compartirla con el dueño. Permite el acceso al GPS en tu navegador.'
                      : 'No se pudo obtener la ubicación del cuidador.',
                  style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: GardenColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: GardenColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: GardenColors.warning, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'El GPS en tiempo real está disponible en la versión web de GARDEN.',
                            style: TextStyle(
                                color: GardenColors.warning, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _PulsingDotSmall extends StatefulWidget {
  final bool active;
  const _PulsingDotSmall({this.active = true});
  @override
  _PulsingDotSmallState createState() => _PulsingDotSmallState();
}

class _PulsingDotSmallState extends State<_PulsingDotSmall>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Container(
          width: 7, height: 7,
          decoration: const BoxDecoration(color: Colors.white54, shape: BoxShape.circle));
    }
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
          width: 7, height: 7,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color textColor;
  final Color subtextColor;
  const _StatChip({
    required this.icon, required this.label, required this.value,
    required this.color, required this.textColor, required this.subtextColor,
  });
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.w800, fontSize: 14)),
          Text(label, style: TextStyle(color: subtextColor, fontSize: 11)),
        ],
      );
}

class _DownArrow extends CustomPainter {
  final Color color;
  const _DownArrow(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_empty_state.dart';
import '../../design/brote.dart';
import '../../design/garden_icons.dart';
import 'my_data_screen.dart';

/// Veterinarias cercanas a la dirección guardada del usuario (Mi Perfil).
/// Pensada para casos de emergencia: mismo dato que usa el cuidador durante
/// un paseo, pero acá filtrado por la ubicación real del dueño de mascota
/// (su ciudad/zona), no la del cuidador en movimiento.
///
/// La más cercana va destacada con "Llamar" y "Cómo llegar"; el resto en una
/// lista con los mismos atajos.
class NearbyVetsScreen extends StatefulWidget {
  const NearbyVetsScreen({super.key});

  @override
  State<NearbyVetsScreen> createState() => _NearbyVetsScreenState();
}

class _NearbyVetsScreenState extends State<NearbyVetsScreen> {
  List<Map<String, dynamic>> _vets = [];
  bool _isLoading = true;
  String? _errorMessage;

  /// Sin dirección guardada (código NO_ADDRESS del backend): antes se veía
  /// como "Error de conexión".
  bool _noAddress = false;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noAddress = false;
    });
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/vets/nearest-for-me'),
        headers: {'Authorization': 'Bearer ${AuthState.token}'},
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        setState(() => _vets = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      } else if (data['error']?['code'] == 'NO_ADDRESS') {
        setState(() => _noAddress = true);
      } else {
        setState(() => _errorMessage = data['error']?['message'] as String? ?? 'No se pudo cargar');
      }
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Sin conexión');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    final ok = await launchUrl(Uri(scheme: 'tel', path: phone.trim()));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo abrir el teléfono. El número es $phone')));
    }
  }

  Future<void> _directions(Map<String, dynamic> vet) async {
    final lat = (vet['lat'] as num?)?.toDouble();
    final lng = (vet['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    HapticFeedback.selectionClick();
    await launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
      mode: LaunchMode.externalApplication,
    );
  }

  /// "850 m" / "1,2 km".
  static String _distance(num? km) {
    if (km == null) return '';
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    Widget body;
    if (_isLoading) {
      body = ListView(padding: const EdgeInsets.all(16), children: [
        const GardenSkeleton(width: double.infinity, height: 150, radius: GardenRadius.xl),
        const SizedBox(height: 14),
        for (var i = 0; i < 3; i++) ...[
          const GardenSkeleton(width: double.infinity, height: 72, radius: GardenRadius.lg),
          const SizedBox(height: 10),
        ],
      ]);
    } else if (_noAddress) {
      body = ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 40),
        GardenEmptyState(
          type: GardenEmptyType.generic,
          brote: BrotePose.buscando,
          title: 'Necesitamos tu dirección',
          subtitle: 'Con tu dirección te mostramos las veterinarias más cerca de tu casa.',
          ctaLabel: 'Completar mi dirección',
          onCta: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyDataScreen()));
            if (mounted) _load();
          },
        ),
      ]);
    } else if (_errorMessage != null) {
      body = ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 40),
        GardenEmptyState(
          type: GardenEmptyType.generic,
          brote: BrotePose.oops,
          title: 'No pudimos cargar las veterinarias',
          subtitle: '$_errorMessage. Revisa tu conexión e inténtalo de nuevo.',
          ctaLabel: 'Reintentar',
          onCta: _load,
        ),
      ]);
    } else if (_vets.isEmpty) {
      body = ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 40),
        GardenEmptyState(
          type: GardenEmptyType.generic,
          title: 'Sin veterinarias cercanas',
          subtitle: 'Todavía no hay veterinarias cargadas en tu zona. Prueba de nuevo más tarde.',
          ctaLabel: 'Actualizar',
          onCta: _load,
        ),
      ]);
    } else {
      final nearest = _vets.first;
      final rest = _vets.skip(1).toList();
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Aviso sereno: en una emergencia, llamar antes de ir.
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const GardenIcon(GIcon.info, size: GIconSize.sm, color: GardenColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Si es una emergencia, llama primero: te dicen si pueden atenderte ya.',
                      style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                // ── La más cercana ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(GardenRadius.xl),
                    boxShadow: GardenShadows.card,
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: GardenColors.error.withValues(alpha: isDark ? 0.18 : 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const GardenIcon(GIcon.veterinaria, size: GIconSize.lg, state: GIconState.active, color: GardenColors.error),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('LA MÁS CERCANA · ${_distance(nearest['distanceKm'] as num?)}',
                              style: const TextStyle(
                                  color: GardenColors.error, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                          const SizedBox(height: 3),
                          Text(nearest['name'] as String? ?? 'Veterinaria',
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 17, height: 1.2)),
                          if ((nearest['address'] as String?)?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 2),
                            Text(nearest['address'] as String, style: TextStyle(color: subtextColor, fontSize: 12.5)),
                          ],
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: GardenButton(
                          label: 'Llamar',
                          gIcon: GIcon.telefono,
                          height: 48,
                          onPressed: () => _call(nearest['phone'] as String?),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GardenButton(
                          label: 'Cómo llegar',
                          gIcon: GIcon.mapa,
                          outline: true,
                          height: 48,
                          onPressed: () => _directions(nearest),
                        ),
                      ),
                    ]),
                  ]),
                ),
                if (rest.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text('OTRAS CERCA',
                        style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9)),
                  ),
                  for (final vet in rest) _VetRow(
                    vet: vet,
                    distance: _distance(vet['distanceKm'] as num?),
                    onCall: () => _call(vet['phone'] as String?),
                    onDirections: () => _directions(vet),
                  ),
                ],
              ]),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Veterinarias cercanas', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: GardenIcon(GIcon.atras, size: GIconSize.md, color: textColor),
          tooltip: 'Volver',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(color: GardenColors.primary, onRefresh: _load, child: body),
    );
  }
}

class _VetRow extends StatelessWidget {
  final Map<String, dynamic> vet;
  final String distance;
  final VoidCallback onCall;
  final VoidCallback onDirections;
  const _VetRow({required this.vet, required this.distance, required this.onCall, required this.onDirections});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final ink = isDark ? GardenColors.primaryLight : GardenColors.primary;

    Widget action(GIcon icon, String label, VoidCallback onTap) => IconButton(
          tooltip: label,
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor: ink.withValues(alpha: isDark ? 0.16 : 0.08),
            fixedSize: const Size(42, 42),
          ),
          icon: GardenIcon(icon, size: GIconSize.sm, color: ink),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(vet['name'] as String? ?? 'Veterinaria',
                style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(
              [
                if (distance.isNotEmpty) distance,
                if ((vet['address'] as String?)?.isNotEmpty ?? false) vet['address'] as String,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: sub, fontSize: 12.5),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        action(GIcon.mapa, 'Cómo llegar', onDirections),
        const SizedBox(width: 6),
        action(GIcon.telefono, 'Llamar', onCall),
      ]),
    );
  }
}

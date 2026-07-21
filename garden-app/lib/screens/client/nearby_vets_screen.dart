import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_empty_state.dart';

/// Veterinarias cercanas a la dirección guardada del usuario (Mi Perfil).
/// Pensada para casos de emergencia: mismo dato que usa el cuidador durante
/// un paseo, pero acá filtrado por la ubicación real del dueño de mascota
/// (su ciudad/zona), no la del cuidador en movimiento.
class NearbyVetsScreen extends StatefulWidget {
  const NearbyVetsScreen({super.key});

  @override
  State<NearbyVetsScreen> createState() => _NearbyVetsScreenState();
}

class _NearbyVetsScreenState extends State<NearbyVetsScreen> {
  List<Map<String, dynamic>> _vets = [];
  bool _isLoading = true;
  String? _errorMessage;

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
    });
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/vets/nearest-for-me'),
        headers: {'Authorization': 'Bearer ${AuthState.token}'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _vets = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      } else {
        setState(() => _errorMessage = data['error']?['message'] as String? ?? 'No se pudo cargar');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error de conexión');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  /// Skeleton que calca el layout de la tarjeta de veterinaria mientras carga.
  Widget _buildVetCardSkeleton(Color surface, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          const GardenSkeleton(width: 48, height: 48, radius: 12),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GardenSkeleton(width: 150, height: 14),
                const SizedBox(height: 6),
                const GardenSkeleton(width: 110, height: 11),
                const SizedBox(height: 6),
                const GardenSkeleton(width: 90, height: 11),
              ],
            ),
          ),
          const SizedBox(width: 14),
          const GardenSkeleton(width: 40, height: 40, radius: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: Text('Veterinarias cercanas', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, __) => _buildVetCardSkeleton(surface, borderColor),
            )
          : RefreshIndicator(
              color: GardenColors.primary,
              onRefresh: _load,
              child: _errorMessage != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 480,
                          child: GardenEmptyState(
                            type: GardenEmptyType.generic,
                            title: 'No pudimos encontrar veterinarias',
                            subtitle: '$_errorMessage — revisá tu conexión y volvé a intentar.',
                            ctaLabel: 'Reintentar',
                            onCta: _load,
                          ),
                        ),
                      ],
                    )
                  : _vets.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: 480,
                              child: GardenEmptyState(
                                type: GardenEmptyType.generic,
                                title: 'Sin veterinarias cercanas',
                                subtitle: 'Todavía no hay veterinarias cargadas en tu zona. Probá de nuevo más tarde.',
                                ctaLabel: 'Actualizar',
                                onCta: _load,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _vets.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final vet = _vets[i];
                            final distanceKm = (vet['distanceKm'] as num?)?.toDouble() ?? 0;
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48, height: 48,
                                    decoration: BoxDecoration(
                                      color: GardenColors.error.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.local_hospital_rounded, color: GardenColors.error, size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(vet['name'] as String, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                                        if ((vet['address'] as String?)?.isNotEmpty ?? false) ...[
                                          const SizedBox(height: 2),
                                          Text(vet['address'] as String, style: TextStyle(color: subtextColor, fontSize: 12.5)),
                                        ],
                                        const SizedBox(height: 4),
                                        Text('${distanceKm.toStringAsFixed(1)} km de tu dirección',
                                            style: const TextStyle(color: GardenColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                  GardenPressable(
                                    pressedScale: 0.85,
                                    onTap: () {
                                      HapticFeedback.mediumImpact();
                                      _call(vet['phone'] as String);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: GardenColors.success.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.phone_rounded, color: GardenColors.success, size: 20),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
    );
  }
}

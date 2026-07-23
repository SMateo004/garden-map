import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_empty_state.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Panel admin: solicitudes de eliminación de cuenta de cuidador.
///
/// Un cuidador NO puede eliminar su cuenta directamente (ver
/// auth.controller.ts deleteAccount) — solo puede solicitarlo. Esta pantalla
/// es donde un admin aprueba (ejecuta la eliminación real) o descarta la
/// solicitud (la cuenta sigue activa). Medida de seguridad ante posible
/// robo/retención indebida de la mascota: se muestra el último punto de
/// ubicación conocido del cuidador al momento de pedir la baja, si lo mandó.
class AdminCaregiverDeletionRequestsScreen extends StatefulWidget {
  final String adminToken;
  const AdminCaregiverDeletionRequestsScreen({super.key, required this.adminToken});

  @override
  State<AdminCaregiverDeletionRequestsScreen> createState() => _AdminCaregiverDeletionRequestsScreenState();
}

class _AdminCaregiverDeletionRequestsScreenState extends State<AdminCaregiverDeletionRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _processingUserId;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  Map<String, String> get _headers => {'Authorization': 'Bearer ${widget.adminToken}'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse('$_baseUrl/admin/caregiver-deletion-requests'), headers: _headers);
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() => _requests = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (e) {
      debugPrint('AdminCaregiverDeletionRequests load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approve(String userId) async {
    setState(() => _processingUserId = userId);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/admin/caregiver-deletion-requests/$userId/approve'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cuenta eliminada'), backgroundColor: GardenColors.success),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?['message'] ?? 'Error al eliminar'), backgroundColor: GardenColors.error),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión'), backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _processingUserId = null);
    }
  }

  Future<void> _dismiss(String userId) async {
    setState(() => _processingUserId = userId);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/admin/caregiver-deletion-requests/$userId/dismiss'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud descartada — la cuenta sigue activa'), backgroundColor: GardenColors.warning),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?['message'] ?? 'Error'), backgroundColor: GardenColors.error),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión'), backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _processingUserId = null);
    }
  }

  Future<void> _confirmApprove(Map<String, dynamic> req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar esta cuenta?'),
        content: Text(
          'Esto anonimiza permanentemente la cuenta de ${req['name']} y transfiere su saldo a Garden. No se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _approve(req['userId'] as String);
  }

  Future<void> _openInMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: GardenColors.warning.withValues(alpha: 0.1),
            child: Text(
              'Un cuidador no puede eliminar su cuenta directamente — estas solicitudes esperan tu aprobación. La cuenta sigue activa mientras tanto.',
              style: TextStyle(color: textColor, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
                : _requests.isEmpty
                    ? const GardenEmptyState(
                        type: GardenEmptyType.bookings,
                        title: 'Sin solicitudes pendientes',
                        subtitle: 'Ningún cuidador pidió eliminar su cuenta.',
                        compact: true,
                      )
                    : RefreshIndicator(
                        color: GardenColors.primary,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _requests.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final r = _requests[i];
                            final userId = r['userId'] as String;
                            final isProcessing = _processingUserId == userId;
                            final lat = (r['lastKnownLat'] as num?)?.toDouble();
                            final lng = (r['lastKnownLng'] as num?)?.toDouble();

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(GardenRadius.lg),
                                border: Border.all(color: GardenColors.warning.withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.person_remove_outlined, color: GardenColors.warning, size: 22),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(r['name'] as String? ?? '—',
                                                style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                                            Text(r['email'] as String? ?? '—',
                                                style: TextStyle(color: subtextColor, fontSize: 12)),
                                            Text(r['phone'] as String? ?? '—',
                                                style: TextStyle(color: subtextColor, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Solicitado: ${r['requestedAt'] ?? '—'}', style: TextStyle(color: subtextColor, fontSize: 11.5)),
                                  if (lat != null && lng != null) ...[
                                    const SizedBox(height: 6),
                                    InkWell(
                                      onTap: () => _openInMaps(lat, lng),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.location_on_outlined, color: GardenColors.primary, size: 16),
                                          const SizedBox(width: 4),
                                          Text('Ver última ubicación conocida', style: TextStyle(color: GardenColors.primary, fontSize: 12.5, decoration: TextDecoration.underline)),
                                        ],
                                      ),
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 6),
                                    Text('Sin ubicación disponible', style: TextStyle(color: subtextColor, fontSize: 11.5, fontStyle: FontStyle.italic)),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: isProcessing ? null : () => _dismiss(userId),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(color: borderColor),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: const Text('Descartar'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: isProcessing ? null : () => _confirmApprove(r),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: GardenColors.error,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: isProcessing
                                              ? const GardenLoadingIndicator(size: 18, color: Colors.white)
                                              : const Text('Eliminar cuenta'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

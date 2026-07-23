import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../widgets/garden_empty_state.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Panel admin: documentos de antecedentes penales (FELCC/REJAP) marcados
/// por el agente de IA (documento-antecedentes.agent.ts) — el agente NUNCA
/// suspende solo, solo marca. Acá un admin abre el documento, lee el
/// veredicto del agente, y decide si suspende la cuenta (cancela y
/// reembolsa reservas activas) o descarta la alerta.
class AdminAntecedentesFlaggedScreen extends StatefulWidget {
  final String adminToken;
  const AdminAntecedentesFlaggedScreen({super.key, required this.adminToken});

  @override
  State<AdminAntecedentesFlaggedScreen> createState() => _AdminAntecedentesFlaggedScreenState();
}

class _AdminAntecedentesFlaggedScreenState extends State<AdminAntecedentesFlaggedScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String? _processingId;

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
      final res = await http.get(Uri.parse('$_baseUrl/admin/antecedentes-flagged'), headers: _headers);
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() => _items = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (e) {
      debugPrint('AdminAntecedentesFlagged load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openDocument(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _dismiss(String profileId) async {
    setState(() => _processingId = profileId);
    try {
      final res = await http.post(Uri.parse('$_baseUrl/admin/antecedentes-flagged/$profileId/dismiss'), headers: _headers);
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alerta descartada — la cuenta sigue activa'), backgroundColor: GardenColors.warning),
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
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _suspend(String profileId) async {
    setState(() => _processingId = profileId);
    try {
      final res = await http.post(Uri.parse('$_baseUrl/admin/antecedentes-flagged/$profileId/suspend'), headers: _headers);
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cuenta suspendida — reservas activas canceladas con reembolso'), backgroundColor: GardenColors.success),
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
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _confirmSuspend(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Suspender esta cuenta?'),
        content: Text(
          'Esto suspende de inmediato a ${item['name']}, oculta su perfil del marketplace, y cancela con reembolso completo cualquier reserva activa que tenga.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, suspender'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _suspend(item['profileId'] as String);
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
            color: GardenColors.error.withValues(alpha: 0.08),
            child: Text(
              'El agente de IA solo marca documentos dudosos o con antecedentes explícitos — nunca suspende solo. Revisá el documento antes de decidir.',
              style: TextStyle(color: textColor, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
                : _items.isEmpty
                    ? const GardenEmptyState(
                        type: GardenEmptyType.bookings,
                        title: 'Sin alertas pendientes',
                        subtitle: 'Ningún documento de antecedentes está marcado para revisión.',
                        compact: true,
                      )
                    : RefreshIndicator(
                        color: GardenColors.primary,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            final profileId = item['profileId'] as String;
                            final isProcessing = _processingId == profileId;
                            final verdict = item['agentVerdict'] as Map?;
                            final razon = verdict?['razon'] as String?;
                            final antecedentesDetectados = verdict?['antecedentesDetectados'] == true;
                            final documentoLicito = verdict?['documentoLicito'];
                            final docUrl = item['antecedentesUrl'] as String?;

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(GardenRadius.lg),
                                border: Border.all(color: GardenColors.error.withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.gavel_rounded, color: GardenColors.error, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item['name'] as String? ?? '—',
                                                style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                                            Text(item['email'] as String? ?? '—', style: TextStyle(color: subtextColor, fontSize: 12)),
                                            Text(item['phone'] as String? ?? '—', style: TextStyle(color: subtextColor, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Subido: ${item['submittedAt'] ?? '—'}', style: TextStyle(color: subtextColor, fontSize: 11.5)),
                                  if (docUrl != null) ...[
                                    const SizedBox(height: 6),
                                    InkWell(
                                      onTap: () => _openDocument(docUrl),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.description_outlined, color: GardenColors.primary, size: 16),
                                          const SizedBox(width: 4),
                                          Text('Ver documento subido', style: TextStyle(color: GardenColors.primary, fontSize: 12.5, decoration: TextDecoration.underline)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (razon != null) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: (isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'VEREDICTO DEL AGENTE'
                                            '${documentoLicito == false ? ' — DOCUMENTO DUDOSO' : ''}'
                                            '${antecedentesDetectados ? ' — ANTECEDENTES DETECTADOS' : ''}',
                                            style: TextStyle(color: GardenColors.error, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(razon, style: TextStyle(color: textColor, fontSize: 12.5)),
                                        ],
                                      ),
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 10),
                                    Text('Fallo técnico al verificar — revisar el documento manualmente.', style: TextStyle(color: subtextColor, fontSize: 11.5, fontStyle: FontStyle.italic)),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: isProcessing ? null : () => _dismiss(profileId),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(color: borderColor),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: const Text('Descartar alerta'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: isProcessing ? null : () => _confirmSuspend(item),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: GardenColors.error,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: isProcessing
                                              ? const GardenLoadingIndicator(size: 18, color: Colors.white)
                                              : const Text('Suspender cuenta'),
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

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../widgets/garden_empty_state.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Panel admin: NIT de empresas en revisión. A diferencia de antecedentes,
/// acá NO hay auto-aprobación ni acción de "suspender" — el agente de IA
/// (nit-verification.agent.ts) solo da contexto, el admin siempre aprueba o
/// rechaza a mano. Rechazar no es punitivo: solo pide resubir el documento.
class AdminNitVerificationsScreen extends StatefulWidget {
  final String adminToken;
  const AdminNitVerificationsScreen({super.key, required this.adminToken});

  @override
  State<AdminNitVerificationsScreen> createState() => _AdminNitVerificationsScreenState();
}

class _AdminNitVerificationsScreenState extends State<AdminNitVerificationsScreen> {
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
      final res = await http.get(Uri.parse('$_baseUrl/admin/nit-verifications'), headers: _headers);
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() => _items = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (e) {
      debugPrint('AdminNitVerifications load error: $e');
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

  Future<void> _approve(String profileId) async {
    setState(() => _processingId = profileId);
    try {
      final res = await http.post(Uri.parse('$_baseUrl/admin/nit-verifications/$profileId/approve'), headers: _headers);
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NIT verificado'), backgroundColor: GardenColors.success),
        );
        await _load();
      } else {
        GardenErrorDialog.show(context, data['error']?['message'] ?? 'Error');
      }
    } catch (_) {
      if (mounted) GardenErrorDialog.show(context, 'Error de conexión');
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _reject(String profileId, String reason) async {
    setState(() => _processingId = profileId);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/admin/nit-verifications/$profileId/reject'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'reason': reason}),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Documento rechazado — se le pidió a la empresa que resuba uno nuevo'), backgroundColor: GardenColors.warning),
        );
        await _load();
      } else {
        GardenErrorDialog.show(context, data['error']?['message'] ?? 'Error');
      }
    } catch (_) {
      if (mounted) GardenErrorDialog.show(context, 'Error de conexión');
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _confirmReject(Map<String, dynamic> item) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar NIT'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('El documento no es válido para ${item['companyName'] ?? item['name']}. Contale por qué:'),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Ej: la foto está borrosa / no corresponde al NIT'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.warning, foregroundColor: Colors.white),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.pop(ctx, reasonController.text.trim());
            },
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (reason != null && reason.isNotEmpty) await _reject(item['profileId'] as String, reason);
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
            color: GardenColors.primary.withValues(alpha: 0.08),
            child: Text(
              'El agente de IA solo da contexto sobre si el documento se ve auténtico — vos siempre decidís. Revisá el documento antes de aprobar o rechazar.',
              style: TextStyle(color: textColor, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
                : _items.isEmpty
                    ? const GardenEmptyState(
                        type: GardenEmptyType.bookings,
                        title: 'Sin NIT pendientes',
                        subtitle: 'Ninguna empresa tiene un NIT esperando revisión.',
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
                            final documentoLicito = verdict?['documentoLicito'];
                            final docUrl = item['nitDocumentUrl'] as String?;

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(GardenRadius.lg),
                                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.receipt_long_rounded, color: GardenColors.primary, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item['companyName'] as String? ?? item['name'] as String? ?? '—',
                                                style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                                            Text('NIT: ${item['nitNumber'] ?? '—'}', style: TextStyle(color: subtextColor, fontSize: 12)),
                                            Text(item['email'] as String? ?? '—', style: TextStyle(color: subtextColor, fontSize: 12)),
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
                                        color: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'VEREDICTO DEL AGENTE${documentoLicito == false ? ' — DOCUMENTO DUDOSO' : ''}',
                                            style: TextStyle(
                                              color: documentoLicito == false ? GardenColors.error : GardenColors.success,
                                              fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.3,
                                            ),
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
                                          onPressed: isProcessing ? null : () => _confirmReject(item),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: GardenColors.warning),
                                            foregroundColor: GardenColors.warning,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: const Text('Rechazar'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: isProcessing ? null : () => _approve(profileId),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: GardenColors.success,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: isProcessing
                                              ? const GardenLoadingIndicator(size: 18, color: Colors.white)
                                              : const Text('Aprobar'),
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

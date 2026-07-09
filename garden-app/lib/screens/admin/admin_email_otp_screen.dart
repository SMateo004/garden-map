import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_empty_state.dart';

/// Panel admin: verificación de correo manual — normalmente SOLO recibe
/// entradas cuando Resend realmente falla al enviar el correo. Con el
/// switch "Mostrar códigos OTP al admin" (Configuración técnica) activo,
/// ADEMÁS lista todos los códigos pendientes vigentes aunque el envío no
/// haya fallado, mostrando el código REAL que ya se le mandó al usuario
/// (no uno regenerado) — pensado solo para pruebas.
class AdminEmailOtpScreen extends StatefulWidget {
  final String adminToken;
  const AdminEmailOtpScreen({super.key, required this.adminToken});

  @override
  State<AdminEmailOtpScreen> createState() => _AdminEmailOtpScreenState();
}

class _AdminEmailOtpScreenState extends State<AdminEmailOtpScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;

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
      final res = await http.get(Uri.parse('$_baseUrl/admin/email-otp-requests'), headers: _headers);
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() => _requests = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (e) {
      debugPrint('AdminEmailOtp load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openDetail(Map<String, dynamic> req) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmailOtpDetailSheet(
        request: req,
        adminToken: widget.adminToken,
        baseUrl: _baseUrl,
        onVerifiedOrClosed: _load,
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

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: GardenColors.error.withValues(alpha: 0.08),
            child: Text(
              'En rojo: Resend falló realmente al enviar el correo. En azul: código pendiente visible solo por el switch de pruebas (el envío por Resend funcionó normal). Cada entrada desaparece cuando el usuario verifica.',
              style: TextStyle(color: textColor, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
                : _requests.isEmpty
                    ? const GardenEmptyState(
                        type: GardenEmptyType.bookings,
                        title: 'Sin fallos de envío',
                        subtitle: 'Resend está entregando los códigos correctamente.',
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
                            final isRealFailure = r['isRealFailure'] as bool? ?? true;
                            final accentColor = isRealFailure ? GardenColors.error : GardenColors.primary;
                            return Material(
                              color: surface,
                              borderRadius: BorderRadius.circular(GardenRadius.lg),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(GardenRadius.lg),
                                onTap: () => _openDetail(r),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(GardenRadius.lg),
                                    border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isRealFailure ? Icons.mark_email_unread_outlined : Icons.visibility_outlined,
                                        color: accentColor, size: 22,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(r['name'] as String? ?? '—',
                                                style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                                            const SizedBox(height: 2),
                                            Text(r['email'] as String? ?? '—',
                                                style: TextStyle(color: subtextColor, fontSize: 12.5)),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded, color: subtextColor),
                                    ],
                                  ),
                                ),
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

class _EmailOtpDetailSheet extends StatefulWidget {
  final Map<String, dynamic> request;
  final String adminToken;
  final String baseUrl;
  final VoidCallback onVerifiedOrClosed;

  const _EmailOtpDetailSheet({
    required this.request,
    required this.adminToken,
    required this.baseUrl,
    required this.onVerifiedOrClosed,
  });

  @override
  State<_EmailOtpDetailSheet> createState() => _EmailOtpDetailSheetState();
}

class _EmailOtpDetailSheetState extends State<_EmailOtpDetailSheet> {
  bool _generating = false;
  String? _message;
  String? _email;
  bool _reused = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  /// Genera un código fresco (10 min de vigencia desde ahora) cada vez que
  /// se abre el detalle. No reintenta Resend — el admin está aquí porque
  /// Resend ya falló, este código es exclusivamente para envío manual.
  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/admin/email-otp-requests/${widget.request['userId']}/message'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() {
          _message = data['data']['message'] as String;
          _email = data['data']['email'] as String;
          _reused = data['data']['reused'] as bool? ?? false;
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?['message'] ?? 'No se pudo generar el código'), backgroundColor: GardenColors.error),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión'), backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _copyMessage() async {
    if (_message == null) return;
    await Clipboard.setData(ClipboardData(text: _message!));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensaje copiado')),
      );
    }
  }

  Future<void> _openEmailClient() async {
    if (_message == null || _email == null) return;
    final uri = Uri(
      scheme: 'mailto',
      path: _email,
      queryParameters: {
        'subject': 'Tu código de verificación de GARDEN',
        'body': _message!,
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el cliente de correo'), backgroundColor: GardenColors.error),
      );
    }
  }

  Future<void> _openWhatsApp() async {
    if (_message == null) return;
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_message!)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp'), backgroundColor: GardenColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(widget.request['name'] as String? ?? '—',
              style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(widget.request['email'] as String? ?? '—', style: TextStyle(color: subtextColor, fontSize: 13)),
          const SizedBox(height: 20),

          if (_generating)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: GardenColors.primary)))
          else if (_message != null) ...[
            Text(
              _reused ? 'CÓDIGO REAL YA ENVIADO POR RESEND' : 'MENSAJE LISTO PARA ENVIAR',
              style: TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
            if (_reused) ...[
              const SizedBox(height: 2),
              Text(
                'Este es el mismo código que el usuario ya recibió en su correo — no se generó uno nuevo.',
                style: TextStyle(color: subtextColor, fontSize: 11.5),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                borderRadius: BorderRadius.circular(GardenRadius.md),
                border: Border.all(color: borderColor),
              ),
              child: Text(_message!, style: TextStyle(color: textColor, fontSize: 14, height: 1.4)),
            ),
            const SizedBox(height: 6),
            Text('Válido por 10 minutos desde ahora.', style: TextStyle(color: subtextColor, fontSize: 11.5)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyMessage,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copiar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openEmailClient,
                    icon: const Icon(Icons.email_outlined, size: 18),
                    label: const Text('Abrir correo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GardenColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _openWhatsApp,
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text('Enviar por WhatsApp en su lugar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: GardenColors.success,
                side: const BorderSide(color: GardenColors.success),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                minimumSize: const Size(double.infinity, 0),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(_reused ? 'Actualizar (sigue siendo el mismo código mientras sea válido)' : 'Generar código nuevo'),
            ),
          ],
        ],
      ),
    );
  }
}

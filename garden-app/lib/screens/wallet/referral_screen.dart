import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Programa de referidos — "Invitá y ganá" (gap de paridad internacional,
/// ≈ referral programs de Uber/Airbnb). El bono se acredita recién cuando
/// el referido completa su primer servicio real (ver
/// grantReferralRewardIfEligible en referral.service.ts) — no por solo
/// registrarse, para evitar abuso.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  bool _loading = true;
  String? _code;
  int _referredCount = 0;
  double _rewardBS = 20;
  bool _canApplyCode = false;
  final TextEditingController _applyController = TextEditingController();
  bool _applying = false;
  String? _applyError;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  String get _token => AuthState.token;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _applyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/referral'), headers: {'Authorization': 'Bearer $_token'});
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        final d = data['data'] as Map<String, dynamic>;
        setState(() {
          _code = d['code'] as String?;
          _referredCount = (d['referredCount'] as num?)?.toInt() ?? 0;
          _rewardBS = (d['rewardBS'] as num?)?.toDouble() ?? 20;
          _canApplyCode = d['canApplyCode'] == true;
        });
      }
    } catch (_) {
      // Sin red — la pantalla queda vacía, el usuario puede reintentar (pull no implementado, es simple).
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyCode() async {
    final code = _applyController.text.trim();
    if (code.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() { _applying = true; _applyError = null; });
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/referral/apply'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        if (mounted) {
          setState(() => _canApplyCode = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✓ Código aplicado — cuando completes tu primer servicio, ambos ganan el bono'),
            backgroundColor: GardenColors.success,
            duration: Duration(seconds: 4),
          ));
        }
      } else if (mounted) {
        setState(() => _applyError = data['error']?['message'] ?? 'No se pudo aplicar el código');
      }
    } catch (e) {
      if (mounted) setState(() => _applyError = 'Error de conexión');
    } finally {
      if (mounted) setState(() => _applying = false);
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
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: surface,
            elevation: 0,
            title: Text('Invitá y ganá', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 17)),
          ),
          body: _loading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                            colors: [GardenColors.primary, GardenColors.forest],
                          ),
                          borderRadius: BorderRadius.circular(GardenRadius.xl),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🎁', style: TextStyle(fontSize: 32)),
                            const SizedBox(height: 10),
                            Text('Invitá a un amigo y los dos ganan Bs ${_rewardBS.toStringAsFixed(0)}',
                                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, height: 1.25)),
                            const SizedBox(height: 6),
                            const Text('El bono se acredita cuando tu invitado complete su primer servicio.',
                                style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Tu código', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(_code ?? '—',
                                  style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 4)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, color: GardenColors.primary),
                              onPressed: _code == null ? null : () async {
                                await Clipboard.setData(ClipboardData(text: _code!));
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                    content: Text('✓ Código copiado'), backgroundColor: GardenColors.success,
                                    duration: Duration(seconds: 2),
                                  ));
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      GardenButton(
                        label: 'Compartir por WhatsApp',
                        icon: Icons.chat_rounded,
                        onPressed: _code == null ? null : () async {
                          final text = Uri.encodeComponent(
                              'Te invito a Garden 🐾 — encontrá cuidadores de mascotas verificados en Santa Cruz. Usá mi código $_code al registrarte y los dos ganamos Bs ${_rewardBS.toStringAsFixed(0)}.');
                          await launchUrl(Uri.parse('https://wa.me/?text=$text'), mode: LaunchMode.externalApplication);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text('$_referredCount persona${_referredCount == 1 ? '' : 's'} ya se unieron con tu código',
                          style: TextStyle(color: subtextColor, fontSize: 12.5)),

                      if (_canApplyCode) ...[
                        const SizedBox(height: 28),
                        Divider(color: borderColor),
                        const SizedBox(height: 20),
                        Text('¿Alguien te invitó?', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('Cargá su código antes de tu primer servicio para que los dos ganen.',
                            style: TextStyle(color: subtextColor, fontSize: 12)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _applyController,
                                textCapitalization: TextCapitalization.characters,
                                style: TextStyle(color: textColor, fontSize: 14, letterSpacing: 2),
                                decoration: InputDecoration(
                                  hintText: 'CÓDIGO',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  filled: true,
                                  fillColor: surface,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                                  errorText: _applyError,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _applying ? null : _applyCode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: GardenColors.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              ),
                              child: _applying
                                  ? const SizedBox(width: 16, height: 16, child: GardenLoadingIndicator(size: 16, color: Colors.white))
                                  : const Text('Aplicar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }
}

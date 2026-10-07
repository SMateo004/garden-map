import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../design/brote.dart';
import '../../design/garden_caregiver_card.dart';
import '../../design/garden_depth.dart';
import '../../design/garden_icons.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../services/referral_invite.dart';
import '../../widgets/garden_empty_state.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Programa de referidos — "Invita y gana". El bono se acredita recién
/// cuando el referido completa su primer servicio real (ver
/// grantReferralRewardIfEligible en referral.service.ts) — no por solo
/// registrarse, para evitar abuso.
class ReferralScreen extends StatefulWidget {
  /// Código que llegó por enlace (/referral?code=...), para cargarlo listo.
  final String? initialCode;
  const ReferralScreen({super.key, this.initialCode});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  bool _loading = true;
  bool _failed = false;
  String? _code;
  int _referredCount = 0;
  int _rewardedCount = 0;
  double _rewardBS = 20;
  bool _canApplyCode = false;

  /// NONE | PENDING | REWARDED — el bono propio, si a este usuario lo invitaron.
  String _myBonus = 'NONE';
  final TextEditingController _applyController = TextEditingController();
  bool _applying = false;
  String? _applyError;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  String get _token => AuthState.token;
  String get _reward => 'Bs ${_rewardBS.toStringAsFixed(_rewardBS % 1 == 0 ? 0 : 2).replaceAll('.', ',')}';
  String get _link => 'https://gardenbo.com/register?ref=$_code';

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
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final res = await http.get(Uri.parse('$_baseUrl/referral'), headers: {'Authorization': 'Bearer $_token'});
      final data = jsonDecode(res.body);
      if (data['success'] != true) throw Exception();
      final d = data['data'] as Map<String, dynamic>;
      final prefill = ReferralInvite.normalize(widget.initialCode) ?? await ReferralInvite.pending();
      if (!mounted) return;
      setState(() {
        _code = d['code'] as String?;
        _referredCount = (d['referredCount'] as num?)?.toInt() ?? 0;
        _rewardedCount = (d['rewardedCount'] as num?)?.toInt() ?? 0;
        _rewardBS = (d['rewardBS'] as num?)?.toDouble() ?? 20;
        _canApplyCode = d['canApplyCode'] == true;
        _myBonus = d['myBonus'] as String? ?? 'NONE';
        if (_canApplyCode && prefill != null && _applyController.text.isEmpty) _applyController.text = prefill;
      });
    } catch (_) {
      // Antes: sin red quedaba "—" como código y "0 personas", sin aviso.
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  Future<void> _copy(String text, String what) async {
    HapticFeedback.selectionClick();
    await Clipboard.setData(ClipboardData(text: text));
    _toast('$what copiado');
  }

  Future<void> _shareWhatsApp() async {
    HapticFeedback.selectionClick();
    final text = Uri.encodeComponent(
        'Te invito a GARDEN, para encontrar cuidadores de mascotas verificados en Santa Cruz. '
        'Regístrate con este enlace y, cuando completes tu primer servicio, los dos ganamos $_reward: $_link '
        '(mi código: $_code)');
    await launchUrl(Uri.parse('https://wa.me/?text=$text'), mode: LaunchMode.externalApplication);
  }

  Future<void> _applyCode() async {
    final code = ReferralInvite.normalize(_applyController.text);
    if (code == null) {
      setState(() => _applyError = 'Revisa el código: son letras y números, sin espacios');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _applying = true;
      _applyError = null;
    });
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/referral/apply'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        await ReferralInvite.clear();
        if (mounted) {
          setState(() {
            _canApplyCode = false;
            _myBonus = 'PENDING';
          });
        }
      } else if (mounted) {
        setState(() => _applyError = data['error']?['message'] ?? 'No se pudo aplicar el código');
      }
    } catch (e) {
      if (mounted) setState(() => _applyError = 'Error de conexión. Intenta de nuevo.');
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

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: surface,
            foregroundColor: textColor,
            elevation: 0,
            title: Text('Invita y gana', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 17)),
          ),
          body: _loading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : _failed
                  ? ListView(padding: const EdgeInsets.all(24), children: [
                      const SizedBox(height: 40),
                      GardenEmptyState(
                        type: GardenEmptyType.generic,
                        brote: BrotePose.oops,
                        title: 'No pudimos cargar tu código',
                        subtitle: 'Revisa tu conexión e inténtalo de nuevo.',
                        ctaLabel: 'Reintentar',
                        onCta: _load,
                      ),
                    ])
                  : RefreshIndicator(
                      color: GardenColors.primary,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                _hero(),
                                const SizedBox(height: 16),
                                _codeCard(isDark),
                                if (_referredCount > 0) ...[
                                  const SizedBox(height: 16),
                                  GardenStatTiles(tiles: [
                                    ('$_referredCount', _referredCount == 1 ? 'se unió' : 'se unieron'),
                                    ('$_rewardedCount', _rewardedCount == 1 ? 'ya ganó contigo' : 'ya ganaron contigo'),
                                  ]),
                                  if (_referredCount > _rewardedCount) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _referredCount - _rewardedCount == 1
                                          ? '1 persona todavía no hizo su primer servicio. Cuando lo haga, ganas $_reward.'
                                          : '${_referredCount - _rewardedCount} personas todavía no hicieron su primer servicio. Ganas $_reward por cada una cuando lo hagan.',
                                      style: TextStyle(
                                          color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary,
                                          fontSize: 12.5,
                                          height: 1.4),
                                    ),
                                  ],
                                ],
                                if (_myBonus == 'PENDING') ...[
                                  const SizedBox(height: 16),
                                  _myBonusCard(isDark),
                                ],
                                if (_canApplyCode) ...[
                                  const SizedBox(height: 20),
                                  _applyCard(isDark),
                                ],
                              ]),
                            ),
                          ),
                        ],
                      ),
                    ),
        );
      },
    );
  }

  /// Promesa y cómo funciona, en tres pasos.
  Widget _hero() {
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
              child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35))),
          ]),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GardenColors.primary, GardenColors.forest],
        ),
        borderRadius: BorderRadius.circular(GardenRadius.xl),
        boxShadow: [BoxShadow(color: GardenColors.forest.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text('Invita a un amigo y los dos ganan $_reward',
                style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, height: 1.2)),
          ),
          const SizedBox(width: 12),
          // Antes el regalo era verde sobre el degradado verde: no se veía.
          const GardenClay(
            size: 60,
            color: GardenColors.lime,
            float: true,
            interactive: false,
            child: GardenClayIcon(GIcon.regalo, color: GardenColors.forest, size: GIconSize.xl),
          ),
        ]),
        const SizedBox(height: 6),
        step(1, 'Comparte tu enlace por WhatsApp.'),
        step(2, 'Tu amigo se registra con él (el código se carga solo).'),
        step(3, 'Cuando complete su primer servicio, $_reward para cada uno en la billetera.'),
      ]),
    );
  }

  Widget _codeCard(bool isDark) {
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final chip = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final code = _code ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        border: Border.all(color: border),
        boxShadow: GardenShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Tu código', style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        // Cada letra en su casilla: se dicta y se lee sin confundirse.
        Semantics(
          label: 'Tu código: ${code.split('').join(' ')}. Toca para copiarlo',
          button: true,
          excludeSemantics: true,
          child: InkWell(
            onTap: code.isEmpty ? null : () => _copy(code, 'Código'),
            borderRadius: BorderRadius.circular(12),
            child: Row(children: [
              Expanded(
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final ch in code.split(''))
                    Container(
                      width: 36,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: chip, borderRadius: BorderRadius.circular(10)),
                      child: Text(ch, style: TextStyle(color: text, fontSize: 22, fontWeight: FontWeight.w900)),
                    ),
                ]),
              ),
              const SizedBox(width: 8),
              GardenIcon(GIcon.copiar, color: isDark ? GardenColors.primaryLight : GardenColors.primary),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        GardenButton(label: 'Compartir por WhatsApp', gIcon: GIcon.chat, onPressed: code.isEmpty ? null : _shareWhatsApp),
        const SizedBox(height: 10),
        GardenButton(
          label: 'Copiar enlace',
          gIcon: GIcon.copiar,
          outline: true,
          onPressed: code.isEmpty ? null : () => _copy(_link, 'Enlace'),
        ),
      ]),
    );
  }

  Widget _myBonusCard(bool isDark) {
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GardenColors.success.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(GardenRadius.lg),
      ),
      child: Row(children: [
        GardenClay(
          size: 40,
          tint: GardenColors.success.withValues(alpha: 0.18),
          interactive: false,
          child: const GardenIcon(GIcon.regalo, color: GardenColors.success, state: GIconState.active),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Te invitaron: ganas $_reward cuando completes tu primer servicio.',
              style: TextStyle(color: text, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35)),
        ),
      ]),
    );
  }

  Widget _applyCard(bool isDark) {
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        border: Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('¿Alguien te invitó?', style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Carga su código antes de tu primer servicio para que los dos ganen $_reward.',
            style: TextStyle(color: sub, fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 12),
        TextField(
          controller: _applyController,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(color: text, fontSize: 16, letterSpacing: 3, fontWeight: FontWeight.w700),
          onSubmitted: (_) => _applyCode(),
          decoration: InputDecoration(
            hintText: 'CÓDIGO',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            filled: true,
            fillColor: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            errorText: _applyError,
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: 10),
        GardenButton(label: 'Aplicar código', outline: true, loading: _applying, onPressed: _applying ? null : _applyCode),
      ]),
    );
  }
}

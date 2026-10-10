import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../design/garden_code_input.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../design/garden_icons.dart';
import '../../theme/garden_motion.dart';

/// Verificar el correo con el código de 6 dígitos (registro de empresa).
/// El código vence a los 10 minutos y admite 5 intentos (email.service.ts).
class EmailVerificationScreen extends StatefulWidget {
  final VoidCallback? onComplete;
  final bool showAppBar;

  const EmailVerificationScreen({
    super.key,
    this.onComplete,
    this.showAppBar = true,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  static const _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.gardenbo.com/api',
  );

  final _codeCtrl = TextEditingController();

  String _email = '';
  bool _isLoading = false;
  bool _isSending = false;
  bool _sent = false;
  bool _showSuccess = false;
  bool _codeError = false;
  String? _errorMessage;

  /// El envío automático falló: el servidor ya avisó a un admin para que lo
  /// mande a mano (EMAIL_OTP_MANUAL_HELP).
  bool _manualHelp = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _loadUserAndSendCode();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AuthState.token}',
      };

  static String? _messageOf(String body) {
    try {
      final data = jsonDecode(body);
      return (data['error']?['message'] ?? data['message']) as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadUserAndSendCode() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/auth/me'), headers: _authHeaders);
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final user = data['data'] ?? data;
        setState(() => _email = user['email'] ?? '');
      }
    } catch (_) {
      // Sin el correo igual se puede verificar; solo no se muestra a dónde.
    }
    await _sendVerificationEmail();
  }

  Future<void> _sendVerificationEmail() async {
    if (_isSending) return;
    setState(() {
      _isSending = true;
      _errorMessage = null;
      _manualHelp = false;
    });
    try {
      final res = await http.post(Uri.parse('$_baseUrl/auth/send-verification-email'), headers: _authHeaders);
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        setState(() => _sent = true);
        _startCooldown();
      } else if (res.statusCode == 429) {
        setState(() => _errorMessage = 'Pediste varios códigos seguidos. Espera unos minutos y vuelve a intentar.');
      } else {
        final failed = res.body.contains('EMAIL_SEND_FAILED');
        setState(() {
          _manualHelp = failed;
          _errorMessage = failed ? null : (_messageOf(res.body) ?? 'No pudimos enviar el correo. Intenta de nuevo.');
        });
      }
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Sin conexión. Revisa tu internet e intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendCooldown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _verifyCode([String? fromInput]) async {
    final code = fromInput ?? _codeCtrl.text;
    if (_isLoading) return;
    if (code.length != 6) {
      setState(() {
        _codeError = true;
        _errorMessage = 'Escribe los 6 dígitos del código.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _codeError = false;
    });
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/verify-email'),
        headers: _authHeaders,
        body: jsonEncode({'code': code}),
      );
      if (!mounted) return;
      final ok = res.statusCode == 200 && (jsonDecode(res.body)['success'] == true);
      if (ok) {
        HapticFeedback.mediumImpact();
        setState(() => _showSuccess = true);
        await Future.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;
        if (widget.onComplete != null) {
          widget.onComplete!();
        } else {
          context.go('/caregiver/home');
        }
      } else {
        // Código incorrecto, vencido o demasiados intentos: el servidor lo
        // dice claro. Se borra para volver a escribir.
        HapticFeedback.heavyImpact();
        _codeCtrl.clear();
        setState(() {
          _codeError = true;
          _errorMessage = _messageOf(res.body) ?? 'Código incorrecto.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Sin conexión. Revisa tu internet e intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textPrimary = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final textSecondary = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: bg,
      // En la web va dentro del registro de empresa, que ya tiene su barra.
      appBar: widget.showAppBar && !kIsWeb
          ? AppBar(
              title: Text('Verificar correo',
                  style: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
              centerTitle: true,
              backgroundColor: bg,
              foregroundColor: textPrimary,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            )
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: AnimatedSwitcher(
                duration: GardenMotion.resolve(context, GardenMotion.standard),
                child: _showSuccess
                    ? _buildSuccess(textPrimary, textSecondary)
                    : _buildForm(isDark, textPrimary, textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(Color textPrimary, Color textSecondary) {
    return Column(
      key: const ValueKey('ok'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(shape: BoxShape.circle, color: GardenColors.success.withValues(alpha: 0.14)),
          child: const GardenIcon(GIcon.confirmado,
              size: GIconSize.hero, color: GardenColors.success, state: GIconState.active),
        ),
        const SizedBox(height: 20),
        Text('Correo verificado', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textPrimary)),
        const SizedBox(height: 6),
        Text('Seguimos con el siguiente paso.', style: TextStyle(fontSize: 14, color: textSecondary)),
      ],
    );
  }

  Widget _buildForm(bool isDark, Color textPrimary, Color textSecondary) {
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(shape: BoxShape.circle, color: GardenColors.primary.withValues(alpha: 0.12)),
            child: const GardenIcon(GIcon.correo,
                size: GIconSize.hero, color: GardenColors.primary, state: GIconState.active),
          ),
        ),
        const SizedBox(height: 22),
        Text('Revisa tu correo',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textPrimary)),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: _isSending && !_sent ? 'Estamos enviando un código de 6 dígitos a ' : 'Te enviamos un código de 6 dígitos a '),
            TextSpan(
              text: _email.isNotEmpty ? _email : 'tu correo',
              style: TextStyle(color: textPrimary, fontWeight: FontWeight.w800),
            ),
            const TextSpan(text: '. Vence en 10 minutos.'),
          ]),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14.5, color: textSecondary, height: 1.45),
        ),
        const SizedBox(height: 28),

        Center(
          child: GardenCodeInput(
            controller: _codeCtrl,
            error: _codeError,
            enabled: !_isLoading,
            onCompleted: _verifyCode,
          ),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const GardenIcon(GIcon.conflicto, size: GIconSize.sm, color: GardenColors.error),
            const SizedBox(width: 6),
            Flexible(
              child: Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: GardenColors.error, fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ]),
        ],
        const SizedBox(height: 24),

        GardenButton(label: 'Verificar', loading: _isLoading, onPressed: _isLoading ? null : () => _verifyCode()),
        const SizedBox(height: 14),

        // Reenviar
        Center(
          child: _isSending
              ? const GardenLoadingIndicator(size: 20, color: GardenColors.primary)
              : _resendCooldown > 0
                  ? Text('¿No llegó? Puedes pedir otro en ${_resendCooldown}s',
                      style: TextStyle(fontSize: 13, color: textSecondary))
                  : TextButton(
                      onPressed: _sendVerificationEmail,
                      child: const Text('Reenviar código',
                          style: TextStyle(fontSize: 14, color: GardenColors.primary, fontWeight: FontWeight.w700)),
                    ),
        ),
        const SizedBox(height: 18),

        // Ayuda o envío manual
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _manualHelp ? GardenColors.warning.withValues(alpha: 0.10) : surface,
            borderRadius: BorderRadius.circular(GardenRadius.lg),
            border: Border.all(color: _manualHelp ? GardenColors.warning.withValues(alpha: 0.35) : border),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GardenIcon(_manualHelp ? GIcon.soporte : GIcon.info,
                size: GIconSize.sm, color: _manualHelp ? GardenColors.warning : textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _manualHelp
                    ? 'No pudimos enviar el correo automáticamente. Ya avisamos al equipo de Garden: te mandarán el código a mano en breve.'
                    : 'Si no lo ves, revisa Spam o Promociones. El correo llega de Garden.',
                style: TextStyle(fontSize: 12.5, color: _manualHelp ? textPrimary : textSecondary, height: 1.4),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../design/garden_code_input.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../design/garden_icons.dart';

/// Paso 8 del wizard de cuidador: verificación combinada de teléfono + email.
/// Reemplaza los antiguos pasos separados 8 (teléfono) y 9 (email) — ambos
/// códigos se envían en paralelo al entrar al paso y cada lado se verifica
/// de forma independiente. El botón "Continuar" solo se habilita cuando
/// AMBOS lados están verificados.
class CombinedVerificationStep extends StatefulWidget {
  /// Número de teléfono (8 dígitos, sin +591) tal como está en el wizard.
  /// Se usa como respaldo mientras se confirma el valor real desde el perfil.
  final String phoneNumber;
  final VoidCallback onComplete;
  final bool showAppBar;
  /// Llamado cuando el usuario confirma un nuevo número de teléfono.
  final void Function(String newPhone)? onChangePhone;

  const CombinedVerificationStep({
    super.key,
    required this.phoneNumber,
    required this.onComplete,
    this.showAppBar = false,
    this.onChangePhone,
  });

  @override
  State<CombinedVerificationStep> createState() => _CombinedVerificationStepState();
}

class _CombinedVerificationStepState extends State<CombinedVerificationStep> {
  static const _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.gardenbo.com/api',
  );

  bool _loadingProfile = true;
  String _phone = '';
  String _email = '';

  // ── Teléfono ─────────────────────────────────────────────────────────────
  bool _phoneVerified = false;
  bool _phoneCodeSent = false;
  bool _phoneSending = false;
  bool _phoneVerifying = false;
  String? _phoneError;
  int _phoneCooldown = 0;
  Timer? _phoneCooldownTimer;
  final _phoneCodeCtrl = TextEditingController();
  bool _phoneCodeError = false;

  // ── Email ────────────────────────────────────────────────────────────────
  bool _emailVerified = false;
  bool _emailCodeSent = false;
  bool _emailSending = false;
  bool _emailVerifying = false;
  String? _emailError;
  int _emailCooldown = 0;
  Timer? _emailCooldownTimer;
  final _emailCodeCtrl = TextEditingController();
  bool _emailCodeError = false;

  String get _fullPhone => '+591${_phone.isNotEmpty ? _phone : widget.phoneNumber}';
  String get _phoneCode => _phoneCodeCtrl.text;
  String get _emailCode => _emailCodeCtrl.text;

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AuthState.token}',
      };

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _phoneCodeCtrl.dispose();
    _emailCodeCtrl.dispose();
    _phoneCooldownTimer?.cancel();
    _emailCooldownTimer?.cancel();
    super.dispose();
  }

  /// Consulta el perfil actual para pre-poblar el estado verificado de cada
  /// lado (un usuario que regresa puede ya tener uno de los dos verificado)
  /// y dispara el envío de OTP SOLO para el lado que aún falte — ambos en
  /// paralelo, sin esperar el uno al otro.
  Future<void> _init() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/caregiver/my-profile'), headers: _authHeaders);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        final profile = data['data'] as Map<String, dynamic>;
        final userNode = profile['user'] as Map<String, dynamic>?;
        setState(() {
          _phone = (userNode?['phone'] as String? ?? widget.phoneNumber).trim();
          _email = (userNode?['email'] as String? ?? '').trim();
          _phoneVerified = profile['phoneVerified'] == true;
          _emailVerified = profile['emailVerified'] == true || userNode?['emailVerified'] == true;
        });
      }
    } catch (_) {
      // Si falla, se asume nada verificado y se intenta enviar ambos códigos igual.
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }

    // Disparar ambos envíos en paralelo (no bloqueante entre sí) — solo para
    // el lado que todavía no está verificado.
    if (!_phoneVerified) _sendPhoneCode();
    if (!_emailVerified) _sendEmailCode();
  }

  // ── Teléfono: enviar / verificar ─────────────────────────────────────────

  void _startPhoneCooldown() {
    _phoneCooldownTimer?.cancel();
    setState(() => _phoneCooldown = 60);
    _phoneCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _phoneCooldown--;
        if (_phoneCooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _sendPhoneCode() async {
    if (_phoneSending) return;
    setState(() { _phoneSending = true; _phoneError = null; });
    try {
      final res = await http.post(Uri.parse('$_baseUrl/auth/caregiver/send-phone-otp'), headers: _authHeaders);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        setState(() { _phoneCodeSent = true; });
        _startPhoneCooldown();
      } else {
        final msg = data['error']?['message'] as String? ?? data['message'] as String? ?? 'No se pudo enviar el código SMS.';
        setState(() => _phoneError = msg);
      }
    } catch (_) {
      if (mounted) setState(() => _phoneError = 'Error de conexión. Verifica tu internet e intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _phoneSending = false);
    }
  }

  Future<void> _verifyPhoneCode() async {
    final code = _phoneCode;
    if (_phoneVerifying) return;
    if (code.length < 6) {
      setState(() { _phoneCodeError = true; _phoneError = 'Escribe los 6 dígitos del código.'; });
      return;
    }
    setState(() { _phoneVerifying = true; _phoneError = null; _phoneCodeError = false; });
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/caregiver/verify-phone'),
        headers: _authHeaders,
        body: jsonEncode({'code': code}),
      );
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        setState(() { _phoneVerified = true; _phoneVerifying = false; });
      } else {
        final msg = data['error']?['message'] as String? ?? 'Código incorrecto. Intenta de nuevo.';
        _phoneCodeCtrl.clear();
        setState(() { _phoneVerifying = false; _phoneError = msg; _phoneCodeError = true; });
      }
    } catch (_) {
      if (mounted) setState(() { _phoneVerifying = false; _phoneError = 'Error de conexión. Intenta de nuevo.'; });
    }
  }

  void _showChangePhoneDialog(Color subtextColor) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar número de teléfono'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ingresa tu número correcto (8 dígitos, empieza en 6 o 7).',
                style: TextStyle(color: subtextColor, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.phone,
              maxLength: 8,
              decoration: const InputDecoration(prefixText: '+591 ', hintText: '7XXXXXXX', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final num = ctrl.text.trim();
              final valid = num.length == 8 && (num.startsWith('6') || num.startsWith('7'));
              if (!valid) return;
              Navigator.pop(ctx);
              widget.onChangePhone?.call(num);
              setState(() {
                _phone = num;
                _phoneCodeSent = false;
                _phoneCodeCtrl.clear();
              });
              _sendPhoneCode();
            },
            child: const Text('Confirmar', style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Email: enviar / verificar ────────────────────────────────────────────

  void _startEmailCooldown() {
    _emailCooldownTimer?.cancel();
    setState(() => _emailCooldown = 60);
    _emailCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _emailCooldown--;
        if (_emailCooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _sendEmailCode() async {
    if (_emailSending) return;
    setState(() { _emailSending = true; _emailError = null; });
    try {
      final res = await http.post(Uri.parse('$_baseUrl/auth/send-verification-email'), headers: _authHeaders);
      if (!mounted) return;
      Map<String, dynamic> data = {};
      try { data = jsonDecode(res.body) as Map<String, dynamic>; } catch (_) {}
      if (res.statusCode == 200 || res.statusCode == 201 || data['success'] == true) {
        setState(() => _emailCodeSent = true);
        _startEmailCooldown();
      } else {
        final msg = data['error']?['message'] as String? ?? data['message'] as String? ?? 'No se pudo enviar el correo de verificación.';
        setState(() => _emailError = msg);
      }
    } catch (_) {
      if (mounted) setState(() => _emailError = 'No se pudo enviar el correo de verificación.');
    } finally {
      if (mounted) setState(() => _emailSending = false);
    }
  }

  Future<void> _verifyEmailCode() async {
    final code = _emailCode;
    if (_emailVerifying) return;
    if (code.length != 6) {
      setState(() { _emailCodeError = true; _emailError = 'Escribe los 6 dígitos del código.'; });
      return;
    }
    setState(() { _emailVerifying = true; _emailError = null; _emailCodeError = false; });
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/verify-email'),
        headers: _authHeaders,
        body: jsonEncode({'code': code}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 || data['success'] == true) {
        if (mounted) setState(() { _emailVerified = true; _emailVerifying = false; });
      } else {
        final msg = data['error']?['message'] as String? ?? data['message'] as String? ?? 'Código incorrecto. Intenta de nuevo.';
        _emailCodeCtrl.clear();
        if (mounted) setState(() { _emailVerifying = false; _emailError = msg; _emailCodeError = true; });
      }
    } catch (_) {
      if (mounted) setState(() { _emailVerifying = false; _emailError = 'Error de conexión. Intenta de nuevo.'; });
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        final bothVerified = _phoneVerified && _emailVerified;

        final body = _loadingProfile
            ? const Center(child: Padding(padding: EdgeInsets.all(48), child: GardenLoadingIndicator(color: GardenColors.primary)))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Verifica tu cuenta',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    Text(
                      'Confirma tu teléfono y tu correo para proteger tu cuenta y activar tu perfil de cuidador.',
                      style: TextStyle(fontSize: 14, color: subtextColor, height: 1.5),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: surfaceEl,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: Text(
                        'Te enviaremos un código de verificación por SMS. Pueden aplicarse tarifas de mensajes y datos; la frecuencia varía. Responde AYUDA para ayuda o ALTO para cancelar.',
                        style: TextStyle(fontSize: 12, color: subtextColor, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 24),

                    _buildVerificationCard(
                      isDark: isDark,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      surfaceEl: surfaceEl,
                      borderColor: borderColor,
                      icon: GIcon.telefono,
                      title: 'Teléfono',
                      subtitle: _phoneCodeSent ? 'Enviamos un código SMS a\n$_fullPhone' : (_phoneSending ? 'Enviando código SMS...' : ''),
                      verified: _phoneVerified,
                      verifiedLabel: _fullPhone,
                      codeSent: _phoneCodeSent,
                      sending: _phoneSending,
                      verifying: _phoneVerifying,
                      cooldown: _phoneCooldown,
                      codeController: _phoneCodeCtrl,
                      codeError: _phoneCodeError,
                      onVerify: _verifyPhoneCode,
                      onResend: _sendPhoneCode,
                      errorMessage: _phoneError,
                      extraAction: widget.onChangePhone != null
                          ? TextButton.icon(
                              onPressed: () => _showChangePhoneDialog(subtextColor),
                              icon: const GardenIcon(GIcon.editar, size: GIconSize.xs, color: GardenColors.primary),
                              label: const Text('Cambiar número', style: TextStyle(color: GardenColors.primary, fontSize: 13)),
                            )
                          : null,
                    ),
                    const SizedBox(height: 20),

                    _buildVerificationCard(
                      isDark: isDark,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      surfaceEl: surfaceEl,
                      borderColor: borderColor,
                      icon: GIcon.correo,
                      title: 'Correo electrónico',
                      subtitle: _emailCodeSent ? 'Enviamos un código a\n$_email' : (_emailSending ? 'Enviando código...' : ''),
                      verified: _emailVerified,
                      verifiedLabel: _email,
                      codeSent: _emailCodeSent,
                      sending: _emailSending,
                      verifying: _emailVerifying,
                      cooldown: _emailCooldown,
                      codeController: _emailCodeCtrl,
                      codeError: _emailCodeError,
                      onVerify: _verifyEmailCode,
                      onResend: _sendEmailCode,
                      errorMessage: _emailError,
                    ),

                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: GardenButton(
                        label: 'Continuar →',
                        onPressed: bothVerified ? widget.onComplete : () {},
                      ),
                    ),
                    if (!bothVerified) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Verifica ambos para continuar',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: subtextColor, fontSize: 12),
                      ),
                    ],

                    if (kIsWeb) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: GardenColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          const GardenIcon(GIcon.info, size: GIconSize.sm, color: GardenColors.warning),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'La verificación por teléfono requiere la app móvil. Descarga Garden en tu celular para completar este paso.',
                              style: TextStyle(color: textColor, fontSize: 13, height: 1.4),
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ],
                ),
              );

        if (!widget.showAppBar) return body;
        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(backgroundColor: bg, elevation: 0, title: Text('Verificación', style: TextStyle(color: textColor))),
          body: SafeArea(child: body),
        );
      },
    );
  }

  Widget _buildVerificationCard({
    required bool isDark,
    required Color textColor,
    required Color subtextColor,
    required Color surfaceEl,
    required Color borderColor,
    required GIcon icon,
    required String title,
    required String subtitle,
    required bool verified,
    required String verifiedLabel,
    required bool codeSent,
    required bool sending,
    required bool verifying,
    required int cooldown,
    required TextEditingController codeController,
    required bool codeError,
    required VoidCallback onVerify,
    required VoidCallback onResend,
    String? errorMessage,
    Widget? extraAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: verified ? GardenColors.success.withValues(alpha: 0.08) : surfaceEl,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: verified ? GardenColors.success.withValues(alpha: 0.4) : borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GardenIcon(icon, size: GIconSize.md, state: GIconState.active),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
            ),
            if (verified)
              const GardenIcon(GIcon.confirmado, size: GIconSize.md, state: GIconState.active, color: GardenColors.success),
          ]),
          if (verified) ...[
            const SizedBox(height: 8),
            Text('Verificado — $verifiedLabel',
                style: const TextStyle(color: GardenColors.success, fontSize: 13, fontWeight: FontWeight.w600)),
          ] else ...[
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(subtitle, style: TextStyle(fontSize: 13, color: subtextColor, height: 1.4)),
            ],
            if (extraAction != null) extraAction,

            if (sending && !codeSent) ...[
              const SizedBox(height: 16),
              const Center(child: GardenLoadingIndicator(color: GardenColors.primary)),
            ],

            if (codeSent) ...[
              const SizedBox(height: 16),
              Center(
                child: GardenCodeInput(
                  controller: codeController,
                  error: codeError,
                  enabled: !verifying,
                  // Dos tarjetas en la misma pantalla: ninguna se enfoca sola.
                  autofocus: false,
                  onCompleted: (_) => onVerify(),
                ),
              ),
              const SizedBox(height: 14),
              if (verifying)
                const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              else
                SizedBox(
                  width: double.infinity,
                  child: GardenButton(label: 'Verificar', height: 44, onPressed: onVerify),
                ),
              const SizedBox(height: 10),
              Center(
                child: cooldown > 0
                    ? Text('Reenviar código en ${cooldown}s', style: TextStyle(color: subtextColor, fontSize: 12))
                    : TextButton(
                        onPressed: onResend,
                        child: const Text('Reenviar código',
                            style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
              ),
            ],

            if (errorMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: GardenColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: GardenColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const GardenIcon(GIcon.conflicto, size: GIconSize.sm, color: GardenColors.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(errorMessage, style: const TextStyle(color: GardenColors.error, fontSize: 12))),
                ]),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

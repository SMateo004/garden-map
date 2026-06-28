import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';

class PhoneVerificationScreen extends StatefulWidget {
  final String phoneNumber; // 8-digit Bolivian number (without country code)
  final VoidCallback? onComplete;
  final bool showAppBar;
  /// Called when the user wants to change the phone number before verifying.
  /// If null, the "Cambiar número" button is not shown.
  final void Function(String newPhone)? onChangePhone;

  const PhoneVerificationScreen({
    super.key,
    required this.phoneNumber,
    this.onComplete,
    this.showAppBar = true,
    this.onChangePhone,
  });

  @override
  State<PhoneVerificationScreen> createState() => _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  static const _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.gardenbo.com/api',
  );

  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _codeSent = false;
  bool _isLoading = false;
  bool _isSending = false;
  String? _errorMessage;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  String get _fullPhone => '+591${widget.phoneNumber}';

  @override
  void initState() {
    super.initState();
    _sendCode();
  }

  @override
  void dispose() {
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    setState(() => _resendCooldown = 60);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _sendCode() async {
    if (_isSending) return;
    setState(() { _isSending = true; _errorMessage = null; });
    try {
      final token = AuthState.token;
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/caregiver/send-phone-otp'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        setState(() { _codeSent = true; _isSending = false; });
        _startResendCooldown();
      } else {
        final msg = data['error']?['message'] as String? ?? 'No se pudo enviar el código.';
        setState(() { _isSending = false; _errorMessage = msg; });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _errorMessage = 'Error de conexión. Verifica tu internet e intenta de nuevo.';
        });
      }
    }
  }

  Future<void> _submitCode() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length < 6) {
      setState(() => _errorMessage = 'Ingresa el código de 6 dígitos completo.');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final token = AuthState.token;
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/caregiver/verify-phone'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'code': code}),
      );
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        setState(() => _isLoading = false);
        widget.onComplete?.call();
      } else {
        final msg = data['error']?['message'] as String? ?? 'Código incorrecto. Intenta de nuevo.';
        setState(() { _isLoading = false; _errorMessage = msg; });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error de conexión. Intenta de nuevo.';
        });
      }
    }
  }

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    final allFilled = _controllers.every((c) => c.text.isNotEmpty);
    if (allFilled) _submitCode();
  }

  void _showChangePhoneDialog(BuildContext context, Color subtextColor) {
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
              decoration: const InputDecoration(
                prefixText: '+591 ',
                hintText: '7XXXXXXX',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              final num = ctrl.text.trim();
              final valid = num.length == 8 &&
                  (num.startsWith('6') || num.startsWith('7'));
              if (!valid) return;
              Navigator.pop(ctx);
              widget.onChangePhone!(num);
            },
            child: const Text('Confirmar',
                style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

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

        final body = SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('📱', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 20),
              Text(
                'Verifica tu teléfono',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _codeSent
                    ? 'Enviamos un código SMS a\n$_fullPhone'
                    : 'Enviando código SMS a\n$_fullPhone...',
                style: TextStyle(fontSize: 15, color: subtextColor, height: 1.5),
                textAlign: TextAlign.center,
              ),
              if (widget.onChangePhone != null) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () => _showChangePhoneDialog(context, subtextColor),
                  icon: const Icon(Icons.edit_outlined, size: 15, color: GardenColors.primary),
                  label: const Text('Cambiar número',
                      style: TextStyle(color: GardenColors.primary, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 26),

              if (_isSending && !_codeSent) ...[
                const CircularProgressIndicator(color: GardenColors.primary),
                const SizedBox(height: 16),
                Text('Enviando código...', style: TextStyle(color: subtextColor, fontSize: 14)),
              ],

              if (_codeSent) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    return Container(
                      width: 46,
                      height: 54,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: surfaceEl,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _controllers[i].text.isNotEmpty
                              ? GardenColors.primary
                              : borderColor,
                          width: _controllers[i].text.isNotEmpty ? 1.5 : 1,
                        ),
                      ),
                      child: TextField(
                        controller: _controllers[i],
                        focusNode: _focusNodes[i],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                        decoration: const InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (v) => _onDigitChanged(i, v),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 28),

                if (_isLoading)
                  const CircularProgressIndicator(color: GardenColors.primary)
                else
                  SizedBox(
                    width: double.infinity,
                    child: GardenButton(
                      label: 'Verificar número',
                      onPressed: _submitCode,
                    ),
                  ),

                const SizedBox(height: 20),
                if (_resendCooldown > 0)
                  Text(
                    'Reenviar código en ${_resendCooldown}s',
                    style: TextStyle(color: subtextColor, fontSize: 13),
                  )
                else
                  TextButton(
                    onPressed: _sendCode,
                    child: const Text(
                      'Reenviar código',
                      style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: GardenColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: GardenColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: GardenColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: GardenColors.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (kIsWeb) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'La verificación por teléfono requiere la app móvil. Descarga Garden en tu celular para completar este paso.',
                          style: TextStyle(color: textColor, fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );

        if (!widget.showAppBar) return body;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            title: Text('Verificación de teléfono', style: TextStyle(color: textColor)),
          ),
          body: SafeArea(child: body),
        );
      },
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';

class PhoneVerificationScreen extends StatefulWidget {
  final String phoneNumber; // 8-digit Bolivian number (without country code)
  final VoidCallback? onComplete;
  final bool showAppBar;

  const PhoneVerificationScreen({
    super.key,
    required this.phoneNumber,
    this.onComplete,
    this.showAppBar = true,
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
  String? _verificationId;
  String? _errorMessage;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  String get _fullPhone => '+591${widget.phoneNumber}';

  @override
  void initState() {
    super.initState();
    if (kDebugMode && !kIsWeb) {
      // En simulador iOS no hay APNs, Firebase no puede verificar la identidad
      // de la app y lanza missing-client-identifier. Esta flag desactiva esa
      // verificación solo en builds de debug. No afecta producción.
      FirebaseAuth.instance.setSettings(appVerificationDisabledForTesting: true);
    }
    if (!kIsWeb) {
      _sendCode();
    }
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
      // Firebase Auth iOS 11.x tiene una aserción que requiere main thread.
      // scheduleTask garantiza ejecución en el frame del scheduler (main thread).
      await SchedulerBinding.instance.scheduleTask<Future<void>>(
        () => FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: _fullPhone,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (PhoneAuthCredential credential) async {
            // Auto-retrieval on Android
            await _verifyWithCredential(credential);
          },
          verificationFailed: (FirebaseAuthException e) {
            if (!mounted) return;
            setState(() {
              _isSending = false;
              _errorMessage = _mapFirebaseError(e.code);
            });
          },
          codeSent: (String verificationId, int? resendToken) {
            if (!mounted) return;
            setState(() {
              _verificationId = verificationId;
              _codeSent = true;
              _isSending = false;
            });
            _startResendCooldown();
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            if (!mounted) return;
            _verificationId = verificationId;
          },
        ),
        Priority.touch,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _errorMessage = 'No se pudo enviar el código. Verifica el número e intenta de nuevo.';
        });
      }
    }
  }

  Future<void> _verifyWithCredential(PhoneAuthCredential credential) async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await result.user?.getIdToken();
      if (idToken == null) throw Exception('No se pudo obtener el token de Firebase.');
      await _confirmWithBackend(idToken);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = _mapFirebaseError(e.code); });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _submitCode() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length < 6) {
      setState(() => _errorMessage = 'Ingresa el código de 6 dígitos completo.');
      return;
    }
    if (_verificationId == null) {
      setState(() => _errorMessage = 'No hay código activo. Reenvía el código.');
      return;
    }
    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: code,
    );
    await _verifyWithCredential(credential);
  }

  Future<void> _confirmWithBackend(String idToken) async {
    try {
      final token = AuthState.token;
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/caregiver/verify-phone'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'firebaseIdToken': idToken}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['success'] == true) {
        setState(() => _isLoading = false);
        widget.onComplete?.call();
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = data['error']?['message'] as String? ?? 'Error al verificar el teléfono.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error de conexión. Intenta de nuevo.';
        });
      }
    }
  }

  String _mapFirebaseError(String code) {
    switch (code) {
      case 'invalid-phone-number': return 'Número de teléfono inválido. Verifica que sea correcto.';
      case 'too-many-requests': return 'Demasiados intentos. Espera unos minutos e intenta de nuevo.';
      case 'invalid-verification-code': return 'Código incorrecto. Revisa el SMS e intenta de nuevo.';
      case 'session-expired': return 'El código expiró. Reenvía un nuevo código.';
      case 'quota-exceeded': return 'Límite de SMS alcanzado. Intenta más tarde.';
      default: return 'Error: $code. Intenta de nuevo.';
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
              const SizedBox(height: 32),

              if (_isSending && !_codeSent) ...[
                const CircularProgressIndicator(color: GardenColors.primary),
                const SizedBox(height: 16),
                Text('Enviando código...', style: TextStyle(color: subtextColor, fontSize: 14)),
              ],

              if (_codeSent) ...[
                // 6-digit OTP input
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

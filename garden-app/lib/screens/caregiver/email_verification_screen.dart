import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class EmailVerificationScreen extends StatefulWidget {
  final VoidCallback? onComplete;
  final bool showAppBar;

  const EmailVerificationScreen({
    super.key,
    this.onComplete,
    this.showAppBar = true,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with SingleTickerProviderStateMixin {
  static const _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:3000/api',
  );

  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  String _email = '';
  String _token = '';
  bool _isLoading = false;
  bool _isSending = false;
  bool _showSuccess = false;
  String? _errorMessage;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  late AnimationController _successAnimController;
  late Animation<double> _successScale;

  @override
  void initState() {
    super.initState();
    _successAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = CurvedAnimation(
      parent: _successAnimController,
      curve: Curves.elasticOut,
    );
    _loadUserAndSendCode();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    _cooldownTimer?.cancel();
    _successAnimController.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

  String get _code => _controllers.map((c) => c.text).join();

  Future<void> _loadUserAndSendCode() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token') ?? '';

    // Fetch user email from /auth/me
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: _authHeaders,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final user = data['data'] ?? data;
        setState(() {
          _email = user['email'] ?? '';
        });
      }
    } catch (_) {
      // Silently ignore - email will just show empty
    }

    await _sendVerificationEmail();
  }

  Future<void> _sendVerificationEmail() async {
    if (_isSending) return;
    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/send-verification-email'),
        headers: _authHeaders,
      );
      if (res.statusCode != 200 && res.statusCode != 201) {
        final data = jsonDecode(res.body);
        setState(() {
          _errorMessage = data['message'] ?? 'Error al enviar el correo';
        });
      } else {
        _startCooldown();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'No se pudo enviar el correo de verificacion';
      });
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendCooldown = 0);
      } else {
        if (mounted) setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _verifyCode() async {
    final code = _code;
    if (code.length != 6) {
      setState(() => _errorMessage = 'Ingresa el codigo de 6 digitos');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/verify-email'),
        headers: _authHeaders,
        body: jsonEncode({'code': code}),
      );
      final data = jsonDecode(res.body);

      if (res.statusCode == 200 || data['success'] == true) {
        setState(() => _showSuccess = true);
        _successAnimController.forward();
        await Future.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;
        if (widget.onComplete != null) {
          widget.onComplete!();
        } else {
          context.go('/caregiver/home');
        }
      } else {
        setState(() {
          _errorMessage =
              data['message'] ?? data['error']?['message'] ?? 'Codigo invalido';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de conexion. Intenta de nuevo.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      // Paste handling: distribute digits across fields
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < 6; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      final focusIndex = digits.length.clamp(0, 5);
      _focusNodes[focusIndex].requestFocus();
      if (digits.length >= 6) {
        _verifyCode();
      }
      return;
    }

    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }

    // Auto-submit when all 6 digits entered
    if (_code.length == 6) {
      _verifyCode();
    }
  }

  void _onKeyPressed(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textPrimary =
        isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final textSecondary =
        isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor =
        isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Verificacion de Email'),
              backgroundColor: bg,
              foregroundColor: textPrimary,
              elevation: 0,
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: _showSuccess ? _buildSuccess(textPrimary) : _buildForm(
              isDark: isDark,
              surface: surface,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              borderColor: borderColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(Color textPrimary) {
    return ScaleTransition(
      scale: _successScale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: GardenGradients.fresh,
            ),
            child: const Icon(Icons.check_rounded, size: 56, color: Colors.white),
          ),
          const SizedBox(height: 24),
          Text(
            'Email verificado',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm({
    required bool isDark,
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
    required Color borderColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: GardenColors.primary.withOpacity(0.12),
          ),
          child: const Icon(
            Icons.email_outlined,
            size: 44,
            color: GardenColors.primary,
          ),
        ),
        const SizedBox(height: 28),

        // Title
        Text(
          'Verifica tu email',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        // Subtitle
        Text(
          _email.isNotEmpty
              ? 'Enviamos un codigo de 6 digitos a'
              : 'Enviamos un codigo de 6 digitos a tu correo',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: textSecondary),
        ),
        if (_email.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            _email,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
        ],
        const SizedBox(height: 32),

        // OTP fields
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) => _buildOtpBox(i, isDark, surface, textPrimary, borderColor)),
        ),
        const SizedBox(height: 8),

        // Error
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: GardenColors.error, fontSize: 14),
          ),
        ],
        const SizedBox(height: 28),

        // Verify button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: GardenColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: GardenColors.primary.withOpacity(0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Verificar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 20),

        // Resend link
        _isSending
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: GardenColors.primary,
                ),
              )
            : TextButton(
                onPressed: _resendCooldown > 0 ? null : _sendVerificationEmail,
                child: Text(
                  _resendCooldown > 0
                      ? 'Reenviar codigo ($_resendCooldown s)'
                      : 'Reenviar codigo',
                  style: TextStyle(
                    fontSize: 14,
                    color: _resendCooldown > 0
                        ? textSecondary.withOpacity(0.5)
                        : GardenColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
      ],
    );
  }

  Widget _buildOtpBox(
    int index,
    bool isDark,
    Color surface,
    Color textPrimary,
    Color borderColor,
  ) {
    final bool hasFocus = _focusNodes[index].hasFocus;
    final bool hasValue = _controllers[index].text.isNotEmpty;

    return Container(
      width: 48,
      height: 56,
      margin: EdgeInsets.only(right: index < 5 ? 8 : 0),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) => _onKeyPressed(index, event),
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6, // allow paste
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: isDark
                ? (hasFocus
                    ? GardenColors.darkSurfaceElevated
                    : surface)
                : (hasFocus
                    ? GardenColors.lightSurfaceElevated
                    : surface),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasValue ? GardenColors.primary : borderColor,
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: GardenColors.primary,
                width: 2,
              ),
            ),
          ),
          onChanged: (value) => _onDigitChanged(index, value),
        ),
      ),
    );
  }
}

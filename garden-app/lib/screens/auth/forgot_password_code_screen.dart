import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';

class ForgotPasswordCodeScreen extends StatefulWidget {
  final String email;
  const ForgotPasswordCodeScreen({super.key, required this.email});
  @override
  State<ForgotPasswordCodeScreen> createState() => _ForgotPasswordCodeScreenState();
}

class _ForgotPasswordCodeScreenState extends State<ForgotPasswordCodeScreen> {
  final List<TextEditingController> _ctrls = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(4, (_) => FocusNode());
  bool _loading = false;
  bool _resending = false;
  int _cooldown = 0;

  String get _baseUrl => const String.fromEnvironment(
        'API_URL',
        defaultValue: 'https://api.gardenbo.com/api',
      );

  String get _code => _ctrls.map((c) => c.text).join();

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    for (final n in _nodes) n.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa los 4 dígitos del código')),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/forgot-password/verify-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': widget.email, 'code': _code}),
      );
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        final tempToken = data['data']['tempToken'] as String;
        context.push('/forgot-password/new', extra: tempToken);
      } else {
        HapticFeedback.heavyImpact();
        GardenSnackBar.error(context, data['error']?['message'] as String? ?? 'El código no es correcto. Intenta de nuevo.');
        // Limpiar campos
        for (final c in _ctrls) c.clear();
        _nodes[0].requestFocus();
      }
    } catch (_) {
      if (mounted) {
        GardenSnackBar.error(context, 'Error de conexión. Revisa tu internet e intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await http.post(
        Uri.parse('$_baseUrl/auth/forgot-password/send-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': widget.email}),
      );
      if (mounted) {
        GardenSnackBar.success(context, 'Código reenviado — revisa tu correo');
        setState(() => _cooldown = 60);
        _startCooldown();
      }
    } catch (_) {
      if (mounted) {
        GardenSnackBar.error(context, 'No se pudo reenviar el código. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _startCooldown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _cooldown > 0) {
        setState(() => _cooldown--);
        _startCooldown();
      }
    });
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
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
        final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textColor),
              onPressed: () => context.pop(),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  const Text('📬', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 20),
                  Text(
                    'Código enviado',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 15, color: subtextColor, height: 1.5),
                      children: [
                        const TextSpan(text: 'Ingresa el código de 4 dígitos que enviamos a '),
                        TextSpan(
                          text: widget.email,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: GardenColors.primary),
                        ),
                        const TextSpan(text: '. Válido por 10 minutos.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Inputs 4 dígitos
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 60,
                        child: TextField(
                          controller: _ctrls[i],
                          focusNode: _nodes[i],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 1,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: surfaceEl,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: borderColor)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: GardenColors.primary, width: 2)),
                          ),
                          onChanged: (val) {
                            if (val.isNotEmpty && i < 3) {
                              _nodes[i + 1].requestFocus();
                            } else if (val.isEmpty && i > 0) {
                              _nodes[i - 1].requestFocus();
                            }
                            if (_code.length == 4) _verify();
                          },
                        ),
                      ),
                    )),
                  ),

                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    child: GardenButton(
                      label: 'Verificar código',
                      loading: _loading,
                      onPressed: _verify,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Reenviar código
                  Center(
                    child: _cooldown > 0
                        ? Text(
                            'Puedes reenviar en ${_cooldown}s',
                            style: TextStyle(color: subtextColor, fontSize: 13),
                          )
                        : TextButton(
                            onPressed: _resending ? null : _resend,
                            child: Text(
                              _resending ? 'Enviando...' : '¿No recibiste el código? Reenviar',
                              style: const TextStyle(color: GardenColors.primary, fontSize: 13),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

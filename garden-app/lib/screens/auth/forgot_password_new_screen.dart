import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';

class ForgotPasswordNewScreen extends StatefulWidget {
  final String tempToken;
  const ForgotPasswordNewScreen({super.key, required this.tempToken});
  @override
  State<ForgotPasswordNewScreen> createState() => _ForgotPasswordNewScreenState();
}

class _ForgotPasswordNewScreenState extends State<ForgotPasswordNewScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void initState() {
    super.initState();
    // Feedback en vivo: repinta el checklist de requisitos mientras se escribe.
    _passwordCtrl.addListener(() => setState(() {}));
  }

  bool get _hasMinLength => _passwordCtrl.text.length >= 8;
  bool get _passwordsMatch => _confirmCtrl.text.isNotEmpty && _confirmCtrl.text == _passwordCtrl.text;

  String get _baseUrl => const String.fromEnvironment(
        'API_URL',
        defaultValue: 'https://api.gardenbo.com/api',
      );

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pass = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pass.length < 8) {
      GardenSnackBar.warning(context, 'La contraseña debe tener al menos 8 caracteres');
      return;
    }
    if (pass != confirm) {
      GardenSnackBar.warning(context, 'Las contraseñas no coinciden');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/forgot-password/set-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'tempToken': widget.tempToken, 'newPassword': pass}),
      );
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        GardenSnackBar.success(context, '¡Contraseña actualizada! Ahora puedes iniciar sesión.');
        // Volver al login limpiando el stack
        context.go('/login');
      } else {
        GardenSnackBar.error(context, data['error']?['message'] as String? ?? 'No se pudo actualizar tu contraseña. Intenta de nuevo.');
      }
    } catch (_) {
      if (mounted) {
        GardenSnackBar.error(context, 'Error de conexión. Revisa tu internet e intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

        InputDecoration _field(String hint, IconData icon, bool obscure, VoidCallback toggle) =>
            InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: subtextColor),
              prefixIcon: Icon(icon, color: subtextColor, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: subtextColor,
                  size: 20,
                ),
                onPressed: toggle,
              ),
              filled: true,
              fillColor: surfaceEl,
              border: OutlineInputBorder(
                  borderRadius: GardenRadius.md_, borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: GardenRadius.md_, borderSide: BorderSide(color: borderColor)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: GardenRadius.md_,
                  borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: GardenSpacing.lg, vertical: 14),
            );

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            automaticallyImplyLeading: false,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🔐', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 20),
                  Text(
                    'Nueva contraseña',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Elige una contraseña segura con al menos 8 caracteres.',
                    style: TextStyle(fontSize: 15, color: subtextColor, height: 1.5),
                  ),
                  const SizedBox(height: 36),

                  Text('Contraseña',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscure1,
                    style: TextStyle(color: textColor),
                    decoration: _field(
                      '••••••••',
                      Icons.lock_outlined,
                      _obscure1,
                      () => setState(() => _obscure1 = !_obscure1),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        _hasMinLength ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 14,
                        color: _hasMinLength ? GardenColors.success : subtextColor,
                      ),
                      const SizedBox(width: 6),
                      Text('Al menos 8 caracteres',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _hasMinLength ? GardenColors.success : subtextColor,
                          )),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Text('Confirmar contraseña',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: _obscure2,
                    style: TextStyle(color: textColor),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                    decoration: _field(
                      '••••••••',
                      Icons.lock_outline,
                      _obscure2,
                      () => setState(() => _obscure2 = !_obscure2),
                    ),
                  ),
                  if (_confirmCtrl.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _passwordsMatch ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                          size: 14,
                          color: _passwordsMatch ? GardenColors.success : GardenColors.error,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _passwordsMatch ? 'Las contraseñas coinciden' : 'Las contraseñas no coinciden',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _passwordsMatch ? GardenColors.success : GardenColors.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: GardenButton(
                      label: 'Guardar contraseña',
                      loading: _loading,
                      onPressed: _submit,
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

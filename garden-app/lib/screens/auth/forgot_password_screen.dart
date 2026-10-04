import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../design/garden_icons.dart';
import '../../theme/garden_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _emailError;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String get _baseUrl => const String.fromEnvironment(
        'API_URL',
        defaultValue: 'https://api.gardenbo.com/api',
      );

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _emailError = 'Ingresa tu correo electrónico');
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      setState(() => _emailError = 'Ingresa un correo válido, ej: tu@correo.com');
      return;
    }
    setState(() { _loading = true; _emailError = null; });
    HapticFeedback.lightImpact();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/forgot-password/send-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      if (!mounted) return;
      // 2xx (incluso si el email no existe) → el API nunca revela si existe,
      // así que siempre avanzamos. Pero un error real (429 rate-limit, 5xx)
      // significa que ningún código fue enviado — no tiene sentido avanzar.
      if (res.statusCode >= 200 && res.statusCode < 300) {
        context.push('/forgot-password/code', extra: email);
      } else {
        Map<String, dynamic>? data;
        try { data = jsonDecode(res.body) as Map<String, dynamic>; } catch (_) {}
        GardenSnackBar.error(
          context,
          (data?['error'] as Map<String, dynamic>?)?['message'] as String? ??
              'No se pudo enviar el código. Intenta de nuevo.',
        );
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

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            leading: IconButton(
              icon: GardenIcon(GIcon.atras, color: textColor, semanticLabel: 'Volver'),
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
                  const GardenIcon(GIcon.seguridad, size: GIconSize.hero, color: GardenColors.primary, state: GIconState.active),
                  const SizedBox(height: 20),
                  Text(
                    'Recupera tu contraseña',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Ingresa tu correo y te enviaremos un código de 4 dígitos para restablecer tu contraseña.',
                    style: TextStyle(fontSize: 15, color: subtextColor, height: 1.5),
                  ),
                  const SizedBox(height: 36),

                  Text(
                    'Correo electrónico',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    style: TextStyle(color: textColor),
                    onChanged: (_) {
                      if (_emailError != null) setState(() => _emailError = null);
                    },
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'tu@correo.com',
                      hintStyle: TextStyle(color: subtextColor),
                      prefixIcon: Padding(padding: const EdgeInsets.all(12), child: GardenIcon(GIcon.correo, color: subtextColor)),
                      errorText: _emailError,
                      filled: true,
                      fillColor: surfaceEl,
                      border: OutlineInputBorder(
                          borderRadius: GardenRadius.md_, borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: GardenRadius.md_, borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: GardenRadius.md_,
                          borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
                      errorBorder: OutlineInputBorder(
                          borderRadius: GardenRadius.md_,
                          borderSide: const BorderSide(color: GardenColors.error, width: 1)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: GardenSpacing.lg, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    child: GardenButton(
                      label: 'Enviar código',
                      loading: _loading,
                      onPressed: _send,
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

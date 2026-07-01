import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_service.dart';
import '../../services/auth_state.dart';
import '../client/my_data_screen.dart';

class BecomeCaregiverScreen extends StatefulWidget {
  const BecomeCaregiverScreen({super.key});

  @override
  State<BecomeCaregiverScreen> createState() => _BecomeCaregiverScreenState();
}

class _BecomeCaregiverScreenState extends State<BecomeCaregiverScreen> {
  bool _isLoading = false;

  static const _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.gardenbo.com/api',
  );

  // ── Completeness check ─────────────────────────────────────────────────────

  bool _isClientDataIncomplete(Map<String, dynamic> u) {
    final phone = (u['phone'] as String? ?? '').trim();
    return (u['firstName'] as String? ?? '').trim().isEmpty ||
        (u['lastName'] as String? ?? '').trim().isEmpty ||
        !RegExp(r'^[67][0-9]{7}$').hasMatch(phone) ||
        (u['addressStreet'] as String? ?? '').trim().isEmpty ||
        (u['dateOfBirth'] == null);
  }

  List<String> _missingFields(Map<String, dynamic> u) {
    final missing = <String>[];
    final phone = (u['phone'] as String? ?? '').trim();
    if ((u['firstName'] as String? ?? '').trim().isEmpty) missing.add('Nombre');
    if ((u['lastName'] as String? ?? '').trim().isEmpty) missing.add('Apellido');
    if (!RegExp(r'^[67][0-9]{7}$').hasMatch(phone)) missing.add('Teléfono');
    if ((u['addressStreet'] as String? ?? '').trim().isEmpty) missing.add('Dirección');
    if (u['dateOfBirth'] == null) missing.add('Fecha de nacimiento');
    return missing;
  }

  // ── Open Mis Datos and retry on return ────────────────────────────────────

  Future<void> _openMisDatosAndRetry() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyDataScreen()),
    );
    // After returning from Mis Datos, retry the registration check
    if (mounted) _initAndStart();
  }

  // ── Show incomplete-profile dialog ────────────────────────────────────────

  void _showIncompleteDialog(List<String> missing) {
    final isDark = themeNotifier.isDark;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.xl)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: GardenColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(GardenRadius.sm),
              ),
              child: Icon(Icons.person_outline_rounded, color: GardenColors.warning, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Completa tus datos primero',
                style: GardenText.labelLarge.copyWith(
                  color: isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Para convertirte en cuidador necesitas tener tu perfil de dueño completo.',
              style: GardenText.body.copyWith(
                color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            ...missing.map((field) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.cancel_outlined, size: 16, color: GardenColors.error),
                  const SizedBox(width: 8),
                  Text(
                    field,
                    style: GardenText.body.copyWith(
                      color: isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancelar',
              style: TextStyle(color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: GardenColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.md)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _openMisDatosAndRetry();
            },
            child: const Text('Completar Mis Datos'),
          ),
        ],
      ),
    );
  }

  // ── Main flow ─────────────────────────────────────────────────────────────

  Future<void> _initAndStart() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final token = AuthState.token;
      if (token.isEmpty) {
        // Visitante sin sesión — directo al registro exclusivo de cuidador
        // (sin selector de rol, sin pasar por login). Esta es la única
        // puerta de entrada al registro de cuidador nuevo en toda la app.
        if (!mounted) return;
        context.go('/register', extra: {'caregiverOnly': true});
        return;
      }

      // Step 1: fetch user profile to check completeness before proceeding
      final meResponse = await http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (meResponse.statusCode == 401) {
        // Sesión expirada/inválida — no es un problema de red. Dispara el
        // flujo global de sesión expirada (limpia tokens + redirige a login
        // con el mensaje correcto) en vez de mostrar "error de conexión".
        AuthState.handleUnauthorized();
        return;
      }

      if (meResponse.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión. Verifica tu internet.'), backgroundColor: GardenColors.error),
        );
        return;
      }

      final meData = jsonDecode(meResponse.body) as Map<String, dynamic>;
      final userData = meData['data'] as Map<String, dynamic>? ?? {};

      if (_isClientDataIncomplete(userData)) {
        final missing = _missingFields(userData);
        _showIncompleteDialog(missing);
        return;
      }

      // Step 2: profile is complete — proceed with caregiver registration
      final prefs = await SharedPreferences.getInstance();

      final response = await http.post(
        Uri.parse('$_baseUrl/auth/init-caregiver-profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 401) {
        AuthState.handleUnauthorized();
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        final result = data['data'] as Map<String, dynamic>;
        final authService = AuthService();
        await authService.saveToken(result['accessToken'] as String);
        await authService.saveRefreshToken(result['refreshToken'] as String);
        await prefs.setString('user_role', 'CAREGIVER');
        await prefs.remove('active_role');
        await prefs.setBool('client_conversion_in_progress', true);

        if (!mounted) return;
        context.go('/caregiver/onboarding', extra: {'clientConversionMode': true});
      } else {
        final errorCode = (data['error'] as Map<String, dynamic>?)?['code'] as String? ?? '';
        if (errorCode == 'CAREGIVER_PROFILE_EXISTS') {
          if (!mounted) return;
          context.go('/caregiver/onboarding', extra: {'resumeMode': true});
          return;
        }
        final msg = (data['error'] as Map<String, dynamic>?)?['message']
            ?? 'No se pudo iniciar el proceso. Intenta de nuevo.';
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: GardenColors.error),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error de conexión. Verifica tu internet.'),
          backgroundColor: GardenColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      appBar: kIsWeb ? null : AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: isDark ? GardenColors.darkTextHint : GardenColors.lightTextHint, size: 18),
          onPressed: () => context.go('/'),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(GardenRadius.sm),
              ),
              child: const Icon(Icons.pets, color: GardenColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Conviértete en Cuidador',
                style: GardenText.h4.copyWith(color: textColor)),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (kIsWeb)
            Container(
              height: 52,
              decoration: BoxDecoration(color: surface, border: Border(bottom: BorderSide(color: borderColor))),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  IconButton(icon: Icon(Icons.arrow_back_rounded, color: textColor, size: 18), onPressed: () => context.go('/')),
                  const SizedBox(width: 6),
                  Text('Conviértete en Cuidador', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: kIsWeb ? 520.0 : double.infinity),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero card ──────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    GardenColors.primary.withValues(alpha: 0.08),
                    GardenColors.lime.withValues(alpha: 0.30),
                  ],
                ),
                borderRadius: BorderRadius.circular(GardenRadius.xl),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.14)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [GardenColors.primary, GardenColors.lime],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: GardenColors.primary.withValues(alpha: 0.30),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 34),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Cuida mascotas y\ngana dinero extra',
                    style: GardenText.h3.copyWith(color: textColor, height: 1.3),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Únete a la comunidad de cuidadores de GARDEN y ofrece tus servicios a dueños de mascotas cerca de ti.',
                    style: GardenText.body.copyWith(color: subtextColor, height: 1.55),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),
            Text('¿Qué puedes hacer como cuidador?',
                style: GardenText.labelLarge.copyWith(color: textColor, fontSize: 14)),
            const SizedBox(height: 14),

            // ── Benefit bullets ────────────────────────────────────────
            _benefit(
              icon: Icons.monetization_on_outlined,
              title: 'Genera ingresos',
              desc: 'Cobra por paseos, guardería y hospedaje a tu propio precio.',
              surface: surface, border: borderColor, text: textColor, sub: subtextColor,
            ),
            _benefit(
              icon: Icons.schedule_outlined,
              title: 'Tú eliges cuándo trabajas',
              desc: 'Configura tu disponibilidad según tu horario y acepta solo las reservas que quieras.',
              surface: surface, border: borderColor, text: textColor, sub: subtextColor,
            ),
            _benefit(
              icon: Icons.verified_user_outlined,
              title: 'Perfil verificado',
              desc: 'Tu cuenta ya tiene los datos básicos. Solo completa la información de cuidador y la verificación.',
              surface: surface, border: borderColor, text: textColor, sub: subtextColor,
            ),
            _benefit(
              icon: Icons.swap_horiz_rounded,
              title: 'Cambia de modo cuando quieras',
              desc: 'Puedes alternar entre modo dueño y modo cuidador en cualquier momento desde tu perfil.',
              surface: surface, border: borderColor, text: textColor, sub: subtextColor,
            ),

            const SizedBox(height: 32),

            // ── CTA ────────────────────────────────────────────────────
            GardenButton(
              label: _isLoading ? 'Verificando...' : 'Comenzar registro',
              loading: _isLoading,
              onPressed: _initAndStart,
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Tu cuenta de dueño se mantiene. Puedes volver a ella en cualquier momento.',
                style: TextStyle(
                  color: subtextColor,
                  fontSize: 12,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
        )),
      )),
        ],
      ),
    );
  }

  Widget _benefit({
    required IconData icon,
    required String title,
    required String desc,
    required Color surface,
    required Color border,
    required Color text,
    required Color sub,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(GardenRadius.md),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(GardenRadius.sm),
              ),
              child: Icon(icon, color: GardenColors.primary, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: text, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 3),
                  Text(desc,
                      style: TextStyle(
                          color: sub, fontSize: 12, height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

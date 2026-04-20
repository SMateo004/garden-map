import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_service.dart';

class BecomeCaregiverScreen extends StatefulWidget {
  const BecomeCaregiverScreen({super.key});

  @override
  State<BecomeCaregiverScreen> createState() => _BecomeCaregiverScreenState();
}

class _BecomeCaregiverScreenState extends State<BecomeCaregiverScreen> {
  bool _isLoading = false;

  static const _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://garden-api-1ldd.onrender.com/api',
  );

  Future<void> _initAndStart() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      if (token.isEmpty) {
        context.go('/login');
        return;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/auth/init-caregiver-profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        final result = data['data'] as Map<String, dynamic>;
        final authService = AuthService();
        await authService.saveToken(result['accessToken'] as String);
        await authService.saveRefreshToken(result['refreshToken'] as String);
        await prefs.setString('user_role', 'CAREGIVER');
        await prefs.remove('active_role');

        if (!mounted) return;
        context.go('/caregiver/onboarding', extra: {'clientConversionMode': true});
      } else {
        final errorCode = (data['error'] as Map<String, dynamic>?)?['code'] as String? ?? '';
        // Ya tiene perfil de cuidador (registro previo incompleto) → retomar wizard
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
        SnackBar(
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
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: isDark ? GardenColors.darkTextHint : GardenColors.lightTextHint, size: 18),
          onPressed: () => context.pop(),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
              label: _isLoading ? 'Iniciando...' : 'Comenzar registro',
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

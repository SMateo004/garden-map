import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_service.dart';
import '../../services/fcm_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa tu correo y contraseña')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authService.login(email: email, password: password);
      if (!mounted) return;
      // Register FCM token now that the user is authenticated
      FcmService.registerAfterLogin();
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? '';
      if (!mounted) return;
      if (role == 'ADMIN') {
        context.go('/admin');
      } else if (role == 'CLIENT') {
        if (kIsWeb) {
          context.go('/marketplace');
        } else {
          context.go('/service-selector');
        }
      } else if (role == 'CAREGIVER') context.go('/caregiver/home');
      else context.go('/test');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 800;
            if (isWide) {
              return Row(
                children: [
                  // Panel izquierdo visual
                  Expanded(
                    child: _buildVisualPanel(),
                  ),
                  // Panel derecho formulario
                  Expanded(
                    child: _buildFormPanel(surface, textColor, subtextColor, borderColor, isDark),
                  ),
                ],
              );
            }
            return _buildFormPanel(surface, textColor, subtextColor, borderColor, isDark);
          },
        ),
      ),
    );
  }

  Widget _buildVisualPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GardenColors.primaryDark, Color(0xFF0D1A07)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.06,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 1,
                ),
                itemCount: 50,
                itemBuilder: (_, __) => const Icon(Icons.eco_rounded, color: Colors.white, size: 32),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: GardenColors.primary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: const Icon(Icons.pets, color: GardenColors.accent, size: 40),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'GARDEN',
                    style: GardenText.h2.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Cuidado profesional\nverificado para\ntu mascota',
                    style: GardenText.h4.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 48),
                  _statRow('200K+', 'mascotas cuidadas'),
                  const SizedBox(height: 16),
                  _statRow('98.5%', 'verificación IA'),
                  const SizedBox(height: 16),
                  _statRow('Polygon', 'blockchain seguro'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String value, String label) {
    return Row(
      children: [
        Container(
          width: 4, height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: GardenText.h4.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            Text(label, style: GardenText.metadata.copyWith(color: Colors.white.withValues(alpha: 0.70))),
          ],
        ),
      ],
    );
  }

  Widget _buildFormPanel(Color surface, Color textColor, Color subtextColor, Color borderColor, bool isDark) {
    return Center(
      child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => context.go('/'),
                child: Text(
                  'GARDEN',
                  style: GardenText.h3.copyWith(
                    color: GardenColors.primary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.arrow_back_rounded, size: 16, color: GardenColors.primary),
                label: Text('Volver', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w500)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
            ],
          ),
          const SizedBox(height: 48),
          Text('Bienvenido de nuevo', style: GardenText.h3.copyWith(color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text('Inicia sesión para gestionar tus reservas', style: GardenText.body.copyWith(color: subtextColor, fontSize: 15)),
          const SizedBox(height: 40),

          // Campo email
          Text('Correo electrónico', style: GardenText.metadata.copyWith(color: textColor, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: 'tu@email.com',
              hintStyle: TextStyle(color: subtextColor),
              prefixIcon: Icon(Icons.email_outlined, color: subtextColor, size: 20),
              filled: true,
              fillColor: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 20),

          // Campo contraseña
          Text('Contraseña', style: GardenText.metadata.copyWith(color: textColor, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: TextStyle(color: textColor),
            onSubmitted: (_) => _handleLogin(),
            decoration: InputDecoration(
              hintText: '••••••••',
              hintStyle: TextStyle(color: subtextColor),
              prefixIcon: Icon(Icons.lock_outlined, color: subtextColor, size: 20),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: subtextColor, size: 20),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              filled: true,
              fillColor: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 32),

          // Botón login
          GardenButton(
            label: 'Iniciar sesión',
            loading: _isLoading,
            onPressed: _handleLogin,
          ),
          const SizedBox(height: 20),

          // Divisor
          Row(
            children: [
              Expanded(child: Divider(color: borderColor)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('o', style: TextStyle(color: subtextColor, fontSize: 13)),
              ),
              Expanded(child: Divider(color: borderColor)),
            ],
          ),
          const SizedBox(height: 20),

          // Botón explorar sin login (solo web)
          if (kIsWeb) GardenButton(
            label: 'Explorar cuidadores',
            outline: true,
            icon: Icons.search,
            onPressed: () => context.go('/marketplace'),
          ),
          const SizedBox(height: 24),

          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('¿No tienes cuenta? ', style: GardenText.metadata.copyWith(color: subtextColor, fontSize: 14)),
                GestureDetector(
                  onTap: () => context.go('/register'),
                  child: Text('Regístrate', style: GardenText.metadata.copyWith(color: GardenColors.primary, fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
      ),
    );
  }
}

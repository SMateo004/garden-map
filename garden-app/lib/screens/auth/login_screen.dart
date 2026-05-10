import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_service.dart';
import '../../services/fcm_service.dart';
import '../../services/social_auth_service.dart';

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

  void _navigateAfterLogin(String role) {
    FcmService.registerAfterLogin();
    if (role == 'ADMIN') {
      context.go('/admin');
    } else if (role == 'CLIENT') {
      kIsWeb ? context.go('/marketplace') : context.go('/service-selector');
    } else if (role == 'CAREGIVER') {
      context.go('/caregiver/home');
    } else {
      context.go('/marketplace');
    }
  }

  void _handleSocialResult(SocialLoginResult result) {
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.error ?? 'Error al iniciar sesión'),
        backgroundColor: GardenColors.error,
      ));
      return;
    }
    if (result.userExists) {
      _navigateAfterLogin(result.role ?? 'CLIENT');
    } else {
      // Email no registrado → ir al registro pre-llenado
      final d = result.userData;
      context.push('/register', extra: {
        'firstName': d?.firstName ?? '',
        'lastName': d?.lastName ?? '',
        'email': d?.email ?? '',
        'fromSocial': true,
      });
    }
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
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? '';
      if (!mounted) return;
      _navigateAfterLogin(role);
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
                  Image.asset('assets/images/logo-white.png', height: 129),
                  const SizedBox(height: 32),
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
            color: Colors.white.withValues(alpha: 0.6),
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
                child: Image.asset('assets/images/logo-horizontal.png', height: 89),
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
                child: Text('o continúa con', style: TextStyle(color: subtextColor, fontSize: 13)),
              ),
              Expanded(child: Divider(color: borderColor)),
            ],
          ),
          const SizedBox(height: 16),

          // Botones de login social
          _SocialLoginButtons(
            onResult: (result) => _handleSocialResult(result),
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

// ── Botones de login social reutilizables ────────────────────────────────────
class _SocialLoginButtons extends StatefulWidget {
  final void Function(SocialLoginResult) onResult;
  const _SocialLoginButtons({required this.onResult});

  @override
  State<_SocialLoginButtons> createState() => _SocialLoginButtonsState();
}

class _SocialLoginButtonsState extends State<_SocialLoginButtons> {
  SocialProvider? _loading;

  Future<void> _handleProvider(SocialProvider provider) async {
    setState(() => _loading = provider);
    try {
      SocialUserData? data;
      if (provider == SocialProvider.google) {
        data = await SocialAuthService.signInWithGoogle();
      } else if (provider == SocialProvider.apple) {
        data = await SocialAuthService.signInWithApple();
      } else {
        data = await SocialAuthService.signInWithFacebook();
      }

      if (data == null) return; // user cancelled

      final result = await SocialAuthService.loginWithBackend(data);
      if (mounted) widget.onResult(result);
    } catch (e) {
      if (mounted) {
        widget.onResult(SocialLoginResult(
          success: false,
          userExists: false,
          error: e.toString().replaceFirst('Exception: ', ''),
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SocialBtn(
          label: 'Continuar con Google',
          loading: _loading == SocialProvider.google,
          onTap: () => _handleProvider(SocialProvider.google),
        ),
        const SizedBox(height: 10),
        _SocialBtn(
          label: 'Continuar con Apple',
          loading: _loading == SocialProvider.apple,
          onTap: () => _handleProvider(SocialProvider.apple),
        ),
        const SizedBox(height: 10),
        _SocialBtn(
          label: 'Continuar con Facebook',
          loading: _loading == SocialProvider.facebook,
          onTap: () => _handleProvider(SocialProvider.facebook),
        ),
      ],
    );
  }
}

class _SocialBtn extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _SocialBtn({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final textColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return SizedBox(
      width: double.infinity,
      height: 46,
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: GardenColors.primary),
                )
              : Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                  ),
                ),
        ),
      ),
    );
  }
}

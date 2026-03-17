import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
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
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? '';
      if (!mounted) return;
      if (role == 'ADMIN') context.go('/admin');
      else if (role == 'CLIENT') context.go('/marketplace');
      else if (role == 'CAREGIVER') context.go('/caregiver/home');
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
          colors: [Color(0xFFFF6B35), Color(0xFFFF4500)],
        ),
      ),
      child: Stack(
        children: [
          // Patrón de fondo con íconos de mascotas
          Positioned.fill(
            child: Opacity(
              opacity: 0.08,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 1,
                ),
                itemCount: 50,
                itemBuilder: (_, __) => const Icon(Icons.pets, color: Colors.white, size: 32),
              ),
            ),
          ),
          // Contenido central
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
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.pets, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'GARDEN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Cuidado profesional\nverificado para\ntu mascota',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Stats
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
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
          ],
        ),
      ],
    );
  }

  Widget _buildFormPanel(Color surface, Color textColor, Color subtextColor, Color borderColor, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle tema
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // En móvil muestra logo, en desktop está en el panel izquierdo
              LayoutBuilder(
                builder: (context, constraints) {
                  return Text(
                    'GARDEN',
                    style: TextStyle(
                      color: GardenColors.primary,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  );
                },
              ),
              IconButton(
                icon: Icon(
                  themeNotifier.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: subtextColor,
                ),
                onPressed: () => themeNotifier.toggle(),
              ),
            ],
          ),
          const SizedBox(height: 48),
          Text('Bienvenido de nuevo', style: TextStyle(color: textColor, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text('Inicia sesión para gestionar tus reservas', style: TextStyle(color: subtextColor, fontSize: 15)),
          const SizedBox(height: 40),

          // Campo email
          Text('Correo electrónico', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
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
          Text('Contraseña', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
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

          // Botón explorar sin login
          GardenButton(
            label: 'Explorar cuidadores',
            outline: true,
            icon: Icons.search,
            onPressed: () => context.go('/marketplace'),
          ),
          const SizedBox(height: 24),

          // Link registro
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('¿No tienes cuenta? ', style: TextStyle(color: subtextColor, fontSize: 14)),
                GestureDetector(
                  onTap: () => context.go('/register'),
                  child: Text('Regístrate', style: TextStyle(color: GardenColors.primary, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

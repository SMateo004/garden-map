import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController  = TextEditingController();
  final _emailController     = TextEditingController();
  final _passwordController  = TextEditingController();
  final _phoneController     = TextEditingController();
  final _authService         = AuthService();
  bool _isLoading            = false;
  bool _obscurePassword      = true;
  String _selectedRole       = 'owner'; // 'owner' o 'caregiver'

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _handleRegister() async {
    if (_selectedRole == 'caregiver') {
      context.go('/caregiver/onboarding', extra: {'email': '', 'password': ''});
      return;
    }

    final firstName = _firstNameController.text.trim();
    final lastName  = _lastNameController.text.trim();
    final email     = _emailController.text.trim();
    final password  = _passwordController.text;
    final phone     = _phoneController.text.trim();

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos')),
      );
      return;
    }
    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La contraseña debe tener al menos 8 caracteres')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_selectedRole == 'owner') {
        await _authService.registerClient(
          firstName: firstName, lastName: lastName, email: email, password: password, phone: phone,
        );
        if (!mounted) return;
        if (kIsWeb) {
          context.go('/client-welcome');
        } else {
          context.go('/service-selector');
        }
      }
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
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
        final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

        return Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: _buildVisualPanel()),
                      Expanded(child: _buildFormPanel(bg, surface, surfaceEl, textColor, subtextColor, borderColor, isDark)),
                    ],
                  );
                }
                return _buildFormPanel(bg, surface, surfaceEl, textColor, subtextColor, borderColor, isDark);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildVisualPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1F2E), Color(0xFF0A0E1A)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.05,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5),
                itemCount: 50,
                itemBuilder: (_, __) => const Icon(Icons.pets, color: Colors.white, size: 32),
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
                      color: GardenColors.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.pets, color: GardenColors.primary, size: 40),
                  ),
                  const SizedBox(height: 32),
                  const Text('Únete a\nGARDEN',
                    style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -1, height: 1.1)),
                  const SizedBox(height: 16),
                  Text('La plataforma de cuidado\nde mascotas más segura\nde Santa Cruz',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16, height: 1.6)),
                  const SizedBox(height: 48),
                  _featureRow(Icons.verified_user_outlined, 'Verificación IA + Blockchain'),
                  const SizedBox(height: 16),
                  _featureRow(Icons.shield_outlined, 'Pagos protegidos con escrow'),
                  const SizedBox(height: 16),
                  _featureRow(Icons.star_outline_rounded, 'Calificaciones verificadas'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: GardenColors.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: GardenColors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildFormPanel(Color bg, Color surface, Color surfaceEl, Color textColor, Color subtextColor, Color borderColor, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('GARDEN', style: TextStyle(color: GardenColors.primary, fontSize: 24, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 40),
          Text('Crear cuenta', style: TextStyle(color: textColor, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text('Únete a la comunidad GARDEN', style: TextStyle(color: subtextColor, fontSize: 15)),
          const SizedBox(height: 32),

          // Selector de rol
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: surfaceEl,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(child: _rolePill('Soy dueño 🐾', 'owner', textColor, subtextColor)),
                Expanded(child: _rolePill('Soy cuidador 🏠', 'caregiver', textColor, subtextColor)),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Introducción para cuidadores
          if (_selectedRole == 'caregiver') ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: GardenColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: GardenColors.primary.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: GardenColors.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.home_outlined, color: GardenColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Conviértete en cuidador',
                          style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _introItem(Icons.verified_user_outlined, 'Verificación de identidad con IA', subtextColor),
                  const SizedBox(height: 8),
                  _introItem(Icons.payments_outlined, 'Pagos seguros con escrow blockchain', subtextColor),
                  const SizedBox(height: 8),
                  _introItem(Icons.calendar_month_outlined, 'Gestiona tu disponibilidad fácilmente', subtextColor),
                  const SizedBox(height: 8),
                  _introItem(Icons.star_outline_rounded, 'Construye tu reputación verificada', subtextColor),
                  const SizedBox(height: 12),
                  Text('Después de crear tu cuenta completarás tu perfil de cuidador con fotos, servicios y precios.',
                    style: TextStyle(color: subtextColor, fontSize: 12, height: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Campos solo para dueños
          if (_selectedRole == 'owner') ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fieldLabel('Nombre', textColor),
                      const SizedBox(height: 8),
                      _textField(controller: _firstNameController, hint: 'Tu nombre', icon: Icons.person_outlined, surfaceEl: surfaceEl, textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fieldLabel('Apellido', textColor),
                      const SizedBox(height: 8),
                      _textField(controller: _lastNameController, hint: 'Tu apellido', icon: Icons.person_outline, surfaceEl: surfaceEl, textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _fieldLabel('Correo electrónico', textColor),
            const SizedBox(height: 8),
            _textField(controller: _emailController, hint: 'tu@email.com', icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress, surfaceEl: surfaceEl, textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
            const SizedBox(height: 20),

            _fieldLabel('Contraseña', textColor),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                hintText: '••••••••',
                hintStyle: TextStyle(color: subtextColor),
                prefixIcon: Icon(Icons.lock_outlined, color: subtextColor, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: subtextColor, size: 20),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                filled: true, fillColor: surfaceEl,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 20),

            _fieldLabel('Teléfono boliviano', textColor),
            const SizedBox(height: 8),
            _textField(controller: _phoneController, hint: '76543210', icon: Icons.phone_outlined, keyboardType: TextInputType.phone, surfaceEl: surfaceEl, textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
            const SizedBox(height: 8),
            Text('8 dígitos, empieza con 6 o 7', style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(height: 32),
          ],

          // Botón registro
          GardenButton(
            label: _selectedRole == 'caregiver' ? 'Comenzar como cuidador →' : 'Crear cuenta',
            loading: _isLoading,
            onPressed: _handleRegister,
          ),
          const SizedBox(height: 24),

          // Link login
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('¿Ya tienes cuenta? ', style: TextStyle(color: subtextColor, fontSize: 14)),
                GestureDetector(
                  onTap: () => context.go('/login'),
                  child: const Text('Inicia sesión', style: TextStyle(color: GardenColors.primary, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rolePill(String label, String role, Color textColor, Color subtextColor) {
    final selected = _selectedRole == role;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? GardenColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected ? [BoxShadow(color: GardenColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Center(
          child: Text(label, style: TextStyle(
            color: selected ? Colors.white : subtextColor,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            fontSize: 14,
          )),
        ),
      ),
    );
  }

  Widget _introItem(IconData icon, String text, Color subtextColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: GardenColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(color: subtextColor, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _fieldLabel(String label, Color textColor) =>
    Text(label, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600));

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color surfaceEl,
    required Color textColor,
    required Color subtextColor,
    required Color borderColor,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: subtextColor),
        prefixIcon: Icon(icon, color: subtextColor, size: 20),
        filled: true, fillColor: surfaceEl,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String _token = '';
  String _role = '';
  Map<String, dynamic>? _caregiverProfile;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _token = prefs.getString('access_token') ?? '';
      _role = prefs.getString('user_role') ?? '';
    });
    if (_token.isNotEmpty) {
      await _loadProfile();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _userData = data['data'];
            _role = _userData?['role'] ?? _role;
          });

          // Si es CAREGIVER, cargar también el perfil profesional
          if (_role == 'CAREGIVER') {
            try {
              final profileResponse = await http.get(
                Uri.parse('$_baseUrl/caregiver/my-profile'),
                headers: {'Authorization': 'Bearer $_token'},
              );
              final profileData = jsonDecode(profileResponse.body);
              if (profileData['success'] == true) {
                setState(() => _caregiverProfile = profileData['data']);
              }
            } catch (e) {
              debugPrint('Error loading caregiver profile: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendVerificationEmail() async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/caregiver/send-verify-email'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (data['success'] == true) {
        // Mostrar dialog para ingresar el código
        _showVerifyCodeDialog(_token, _baseUrl);
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al enviar correo');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error),
      );
    }
  }

  void _showVerifyCodeDialog(String token, String baseUrl) {
    final codeController = TextEditingController();
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = themeNotifier.isDark;
          final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
          final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
          final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

          return Dialog(
            backgroundColor: surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: GardenColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mark_email_read_outlined, color: GardenColors.primary, size: 28),
                  ),
                  const SizedBox(height: 16),
                  Text('Verifica tu correo',
                    style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Te enviamos un código de verificación. Ingrésalo a continuación.',
                    style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      hintText: '000000',
                      hintStyle: TextStyle(color: subtextColor, letterSpacing: 8),
                      counterText: '',
                      filled: true,
                      fillColor: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: GardenColors.primary, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 20),
                  GardenButton(
                    label: isVerifying ? 'Verificando...' : 'Confirmar código',
                    loading: isVerifying,
                    onPressed: () async {
                      final code = codeController.text.trim();
                      if (code.length < 4) return;
                      setDialogState(() => isVerifying = true);
                      try {
                        final response = await http.post(
                          Uri.parse('$baseUrl/caregiver/verify-email'),
                          headers: {
                            'Authorization': 'Bearer $token',
                            'Content-Type': 'application/json',
                          },
                          body: jsonEncode({'code': code}),
                        );
                        final data = jsonDecode(response.body);
                        if (!mounted) return;
                        if (data['success'] == true) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Correo verificado correctamente'),
                              backgroundColor: GardenColors.success,
                            ),
                          );
                          // Recargar el perfil para actualizar el estado
                          _loadProfile();
                        } else {
                          setDialogState(() => isVerifying = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(data['error']?['message'] ?? 'Código incorrecto'),
                              backgroundColor: GardenColors.error,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isVerifying = false);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Cancelar', style: TextStyle(color: subtextColor)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) context.go('/marketplace');
  }

  Widget _profileTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        tileColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(icon, color: GardenColors.primary),
        title: Text(title, style: TextStyle(color: theme.colorScheme.onSurface)),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Mi perfil'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          if (_token.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _logout,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _token.isEmpty || _userData == null
                  ? _buildUnauthenticatedState()
                  : _buildAuthenticatedState(),
            ),
    );
  }

  Widget _buildUnauthenticatedState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.person_outline, size: 80, color: GardenColors.primary),
          const SizedBox(height: 16),
          const Text('Inicia sesión para ver tu perfil',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Gestiona tus reservas, mascotas y configuración',
              style: TextStyle(color: GardenColors.darkTextSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 32),
          GardenButton(label: 'Iniciar sesión', onPressed: () => context.push('/login')),
          const SizedBox(height: 12),
          GardenButton(label: 'Registrarse', outline: true, onPressed: () => context.push('/register')),
        ],
      ),
    );
  }

  Widget _buildAuthenticatedState() {
    final theme = Theme.of(context);
    final user = _userData!;
    
    String roleLabel = 'Usuario';
    Color roleColor = GardenColors.primary;
    if (_role == 'CLIENT') {
      roleLabel = 'Dueño de mascota';
      roleColor = Colors.green;
    } else if (_role == 'CAREGIVER') {
      roleLabel = 'Cuidador';
      roleColor = GardenColors.primary;
    } else if (_role == 'ADMIN') {
      roleLabel = 'Administrador';
      roleColor = Colors.blue;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            GardenAvatar(
              imageUrl: user['profilePicture'],
              size: 80,
              initials: '${user['firstName']} ${user['lastName']}',
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${user['firstName']} ${user['lastName']}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  // Fila unificada de email y verificación
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.email_outlined, size: 14, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                      const SizedBox(width: 8),
                      Text(
                        user['email'] as String? ?? '',
                        style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13),
                      ),
                      const SizedBox(width: 10),
                      if (user['emailVerified'] != true)
                        GestureDetector(
                          onTap: _sendVerificationEmail,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: GardenColors.warning.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: GardenColors.warning.withOpacity(0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.mark_email_unread_outlined, size: 12, color: GardenColors.warning),
                                const SizedBox(width: 4),
                                const Text('Verificar',
                                  style: TextStyle(color: GardenColors.warning, fontSize: 11, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      if (user['emailVerified'] == true)
                        const Icon(Icons.verified_outlined, size: 16, color: GardenColors.success),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: roleColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(roleLabel,
                        style: TextStyle(color: roleColor, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        
        const Text('Mi cuenta', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        
        if (_role == 'CLIENT') ...[
          _profileTile(icon: Icons.pets, title: 'Mis mascotas', onTap: () => context.push('/my-pets')),
          _profileTile(icon: Icons.calendar_today, title: 'Mis reservas', onTap: () => context.push('/my-bookings')),
          _profileTile(icon: Icons.star_outline, title: 'Mis calificaciones', 
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Próximamente')))),
          _profileTile(icon: Icons.account_balance_wallet_outlined, title: 'Mi billetera', onTap: () => context.push('/wallet')),
        ],
        
        if (_role == 'CAREGIVER') ...[
          _profileTile(
            icon: Icons.assignment_outlined,
            title: 'Datos del cuidador',
            onTap: () => context.push('/caregiver/profile-data'),
          ),
          _profileTile(icon: Icons.edit_outlined, title: 'Editar perfil', onTap: () => context.push('/caregiver/edit-profile')),
          _profileTile(icon: Icons.home_outlined, title: 'Mi panel', onTap: () => context.push('/caregiver/home')),
          // Solo mostrar si no está verificado (NI por admin, NI el perfil completo, NI por IA)
          if (_caregiverProfile?['verified'] != true && 
              _caregiverProfile?['verificationStatus'] != 'VERIFIED' &&
              _caregiverProfile?['identityVerificationStatus'] != 'VERIFIED')
            _profileTile(icon: Icons.verified_user_outlined, title: 'Verificación IA', onTap: () => context.push('/caregiver/verification')),
          _profileTile(icon: Icons.calendar_month, title: 'Mi disponibilidad', onTap: () => context.push('/caregiver/home')),
          _profileTile(icon: Icons.account_balance_wallet_outlined, title: 'Mi billetera', onTap: () => context.push('/wallet')),
        ],
        
        if (_role == 'ADMIN') ...[
          _profileTile(icon: Icons.admin_panel_settings, title: 'Panel admin', onTap: () => context.push('/admin')),
        ],

        const SizedBox(height: 24),
        const Text('Preferencias', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            tileColor: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(
              themeNotifier.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              color: GardenColors.primary,
            ),
            title: Text('Modo oscuro', style: TextStyle(color: theme.colorScheme.onSurface)),
            trailing: Switch(
              value: themeNotifier.isDark,
              onChanged: (_) => themeNotifier.toggle(),
              activeColor: GardenColors.primary,
            ),
          ),
        ),
        
        _profileTile(icon: Icons.notifications_outlined, title: 'Notificaciones', 
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Próximamente')))),
        
        const SizedBox(height: 40),
        GardenButton(
          label: 'Cerrar sesión',
          outline: true,
          color: GardenColors.error,
          onPressed: _logout,
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../services/language_service.dart';
import '../client/my_data_screen.dart';
import '../client/my_ratings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _isDeletingAccount = false;
  String _token = '';
  String _role = '';
  Map<String, dynamic>? _caregiverProfile;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

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


  void _showLanguageSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AnimatedBuilder(
        animation: languageNotifier,
        builder: (context, _) {
          final isDark = themeNotifier.isDark;
          final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
          final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
          final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

          return GlassBox(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 20),
                Text('Idioma', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Solo cambia las etiquetas de la app', style: TextStyle(color: subtextColor, fontSize: 13)),
                const SizedBox(height: 20),
                for (final lang in AppLanguage.values)
                  _langOption(lang, textColor, subtextColor, ctx),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _langOption(AppLanguage lang, Color textColor, Color subtextColor, BuildContext sheetCtx) {
    final labels = {AppLanguage.es: ('🇧🇴', 'Español'), AppLanguage.en: ('🇺🇸', 'English'), AppLanguage.pt: ('🇧🇷', 'Português')};
    final (flag, name) = labels[lang]!;
    final selected = languageNotifier.language == lang;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Text(flag, style: const TextStyle(fontSize: 28)),
      title: Text(name, style: TextStyle(color: textColor, fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
      trailing: selected ? const Icon(Icons.check_circle_rounded, color: GardenColors.primary) : null,
      onTap: () {
        languageNotifier.setLanguage(lang);
        Navigator.pop(sheetCtx);
      },
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('user_role');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_photo');
    if (mounted) context.go('/login');
  }

  Future<void> _deleteAccount() async {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final passwordController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: GardenColors.error.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.delete_forever_outlined, color: GardenColors.error, size: 28),
                ),
                const SizedBox(height: 16),
                Text('Eliminar cuenta', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'Esta acción es irreversible. Perderás tus calificaciones, historial y cualquier saldo en tu billetera (transferido a Garden).\n\nIngresa tu contraseña para confirmar.',
                  style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Contraseña',
                    hintStyle: TextStyle(color: subtextColor),
                    filled: true,
                    fillColor: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.error, width: 2)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancelar', style: TextStyle(color: subtextColor)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GardenColors.error,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Eliminar', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final password = passwordController.text.trim();
    if (password.isEmpty) return;

    setState(() => _isDeletingAccount = true);
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/auth/account'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'password': password}),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (mounted) context.go('/login');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?['message'] ?? 'Error al eliminar la cuenta'), backgroundColor: GardenColors.error),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de conexión: $e'), backgroundColor: GardenColors.error),
      );
    } finally {
      if (mounted) setState(() => _isDeletingAccount = false);
    }
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

  Widget _buildAccountInfoTile() {
    final theme = Theme.of(context);
    final isDark = themeNotifier.isDark;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final user = _userData;
    if (user == null) return const SizedBox.shrink();

    String createdAt = '';
    try {
      final dt = DateTime.parse(user['createdAt'] as String? ?? '').toLocal();
      createdAt = '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {}

    final walletAddress = user['walletAddress'] as String? ??
        (_caregiverProfile?['walletAddress'] as String?) ?? '';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _infoRow(Icons.calendar_today_outlined, 'Miembro desde', createdAt.isNotEmpty ? createdAt : 'N/A', subtextColor),
          if (walletAddress.isNotEmpty) ...[
            Divider(height: 1, color: theme.dividerColor),
            _infoRow(Icons.account_balance_wallet_outlined, 'Wallet blockchain', '${walletAddress.substring(0, 6)}...${walletAddress.substring(walletAddress.length - 4)}', subtextColor),
          ],
          Divider(height: 1, color: theme.dividerColor),
          _infoRow(Icons.fingerprint_outlined, 'ID de cuenta', (user['id'] as String? ?? '').isNotEmpty ? '${(user['id'] as String).substring(0, 8)}...' : 'N/A', subtextColor),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color subtextColor) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: GardenColors.primary),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14)),
          const Spacer(),
          Text(value, style: TextStyle(color: subtextColor, fontSize: 13)),
        ],
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
              imageUrl: (_caregiverProfile?['profilePhoto'] as String?)?.isNotEmpty == true
                  ? _caregiverProfile!['profilePhoto'] as String
                  : user['profilePicture'] as String?,
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
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.mark_email_unread_outlined, size: 12, color: GardenColors.warning),
                                SizedBox(width: 4),
                                Text('Verificar',
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
          _profileTile(icon: Icons.person_outlined, title: 'Mis Datos', onTap: () async {
            final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyDataScreen()));
            if (result == true && mounted) _loadProfile();
          }),
          _profileTile(icon: Icons.pets, title: 'Mis mascotas', onTap: () => context.push('/my-pets')),
          _profileTile(icon: Icons.calendar_today, title: 'Mis reservas', onTap: () => context.push('/my-bookings')),
          _profileTile(icon: Icons.favorite_border, title: 'Cuidadores favoritos', onTap: () => context.push('/favorites')),
          _profileTile(icon: Icons.star_outline, title: 'Mis calificaciones',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRatingsScreen()))),
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

        if (_role == 'CLIENT')
          AnimatedBuilder(
            animation: languageNotifier,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                onTap: _showLanguageSheet,
                tileColor: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const Icon(Icons.language_outlined, color: GardenColors.primary),
                title: Text('Idioma', style: TextStyle(color: theme.colorScheme.onSurface)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(languageNotifier.displayName,
                      style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 14)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
        
        const SizedBox(height: 24),
        const Text('Accesibilidad', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildAccountInfoTile(),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            tileColor: GardenColors.error.withOpacity(0.05),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: GardenColors.error.withOpacity(0.3)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: _isDeletingAccount
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.error))
                : const Icon(Icons.delete_forever_outlined, color: GardenColors.error),
            title: const Text('Eliminar cuenta', style: TextStyle(color: GardenColors.error, fontWeight: FontWeight.w600)),
            subtitle: const Text('Esta acción es permanente e irreversible', style: TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, color: GardenColors.error),
            onTap: _isDeletingAccount ? null : _deleteAccount,
          ),
        ),
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

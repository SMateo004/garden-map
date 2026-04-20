import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../services/language_service.dart';
import '../../services/auth_service.dart';
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
  bool _isSwitchingRole = false;
  String _token = '';
  String _role = '';
  String _activeRole = '';
  Map<String, dynamic>? _caregiverProfile;

  /// Rol efectivo: activeRole si está activo, si no el rol permanente.
  String get _effectiveRole => _activeRole.isNotEmpty ? _activeRole : _role;

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
      _activeRole = prefs.getString('active_role') ?? '';
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
          final prefs = await SharedPreferences.getInstance();
          final apiActiveRole = data['data']?['activeRole'] as String? ?? '';
          // Sincronizar active_role desde la API (fuente de verdad)
          if (apiActiveRole.isNotEmpty) {
            await prefs.setString('active_role', apiActiveRole);
          } else {
            await prefs.remove('active_role');
          }
          setState(() {
            _userData = data['data'];
            _role = _userData?['role'] ?? _role;
            _activeRole = apiActiveRole;
          });

          // Si el rol permanente es CAREGIVER, cargar también el perfil profesional
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
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final hintColor = isDark ? GardenColors.darkTextHint : GardenColors.lightTextHint;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(GardenRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GardenRadius.md),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(GardenRadius.sm),
                  ),
                  child: Icon(icon, color: GardenColors.primary, size: 17),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(title,
                      style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                Icon(Icons.chevron_right_rounded, color: hintColor, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountInfoTile() {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
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
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.md),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          _infoRow(Icons.calendar_today_outlined, 'Miembro desde', createdAt.isNotEmpty ? createdAt : 'N/A', textColor, subtextColor),
          if (walletAddress.isNotEmpty) ...[
            Divider(height: 1, color: borderColor),
            _infoRow(Icons.account_balance_wallet_outlined, 'Wallet blockchain', '${walletAddress.substring(0, 6)}...${walletAddress.substring(walletAddress.length - 4)}', textColor, subtextColor),
          ],
          Divider(height: 1, color: borderColor),
          _infoRow(Icons.fingerprint_outlined, 'ID de cuenta', (user['id'] as String? ?? '').isNotEmpty ? '${(user['id'] as String).substring(0, 8)}...' : 'N/A', textColor, subtextColor),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color textColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: GardenColors.primary),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value, style: TextStyle(color: subtextColor, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final hintColor = isDark ? GardenColors.darkTextHint : GardenColors.lightTextHint;

    return Scaffold(
      backgroundColor: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(GardenRadius.sm),
              ),
              child: const Icon(Icons.person_rounded, color: GardenColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Mi Perfil', style: GardenText.h4.copyWith(color: textColor)),
          ],
        ),
        centerTitle: true,
        actions: [
          if (_token.isNotEmpty)
            IconButton(
              icon: Icon(Icons.logout_rounded, color: hintColor, size: 20),
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
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final user = _userData!;

    String roleLabel = 'Usuario';
    Color roleColor = GardenColors.primary;
    if (_effectiveRole == 'CLIENT') {
      roleLabel = _role == 'CAREGIVER' ? 'Dueño de mascota (modo temporal)' : 'Dueño de mascota';
      roleColor = GardenColors.success;
    } else if (_effectiveRole == 'CAREGIVER') {
      roleLabel = 'Cuidador';
      roleColor = GardenColors.primary;
    } else if (_effectiveRole == 'ADMIN') {
      roleLabel = 'Administrador';
      roleColor = GardenColors.info;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header card ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                GardenColors.primary.withValues(alpha: 0.07),
                GardenColors.lime.withValues(alpha: 0.25),
              ],
            ),
            borderRadius: BorderRadius.circular(GardenRadius.xl),
            border: Border.all(color: GardenColors.primary.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              GardenAvatar(
                imageUrl: (_caregiverProfile?['profilePhoto'] as String?)?.isNotEmpty == true
                    ? _caregiverProfile!['profilePhoto'] as String
                    : user['profilePicture'] as String?,
                size: 72,
                initials: '${user['firstName']} ${user['lastName']}',
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${user['firstName']} ${user['lastName']}',
                        style: GardenText.h4.copyWith(color: textColor)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.email_outlined, size: 12, color: subtextColor),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            user['email'] as String? ?? '',
                            style: GardenText.bodySmall.copyWith(color: subtextColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (user['emailVerified'] == true)
                          const Icon(Icons.verified_rounded, size: 14, color: GardenColors.success)
                        else
                          GestureDetector(
                            onTap: _sendVerificationEmail,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: GardenColors.warning.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(GardenRadius.full),
                                border: Border.all(color: GardenColors.warning.withValues(alpha: 0.4)),
                              ),
                              child: const Text('Verificar',
                                style: TextStyle(color: GardenColors.warning, fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: roleColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(GardenRadius.full),
                        border: Border.all(color: roleColor.withValues(alpha: 0.25)),
                      ),
                      child: Text(roleLabel,
                          style: TextStyle(color: roleColor, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        _sectionLabel('Mi cuenta', textColor),
        const SizedBox(height: 10),
        
        if (_effectiveRole == 'CLIENT') ...[
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
          // Solo para CLIENT permanente (no para CAREGIVER actuando como CLIENT)
          if (_role == 'CLIENT')
            _profileTile(
              icon: Icons.volunteer_activism_outlined,
              title: 'Conviérteme en cuidador',
              onTap: () => context.push('/become-caregiver'),
            ),
        ],

        if (_effectiveRole == 'CAREGIVER') ...[
          _profileTile(
            icon: Icons.assignment_outlined,
            title: 'Datos del cuidador',
            onTap: () => context.push('/caregiver/profile-data'),
          ),
          _profileTile(icon: Icons.edit_outlined, title: 'Editar perfil', onTap: () => context.push('/caregiver/edit-profile')),
          _profileTile(icon: Icons.home_outlined, title: 'Mi panel', onTap: () => context.push('/caregiver/home')),
          if (_caregiverProfile?['verified'] != true &&
              _caregiverProfile?['verificationStatus'] != 'VERIFIED' &&
              _caregiverProfile?['identityVerificationStatus'] != 'VERIFIED')
            _profileTile(icon: Icons.verified_user_outlined, title: 'Verificación IA', onTap: () => context.push('/caregiver/verification')),
          _profileTile(icon: Icons.calendar_month, title: 'Mi disponibilidad', onTap: () => context.push('/caregiver/home')),
          _profileTile(icon: Icons.account_balance_wallet_outlined, title: 'Mi billetera', onTap: () => context.push('/wallet')),
        ],

        if (_effectiveRole == 'ADMIN') ...[
          _profileTile(icon: Icons.admin_panel_settings, title: 'Panel admin', onTap: () => context.push('/admin')),
        ],

        const SizedBox(height: 24),
        _sectionLabel('Preferencias', textColor),
        const SizedBox(height: 10),

        // Modo oscuro
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            borderRadius: BorderRadius.circular(GardenRadius.md),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GardenRadius.md),
                border: Border.all(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: GardenColors.primary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(GardenRadius.sm),
                    ),
                    child: Icon(
                      themeNotifier.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                      color: GardenColors.primary, size: 17,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Modo oscuro',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  Switch(
                    value: themeNotifier.isDark,
                    onChanged: (_) => themeNotifier.toggle(),
                    activeColor: GardenColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),

        _profileTile(icon: Icons.notifications_outlined, title: 'Notificaciones',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Próximamente')))),

        if (_effectiveRole == 'CLIENT')
          AnimatedBuilder(
            animation: languageNotifier,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
                borderRadius: BorderRadius.circular(GardenRadius.md),
                child: InkWell(
                  onTap: _showLanguageSheet,
                  borderRadius: BorderRadius.circular(GardenRadius.md),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(GardenRadius.md),
                      border: Border.all(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: GardenColors.primary.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(GardenRadius.sm),
                          ),
                          child: const Icon(Icons.language_outlined, color: GardenColors.primary, size: 17),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text('Idioma',
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        Text(languageNotifier.displayName,
                            style: TextStyle(color: subtextColor, fontSize: 13)),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded,
                            color: isDark ? GardenColors.darkTextHint : GardenColors.lightTextHint, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        const SizedBox(height: 24),
        _sectionLabel('Cuenta', textColor),
        const SizedBox(height: 10),
        if (_role == 'CAREGIVER') ...[
          _switchRoleTile(textColor),
          const SizedBox(height: 8),
        ],
        _buildAccountInfoTile(),
        const SizedBox(height: 8),
        const SizedBox(height: 28),
        GardenButton(
          label: 'Cerrar sesión',
          outline: true,
          color: GardenColors.error,
          onPressed: _logout,
        ),
        const SizedBox(height: 20),
        Center(
          child: GestureDetector(
            onTap: _isDeletingAccount ? null : _deleteAccount,
            child: _isDeletingAccount
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: GardenColors.error),
                  )
                : Text(
                    'Eliminar cuenta',
                    style: TextStyle(
                      color: GardenColors.error.withValues(alpha: 0.45),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      decoration: TextDecoration.underline,
                      decorationColor: GardenColors.error.withValues(alpha: 0.3),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Switch role ─────────────────────────────────────────────────────────────

  Widget _switchRoleTile(Color textColor) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final isSwitchedToClient = _activeRole == 'CLIENT';
    final label = isSwitchedToClient ? 'Volver a modo cuidador' : 'Cambiar a modo dueño';
    final icon = isSwitchedToClient ? Icons.pets : Icons.swap_horiz_rounded;
    final accent = isSwitchedToClient ? GardenColors.primary : GardenColors.success;

    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.md),
        child: InkWell(
          onTap: _isSwitchingRole ? null : () => _onSwitchRoleTap(isSwitchedToClient),
          borderRadius: BorderRadius.circular(GardenRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GardenRadius.md),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(GardenRadius.sm),
                  ),
                  child: _isSwitchingRole
                      ? SizedBox(
                          width: 17, height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                        )
                      : Icon(icon, color: accent, size: 17),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: isDark ? GardenColors.darkTextHint : GardenColors.lightTextHint, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Verifica reservas activas antes de mostrar el sheet de cambio de rol.
  Future<void> _onSwitchRoleTap(bool isSwitchedToClient) async {
    int activeBookings = 0;
    // Solo verificar si está cambiando de CAREGIVER → CLIENT
    if (!isSwitchedToClient && _token.isNotEmpty) {
      try {
        final res = await http.get(
          Uri.parse('$_baseUrl/caregiver/bookings?limit=5'),
          headers: {'Authorization': 'Bearer $_token'},
        ).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['success'] == true) {
            final bookings = (data['data'] as List? ?? []).cast<Map<String, dynamic>>();
            activeBookings = bookings.where((b) => b['status'] == 'IN_PROGRESS').length;
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
    _showSwitchRoleSheet(isSwitchedToClient, activeBookings: activeBookings);
  }

  void _showSwitchRoleSheet(bool isSwitchedToClient, {int activeBookings = 0}) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final targetRole = isSwitchedToClient ? 'CAREGIVER' : 'CLIENT';
    final title = isSwitchedToClient ? 'Volver a modo cuidador' : 'Cambiar a modo dueño de mascota';
    final description = isSwitchedToClient
        ? 'Volverás a tu interfaz de cuidador. Todas tus opciones de cuidador estarán disponibles nuevamente.'
        : 'Usarás la app como dueño de mascota. Podrás hacer reservas con otros cuidadores pero no contigo mismo. Tu perfil de cuidador se mantendrá y podrás volver cuando quieras.';
    final iconData = isSwitchedToClient ? Icons.pets : Icons.swap_horiz_rounded;
    final accent = isSwitchedToClient ? GardenColors.primary : GardenColors.success;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => GlassBox(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 24),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(iconData, color: accent, size: 28),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              description,
              style: TextStyle(color: subtextColor, fontSize: 13, height: 1.55),
              textAlign: TextAlign.center,
            ),
            if (activeBookings > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: GardenColors.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(GardenRadius.md),
                  border: Border.all(color: GardenColors.warning.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: GardenColors.warning, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Tienes $activeBookings servicio${activeBookings > 1 ? 's' : ''} en curso. Podrás seguir gestionándolo${activeBookings > 1 ? 's' : ''} desde tu panel de cuidador.',
                        style: const TextStyle(
                            color: GardenColors.warning, fontSize: 12, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            GardenButton(
              label: 'Confirmar',
              onPressed: () {
                Navigator.pop(context);
                _doSwitchRole(targetRole);
              },
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar', style: TextStyle(color: subtextColor)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doSwitchRole(String targetRole) async {
    if (_isSwitchingRole) return;
    setState(() => _isSwitchingRole = true);
    try {
      final authService = AuthService();
      final effectiveRole = await authService.switchRole(
        token: _token,
        targetRole: targetRole,
      );
      if (!mounted) return;
      // Actualizar token local (los nuevos tokens ya están en prefs)
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _token = prefs.getString('access_token') ?? _token;
        _activeRole = effectiveRole == _role ? '' : effectiveRole;
      });
      if (!mounted) return;
      if (effectiveRole == 'CAREGIVER') {
        context.go('/caregiver/home');
      } else {
        context.go('/service-selector');
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
      if (mounted) setState(() => _isSwitchingRole = false);
    }
  }

  Widget _sectionLabel(String label, Color textColor) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Text(
      label,
      style: GardenText.labelLarge.copyWith(
        color: textColor,
        fontSize: 13,
        letterSpacing: 0.5,
      ),
    ),
  );
}

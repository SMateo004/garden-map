import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../client/my_data_screen.dart';
import '../client/my_ratings_screen.dart';
import '../client/nearby_vets_screen.dart';
import 'blocked_users_screen.dart';
import 'notification_settings_screen.dart';
import 'change_pin_dialog.dart';
import '../../services/auth_state.dart';
import '../../widgets/phone_change_flow.dart';
import '../../design/garden_icons.dart';
import '../../services/work_mode.dart';
import '../../widgets/mode_switcher_card.dart';
import '../../services/secure_storage_service.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../theme/garden_motion.dart';
import '../../design/garden_depth.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _isDeletingAccount = false;
  bool _conversionInProgress = false;
  bool _isAbandoningConversion = false;
  String _token = '';
  String _role = '';
  String _activeRole = '';
  Map<String, dynamic>? _caregiverProfile;

  // Pulsing animation for incomplete profile tiles
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  /// Rol efectivo: activeRole si está activo, si no el rol permanente.
  String get _effectiveRole => _activeRole.isNotEmpty ? _activeRole : _role;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  // ── Completeness checks ────────────────────────────────────────────────────

  /// True when the CLIENT's core data is missing at least one required field.
  /// Phone must be a real Bolivian number — social-login pre-registration
  /// (Google) leaves a `social_pending_...` placeholder that never
  /// matches this format, so accounts created that way are correctly flagged
  /// incomplete until the user fills in the real value.
  bool get _isClientDataIncomplete {
    final u = _userData;
    if (u == null) return false;
    String str(String k) => (u[k] as String? ?? '').trim();
    // Mismos campos que exige "Guardar cambios" en Mis Datos (_missingFields),
    // salvo NIT/Carnet y razón social, que viven en el perfil y no llegan en
    // /auth/me. Departamento/condominio solo aplican a quien marcó departamento.
    return str('firstName').isEmpty ||
        str('lastName').isEmpty ||
        !RegExp(r'^[67][0-9]{7}$').hasMatch(str('phone')) ||
        str('addressStreet').isEmpty ||
        str('addressNumber').isEmpty ||
        str('addressReference').isEmpty ||
        str('addressZone').isEmpty ||
        u['cityId'] == null ||
        u['addressLat'] == null ||
        u['addressLng'] == null ||
        u['dateOfBirth'] == null ||
        str('bio').isEmpty ||
        str('profilePicture').isEmpty ||
        // Teléfono sin verificar: es el canal de contacto, el botón pulsa hasta
        // que se confirme con el código (ver my_data_screen.dart).
        u['phoneVerified'] != true;
  }

  /// True when "Datos del cuidador" is missing any required field.
  /// Usa el % ya calculado por el backend (onboardingStatus.percentage,
  /// recalculado en cada GET /my-profile) — misma fuente de verdad que el
  /// resto de la app, en vez de un chequeo local que puede desincronizarse.
  bool get _isCaregiverDataIncomplete {
    final p = _caregiverProfile;
    if (p == null) return false;
    final percentage = (p['onboardingStatus'] as Map<String, dynamic>?)?['percentage'] as int?;
    // Teléfono sin verificar también enciende el aviso (phoneVerified viene de /auth/me).
    final phoneUnverified = _userData != null && _userData!['phoneVerified'] != true;
    return (percentage ?? 0) < 100 || phoneUnverified;
  }

  /// Antes de entrar a "Datos del cuidador": si el teléfono no está verificado,
  /// ofrece verificarlo ahí mismo (sin bloquear la entrada).
  Future<void> _offerPhoneVerification() async {
    final u = _userData;
    if (u == null || u['phoneVerified'] == true) return;
    final phone = (u['phone'] as String? ?? '').trim();
    if (phone.isEmpty || phone.startsWith('social_pending_')) return;
    final verified = await PhoneVerifyPrompt.offer(context, baseUrl: _baseUrl, token: AuthState.token, phone: phone);
    if (verified && mounted) await _loadProfile();
  }

  /// true = cuidador amateur con capacitación AMATEUR obligatoria pendiente
  /// (mismo flag que gatea su visibilidad en el marketplace).
  bool get _hasPendingTraining =>
      _caregiverProfile?['isAmateur'] == true && _caregiverProfile?['trainingComplete'] == false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward(); // una vez y queda resaltado: sin bucles (GardenMotion)
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: GardenMotion.move);
    _loadInitialData();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _token = AuthState.token;
      _role = prefs.getString('user_role') ?? '';
      _activeRole = prefs.getString('active_role') ?? '';
      _conversionInProgress = prefs.getBool('client_conversion_in_progress') ?? false;
    });
    if (_token.isNotEmpty) {
      await _loadProfile();
    } else {
      setState(() => _isLoading = false);
    }
  }

  /// Refresca solo _caregiverProfile (sin spinner de página completa) — usado
  /// al volver de "Datos del cuidador" para que el pulso se apague de
  /// inmediato si el cuidador completó todo, sin esperar a un reload manual.
  Future<void> _refreshCaregiverProfile() async {
    if (_token.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && mounted) {
        setState(() => _caregiverProfile = data['data']);
      }
    } catch (e) {
      debugPrint('Error refreshing caregiver profile: $e');
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
          final apiRole = data['data']?['role'] as String? ?? _role;
          AuthState.updateRole(role: apiRole, activeRole: apiActiveRole);
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
        Uri.parse('$_baseUrl/auth/send-verification-email'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (data['success'] == true) {
        _showVerifyCodeDialog(_token, _baseUrl);
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al enviar correo');
      }
    } catch (e) {
      if (!mounted) return;
      GardenErrorDialog.show(context, e.toString());
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
                  GardenClay(size: 56, tint: GardenColors.primary.withValues(alpha: 0.1), interactive: false, child: const GardenIcon(GIcon.correo, size: GIconSize.lg, color: GardenColors.primary)),
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
                      final nav = Navigator.of(ctx);
                      final scaffoldMsg = ScaffoldMessenger.of(context);
                      try {
                        final response = await http.post(
                          Uri.parse('$baseUrl/auth/verify-email'),
                          headers: {
                            'Authorization': 'Bearer $token',
                            'Content-Type': 'application/json',
                          },
                          body: jsonEncode({'code': code}),
                        );
                        final data = jsonDecode(response.body);
                        if (!mounted) return;
                        if (data['success'] == true) {
                          nav.pop();
                          scaffoldMsg.showSnackBar(
                            const SnackBar(
                              content: Text('Correo verificado'),
                              backgroundColor: GardenColors.success,
                            ),
                          );
                          // Recargar el perfil para actualizar el estado
                          _loadProfile();
                        } else {
                          setDialogState(() => isVerifying = false);
                          GardenErrorDialog.show(context, data['error']?['message'] ?? 'Código incorrecto');
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
    // Limpia el token en memoria y en almacenamiento seguro
    await AuthState.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_role');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_photo');
    await prefs.remove('active_role');
    if (mounted) context.go('/login');
  }

  Future<void> _deleteAccount() async {
    HapticFeedback.mediumImpact();
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
                GardenClay(size: 56, tint: GardenColors.error.withValues(alpha: 0.1), interactive: false, child: const GardenIcon(GIcon.eliminar, size: GIconSize.lg, color: GardenColors.error)),
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
        GardenErrorDialog.show(context, data['error']?['message'] ?? 'Error al eliminar la cuenta');
      }
    } catch (e) {
      GardenErrorDialog.show(context, 'Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _isDeletingAccount = false);
    }
  }


  Widget _profileTile({
    required GIcon icon,
    required String title,
    required VoidCallback? onTap,
    bool highlight = false,
    Widget? trailing,
  }) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final hintColor = isDark ? GardenColors.darkTextHint : GardenColors.lightTextHint;

    if (highlight) {
      return AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, _) {
          final t = _pulseAnim.value;
          final pulseBorder = Color.lerp(
            GardenColors.warning, // amber base
            GardenColors.warning, // amber bright
            t,
          )!;
          final glowAlpha = 0.18 + 0.22 * t;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GardenPressable(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(GardenRadius.md),
                  border: Border.all(color: pulseBorder, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: pulseBorder.withValues(alpha: glowAlpha),
                      blurRadius: 10 + 8 * t,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: GardenColors.warning.withValues(alpha: 0.12 + 0.06 * t),
                        borderRadius: BorderRadius.circular(GardenRadius.sm),
                      ),
                      child: GardenIcon(icon, color: GardenColors.warning, size: GIconSize.md, state: GIconState.active),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title,
                              style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(
                            'Completa tu perfil',
                            style: TextStyle(
                              color: GardenColors.warning.withValues(alpha: 0.85 + 0.15 * t),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GardenIcon(GIcon.siguiente, size: GIconSize.sm, color: GardenColors.warning),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    // Normal tile — GlassBox + squish táctil, consistente con el nav bar.
    return Opacity(
      opacity: onTap == null ? 0.55 : 1.0,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GardenPressable(
          onTap: onTap,
          child: GlassBox(
            borderRadius: BorderRadius.circular(GardenRadius.md),
            blurSigma: 16,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(GardenRadius.sm),
                  ),
                  child: GardenIcon(icon, color: GardenColors.primary, size: GIconSize.md, state: GIconState.active),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
                trailing ?? GardenIcon(GIcon.siguiente, color: hintColor, size: GIconSize.sm),
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
          _infoRow(GIcon.calendario, 'Miembro desde', createdAt.isNotEmpty ? createdAt : 'N/A', textColor, subtextColor),
          if (walletAddress.isNotEmpty) ...[
            Divider(height: 1, color: borderColor),
            _infoRow(GIcon.billetera, 'Wallet blockchain', walletAddress.length >= 10 ? '${walletAddress.substring(0, 6)}...${walletAddress.substring(walletAddress.length - 4)}' : walletAddress, textColor, subtextColor),
          ],
          Divider(height: 1, color: borderColor),
          _infoRow(GIcon.huellaDigital, 'ID de cuenta', (user['id'] as String? ?? '').isNotEmpty ? '${(user['id'] as String).substring(0, 8)}...' : 'N/A', textColor, subtextColor),
        ],
      ),
    );
  }

  Widget _infoRow(GIcon icon, String label, String value, Color textColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GardenIcon(icon, size: GIconSize.sm, color: GardenColors.primary, state: GIconState.active),
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
    // AnimatedBuilder garantiza que ESTA pantalla se reconstruya cada vez que
    // el tema cambia — incluyendo cuando el usuario lo cambia desde aquí mismo.
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final hintColor = isDark ? GardenColors.darkTextHint : GardenColors.lightTextHint;

        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        return Scaffold(
          backgroundColor: bg,
          appBar: kIsWeb ? null : AppBar(
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
                  child: const GardenIcon(GIcon.perfil, size: GIconSize.sm, state: GIconState.active, color: GardenColors.primary),
                ),
                const SizedBox(width: 10),
                Text('Mi Perfil', style: GardenText.h4.copyWith(color: textColor)),
              ],
            ),
            centerTitle: true,
            actions: [
              if (_token.isNotEmpty)
                IconButton(
                  icon: GardenIcon(GIcon.salir, size: GIconSize.md, color: hintColor),
                  onPressed: _logout,
                ),
            ],
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
                      GardenBackButton(size: 32, iconColor: textColor, onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 6),
                      Text('Mi Perfil', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (_token.isNotEmpty)
                        IconButton(icon: GardenIcon(GIcon.salir, size: GIconSize.sm, color: hintColor), onPressed: _logout, tooltip: 'Cerrar sesión'),
                    ],
                  ),
                ),
              Expanded(child: _isLoading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: kIsWeb ? 900.0 : double.infinity),
                    child: _token.isEmpty || _userData == null
                        ? _buildUnauthenticatedState()
                        : kIsWeb ? _buildWebAuthenticatedState() : _buildAuthenticatedState(),
                  )),
                )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUnauthenticatedState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 60),
          const GardenIcon(GIcon.perfil, size: GIconSize.hero, color: GardenColors.primary),
          const SizedBox(height: 16),
          const Text('Inicia sesión para ver tu perfil',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Gestiona tus reservas, mascotas y configuración',
              style: TextStyle(color: GardenColors.textHint),
              textAlign: TextAlign.center),
          const SizedBox(height: 32),
          GardenButton(label: 'Iniciar sesión', onPressed: () => context.push('/login')),
          const SizedBox(height: 12),
          GardenButton(label: 'Registrarse', outline: true, onPressed: () => context.push('/register')),
        ],
      ),
    );
  }

  // ── Web 2-column layout ──────────────────────────────────────────────────────

  Widget _buildWebAuthenticatedState() {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
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

    // ── data for account info card ───────────────────────────────
    String createdAt = '';
    try {
      final dt = DateTime.parse(user['createdAt'] as String? ?? '').toLocal();
      createdAt = '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {}
    final walletAddress = user['walletAddress'] as String? ??
        (_caregiverProfile?['walletAddress'] as String?) ?? '';
    final userId = user['id'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header card (full width) ────────────────────────────
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
                size: 64,
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
                        GardenIcon(GIcon.correo, size: GIconSize.xs, color: subtextColor),
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
                          const GardenIcon(GIcon.verificado, size: GIconSize.xs, state: GIconState.active, color: GardenColors.success)
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
        const SizedBox(height: 20),

        // ── Banner conversión (full width) ──────────────────────
        if (_role == 'CAREGIVER' && _conversionInProgress) ...[
          _buildConversionBanner(textColor, subtextColor),
          const SizedBox(height: 20),
        ],

        // ── 2-column body ───────────────────────────────────────
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: info + theme
              Expanded(
                flex: 40,
                child: Column(
                  children: [
                    // Account info card
                    Container(
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(GardenRadius.md),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                            child: Row(children: [
                              const GardenIcon(GIcon.info, size: GIconSize.xs, color: GardenColors.primary),
                              const SizedBox(width: 8),
                              Text('Información de cuenta',
                                  style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                          Divider(height: 1, color: borderColor),
                          _infoRow(GIcon.calendario, 'Miembro desde',
                              createdAt.isNotEmpty ? createdAt : 'N/A', textColor, subtextColor),
                          if (walletAddress.isNotEmpty) ...[
                            Divider(height: 1, color: borderColor),
                            _infoRow(GIcon.billetera, 'Wallet blockchain',
                                '${walletAddress.substring(0, 6)}...${walletAddress.substring(walletAddress.length - 4)}',
                                textColor, subtextColor),
                          ],
                          Divider(height: 1, color: borderColor),
                          _infoRow(GIcon.huellaDigital, 'ID de cuenta',
                              userId.isNotEmpty ? '${userId.substring(0, 8)}...' : 'N/A',
                              textColor, subtextColor),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Theme selector card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(GardenRadius.md),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const GardenIcon(GIcon.apariencia, size: GIconSize.xs, color: GardenColors.primary),
                            const SizedBox(width: 8),
                            Text('Apariencia',
                                style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w700)),
                          ]),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                              borderRadius: BorderRadius.circular(GardenRadius.md),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                _ThemeOptionBtn(icon: GIcon.dispositivo, label: 'Sistema',
                                    selected: themeNotifier.mode == GardenThemeMode.system, isDark: isDark,
                                    onTap: () => themeNotifier.setMode(GardenThemeMode.system)),
                                _ThemeOptionDivider(isDark: isDark),
                                _ThemeOptionBtn(icon: GIcon.modoClaro, label: 'Claro',
                                    selected: themeNotifier.mode == GardenThemeMode.light, isDark: isDark,
                                    onTap: () => themeNotifier.setMode(GardenThemeMode.light)),
                                _ThemeOptionDivider(isDark: isDark),
                                _ThemeOptionBtn(icon: GIcon.modoOscuro, label: 'Oscuro',
                                    selected: themeNotifier.mode == GardenThemeMode.dark, isDark: isDark,
                                    onTap: () => themeNotifier.setMode(GardenThemeMode.dark)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            themeNotifier.mode == GardenThemeMode.system
                                ? 'Sigue la configuración de tu teléfono'
                                : themeNotifier.mode == GardenThemeMode.dark
                                    ? 'Modo oscuro activado'
                                    : 'Modo claro activado',
                            style: TextStyle(color: subtextColor, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Right: navigation tiles
              Expanded(
                flex: 60,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mi cuenta', style: GardenText.labelLarge.copyWith(color: textColor, fontSize: 12, letterSpacing: 0.4)),
                    const SizedBox(height: 8),
                    if (WorkMode.available.length >= 2) ...[
                      ModeSwitcherCard(isCompany: _caregiverProfile?['isCompany'] == true),
                      const SizedBox(height: 14),
                    ],
                    if (_effectiveRole == 'CLIENT') ...[
                      _profileTile(icon: GIcon.perfil, title: 'Mis Datos', highlight: _isClientDataIncomplete, onTap: () async {
                        final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyDataScreen()));
                        if (result == true && mounted) _loadProfile();
                      }),
                      _profileTile(icon: GIcon.mascotas, title: 'Mis mascotas', onTap: () => context.push('/my-pets')),
                      _profileTile(icon: GIcon.calendario, title: 'Mis reservas', onTap: () => context.push('/my-bookings')),
                      _profileTile(icon: GIcon.favorito, title: 'Cuidadores favoritos', onTap: () => context.push('/favorites')),
                      _profileTile(icon: GIcon.estrella, title: 'Mis calificaciones',
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRatingsScreen()))),
                      _profileTile(icon: GIcon.billetera, title: 'Mi billetera', onTap: () => context.push('/wallet')),
                      _profileTile(icon: GIcon.veterinaria, title: 'Veterinarias cercanas',
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NearbyVetsScreen()))),
                      if (_role == 'CLIENT')
                        _profileTile(icon: GIcon.donar, title: 'Conviérteme en cuidador',
                            onTap: () => context.push('/become-caregiver')),
                      if (_role == 'CLIENT') _joinTeamTile(),
                    ],
                    if (_effectiveRole == 'CAREGIVER' && AuthState.isCaregiverStaff) ...[
                      // Empleado de una empresa — solo operativo, nada de
                      // billetera/precios/config del negocio (eso es del dueño).
                      _profileTile(icon: GIcon.calendario, title: 'Mis reservas',
                          onTap: () => context.push('/caregiver-staff/home')),
                    ],
                    if (_effectiveRole == 'CAREGIVER' && !AuthState.isCaregiverStaff) ...[
                      _profileTile(icon: GIcon.antecedentes, title: 'Datos del cuidador',
                          highlight: _isCaregiverDataIncomplete,
                          onTap: () async {
                            await _offerPhoneVerification();
                            if (!mounted) return;
                            await context.push('/caregiver/profile-data');
                            await _refreshCaregiverProfile();
                          }),
                      _profileTile(icon: GIcon.editar, title: 'Editar perfil',
                          onTap: () => context.push('/caregiver/edit-profile')),
                      _profileTile(icon: GIcon.inicio, title: 'Mi panel',
                          onTap: () => context.push('/caregiver/home')),
                      _profileTile(icon: GIcon.mascotas, title: 'Mascotas',
                          onTap: () => context.push('/caregiver/pets')),
                      if (_caregiverProfile?['isCompany'] == true) ...[
                        _profileTile(icon: GIcon.equipo, title: 'Mi equipo',
                            onTap: () => context.push('/caregiver/staff')),
                        _profileTile(icon: GIcon.inicio, title: 'Recepción',
                            onTap: () => context.push('/caregiver/reception')),
                      ],
                      if (_caregiverProfile?['verified'] != true &&
                          _caregiverProfile?['verificationStatus'] != 'VERIFIED' &&
                          _caregiverProfile?['identityVerificationStatus'] != 'VERIFIED')
                        _profileTile(icon: GIcon.verificado, title: 'Verificación IA',
                            onTap: () => context.push('/caregiver/verification')),
                      _profileTile(icon: GIcon.disponibilidad, title: 'Mi disponibilidad',
                          onTap: () => context.push('/caregiver/home')),
                      _profileTile(icon: GIcon.capacitacion, title: 'Capacitaciones',
                          highlight: _hasPendingTraining,
                          onTap: () => context.push('/caregiver/trainings')),
                      _profileTile(icon: GIcon.billetera, title: 'Mi billetera',
                          onTap: () => context.push('/wallet')),
                    ],
                    if (_effectiveRole == 'ADMIN') ...[
                      _profileTile(icon: GIcon.ajustes, title: 'Panel admin',
                          onTap: () => context.push('/admin')),
                    ],
                    const SizedBox(height: 16),
                    Text('Soporte', style: GardenText.labelLarge.copyWith(color: textColor, fontSize: 12, letterSpacing: 0.4)),
                    const SizedBox(height: 8),
                    _profileTile(
                      icon: GIcon.ayuda,
                      title: 'Centro de ayuda',
                      onTap: () => context.push('/help-center'),
                    ),
                    const SizedBox(height: 16),
                    Text('Legal', style: GardenText.labelLarge.copyWith(color: textColor, fontSize: 12, letterSpacing: 0.4)),
                    const SizedBox(height: 8),
                    _profileTile(icon: GIcon.legal, title: 'Términos y Condiciones',
                        onTap: () => context.push('/terms')),
                    _profileTile(icon: GIcon.seguridad, title: 'Política de Privacidad',
                        onTap: () => context.push('/privacy')),
                    const SizedBox(height: 16),
                    Text('Privacidad y seguridad', style: GardenText.labelLarge.copyWith(color: textColor, fontSize: 12, letterSpacing: 0.4)),
                    const SizedBox(height: 8),
                    _profileTile(icon: GIcon.seguridad, title: 'Cambiar PIN',
                        onTap: () => showChangePinDialog(context)),
                    _profileTile(icon: GIcon.bloqueado, title: 'Usuarios bloqueados',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockedUsersScreen()))),
                    const SizedBox(height: 16),
                    Text('Sesión', style: GardenText.labelLarge.copyWith(color: textColor, fontSize: 12, letterSpacing: 0.4)),
                    const SizedBox(height: 8),
                    _profileTile(icon: GIcon.notificaciones, title: 'Notificaciones',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()))),
                    const SizedBox(height: 8),
                    // Logout button as a tile
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: surface,
                        borderRadius: BorderRadius.circular(GardenRadius.md),
                        child: InkWell(
                          onTap: _logout,
                          borderRadius: BorderRadius.circular(GardenRadius.md),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(GardenRadius.md),
                              border: Border.all(color: GardenColors.error.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: GardenColors.error.withValues(alpha: 0.09),
                                    borderRadius: BorderRadius.circular(GardenRadius.sm),
                                  ),
                                  child: const GardenIcon(GIcon.salir, size: GIconSize.sm, color: GardenColors.error),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text('Cerrar sesión',
                                      style: TextStyle(color: GardenColors.error, fontWeight: FontWeight.w600, fontSize: 14)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: GestureDetector(
                        onTap: _isDeletingAccount ? null : _deleteAccount,
                        child: _isDeletingAccount
                            ? const GardenLoadingIndicator(size: 14, color: GardenColors.error)
                            : Text('Eliminar cuenta', style: TextStyle(
                                color: GardenColors.error.withValues(alpha: 0.45),
                                fontSize: 12, fontWeight: FontWeight.w400,
                                decoration: TextDecoration.underline,
                                decorationColor: GardenColors.error.withValues(alpha: 0.3))),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
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
                        GardenIcon(GIcon.correo, size: GIconSize.xs, color: subtextColor),
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
                          const GardenIcon(GIcon.verificado, size: GIconSize.xs, state: GIconState.active, color: GardenColors.success)
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

        // ── Banner: conversión CLIENT→CAREGIVER en progreso ──────────
        if (_role == 'CAREGIVER' && _conversionInProgress) ...[
          _buildConversionBanner(textColor, subtextColor),
          const SizedBox(height: 20),
        ],

        _sectionLabel('Mi cuenta', textColor),
        const SizedBox(height: 10),
        if (WorkMode.available.length >= 2) ...[
          ModeSwitcherCard(isCompany: _caregiverProfile?['isCompany'] == true),
          const SizedBox(height: 14),
        ],
        
        if (_effectiveRole == 'CLIENT') ...[
          _profileTile(icon: GIcon.perfil, title: 'Mis Datos', highlight: _isClientDataIncomplete, onTap: () async {
            final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyDataScreen()));
            if (result == true && mounted) _loadProfile();
          }),
          _profileTile(icon: GIcon.mascotas, title: 'Mis mascotas', onTap: () => context.push('/my-pets')),
          _profileTile(icon: GIcon.calendario, title: 'Mis reservas', onTap: () => context.push('/my-bookings')),
          _profileTile(icon: GIcon.favorito, title: 'Cuidadores favoritos', onTap: () => context.push('/favorites')),
          _profileTile(icon: GIcon.estrella, title: 'Mis calificaciones',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRatingsScreen()))),
          _profileTile(icon: GIcon.billetera, title: 'Mi billetera', onTap: () => context.push('/wallet')),
          _profileTile(icon: GIcon.veterinaria, title: 'Veterinarias cercanas',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NearbyVetsScreen()))),
          // Solo para CLIENT permanente (no para CAREGIVER actuando como CLIENT)
          if (_role == 'CLIENT')
            _profileTile(
              icon: GIcon.donar,
              title: 'Conviérteme en cuidador',
              onTap: () => context.push('/become-caregiver'),
            ),
          if (_role == 'CLIENT') _joinTeamTile(),
        ],

        if (_effectiveRole == 'CAREGIVER' && AuthState.isCaregiverStaff) ...[
          _profileTile(icon: GIcon.calendario, title: 'Mis reservas', onTap: () => context.push('/caregiver-staff/home')),
        ],

        if (_effectiveRole == 'CAREGIVER' && !AuthState.isCaregiverStaff) ...[
          _profileTile(
            icon: GIcon.antecedentes,
            title: 'Datos del cuidador',
            highlight: _isCaregiverDataIncomplete,
            onTap: () async {
              await context.push('/caregiver/profile-data');
              await _refreshCaregiverProfile();
            },
          ),
          _profileTile(icon: GIcon.editar, title: 'Editar perfil', onTap: () => context.push('/caregiver/edit-profile')),
          _profileTile(icon: GIcon.inicio, title: 'Mi panel', onTap: () => context.push('/caregiver/home')),
          _profileTile(icon: GIcon.mascotas, title: 'Mascotas', onTap: () => context.push('/caregiver/pets')),
          if (_caregiverProfile?['isCompany'] == true) ...[
            _profileTile(icon: GIcon.equipo, title: 'Mi equipo', onTap: () => context.push('/caregiver/staff')),
            _profileTile(icon: GIcon.inicio, title: 'Recepción', onTap: () => context.push('/caregiver/reception')),
          ],
          if (_caregiverProfile?['verified'] != true &&
              _caregiverProfile?['verificationStatus'] != 'VERIFIED' &&
              _caregiverProfile?['identityVerificationStatus'] != 'VERIFIED')
            _profileTile(icon: GIcon.verificado, title: 'Verificación IA', onTap: () => context.push('/caregiver/verification')),
          _profileTile(icon: GIcon.disponibilidad, title: 'Mi disponibilidad', onTap: () => context.push('/caregiver/home')),
          _profileTile(icon: GIcon.capacitacion, title: 'Capacitaciones',
              highlight: _hasPendingTraining, onTap: () => context.push('/caregiver/trainings')),
          _profileTile(icon: GIcon.billetera, title: 'Mi billetera', onTap: () => context.push('/wallet')),
        ],

        if (_effectiveRole == 'ADMIN') ...[
          _profileTile(icon: GIcon.ajustes, title: 'Panel admin', onTap: () => context.push('/admin')),
        ],

        const SizedBox(height: 24),
        _sectionLabel('Preferencias', textColor),
        const SizedBox(height: 10),

        // ── Selector de tema ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
              borderRadius: BorderRadius.circular(GardenRadius.md),
              border: Border.all(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: GardenColors.primary.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(GardenRadius.sm),
                      ),
                      child: const GardenIcon(GIcon.apariencia, size: GIconSize.sm, color: GardenColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Text('Apariencia',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 12),
                // Selector de 3 opciones
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                    borderRadius: BorderRadius.circular(GardenRadius.md),
                    border: Border.all(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                  ),
                  child: Row(
                    children: [
                      _ThemeOptionBtn(
                        icon: GIcon.dispositivo,
                        label: 'Sistema',
                        selected: themeNotifier.mode == GardenThemeMode.system,
                        isDark: isDark,
                        onTap: () => themeNotifier.setMode(GardenThemeMode.system),
                      ),
                      _ThemeOptionDivider(isDark: isDark),
                      _ThemeOptionBtn(
                        icon: GIcon.modoClaro,
                        label: 'Claro',
                        selected: themeNotifier.mode == GardenThemeMode.light,
                        isDark: isDark,
                        onTap: () => themeNotifier.setMode(GardenThemeMode.light),
                      ),
                      _ThemeOptionDivider(isDark: isDark),
                      _ThemeOptionBtn(
                        icon: GIcon.modoOscuro,
                        label: 'Oscuro',
                        selected: themeNotifier.mode == GardenThemeMode.dark,
                        isDark: isDark,
                        onTap: () => themeNotifier.setMode(GardenThemeMode.dark),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  themeNotifier.mode == GardenThemeMode.system
                      ? 'Sigue la configuración de tu teléfono'
                      : themeNotifier.mode == GardenThemeMode.dark
                          ? 'Modo oscuro activado'
                          : 'Modo claro activado',
                  style: TextStyle(
                    color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),

        _profileTile(icon: GIcon.notificaciones, title: 'Notificaciones',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Próximamente')))),

        const SizedBox(height: 24),
        _sectionLabel('Soporte', textColor),
        const SizedBox(height: 10),
        _profileTile(
          icon: GIcon.ayuda,
          title: 'Centro de ayuda',
          onTap: () => context.push('/help-center'),
        ),

        const SizedBox(height: 24),
        _sectionLabel('Legal', textColor),
        const SizedBox(height: 10),
        _profileTile(
          icon: GIcon.legal,
          title: 'Términos y Condiciones',
          onTap: () => context.push('/terms'),
        ),
        const SizedBox(height: 8),
        _profileTile(
          icon: GIcon.seguridad,
          title: 'Política de Privacidad',
          onTap: () => context.push('/privacy'),
        ),

        const SizedBox(height: 24),
        _sectionLabel('Privacidad y seguridad', textColor),
        const SizedBox(height: 10),
        _profileTile(icon: GIcon.seguridad, title: 'Cambiar PIN',
            onTap: () => showChangePinDialog(context)),
        const SizedBox(height: 8),
        _profileTile(icon: GIcon.bloqueado, title: 'Usuarios bloqueados',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockedUsersScreen()))),

        const SizedBox(height: 24),
        _sectionLabel('Cuenta', textColor),
        const SizedBox(height: 10),
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
                ? const GardenLoadingIndicator(size: 14, color: GardenColors.error)
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

  // ── Equipo de una empresa ───────────────────────────────────────────────────
  // El cambio entre dueño / cuidador / empleado vive en ModeSwitcherCard.
  // Esta fila es solo para quien aún no tiene otra identidad (dueño de mascota).

  Widget _joinTeamTile() => _profileTile(
        icon: GIcon.equipo,
        title: 'Unirme a un equipo',
        onTap: () => context.push('/caregiver-staff/join'),
      );

  // ── Conversión CLIENT→CAREGIVER en progreso ─────────────────────────────────

  Widget _buildConversionBanner(Color textColor, Color subtextColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GardenColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(GardenRadius.xl),
        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: GardenColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const GardenIcon(GIcon.esperando, size: GIconSize.sm, color: GardenColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Registro de cuidador en progreso',
                        style: TextStyle(
                            color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('Completa el formulario para activar tu perfil.',
                        style: TextStyle(color: subtextColor, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GardenButton(
            label: 'Continuar formulario',
            onPressed: () => context.push('/caregiver/onboarding',
                extra: {'clientConversionMode': true}),
          ),
          const SizedBox(height: 8),
          Center(
            child: GestureDetector(
              onTap: _isAbandoningConversion ? null : _confirmAbandonConversion,
              child: _isAbandoningConversion
                  ? const GardenLoadingIndicator(size: 14, color: GardenColors.error)
                  : Text(
                      'Abandonar formulario',
                      style: TextStyle(
                        color: GardenColors.error.withValues(alpha: 0.55),
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        decorationColor: GardenColors.error.withValues(alpha: 0.35),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmAbandonConversion() {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GardenClay(size: 52, tint: GardenColors.error.withValues(alpha: 0.10), interactive: false, child: const GardenIcon(GIcon.cancelado, size: GIconSize.lg, color: GardenColors.error)),
              const SizedBox(height: 14),
              Text('¿Abandonar el registro?',
                  style: TextStyle(
                      color: textColor, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Tu cuenta volverá al modo dueño de mascota. Podrás iniciar el proceso de nuevo cuando quieras.',
                style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancelar',
                          style: TextStyle(color: subtextColor)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GardenColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _abandonConversion();
                      },
                      child: const Text('Abandonar',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abandonConversion() async {
    if (_isAbandoningConversion) return;
    setState(() => _isAbandoningConversion = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/abandon-caregiver-profile'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        final result = data['data'] as Map<String, dynamic>;
        // Actualizar tokens en almacenamiento seguro y caché en memoria
        await AuthState.update(result['accessToken'] as String);
        await SecureStorageService.saveRefreshToken(result['refreshToken'] as String);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_role', 'CLIENT');
        await prefs.remove('active_role');
        AuthState.updateRole(role: 'CLIENT', activeRole: '');
        await prefs.remove('client_conversion_in_progress');
        if (!mounted) return;
        context.go('/service-selector');
      } else {
        final msg = (data['error'] as Map<String, dynamic>?)?['message']
            ?? 'No se pudo abandonar el proceso.';
        if (!mounted) return;
        GardenErrorDialog.show(context, msg);
      }
    } catch (_) {
      if (!mounted) return;
      GardenErrorDialog.show(context, 'Error de conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isAbandoningConversion = false);
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

// ── Widgets privados para el selector de tema ─────────────────────────────────

class _ThemeOptionBtn extends StatelessWidget {
  final GIcon icon;
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _ThemeOptionBtn({
    required this.icon,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unselectedColor =
        isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (selected) return;
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? GardenColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(GardenRadius.sm),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GardenIcon(
                icon,
                size: GIconSize.sm,
                state: selected ? GIconState.active : GIconState.idle,
                color: selected ? Colors.white : unselectedColor,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : unselectedColor,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeOptionDivider extends StatelessWidget {
  final bool isDark;
  const _ThemeOptionDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder,
    );
  }
}

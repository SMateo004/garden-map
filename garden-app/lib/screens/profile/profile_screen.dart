import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
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
import '../../services/business_features.dart';
import '../../widgets/mode_switcher_card.dart';
import '../../services/secure_storage_service.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../design/brote.dart';
import '../../design/garden_depth.dart';
import '../../design/garden_settings.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _isDeletingAccount = false;
  bool _conversionInProgress = false;
  bool _isAbandoningConversion = false;
  String _token = '';
  String _role = '';
  String _activeRole = '';
  Map<String, dynamic>? _caregiverProfile;

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
    _loadInitialData();
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
            title: Text('Mi perfil', style: GardenText.h4.copyWith(color: textColor)),
            centerTitle: true,
            actions: [
              if (_token.isNotEmpty)
                IconButton(
                  icon: GardenIcon(GIcon.salir, size: GIconSize.md, color: hintColor),
                  onPressed: _logout,
                  tooltip: 'Cerrar sesión',
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
                      Text('Mi perfil', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
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
                    constraints: const BoxConstraints(maxWidth: kIsWeb ? 900.0 : double.infinity),
                    child: _token.isEmpty || _userData == null
                        ? _buildUnauthenticatedState()
                        : _buildAuthenticatedState(wide: kIsWeb && MediaQuery.sizeOf(context).width >= 760),
                  )),
                )),
            ],
          ),
        );
      },
    );
  }

  // ── Piezas de la pantalla ────────────────────────────────────────────────────

  String get _roleLabel => switch (_effectiveRole) {
        // El modo se cambia con la barra de abajo: sin "(modo temporal)".
        'CLIENT' => 'Dueño de mascota',
        'CAREGIVER' => AuthState.isCaregiverStaff ? 'Cuidador de un equipo' : 'Cuidador',
        'ADMIN' => 'Administrador',
        _ => 'Usuario',
      };

  Color get _roleColor => switch (_effectiveRole) {
        'CLIENT' => GardenColors.success,
        'ADMIN' => GardenColors.info,
        _ => GardenColors.primary,
      };

  String? get _since {
    final dt = DateTime.tryParse(_userData?['createdAt'] as String? ?? '')?.toLocal();
    if (dt == null) return null;
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return 'En GARDEN desde ${months[dt.month - 1]} ${dt.year}';
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copiado')));
  }

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  Widget _header() {
    final user = _userData!;
    final cgPhoto = _caregiverProfile?['profilePhoto'] as String?;
    return GardenProfileHeader(
      name: '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim(),
      email: user['email'] as String? ?? '',
      photoUrl: cgPhoto != null && cgPhoto.isNotEmpty ? cgPhoto : user['profilePicture'] as String?,
      emailVerified: user['emailVerified'] == true,
      onVerifyEmail: _sendVerificationEmail,
      roleLabel: _roleLabel,
      roleColor: _roleColor,
      since: _since,
    );
  }

  /// Lo propio de cada rol: lo que se usa todos los días va primero.
  List<Widget> _roleGroups() {
    if (_effectiveRole == 'CLIENT') {
      return [
        GardenSettingsGroup(title: 'Mi cuenta', children: [
          GardenSettingsRow(
            icon: GIcon.perfil,
            title: 'Mis datos',
            tone: _isClientDataIncomplete ? GardenSettingsTone.attention : GardenSettingsTone.normal,
            subtitle: _isClientDataIncomplete ? 'Te faltan datos por completar' : null,
            onTap: () async {
              final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyDataScreen()));
              if (result == true && mounted) _loadProfile();
            },
          ),
          GardenSettingsRow(icon: GIcon.mascotas, title: 'Mis mascotas', onTap: () => context.push('/my-pets')),
          GardenSettingsRow(icon: GIcon.calendario, title: 'Mis reservas', onTap: () => context.push('/my-bookings')),
          GardenSettingsRow(icon: GIcon.billetera, title: 'Mi billetera', onTap: () => context.push('/wallet')),
        ]),
        GardenSettingsGroup(title: 'Para ti', children: [
          GardenSettingsRow(icon: GIcon.favorito, title: 'Cuidadores favoritos', onTap: () => context.push('/favorites')),
          GardenSettingsRow(icon: GIcon.estrella, title: 'Mis calificaciones', onTap: () => _open(const MyRatingsScreen())),
          GardenSettingsRow(icon: GIcon.veterinaria, title: 'Veterinarias cercanas', onTap: () => _open(const NearbyVetsScreen())),
        ]),
        // Solo para CLIENT permanente (no para CAREGIVER actuando como CLIENT).
        if (_role == 'CLIENT')
          GardenSettingsGroup(title: 'Trabaja con GARDEN', children: [
            GardenSettingsRow(
                icon: GIcon.donar,
                title: 'Hazte cuidador',
                subtitle: 'Gana dinero cuidando mascotas',
                onTap: () => context.push('/become-caregiver')),
            // "Unirme a un equipo" ya no se ofrece a un dueño de mascota: vive en el selector de perfil,
            // solo en modo cuidador (mode_switcher_card.dart).
          ]),
      ];
    }
    if (_effectiveRole == 'CAREGIVER' && AuthState.isCaregiverStaff) {
      // Empleado de una empresa: solo lo operativo (billetera, precios y
      // configuración del negocio son del dueño).
      return [
        GardenSettingsGroup(title: 'Mi trabajo', children: [
          GardenSettingsRow(icon: GIcon.calendario, title: 'Mis reservas', onTap: () => context.push('/caregiver-staff/home')),
        ]),
      ];
    }
    if (_effectiveRole == 'CAREGIVER') {
      final p = _caregiverProfile;
      final isCompany = p?['isCompany'] == true;
      final verified = p?['verified'] == true ||
          p?['verificationStatus'] == 'VERIFIED' ||
          p?['identityVerificationStatus'] == 'VERIFIED';
      return [
        GardenSettingsGroup(title: 'Mi trabajo', children: [
          GardenSettingsRow(icon: GIcon.inicio, title: 'Mi panel', onTap: () => context.push('/caregiver/home')),
          // Antes abría el panel en "Inicio", igual que "Mi panel".
          GardenSettingsRow(
              icon: GIcon.disponibilidad,
              title: 'Mi disponibilidad',
              onTap: () => context.push('/caregiver/home?tab=disponibilidad')),
          GardenSettingsRow(icon: GIcon.mascotas, title: 'Mascotas', onTap: () => context.push('/caregiver/pets')),
          // Equipo y recepción solo si el admin los habilitó para este negocio.
          if (isCompany && BusinessFeatures.has(p, BusinessFeatures.staffTeam))
            GardenSettingsRow(icon: GIcon.equipo, title: 'Mi equipo', onTap: () => context.push('/caregiver/staff')),
          if (isCompany && BusinessFeatures.has(p, BusinessFeatures.reception))
            GardenSettingsRow(icon: GIcon.habitacion, title: 'Recepción', onTap: () => context.push('/caregiver/reception')),
          GardenSettingsRow(icon: GIcon.billetera, title: 'Mi billetera', onTap: () => context.push('/wallet')),
          // Solo en modo cuidador: además del atajo dentro del selector de perfil,
          // a la vista en su grupo de trabajo.
          if (!isCompany && !AuthState.hasStaffMembership)
            GardenSettingsRow(
                icon: GIcon.equipo,
                title: 'Unirme a un equipo',
                subtitle: 'Si una empresa te invitó con un código',
                onTap: () => context.push('/caregiver-staff/join')),
        ]),
        GardenSettingsGroup(title: 'Mi perfil de cuidador', children: [
          GardenSettingsRow(
            icon: GIcon.antecedentes,
            title: 'Datos del cuidador',
            tone: _isCaregiverDataIncomplete ? GardenSettingsTone.attention : GardenSettingsTone.normal,
            subtitle: _isCaregiverDataIncomplete ? 'Te faltan datos por completar' : null,
            onTap: () async {
              // Antes solo la versión web ofrecía verificar el teléfono aquí.
              await _offerPhoneVerification();
              if (!mounted) return;
              await context.push('/caregiver/profile-data');
              await _refreshCaregiverProfile();
            },
          ),
          GardenSettingsRow(
              icon: GIcon.editar, title: 'Editar perfil público', onTap: () => context.push('/caregiver/edit-profile')),
          if (!verified)
            GardenSettingsRow(
                icon: GIcon.verificado,
                title: 'Verificar mi identidad',
                tone: GardenSettingsTone.attention,
                subtitle: 'Los dueños confían más en perfiles verificados',
                onTap: () => context.push('/caregiver/verification')),
          GardenSettingsRow(
            icon: GIcon.capacitacion,
            title: 'Capacitaciones',
            tone: _hasPendingTraining ? GardenSettingsTone.attention : GardenSettingsTone.normal,
            subtitle: _hasPendingTraining ? 'Complétala para aparecer en la búsqueda' : null,
            onTap: () => context.push('/caregiver/trainings'),
          ),
        ]),
      ];
    }
    if (_effectiveRole == 'ADMIN') {
      return [
        GardenSettingsGroup(title: 'Administración', children: [
          GardenSettingsRow(icon: GIcon.ajustes, title: 'Panel admin', onTap: () => context.push('/admin')),
        ]),
      ];
    }
    return const [];
  }

  /// Lo que es igual para todos: preferencias, seguridad, ayuda y la cuenta.
  List<Widget> _commonGroups() {
    final user = _userData!;
    final userId = user['id'] as String? ?? '';
    final wallet = user['walletAddress'] as String? ?? (_caregiverProfile?['walletAddress'] as String?) ?? '';
    final isDark = themeNotifier.isDark;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    Widget value(String v) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(v, style: TextStyle(color: sub, fontSize: 12)),
        );

    return [
      GardenSettingsGroup(title: 'Preferencias', children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Apariencia', style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            GardenSegmented<GardenThemeMode>(
              options: const [
                (GardenThemeMode.system, GIcon.dispositivo, 'Sistema'),
                (GardenThemeMode.light, GIcon.modoClaro, 'Claro'),
                (GardenThemeMode.dark, GIcon.modoOscuro, 'Oscuro'),
              ],
              selected: themeNotifier.mode,
              onSelect: themeNotifier.setMode,
            ),
          ]),
        ),
        // En celular decía "Próximamente" aunque la pantalla ya existía (web sí la abría).
        GardenSettingsRow(
            icon: GIcon.notificaciones, title: 'Notificaciones', onTap: () => _open(const NotificationSettingsScreen())),
      ]),
      GardenSettingsGroup(title: 'Privacidad y seguridad', children: [
        GardenSettingsRow(icon: GIcon.seguridad, title: 'Cambiar PIN', onTap: () => showChangePinDialog(context)),
        GardenSettingsRow(icon: GIcon.bloqueado, title: 'Usuarios bloqueados', onTap: () => _open(const BlockedUsersScreen())),
      ]),
      GardenSettingsGroup(title: 'Ayuda', children: [
        GardenSettingsRow(icon: GIcon.ayuda, title: 'Centro de ayuda', onTap: () => context.push('/help-center')),
        GardenSettingsRow(icon: GIcon.legal, title: 'Términos y condiciones', onTap: () => context.push('/terms')),
        GardenSettingsRow(icon: GIcon.seguridad, title: 'Política de privacidad', onTap: () => context.push('/privacy')),
      ]),
      // Lo técnico, al final y para copiarlo si soporte lo pide.
      GardenSettingsGroup(title: 'Datos de la cuenta', children: [
        if (userId.length >= 8)
          GardenSettingsRow(
            icon: GIcon.huellaDigital,
            title: 'ID de cuenta',
            subtitle: 'Toca para copiarlo',
            trailing: value('${userId.substring(0, 8)}…'),
            onTap: () => _copy('ID de cuenta', userId),
          ),
        if (wallet.length >= 10)
          GardenSettingsRow(
            icon: GIcon.billetera,
            title: 'Wallet blockchain',
            subtitle: 'Toca para copiarla',
            trailing: value('${wallet.substring(0, 6)}…${wallet.substring(wallet.length - 4)}'),
            onTap: () => _copy('Wallet', wallet),
          ),
      ]),
      GardenSettingsGroup(children: [
        GardenSettingsRow(icon: GIcon.salir, title: 'Cerrar sesión', tone: GardenSettingsTone.danger, onTap: _logout),
      ]),
      Center(
        child: TextButton(
          onPressed: _isDeletingAccount ? null : _deleteAccount,
          child: _isDeletingAccount
              ? const GardenLoadingIndicator(size: 14, color: GardenColors.error)
              : Text('Eliminar mi cuenta',
                  style: TextStyle(color: GardenColors.error.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
    ];
  }

  /// Una sola pantalla para celular y web: en pantallas anchas, lo del rol a
  /// la izquierda y los ajustes a la derecha (antes eran dos copias del mismo
  /// menú que se habían desincronizado).
  Widget _buildAuthenticatedState({required bool wide}) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final top = <Widget>[
      _header(),
      const SizedBox(height: 18),
      if (_role == 'CAREGIVER' && _conversionInProgress) ...[
        _buildConversionBanner(textColor, subtextColor),
        const SizedBox(height: 18),
      ],
      if (WorkMode.available.length >= 2) ...[
        ModeSwitcherCard(isCompany: _caregiverProfile?['isCompany'] == true),
        const SizedBox(height: 18),
      ],
    ];
    if (!wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...top,
        ..._roleGroups(),
        ..._commonGroups(),
        const SizedBox(height: 32),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ...top,
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _roleGroups())),
        const SizedBox(width: 20),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _commonGroups())),
      ]),
      const SizedBox(height: 32),
    ]);
  }

  Widget _buildUnauthenticatedState() {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            const Center(child: Brote(pose: BrotePose.hola, size: 120)),
            const SizedBox(height: 16),
            Text('Inicia sesión para ver tu perfil',
                textAlign: TextAlign.center, style: GardenText.h4.copyWith(color: textColor, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('Tus reservas, mascotas y ajustes, en un solo lugar.',
                style: TextStyle(color: subtextColor, fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 28),
            GardenButton(label: 'Iniciar sesión', onPressed: () => context.push('/login')),
            const SizedBox(height: 12),
            GardenButton(label: 'Crear cuenta', outline: true, onPressed: () => context.push('/register')),
          ],
        ),
      ),
    );
  }

  // ── Switch role ─────────────────────────────────────────────────────────────

  // ── Equipo de una empresa ───────────────────────────────────────────────────
  // El cambio entre dueño / cuidador / empleado vive en ModeSwitcherCard.
  // Esta fila es solo para quien aún no tiene otra identidad (dueño de mascota).


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

}

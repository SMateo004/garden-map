import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../design/brote.dart';
import '../../design/garden_depth.dart';
import '../../design/garden_icons.dart';
import '../../design/garden_service.dart';
import '../../design/garden_service_icon.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_service.dart';
import '../../services/auth_state.dart';
import '../client/my_data_screen.dart';
import '../../theme/garden_motion.dart';

/// Primera pantalla del teléfono (invitados y recién logueados): elegir qué
/// necesita la mascota. Tres tarjetas planas con el icono y color de cada
/// servicio, y lo que falta para reservar dicho ahí mismo (antes salía una
/// ventana emergente al segundo de entrar).
class MobileServiceSelectorScreen extends StatefulWidget {
  const MobileServiceSelectorScreen({super.key});

  @override
  State<MobileServiceSelectorScreen> createState() =>
      _MobileServiceSelectorScreenState();
}

/// Lo que le falta al dueño para poder reservar.
enum _Missing { profile, pet }

class _MobileServiceSelectorScreenState extends State<MobileServiceSelectorScreen> {
  String? _userName;
  String? _tapping; // servicio tocado, para hundir su tarjeta
  _Missing? _missing;

  @override
  void initState() {
    super.initState();
    _loadName();
    // Un login que ocurre con esta pantalla ya montada debajo (invitado en
    // /service-selector → push a /login → go de vuelta) reutiliza este
    // mismo State — initState no vuelve a correr, así que ni el nombre ni
    // AuthState.hasSession (leído en vivo en build) se reflejaban hasta
    // tocar algo que forzara un rebuild. Ver doc de loginSuccessNotifier.
    loginSuccessNotifier.addListener(_onLoginSuccess);
    _checkWhatsMissing();
  }

  static const _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.gardenbo.com/api',
  );

  /// Mismos campos que _isClientDataIncomplete en profile_screen.dart —
  /// si cambian ahí, cambiar acá también.
  bool _isProfileIncomplete(Map<String, dynamic> user) {
    final phone = (user['phone'] as String? ?? '').trim();
    return (user['firstName'] as String? ?? '').trim().isEmpty ||
        (user['lastName'] as String? ?? '').trim().isEmpty ||
        !RegExp(r'^[67][0-9]{7}$').hasMatch(phone) ||
        (user['addressStreet'] as String? ?? '').trim().isEmpty ||
        (user['dateOfBirth'] == null) ||
        (user['profilePicture'] as String? ?? '').trim().isEmpty;
  }

  /// Perfil incompleto o sin mascotas: los dos impiden reservar.
  Future<void> _checkWhatsMissing() async {
    if (!AuthState.hasSession) {
      if (mounted) setState(() => _missing = null);
      return;
    }
    final token = AuthState.token;
    if (token.isEmpty) return;

    Map<String, dynamic> user;
    try {
      user = await AuthService().getMe(token);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (_isProfileIncomplete(user)) {
      setState(() => _missing = _Missing.profile);
      return;
    }

    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/client/pets'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] != true) return;
      final pets = data['data'] as List<dynamic>;
      if (mounted) setState(() => _missing = pets.isEmpty ? _Missing.pet : null);
    } catch (_) {
      return;
    }
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _userName = prefs.getString('user_name')?.split(' ').first);
  }

  Future<void> _select(GardenService service) async {
    HapticFeedback.selectionClick();
    setState(() => _tapping = service.apiValue);
    await Future.delayed(GardenMotion.resolve(context, GardenMotion.instant));
    if (!mounted) return;
    context.go('/marketplace?service=${service.apiValue.toLowerCase()}');
  }

  Future<void> _fixMissing() async {
    HapticFeedback.selectionClick();
    if (_missing == _Missing.profile) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyDataScreen()));
      if (mounted) _checkWhatsMissing();
    } else {
      context.go('/my-pets-tab');
    }
  }

  @override
  void dispose() {
    loginSuccessNotifier.removeListener(_onLoginSuccess);
    super.dispose();
  }

  void _onLoginSuccess() {
    _loadName();
    _checkWhatsMissing();
    if (mounted) setState(() {}); // fuerza releer AuthState.hasSession en build()
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final hasSession = AuthState.hasSession;

    final greeting = hasSession
        ? (_userName != null ? 'Hola, $_userName' : 'Hola')
        : 'Hola, qué gusto verte';

    // Entrada escalonada corta; con movimiento reducido aparece todo junto.
    Widget enter(Widget child, int i) => child
        .animate()
        .fadeIn(duration: GardenMotion.resolve(context, GardenMotion.quick), delay: (60 * i).ms)
        .slideY(begin: 0.06, end: 0, duration: GardenMotion.resolve(context, GardenMotion.quick), curve: GardenMotion.enter);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                // ── Barra: marca y, para invitados, entrar ──
                Row(children: [
                  Image.asset(isDark ? 'assets/images/logo-horizontal-dark.png' : 'assets/images/logo-horizontal.png', height: 48),
                  const Spacer(),
                  if (!hasSession) ...[
                    TextButton(
                      onPressed: () => context.push('/login'),
                      child: const Text('Iniciar sesión',
                          style: TextStyle(color: GardenColors.primary, fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
                const SizedBox(height: 18),

                // ── Saludo ──
                enter(
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    const Brote(pose: BrotePose.hola, size: 64),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(greeting,
                            style: TextStyle(color: subtextColor, fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('¿Qué necesita tu mascota hoy?',
                            style: TextStyle(color: textColor, fontSize: 25, fontWeight: FontWeight.w900, height: 1.15)),
                      ]),
                    ),
                  ]),
                  0,
                ),
                const SizedBox(height: 20),

                // ── Lo que falta para reservar ──
                if (_missing != null) ...[
                  enter(_MissingCard(missing: _missing!, onTap: _fixMissing), 1),
                  const SizedBox(height: 14),
                ],

                // ── Servicios (día → noche) ──
                for (final (i, s) in GardenService.values.indexed) ...[
                  enter(
                    _ServiceCard(
                      service: s,
                      isTapping: _tapping == s.apiValue,
                      onTap: () => _select(s),
                    ),
                    i + 2,
                  ),
                  const SizedBox(height: 12),
                ],

                const SizedBox(height: 4),
                Center(
                  child: Text('Puedes cambiar de servicio cuando quieras.',
                      style: TextStyle(color: subtextColor, fontSize: 12.5)),
                ),

                // ── Invitados: crear cuenta ──
                if (!hasSession) ...[
                  const SizedBox(height: 20),
                  GardenButton(label: 'Crear cuenta gratis', outline: true, onPressed: () => context.push('/register')),
                ],

                // ── Entrada al registro de cuidador: no hay otra desde la
                // primera pantalla de la app. ──
                const SizedBox(height: 22),
                _CaregiverInvite(onTap: () => context.push('/become-caregiver')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tarjeta de servicio ──────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  final GardenService service;
  final bool isTapping;
  final VoidCallback onTap;

  const _ServiceCard({required this.service, required this.isTapping, required this.onTap});

  /// Qué es, en una frase, y tres datos ciertos (verificados contra las reglas
  /// del servidor: paseo de 30 o 60 min, guardería de 3 a 10 h, hasta 3
  /// mascotas por reserva).
  (String, List<String>) get _copy => switch (service) {
        GardenService.paseo => (
            'Un cuidador pasea a tu perro y lo trae de vuelta.',
            ['30 o 60 min', 'GPS en vivo', 'Fotos'],
          ),
        GardenService.guarderia => (
            'Tu mascota pasa el día con un cuidador mientras trabajas.',
            ['3 a 10 horas', 'Mañana o tarde', 'Varios días'],
          ),
        GardenService.hospedaje => (
            'Se queda a dormir en casa del cuidador.',
            ['Por noche', 'Chat y fotos'],
          ),
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final ink = service.ink(isDark);
    final (description, facts) = _copy;

    return Semantics(
      button: true,
      label: '${service.label}. $description',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: GardenPress(
          radius: BorderRadius.circular(GardenRadius.xl),
          child: AnimatedContainer(
            duration: GardenMotion.resolve(context, GardenMotion.instant),
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            decoration: BoxDecoration(
              color: service.soft(isDark),
              borderRadius: BorderRadius.circular(GardenRadius.xl),
              border: Border.all(color: isTapping ? ink : ink.withValues(alpha: 0.25), width: isTapping ? 1.5 : 1),
            ),
            child: Row(children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: surface, shape: BoxShape.circle),
                child: GardenServiceIcon(service, size: 34, active: true),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(service.label,
                      style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(description, style: TextStyle(color: subtextColor, fontSize: 13, height: 1.35)),
                  const SizedBox(height: 6),
                  // Cada dato entero en su línea: nunca "Fotos del / paseo".
                  Wrap(spacing: 10, runSpacing: 2, children: [
                    for (final f in facts)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 4, height: 4, decoration: BoxDecoration(color: ink, shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Text(f, style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w800)),
                      ]),
                  ]),
                ]),
              ),
              const SizedBox(width: 6),
              GardenIcon(GIcon.siguiente, size: GIconSize.sm, color: ink),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Lo que falta para reservar ───────────────────────────────────────────────

class _MissingCard extends StatelessWidget {
  final _Missing missing;
  final VoidCallback onTap;
  const _MissingCard({required this.missing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final profile = missing == _Missing.profile;
    final (icon, title, body, cta) = profile
        ? (GIcon.perfil, 'Completa tu perfil', 'Lo necesitas para tu primera reserva.', 'Completar')
        : (GIcon.mascotas, 'Agrega a tu mascota', 'Los cuidadores necesitan conocerla antes de reservar.', 'Agregar');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: GardenColors.warning.withValues(alpha: isDark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        border: Border.all(color: GardenColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        GardenIcon(icon, color: GardenColors.warning, state: GIconState.active),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: textColor, fontSize: 14.5, fontWeight: FontWeight.w800)),
            Text(body, style: TextStyle(color: subtextColor, fontSize: 12.5, height: 1.3)),
          ]),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onTap,
          child: Text(cta, style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

// ── ¿Quieres cuidar mascotas? ────────────────────────────────────────────────

class _CaregiverInvite extends StatelessWidget {
  final VoidCallback onTap;
  const _CaregiverInvite({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: GardenPress(
          radius: BorderRadius.circular(GardenRadius.lg),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GardenRadius.lg),
              border: Border.all(color: border),
            ),
            child: Row(children: [
              const GardenIcon(GIcon.huella, color: GardenColors.primary, state: GIconState.active),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('¿Te gustaría cuidar mascotas?',
                      style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w800)),
                  Text('Gana dinero con paseos, guardería u hospedaje.',
                      style: TextStyle(color: subtextColor, fontSize: 12.5)),
                ]),
              ),
              const GardenIcon(GIcon.siguiente, size: GIconSize.sm, color: GardenColors.primary),
            ]),
          ),
        ),
      ),
    );
  }
}

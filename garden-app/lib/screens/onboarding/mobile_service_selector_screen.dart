import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_service.dart';
import '../../services/auth_state.dart';
import '../client/my_data_screen.dart';

class MobileServiceSelectorScreen extends StatefulWidget {
  const MobileServiceSelectorScreen({super.key});

  @override
  State<MobileServiceSelectorScreen> createState() =>
      _MobileServiceSelectorScreenState();
}

class _MobileServiceSelectorScreenState
    extends State<MobileServiceSelectorScreen> with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _card1Fade;
  late final Animation<Offset> _card1Slide;
  late final Animation<double> _card2Fade;
  late final Animation<Offset> _card2Slide;
  late final Animation<double> _card3Fade;
  late final Animation<Offset> _card3Slide;

  String? _userName;
  String? _tapping; // 'paseo' | 'hospedaje' | 'guarderia' — para animación de tap

  @override
  void initState() {
    super.initState();
    _loadName();

    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));

    _headerFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceCtrl,
          curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
    );
    _headerSlide =
        Tween<Offset>(begin: const Offset(0, -0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceCtrl,
          curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
    );
    _card1Fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceCtrl,
          curve: const Interval(0.25, 0.65, curve: Curves.easeOut)),
    );
    _card1Slide =
        Tween<Offset>(begin: const Offset(-0.2, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceCtrl,
          curve: const Interval(0.25, 0.65, curve: Curves.easeOut)),
    );
    _card2Fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceCtrl,
          curve: const Interval(0.45, 0.80, curve: Curves.easeOut)),
    );
    _card2Slide =
        Tween<Offset>(begin: const Offset(0.2, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceCtrl,
          curve: const Interval(0.45, 0.80, curve: Curves.easeOut)),
    );
    _card3Fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceCtrl,
          curve: const Interval(0.60, 1.0, curve: Curves.easeOut)),
    );
    _card3Slide =
        Tween<Offset>(begin: const Offset(-0.2, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceCtrl,
          curve: const Interval(0.60, 1.0, curve: Curves.easeOut)),
    );

    _entranceCtrl.forward();

    // Da tiempo a la animación de entrada antes de tapar la pantalla con un diálogo.
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _maybeShowProfileOrPetNudge();
    });
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

  Future<void> _maybeShowProfileOrPetNudge() async {
    if (!AuthState.hasSession) return;
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
      await showDialog<void>(
        context: context,
        builder: (ctx) => GardenGlassDialog(
          title: const Text('Completa tu perfil'),
          content: const Text(
            'Completa tu perfil ahora para poder realizar tu primera reserva.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Ahora no',
                  style: TextStyle(
                      color: themeNotifier.isDark
                          ? GardenColors.darkTextSecondary
                          : GardenColors.lightTextSecondary)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const MyDataScreen()));
              },
              child: const Text('Completar perfil',
                  style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return;
    }

    // Perfil completo — si no tiene mascotas registradas, es obligatorio
    // agregar una antes de poder reservar, así que se lo sugerimos acá.
    List<dynamic> pets = [];
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/client/pets'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) pets = data['data'] as List<dynamic>;
    } catch (_) {
      return;
    }
    if (!mounted || pets.isNotEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => GardenGlassDialog(
        title: const Text('Añade a tu mascota'),
        content: const Text(
          'Para poder reservar un servicio, primero necesitas registrar a tu mascota.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Ahora no',
                style: TextStyle(
                    color: themeNotifier.isDark
                        ? GardenColors.darkTextSecondary
                        : GardenColors.lightTextSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/my-pets-tab');
            },
            child: const Text('Añadir mascota',
                style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _userName = prefs.getString('user_name')?.split(' ').first);
  }

  Future<void> _select(String service) async {
    HapticFeedback.selectionClick();
    setState(() => _tapping = service);
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    context.go('/marketplace?service=$service');
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final safePad = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _entranceCtrl,
          builder: (_, __) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, safePad.top > 0 ? 16 : 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Header ──
                SlideTransition(
                  position: _headerSlide,
                  child: FadeTransition(
                    opacity: _headerFade,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: GardenColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.pets_rounded,
                                      color: GardenColors.primary, size: 14),
                                  SizedBox(width: 5),
                                  Text('GARDEN',
                                      style: TextStyle(
                                        color: GardenColors.primary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        letterSpacing: 1,
                                      )),
                                ],
                              ),
                            ),
                            if (!AuthState.hasSession)
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () => context.push('/login'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: GardenColors.primary,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Iniciar sesión',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  ),
                                  const SizedBox(width: 4),
                                  ElevatedButton(
                                    onPressed: () => context.push('/register'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: GardenColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20)),
                                      textStyle: const TextStyle(
                                          fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                    child: const Text('Registrarse'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          AuthState.hasSession
                              ? (_userName != null ? '¡Hola, $_userName! 👋' : '¡Bienvenido! 👋')
                              : 'Hola 👋\nQue gusto verte por aqui',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '¿Qué servicio necesitas\npara tu mascota hoy?',
                          style: TextStyle(
                            color: subtextColor,
                            fontSize: 17,
                            height: 1.4,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Tarjeta PASEO ──
                SlideTransition(
                  position: _card1Slide,
                  child: FadeTransition(
                    opacity: _card1Fade,
                    child: _ServiceCard(
                      service: 'paseo',
                      emoji: '🦮',
                      title: 'Paseo',
                      description: 'Un cuidador lleva a tu perro a pasear. Disponible en bloques de 1 hora.',
                      features: const ['Seguimiento GPS', 'Fotos durante el paseo', 'Hasta 3 perros'],
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                      ),
                      isTapping: _tapping == 'paseo',
                      surface: surface,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      onTap: () => _select('paseo'),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Tarjeta HOSPEDAJE ──
                SlideTransition(
                  position: _card2Slide,
                  child: FadeTransition(
                    opacity: _card2Fade,
                    child: _ServiceCard(
                      service: 'hospedaje',
                      emoji: '🏠',
                      title: 'Hospedaje',
                      description: 'Tu mascota se queda en casa del cuidador. Cuidado 24/7 por noches completas.',
                      features: const ['Precio por noche', 'Actualizaciones diarias', 'Casa verificada'],
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                      ),
                      isTapping: _tapping == 'hospedaje',
                      surface: surface,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      onTap: () => _select('hospedaje'),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Tarjeta GUARDERÍA ──
                SlideTransition(
                  position: _card3Slide,
                  child: FadeTransition(
                    opacity: _card3Fade,
                    child: _ServiceCard(
                      service: 'guarderia',
                      emoji: '🏡',
                      title: 'Guardería',
                      description: 'Deja a tu mascota por horas con un cuidador. Ideal para jornadas laborales.',
                      features: const ['Por horas (3h a 10h)', 'Foto al inicio y al final', 'Precio por hora'],
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
                      ),
                      isTapping: _tapping == 'guarderia',
                      surface: surface,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      onTap: () => _select('guarderia'),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Footer ──
                FadeTransition(
                  opacity: _card2Fade,
                  child: Center(
                    child: Text(
                      'Siempre puedes cambiar el servicio después',
                      style: TextStyle(
                          color: subtextColor.withValues(alpha: 0.6),
                          fontSize: 12),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── CTA cuidador — no hay un botón dedicado en el flujo de
                // login/registro, así que este texto es la única entrada al
                // registro de cuidador desde la primera pantalla de la app. ──
                FadeTransition(
                  opacity: _card2Fade,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => context.push('/become-caregiver'),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(color: subtextColor, fontSize: 13),
                          children: [
                            const TextSpan(text: '¿Querés cuidar mascotas? '),
                            TextSpan(
                              text: 'Conviértete en cuidador',
                              style: TextStyle(
                                color: GardenColors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
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
  final String service;
  final String emoji;
  final String title;
  final String description;
  final List<String> features;
  final Gradient gradient;
  final bool isTapping;
  final Color surface;
  final Color textColor;
  final Color subtextColor;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.service,
    required this.emoji,
    required this.title,
    required this.description,
    required this.features,
    required this.gradient,
    required this.isTapping,
    required this.surface,
    required this.textColor,
    required this.subtextColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isTapping ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Emoji
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 14),

              // Texto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        )),
                    const SizedBox(height: 3),
                    Text(description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 12,
                          height: 1.35,
                        )),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 5,
                      runSpacing: 3,
                      children: features.map((f) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(f,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            )),
                      )).toList(),
                    ),
                  ],
                ),
              ),

              // Flecha
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

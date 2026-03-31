import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

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

  String? _userName;
  String? _tapping; // 'paseo' | 'hospedaje' — para animación de tap

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
          curve: const Interval(0.45, 0.85, curve: Curves.easeOut)),
    );
    _card2Slide =
        Tween<Offset>(begin: const Offset(0.2, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceCtrl,
          curve: const Interval(0.45, 0.85, curve: Curves.easeOut)),
    );

    _entranceCtrl.forward();
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _userName = prefs.getString('user_name')?.split(' ').first);
  }

  Future<void> _select(String service) async {
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
          builder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: safePad.top > 0 ? 16 : 24),

                // ── Header ──
                SlideTransition(
                  position: _headerSlide,
                  child: FadeTransition(
                    opacity: _headerFade,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
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
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _userName != null
                              ? '¡Hola, $_userName! 👋'
                              : '¡Bienvenido! 👋',
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

                const SizedBox(height: 36),

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

                const Spacer(),

                // ── Footer ──
                FadeTransition(
                  opacity: _card2Fade,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Center(
                      child: Text(
                        'Siempre puedes cambiar el servicio después',
                        style: TextStyle(
                            color: subtextColor.withValues(alpha: 0.6),
                            fontSize: 12),
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
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Emoji grande
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 36)),
                ),
              ),
              const SizedBox(width: 16),

              // Texto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        )),
                    const SizedBox(height: 4),
                    Text(description,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          height: 1.4,
                        )),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: features.map((f) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(f,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

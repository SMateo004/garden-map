import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class ClientWelcomeScreen extends StatefulWidget {
  const ClientWelcomeScreen({super.key});

  @override
  State<ClientWelcomeScreen> createState() => _ClientWelcomeScreenState();
}

class _ClientWelcomeScreenState extends State<ClientWelcomeScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  late AnimationController _illustrationController;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _illustrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.18, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _illustrationController,
      curve: Curves.easeOut,
    ));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _illustrationController, curve: Curves.easeOut),
    );
    _illustrationController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _illustrationController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _illustrationController.reset();
    _illustrationController.forward();
  }

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? '';
    if (userId.isNotEmpty) {
      await prefs.setBool('welcome_seen_$userId', true);
    }
    if (!mounted) return;
    context.go('/marketplace');
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
    } else {
      _complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        return Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: Column(
              children: [
                // ── BARRA SUPERIOR ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GardenSpacing.lg,
                    vertical: GardenSpacing.sm,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Logo pequeño
                      Row(
                        children: [
                          Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: GardenColors.primary,
                              borderRadius: GardenRadius.sm_,
                            ),
                            child: const Center(
                              child: Text('🌱', style: TextStyle(fontSize: 14)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'GARDEN',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                      // Botón saltar
                      if (_currentPage < 2)
                        TextButton(
                          onPressed: _complete,
                          style: TextButton.styleFrom(
                            foregroundColor: subtextColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: GardenSpacing.md,
                              vertical: GardenSpacing.xs,
                            ),
                          ),
                          child: const Text(
                            'Saltar',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        )
                      else
                        const SizedBox(width: 60),
                    ],
                  ),
                ),

                // ── PÁGINA DE CONTENIDO ─────────────────────────
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    children: [
                      _OnboardingPage(
                        slideAnim: _slideAnim,
                        fadeAnim: _fadeAnim,
                        illustration: _Page1Illustration(isDark: isDark),
                        title: 'Encuentra al cuidador perfecto',
                        subtitle: 'Filtra por zona, tipo de servicio y tamaño de tu mascota. Lee reseñas reales de dueños como tú.',
                        textColor: textColor,
                        subtextColor: subtextColor,
                      ),
                      _OnboardingPage(
                        slideAnim: _slideAnim,
                        fadeAnim: _fadeAnim,
                        illustration: _Page2Illustration(isDark: isDark),
                        title: 'Reserva con total seguridad',
                        subtitle: 'Tu pago queda bloqueado en Polygon Blockchain hasta que el servicio se complete. Cero riesgo.',
                        textColor: textColor,
                        subtextColor: subtextColor,
                      ),
                      _OnboardingPage(
                        slideAnim: _slideAnim,
                        fadeAnim: _fadeAnim,
                        illustration: _Page3Illustration(isDark: isDark),
                        title: 'Tu mascota en buenas manos',
                        subtitle: 'Recibe fotos en tiempo real durante el servicio y chatea directamente con el cuidador.',
                        textColor: textColor,
                        subtextColor: subtextColor,
                      ),
                    ],
                  ),
                ),

                // ── CONTROLES INFERIORES ────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GardenSpacing.xxxl,
                    GardenSpacing.lg,
                    GardenSpacing.xxxl,
                    GardenSpacing.xxxl,
                  ),
                  child: Column(
                    children: [
                      // Dots de progreso
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (i) {
                          final active = _currentPage == i;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeInOut,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 6,
                            width: active ? 28 : 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? GardenColors.primary
                                  : borderColor,
                              borderRadius: GardenRadius.full_,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: GardenSpacing.xxl),
                      // Botón acción
                      GardenButton(
                        label: _currentPage == 2 ? 'Empezar' : 'Siguiente',
                        icon: _currentPage == 2
                            ? Icons.rocket_launch_rounded
                            : Icons.arrow_forward_rounded,
                        onPressed: _nextPage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── PÁGINA GENÉRICA CON ANIMACIÓN ─────────────────────────────────────────
class _OnboardingPage extends StatelessWidget {
  final Animation<Offset> slideAnim;
  final Animation<double> fadeAnim;
  final Widget illustration;
  final String title;
  final String subtitle;
  final Color textColor;
  final Color subtextColor;

  const _OnboardingPage({
    required this.slideAnim,
    required this.fadeAnim,
    required this.illustration,
    required this.title,
    required this.subtitle,
    required this.textColor,
    required this.subtextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GardenSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Ilustración animada
          SlideTransition(
            position: slideAnim,
            child: FadeTransition(
              opacity: fadeAnim,
              child: illustration,
            ),
          ),
          const SizedBox(height: GardenSpacing.xxxl),
          // Título
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: GardenSpacing.md),
          // Subtítulo
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: subtextColor,
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── ILUSTRACIÓN PÁGINA 1: MARKETPLACE ────────────────────────────────────
class _Page1Illustration extends StatelessWidget {
  final bool isDark;
  const _Page1Illustration({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return SizedBox(
      height: 230,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Barra de búsqueda ────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: GardenRadius.full_,
                border: Border.all(color: GardenColors.primary, width: 1.5),
                boxShadow: GardenShadows.card,
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const Icon(Icons.search_rounded, color: GardenColors.primary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Buscar cuidador en tu zona...',
                    style: TextStyle(
                      color: subtextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Tarjeta de cuidador trasera (rotada) ─────────────
          Positioned(
            top: 52, right: 0,
            child: Transform.rotate(
              angle: 0.06,
              child: _MiniCaregiverCard(
                name: 'Carlos R.',
                rating: '4.8',
                price: 'Bs.70',
                emoji: '🐾',
                surface: surface,
                border: border,
                textColor: textColor,
                subtextColor: subtextColor,
              ),
            ),
          ),

          // ── Tarjeta de cuidador principal (frente) ───────────
          Positioned(
            top: 52, left: 0,
            child: _MiniCaregiverCard(
              name: 'Ana García',
              rating: '4.9',
              price: 'Bs.80',
              emoji: '🐕',
              verified: true,
              surface: surface,
              border: border,
              textColor: textColor,
              subtextColor: subtextColor,
            ),
          ),

          // ── Chips de filtro ───────────────────────────────────
          const Positioned(
            bottom: 0, left: 0,
            child: Row(
              children: [
                _FilterChip(label: 'Equipetrol', color: GardenColors.primary),
                SizedBox(width: 6),
                _FilterChip(label: '★ 4.5+', color: GardenColors.star),
                SizedBox(width: 6),
                _FilterChip(label: 'Pequeños', color: GardenColors.secondary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniCaregiverCard extends StatelessWidget {
  final String name;
  final String rating;
  final String price;
  final String emoji;
  final bool verified;
  final Color surface;
  final Color border;
  final Color textColor;
  final Color subtextColor;

  const _MiniCaregiverCard({
    required this.name,
    required this.rating,
    required this.price,
    required this.emoji,
    this.verified = false,
    required this.surface,
    required this.border,
    required this.textColor,
    required this.subtextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 158,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: GardenRadius.lg_,
        border: Border.all(color: border),
        boxShadow: GardenShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: GardenColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: GardenColors.star, size: 10),
                        const SizedBox(width: 2),
                        Text(
                          rating,
                          style: const TextStyle(
                            color: GardenColors.star,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                price,
                style: const TextStyle(
                  color: GardenColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                '/paseo',
                style: TextStyle(color: subtextColor, fontSize: 9),
              ),
            ],
          ),
          if (verified) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: GardenColors.success.withValues(alpha: 0.1),
                borderRadius: GardenRadius.full_,
                border: Border.all(color: GardenColors.success.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, color: GardenColors.success, size: 10),
                  SizedBox(width: 4),
                  Text(
                    'Verificado IA',
                    style: TextStyle(
                      color: GardenColors.success,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color color;
  const _FilterChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: GardenRadius.full_,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── ILUSTRACIÓN PÁGINA 2: SEGURIDAD BLOCKCHAIN ───────────────────────────
class _Page2Illustration extends StatelessWidget {
  final bool isDark;
  const _Page2Illustration({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;

    return SizedBox(
      height: 230,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Escudo principal ─────────────────────────────────
          CustomPaint(
            size: const Size(140, 160),
            painter: _ShieldPainter(isDark: isDark),
            child: SizedBox(
              width: 140,
              height: 160,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  // Ícono de candado dentro del escudo
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: GardenColors.success.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: GardenColors.success.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: GardenColors.success,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '100% Seguro',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Badge Polygon ─────────────────────────────────────
          Positioned(
            top: 8, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: GardenColors.polygon.withValues(alpha: 0.14),
                borderRadius: GardenRadius.full_,
                border: Border.all(color: GardenColors.polygon.withValues(alpha: 0.4)),
                boxShadow: GardenShadows.card,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('⬡', style: TextStyle(color: GardenColors.polygon, fontSize: 13)),
                  SizedBox(width: 5),
                  Text(
                    'Polygon',
                    style: TextStyle(
                      color: GardenColors.polygon,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Pago bloqueado (izquierda) ────────────────────────
          const Positioned(
            left: 0, bottom: 32,
            child: Column(
              children: [
                _MoneyBubble(amount: 'Bs.80', color: GardenColors.primary, label: 'Cliente paga'),
                SizedBox(height: 6),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: GardenColors.success,
                  size: 18,
                ),
              ],
            ),
          ),

          // ── Pago liberado (derecha) ───────────────────────────
          const Positioned(
            right: 0, bottom: 32,
            child: Column(
              children: [
                Icon(
                  Icons.arrow_forward_rounded,
                  color: GardenColors.success,
                  size: 18,
                ),
                SizedBox(height: 6),
                _MoneyBubble(amount: 'Bs.80', color: GardenColors.success, label: 'Cuidador cobra'),
              ],
            ),
          ),

          // ── Checkmark flotante arriba ─────────────────────────
          Positioned(
            top: 0, left: 24,
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: GardenColors.success,
                shape: BoxShape.circle,
                boxShadow: GardenShadows.primary,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyBubble extends StatelessWidget {
  final String amount;
  final Color color;
  final String label;

  const _MoneyBubble({
    required this.amount,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: GardenRadius.md_,
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            amount,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.7),
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// CustomPainter para el escudo
class _ShieldPainter extends CustomPainter {
  final bool isDark;
  const _ShieldPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = GardenColors.success.withValues(alpha: isDark ? 0.10 : 0.08)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = GardenColors.success.withValues(alpha: isDark ? 0.35 : 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path();
    final w = size.width;
    final h = size.height;

    // Forma de escudo
    path.moveTo(w * 0.5, 0);
    path.lineTo(w * 0.95, h * 0.15);
    path.quadraticBezierTo(w * 0.98, h * 0.2, w * 0.98, h * 0.28);
    path.lineTo(w * 0.98, h * 0.55);
    path.quadraticBezierTo(w * 0.95, h * 0.82, w * 0.5, h);
    path.quadraticBezierTo(w * 0.05, h * 0.82, w * 0.02, h * 0.55);
    path.lineTo(w * 0.02, h * 0.28);
    path.quadraticBezierTo(w * 0.02, h * 0.2, w * 0.05, h * 0.15);
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => old.isDark != isDark;
}

// ── ILUSTRACIÓN PÁGINA 3: FOTOS EN TIEMPO REAL ───────────────────────────
class _Page3Illustration extends StatelessWidget {
  final bool isDark;
  const _Page3Illustration({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return SizedBox(
      height: 230,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // ── Silueta del teléfono ──────────────────────────────
          Container(
            width: 130, height: 210,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: border, width: 2),
              boxShadow: GardenShadows.elevated,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                children: [
                  // Notch del teléfono
                  Container(
                    height: 22,
                    color: surfaceEl,
                    child: Center(
                      child: Container(
                        width: 40, height: 5,
                        decoration: BoxDecoration(
                          color: border,
                          borderRadius: GardenRadius.full_,
                        ),
                      ),
                    ),
                  ),
                  // Foto de la mascota (simulada con container + emoji)
                  Container(
                    width: double.infinity,
                    height: 110,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          GardenColors.secondary.withValues(alpha: 0.3),
                          GardenColors.primary.withValues(alpha: 0.2),
                        ],
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Text('🐶', style: TextStyle(fontSize: 52)),
                        // Punto de grabación en vivo
                        Positioned(
                          top: 8, right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: GardenColors.error,
                              borderRadius: GardenRadius.full_,
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, color: Colors.white, size: 6),
                                SizedBox(width: 3),
                                Text(
                                  'EN VIVO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 7,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Chat mini dentro del teléfono
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Mensaje del cuidador
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: surfaceEl,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
                                bottomRight: Radius.circular(10),
                              ),
                            ),
                            child: Text(
                              '¡Todo bien! 🐾',
                              style: TextStyle(color: textColor, fontSize: 9),
                            ),
                          ),
                          const SizedBox(height: 5),
                          // Mensaje del cliente
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: const BoxDecoration(
                                color: GardenColors.primary,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(10),
                                  topRight: Radius.circular(10),
                                  bottomLeft: Radius.circular(10),
                                ),
                              ),
                              child: const Text(
                                '¡Gracias! 😊',
                                style: TextStyle(color: Colors.white, fontSize: 9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Notificación de foto (derecha flotante) ───────────
          Positioned(
            right: -8, top: 28,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: GardenRadius.md_,
                border: Border.all(color: border),
                boxShadow: GardenShadows.card,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: GardenColors.secondary.withValues(alpha: 0.15),
                      borderRadius: GardenRadius.sm_,
                    ),
                    child: const Center(
                      child: Text('📸', style: TextStyle(fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Nueva foto',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'hace 2 min',
                        style: TextStyle(color: subtextColor, fontSize: 8),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Corazón flotante (izquierda) ──────────────────────
          Positioned(
            left: 4, top: 60,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: GardenColors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: GardenColors.error.withValues(alpha: 0.3)),
              ),
              child: const Center(
                child: Text('❤️', style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

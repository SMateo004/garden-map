import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

// ── Modelo ──────────────────────────────────────────────────────────────────

class _Step {
  final Color color;
  final Color accentColor;
  final IconData icon;
  final String emoji;
  final IconData decorIcon1;
  final IconData decorIcon2;
  final String title;
  final String subtitle;
  const _Step({
    required this.color, required this.accentColor,
    required this.icon, required this.emoji,
    required this.decorIcon1, required this.decorIcon2,
    required this.title, required this.subtitle,
  });
}

const _kSteps = [
  _Step(
    color: Color(0xFF2D7D32), accentColor: Color(0xFF66BB6A),
    icon: Icons.search_rounded, emoji: '🔍',
    decorIcon1: Icons.location_on_rounded, decorIcon2: Icons.star_rounded,
    title: 'Encuentra tu cuidador',
    subtitle: 'Explora cuidadores verificados cerca de ti en Santa Cruz, con fotos reales y reseñas de dueños como tú.',
  ),
  _Step(
    color: Color(0xFF1565C0), accentColor: Color(0xFF42A5F5),
    icon: Icons.pets_rounded, emoji: '🐾',
    decorIcon1: Icons.favorite_rounded, decorIcon2: Icons.verified_rounded,
    title: 'Perfiles de confianza',
    subtitle: 'Cada cuidador pasa por verificación de identidad. Revisa su experiencia, servicios y disponibilidad.',
  ),
  _Step(
    color: Color(0xFF6A1B9A), accentColor: Color(0xFFAB47BC),
    icon: Icons.calendar_today_rounded, emoji: '📅',
    decorIcon1: Icons.access_time_rounded, decorIcon2: Icons.check_circle_rounded,
    title: 'Reserva en segundos',
    subtitle: 'Elige el servicio, la fecha y el horario que más te convenga. Sin llamadas ni complicaciones.',
  ),
  _Step(
    color: Color(0xFFE65100), accentColor: Color(0xFFFFA726),
    icon: Icons.lock_rounded, emoji: '🔒',
    decorIcon1: Icons.shield_rounded, decorIcon2: Icons.credit_card_rounded,
    title: 'Pago 100% seguro',
    subtitle: 'Tu dinero queda retenido en un contrato inteligente hasta que confirmes que el servicio fue completado.',
  ),
  _Step(
    color: Color(0xFF00695C), accentColor: Color(0xFF26A69A),
    icon: Icons.photo_camera_rounded, emoji: '📸',
    decorIcon1: Icons.notifications_rounded, decorIcon2: Icons.star_rounded,
    title: 'Tranquilidad total',
    subtitle: 'Recibe fotos y actualizaciones en tiempo real durante el servicio. Al final, califica la experiencia.',
  ),
];

// ── Pantalla principal ───────────────────────────────────────────────────────

class MobileOnboardingScreen extends StatefulWidget {
  const MobileOnboardingScreen({super.key});

  @override
  State<MobileOnboardingScreen> createState() => _MobileOnboardingScreenState();
}

class _MobileOnboardingScreenState extends State<MobileOnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _page = 0;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn));
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mobile_onboarding_seen', true);
    if (mounted) context.go('/login');
  }

  void _next() {
    if (_page < _kSteps.length - 1) {
      _fadeCtrl.reverse().then((_) {
        _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
        _fadeCtrl.forward();
      });
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _kSteps[_page];
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Fondo degradado animado
          AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [step.color, step.accentColor],
              ),
            ),
          ),

          // PageView con ilustraciones
          PageView.builder(
            controller: _pageCtrl,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (i) {
              setState(() => _page = i);
              _fadeCtrl.forward(from: 0);
            },
            itemCount: _kSteps.length,
            itemBuilder: (_, i) => _StepIllustration(step: _kSteps[i], stepIndex: i, size: size),
          ),

          // Panel inferior con texto y botones
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(28, 32, 28, MediaQuery.of(context).padding.bottom + 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.5),
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      step.title,
                      textAlign: TextAlign.center,
                      style: GardenText.h3.copyWith(
                        color: Colors.white,
                        fontSize: 26,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      step.subtitle,
                      textAlign: TextAlign.center,
                      style: GardenText.body.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Dots indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_kSteps.length, (i) {
                        final active = i == _page;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),

                    // Botón principal
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _next,
                        child: Text(
                          _page == _kSteps.length - 1 ? '¡Comenzar!' : 'Siguiente',
                          style: GardenText.body.copyWith(
                            color: step.color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),

                    // Saltar
                    if (_page < _kSteps.length - 1) ...[
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _finish,
                        child: Text(
                          'Saltar introducción',
                          style: GardenText.metadata.copyWith(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Ilustración por paso ─────────────────────────────────────────────────────

class _StepIllustration extends StatefulWidget {
  final _Step step;
  final int stepIndex;
  final Size size;
  const _StepIllustration({required this.step, required this.stepIndex, required this.size});

  @override
  State<_StepIllustration> createState() => _StepIllustrationState();
}

class _StepIllustrationState extends State<_StepIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _float;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _float = Tween<double>(begin: -10, end: 10)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _scale = Tween<double>(begin: 0.94, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.step;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Stack(
        fit: StackFit.expand,
        children: [
          // Círculos decorativos de fondo
          Positioned(
            top: -70, right: -70,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            top: 100, left: -50,
            child: Container(
              width: 140, height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),

          // Iconos flotantes decorativos
          Positioned(
            top: widget.size.height * 0.09 + _float.value * 0.4,
            left: 36,
            child: Opacity(
              opacity: 0.22,
              child: Icon(s.decorIcon1, color: Colors.white, size: 34),
            ),
          ),
          Positioned(
            top: widget.size.height * 0.18 - _float.value * 0.3,
            right: 44,
            child: Opacity(
              opacity: 0.22,
              child: Icon(s.decorIcon2, color: Colors.white, size: 28),
            ),
          ),
          Positioned(
            top: widget.size.height * 0.28 + _float.value * 0.2,
            left: 90,
            child: Opacity(
              opacity: 0.12,
              child: Icon(s.icon, color: Colors.white, size: 22),
            ),
          ),

          // Emoji central flotante
          Positioned(
            top: 0,
            bottom: widget.size.height * 0.44,
            left: 0, right: 0,
            child: Center(
              child: Transform.translate(
                offset: Offset(0, _float.value),
                child: ScaleTransition(
                  scale: _scale,
                  child: Container(
                    width: 164,
                    height: 164,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 40,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(s.emoji, style: const TextStyle(fontSize: 74)),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Badge "Paso X de 5"
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(s.icon, color: Colors.white, size: 13),
                  const SizedBox(width: 6),
                  Text(
                    'Paso ${widget.stepIndex + 1} de ${_kSteps.length}',
                    style: GardenText.metadata.copyWith(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/garden_theme.dart';

// ── Data model ───────────────────────────────────────────────────────────────

class TutorialStep {
  final String emoji;
  final String title;
  final String body;
  /// null → centred welcome card (no spotlight)
  final Offset? spotlightCenter;
  final double spotlightRadius;

  const TutorialStep({
    required this.emoji,
    required this.title,
    required this.body,
    this.spotlightCenter,
    this.spotlightRadius = 54,
  });
}

// ── Public API ────────────────────────────────────────────────────────────────

class GardenTutorial {
  GardenTutorial._();

  /// Displays the tutorial overlay once per user.
  /// [prefKey] should be unique per role, e.g. 'tutorial_caregiver_v1_$userId'.
  /// Silently skips if the key has already been set in SharedPreferences.
  static Future<void> maybeShow(
    BuildContext context, {
    required String prefKey,
    required List<TutorialStep> Function(Size size, double bottomPad) stepsBuilder,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(prefKey) == true) return;
    await prefs.setBool(prefKey, true);
    if (!context.mounted) return;

    final size = MediaQuery.of(context).size;
    final bottom = MediaQuery.of(context).padding.bottom;
    final steps = stepsBuilder(size, bottom);
    if (steps.isEmpty || !context.mounted) return;

    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (_) => _TutorialOverlay(
        steps: steps,
        onDismiss: () => entry?.remove(),
      ),
    );
    Overlay.of(context).insert(entry);
  }

  /// Returns the screen-space centre of a bottom-nav item.
  /// Works with LiquidGlassNavBar (outer padding 20+20, GlassBox 4+4, nav h ≈ 40 above safe area).
  static Offset navItemOffset(int index, int total, Size size, double bottomPad) {
    final itemWidth = (size.width - 48) / total;
    final x = 24 + itemWidth * (index + 0.5);
    final y = size.height - bottomPad - 42;
    return Offset(x, y);
  }
}

// ── Overlay ───────────────────────────────────────────────────────────────────

class _TutorialOverlay extends StatefulWidget {
  final List<TutorialStep> steps;
  final VoidCallback onDismiss;

  const _TutorialOverlay({required this.steps, required this.onDismiss});

  @override
  State<_TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<_TutorialOverlay>
    with TickerProviderStateMixin {
  int _step = 0;
  late final AnimationController _pulseCtrl;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < widget.steps.length - 1) {
      _fadeCtrl.reverse().then((_) {
        if (!mounted) return;
        setState(() => _step++);
        _fadeCtrl.forward();
      });
    } else {
      _dismiss();
    }
  }

  void _dismiss() {
    _fadeCtrl.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottom = MediaQuery.of(context).padding.bottom;
    final step = widget.steps[_step];
    final isLast = _step == widget.steps.length - 1;
    final hasSpot = step.spotlightCenter != null;

    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            // ── Dark overlay + spotlight ──────────────────────────────────
            if (hasSpot)
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => SizedBox.fromSize(
                  size: size,
                  child: CustomPaint(
                    painter: _SpotlightPainter(
                      center: step.spotlightCenter!,
                      innerRadius: step.spotlightRadius,
                      glowRadius: step.spotlightRadius * _pulseAnim.value,
                    ),
                  ),
                ),
              )
            else
              Container(color: const Color(0xCC000000)),

            // ── Card ─────────────────────────────────────────────────────
            if (hasSpot)
              _buildPositionedCard(step, size, bottom, isLast)
            else
              _buildCenteredCard(step, isLast),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionedCard(
      TutorialStep step, Size size, double bottom, bool isLast) {
    final c = step.spotlightCenter!;
    final r = step.spotlightRadius;
    const cardH = 196.0;
    const gap = 22.0;

    final belowTop = c.dy + r + gap;
    final aboveTop = c.dy - r - gap - cardH;
    final topPos =
        (belowTop + cardH < size.height - bottom - 16) ? belowTop : aboveTop;

    return Positioned(
      top: topPos,
      left: 16,
      right: 16,
      child: _StepCard(
        step: step,
        current: _step,
        total: widget.steps.length,
        isLast: isLast,
        onNext: _next,
        onSkip: _dismiss,
      ),
    );
  }

  Widget _buildCenteredCard(TutorialStep step, bool isLast) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: _StepCard(
          step: step,
          current: _step,
          total: widget.steps.length,
          isLast: isLast,
          onNext: _next,
          onSkip: _dismiss,
          centered: true,
        ),
      ),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  final Offset center;
  final double innerRadius;
  final double glowRadius;

  const _SpotlightPainter({
    required this.center,
    required this.innerRadius,
    required this.glowRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Glow halo behind overlay
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          GardenColors.primary.withValues(alpha: 0.50),
          GardenColors.primary.withValues(alpha: 0.0),
        ],
        stops: const [0.48, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
    canvas.drawCircle(center, glowRadius, glowPaint);

    // Dark overlay with circular cutout
    final overlayPaint = Paint()..color = const Color(0xCC000000);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: innerRadius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    // Green ring
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..color = GardenColors.primary.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.center != center ||
      old.innerRadius != innerRadius ||
      old.glowRadius != glowRadius;
}

// ── Step card ─────────────────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final TutorialStep step;
  final int current;
  final int total;
  final bool isLast;
  final bool centered;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _StepCard({
    required this.step,
    required this.current,
    required this.total,
    required this.isLast,
    required this.onNext,
    required this.onSkip,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, centered ? 24 : 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emoji + progress dots
          Row(
            children: [
              Text(step.emoji, style: const TextStyle(fontSize: 30)),
              const Spacer(),
              Row(
                children: List.generate(total, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  margin: const EdgeInsets.only(left: 5),
                  width: i == current ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == current
                        ? GardenColors.primary
                        : GardenColors.primary.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                )),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            step.title,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step.body,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              if (!isLast)
                GestureDetector(
                  onTap: onSkip,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text(
                      'Saltar',
                      style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: onNext,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                  decoration: BoxDecoration(
                    color: GardenColors.primary,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: GardenColors.primary.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    isLast ? '¡Entendido! ✓' : 'Siguiente →',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

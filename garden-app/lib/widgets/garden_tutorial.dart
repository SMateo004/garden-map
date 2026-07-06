import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/garden_theme.dart';

// ── Data model ───────────────────────────────────────────────────────────────

class TutorialStep {
  final String emoji;
  final String title;
  final String body;

  /// Pre-calculated center (mobile bottom nav). Null → centred welcome card.
  final Offset? spotlightCenter;

  /// Alternative to spotlightCenter: resolved at render time from a GlobalKey.
  /// Useful for web elements whose position isn't known until layout.
  final GlobalKey? targetKey;
  final double spotlightRadius;

  const TutorialStep({
    required this.emoji,
    required this.title,
    required this.body,
    this.spotlightCenter,
    this.targetKey,
    this.spotlightRadius = 54,
  });
}

// ── Public API ────────────────────────────────────────────────────────────────

class GardenTutorial {
  GardenTutorial._();

  /// Shows the tutorial overlay exactly once per user (keyed by [prefKey]).
  static Future<void> maybeShow(
    BuildContext context, {
    required String prefKey,
    required List<TutorialStep> Function(Size size, double bottomPad)
    stepsBuilder,
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
      builder:
          (_) =>
              _TutorialOverlay(steps: steps, onDismiss: () => entry?.remove()),
    );
    Overlay.of(context).insert(entry);
  }

  /// Returns the screen-space centre of a LiquidGlassNavBar tab (mobile).
  /// Outer padding 20+20, GlassBox 4+4; nav visual height ≈ 42 above safe area.
  static Offset navItemOffset(
    int index,
    int total,
    Size size,
    double bottomPad,
  ) {
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
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.22,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

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

  /// Resolves the spotlight center from either a pre-calculated Offset
  /// or a GlobalKey (reads the RenderBox position at render time).
  Offset? _center(TutorialStep step) {
    if (step.spotlightCenter != null) return step.spotlightCenter;
    final ctx = step.targetKey?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final pos = box.localToGlobal(Offset.zero);
    return pos + Offset(box.size.width / 2, box.size.height / 2);
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
    final center = _center(step);
    final hasSpot = center != null;

    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            // ── Overlay + spotlight ───────────────────────────────────────
            if (hasSpot)
              AnimatedBuilder(
                animation: _pulseAnim,
                builder:
                    (_, __) => SizedBox.fromSize(
                      size: size,
                      child: CustomPaint(
                        painter: _SpotlightPainter(
                          center: center,
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
              _buildPositionedCard(step, center, size, bottom, isLast)
            else
              _buildCenteredCard(step, isLast),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionedCard(
    TutorialStep step,
    Offset c,
    Size size,
    double bottom,
    bool isLast,
  ) {
    final r = step.spotlightRadius;
    const gap = 20.0;
    // Real content height is dynamic (varies with text length/screen width) —
    // never assume a fixed card height for positioning. Instead cap the card
    // at the space actually available so it can shrink-to-fit or scroll
    // internally, but can never push its button row off-screen.
    final maxCardHeight = size.height - bottom - 32;

    // Left-side element (sidebar, web): place card to the right
    if (c.dx < size.width * 0.35) {
      return Positioned(
        top: 16,
        bottom: bottom + 16,
        left: c.dx + r + gap,
        right: 16,
        child: Align(
          alignment: Alignment.centerLeft,
          child: _StepCard(
            step: step,
            current: _step,
            total: widget.steps.length,
            isLast: isLast,
            onNext: _next,
            onSkip: _dismiss,
            maxHeight: maxCardHeight,
          ),
        ),
      );
    }

    // Top-area element (header tabs, web): place card below, anchored by its
    // top edge (grows downward — safe since we cap maxHeight above).
    // Bottom-area element (mobile nav): place card above, anchored by its
    // BOTTOM edge so it grows upward from the spotlight regardless of its
    // real height, instead of computing `top` from a guessed height.
    final belowTop = c.dy + r + gap;
    final roomBelow = size.height - bottom - 16 - belowTop;
    final placeBelow =
        roomBelow >= 120; // enough room for at least a compact card

    if (placeBelow) {
      return Positioned(
        top: belowTop,
        left: 16,
        right: 16,
        child: _StepCard(
          step: step,
          current: _step,
          total: widget.steps.length,
          isLast: isLast,
          onNext: _next,
          onSkip: _dismiss,
          maxHeight: roomBelow,
        ),
      );
    }

    final bottomPos = size.height - (c.dy - r - gap);
    return Positioned(
      bottom: bottomPos,
      left: 16,
      right: 16,
      child: _StepCard(
        step: step,
        current: _step,
        total: widget.steps.length,
        isLast: isLast,
        onNext: _next,
        onSkip: _dismiss,
        maxHeight: c.dy - r - gap - 16,
      ),
    );
  }

  Widget _buildCenteredCard(TutorialStep step, bool isLast) {
    final size = MediaQuery.of(context).size;
    final bottom = MediaQuery.of(context).padding.bottom;
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
          maxHeight: size.height - bottom - 64,
        ),
      ),
    );
  }
}

// ── Spotlight painter ─────────────────────────────────────────────────────────

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
    // Glow halo (drawn before the overlay so it shows through the cutout)
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            GardenColors.primary.withValues(alpha: 0.50),
            GardenColors.primary.withValues(alpha: 0.0),
          ],
          stops: const [0.48, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: glowRadius)),
    );

    // Dark overlay with circular cutout (even-odd fill rule)
    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addOval(Rect.fromCircle(center: center, radius: innerRadius))
        ..fillType = PathFillType.evenOdd,
      Paint()..color = const Color(0xCC000000),
    );

    // Green ring on the spotlight edge
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

  /// Hard cap so the card can never push its button row off-screen — if the
  /// title/body content doesn't fit, only that section scrolls internally.
  final double maxHeight;

  const _StepCard({
    required this.step,
    required this.current,
    required this.total,
    required this.isLast,
    required this.onNext,
    required this.onSkip,
    required this.maxHeight,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight.clamp(120.0, double.infinity),
      ),
      child: Container(
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
                  children: List.generate(
                    total,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      margin: const EdgeInsets.only(left: 5),
                      width: i == current ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color:
                            i == current
                                ? GardenColors.primary
                                : GardenColors.primary.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                  ],
                ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 11,
                    ),
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
      ),
    );
  }
}

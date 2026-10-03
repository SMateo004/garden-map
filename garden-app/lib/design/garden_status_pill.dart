import 'package:flutter/material.dart';

import '../narrative/booking_story.dart';
import '../theme/garden_motion.dart';
import 'garden_service.dart';

// ── PÍLDORA DE ESTADO ──────────────────────────────────────────────────────
// La única forma de mostrar el estado de una reserva. El punto pulsa solo
// cuando el servicio está en vivo.
//
//   GardenStatusPill(story)
//   GardenStatusPill(story, service: GardenService.paseo, trailing: '23 min')
class GardenStatusPill extends StatelessWidget {
  final BookingStory story;
  final GardenService? service;

  /// Texto extra después del estado, ej. tiempo transcurrido.
  final String? trailing;
  final bool dense;

  const GardenStatusPill(
    this.story, {
    super.key,
    this.service,
    this.trailing,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = StoryColors.of(story.tone, isDark: isDark, service: service);
    final label = trailing == null ? story.pill : '${story.pill} · $trailing';

    return AnimatedContainer(
      duration: GardenMotion.resolve(context, GardenMotion.expressive),
      curve: GardenMotion.enter,
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: colors.soft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GardenLiveDot(color: colors.ink, live: story.isLive, size: dense ? 6 : 7),
          SizedBox(width: dense ? 5 : 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.ink,
                fontSize: dense ? 11 : 12.5,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Punto de estado. Con [live] emite un pulso suave en bucle — el único bucle
/// permitido por GardenMotion junto con el icono del servicio en curso.
class GardenLiveDot extends StatefulWidget {
  final Color color;
  final bool live;
  final double size;

  const GardenLiveDot({super.key, required this.color, this.live = false, this.size = 7});

  @override
  State<GardenLiveDot> createState() => _GardenLiveDotState();
}

class _GardenLiveDotState extends State<GardenLiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(GardenLiveDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final run = widget.live && !GardenMotion.reduced(context);
    if (run && !_c.isAnimating) _c.repeat();
    if (!run && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox.square(
      dimension: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => DecoratedBox(
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: _c.isAnimating
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.5 * (1 - _c.value)),
                      spreadRadius: s * _c.value,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

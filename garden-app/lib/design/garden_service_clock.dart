import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_icons.dart';
import 'garden_service.dart';

/// Cuánto falta y cuándo vuelve, para el dueño durante el servicio en vivo.
///
/// El encabezado ya muestra el cronómetro ("En vivo · 00:23:10"); antes esta
/// tarjeta repetía lo mismo ("23 min de 60 min"). Lo que el dueño quiere saber
/// es cuánto falta y a qué hora vuelve su mascota: eso va grande, con un anillo
/// que se llena con el color del servicio.
class GardenServiceClock extends StatelessWidget {
  final GardenService service;

  /// 0..1 del tiempo contratado ya transcurrido.
  final double progress;

  /// Lo grande del centro del anillo ("37", "2/3") y lo que va debajo ("min").
  final String value;
  final String unit;

  /// "Vuelve a las 10:05" / "Se cumplió el tiempo".
  final String title;

  /// "Empezó a las 9:02 · 60 min contratados".
  final String? subtitle;

  /// Acción opcional a la derecha o debajo (ej. "Ampliar").
  final Widget? action;

  const GardenServiceClock({
    super.key,
    required this.service,
    required this.progress,
    required this.value,
    required this.unit,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final ink = service.ink(isDark);
    final done = progress >= 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.xl),
        boxShadow: GardenShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Semantics(
            label: '$value $unit',
            excludeSemantics: true,
            child: SizedBox(
              width: 92,
              height: 92,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
                duration: GardenMotion.resolve(context, GardenMotion.expressive),
                curve: GardenMotion.enter,
                builder: (_, p, __) => CustomPaint(
                  painter: _RingPainter(progress: p, color: ink, track: service.soft(isDark)),
                  child: Center(
                    // Tiempo cumplido: un visto en vez de "0".
                    child: done
                        ? const GardenIcon(GIcon.hecho, size: GIconSize.xl, state: GIconState.active, color: GardenColors.success)
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(value,
                                style: TextStyle(
                                    color: text, fontSize: value.length > 4 ? 18 : 24, fontWeight: FontWeight.w900, height: 1)),
                            const SizedBox(height: 2),
                            Text(unit, style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w700)),
                          ]),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(service.label.toUpperCase(),
                  style: TextStyle(color: ink, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.9)),
              const SizedBox(height: 4),
              Text(title,
                  style: TextStyle(color: done ? GardenColors.success : text, fontSize: 17, fontWeight: FontWeight.w900, height: 1.2)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: TextStyle(color: sub, fontSize: 12.5, height: 1.35)),
              ],
            ]),
          ),
        ]),
        if (action != null) ...[
          const SizedBox(height: 14),
          action!,
        ],
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  _RingPainter({required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (progress <= 0) return;
    final fg = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [Color.lerp(color, Colors.white, 0.35)!, color],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color || old.track != track;
}

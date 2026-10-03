import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_service.dart';

// ── ICONOS PROPIOS DE LOS SERVICIOS ────────────────────────────────────────
// Dibujados en una grilla de 48 unidades con trazo 3 (≈ 1,5 px a 24 px, igual
// que Phosphor regular) para que convivan con el resto de GardenIcon.
//
//   idle    → trazo en color de texto secundario
//   active  → color del servicio + relleno suave (duotono)
//   live    → bucle mientras el servicio está en curso:
//               paseo: huellas que aparecen en secuencia
//               guardería: rayos del sol girando lento
//               hospedaje: "z" que flotan sobre la casa
//
// Puente hasta tener las versiones finales en Rive hechas por ilustración:
// la API (GardenIcon(GIcon.paseo, live: true)) no cambia cuando se reemplace.
class GardenServiceIcon extends StatefulWidget {
  final GardenService service;
  final double size;
  final bool active;
  final bool live;
  final Color? color;
  final String? semanticLabel;

  const GardenServiceIcon(
    this.service, {
    super.key,
    this.size = 24,
    this.active = false,
    this.live = false,
    this.color,
    this.semanticLabel,
  });

  @override
  State<GardenServiceIcon> createState() => _GardenServiceIconState();
}

class _GardenServiceIconState extends State<GardenServiceIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop;

  Duration get _period => switch (widget.service) {
        GardenService.paseo     => const Duration(milliseconds: 2400),
        GardenService.guarderia => const Duration(seconds: 12),
        GardenService.hospedaje => const Duration(milliseconds: 2800),
      };

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(vsync: this, duration: _period);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoop();
  }

  @override
  void didUpdateWidget(GardenServiceIcon old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service) _loop.duration = _period;
    _syncLoop();
  }

  void _syncLoop() {
    final shouldRun = widget.live && !GardenMotion.reduced(context);
    if (shouldRun && !_loop.isAnimating) {
      _loop.repeat();
    } else if (!shouldRun && _loop.isAnimating) {
      _loop.stop();
      _loop.value = 0;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = widget.active || widget.live;
    final ink = widget.color ??
        (active
            ? widget.service.ink(isDark)
            : (isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary));

    // Pop corto al pasar de idle a active — una vez, nunca en bucle.
    return Semantics(
      label: widget.semanticLabel,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(active),
        tween: Tween(begin: active ? 0.82 : 1, end: 1),
        duration: GardenMotion.resolve(context, GardenMotion.quick),
        curve: GardenMotion.pop,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _loop,
            builder: (context, _) => CustomPaint(
              size: Size.square(widget.size),
              painter: _ServicePainter(
                service: widget.service,
                ink: ink,
                duotone: active,
                live: widget.live && _loop.isAnimating,
                t: _loop.value,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServicePainter extends CustomPainter {
  final GardenService service;
  final Color ink;
  final bool duotone;
  final bool live;
  final double t;

  _ServicePainter({
    required this.service,
    required this.ink,
    required this.duotone,
    required this.live,
    required this.t,
  });

  static const _stroke = 3.0;
  static const _soft = 0.28;

  Paint get _line => Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = _stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint _fill([double opacity = 1]) => Paint()
    ..color = ink.withValues(alpha: ink.a * opacity)
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    switch (service) {
      case GardenService.paseo:
        _paintWalk(canvas);
      case GardenService.guarderia:
        _paintDay(canvas);
      case GardenService.hospedaje:
        _paintNight(canvas);
    }
    canvas.restore();
  }

  // Huella: almohadilla + cuatro dedos.
  void _paw(Canvas canvas, Offset c, Paint p, [double scale = 1]) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(scale);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 8.6, height: 7.2), p);
    canvas.drawCircle(const Offset(-4.6, -5.6), 1.85, p);
    canvas.drawCircle(const Offset(-1.1, -7.6), 1.85, p);
    canvas.drawCircle(const Offset(2.8, -7.0), 1.85, p);
    canvas.drawCircle(const Offset(5.3, -3.9), 1.75, p);
    canvas.restore();
  }

  void _paintWalk(Canvas canvas) {
    const paws = [Offset(11, 38), Offset(24, 26.5), Offset(37, 15)];
    if (duotone) {
      // Duotono: el camino recorrido como puntos suaves entre las huellas.
      final trail = Path()
        ..moveTo(4, 46)
        ..quadraticBezierTo(20, 36, 24, 26)
        ..quadraticBezierTo(29, 15, 45, 5);
      final dot = Paint()..color = ink.withValues(alpha: ink.a * 0.35);
      for (final m in trail.computeMetrics()) {
        for (double d = 2; d < m.length; d += 5.5) {
          final pos = m.getTangentForOffset(d)?.position;
          if (pos == null) continue;
          // Sin puntos debajo de las huellas: quedarían tapados y ensucian.
          if (paws.any((p) => (p - pos).distance < 7.5)) continue;
          canvas.drawCircle(pos, 1.3, dot);
        }
      }
    }
    for (var i = 0; i < paws.length; i++) {
      if (!live) {
        _paw(canvas, paws[i], _fill());
        continue;
      }
      // Cada huella aparece 0,15 del ciclo después de la anterior y se
      // desvanece al final: se lee como pasos.
      final start = i * 0.15;
      final local = ((t - start) / 0.25).clamp(0.0, 1.0);
      final fade = t > 0.8 ? (1 - (t - 0.8) / 0.2).clamp(0.0, 1.0) : 1.0;
      final appear = Curves.easeOutBack.transform(local);
      if (local <= 0) continue;
      _paw(canvas, paws[i], _fill(local.clamp(0.0, 1.0) * fade), 0.6 + 0.4 * appear);
    }
  }

  void _paintDay(Canvas canvas) {
    const c = Offset(24, 24);
    if (duotone) canvas.drawCircle(c, 9.5, _fill(_soft));
    canvas.drawCircle(c, 9.5, _line);

    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (live) canvas.rotate(t * 2 * math.pi);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(dir * 15, dir * 20, _line);
    }
    canvas.restore();

    // Huella pequeña dentro del sol.
    _paw(canvas, const Offset(24, 27), _fill(), 0.62);
  }

  void _paintNight(Canvas canvas) {
    final body = Path()
      ..moveTo(12, 21)
      ..lineTo(24, 11.5)
      ..lineTo(36, 21)
      ..lineTo(36, 39)
      ..lineTo(12, 39)
      ..close();
    if (duotone) canvas.drawPath(body, _fill(_soft));

    final roof = Path()
      ..moveTo(7, 24)
      ..lineTo(24, 10)
      ..lineTo(41, 24);
    canvas.drawPath(roof, _line);
    canvas.drawPath(
      Path()
        ..moveTo(12, 20.5)
        ..lineTo(12, 39)
        ..lineTo(36, 39)
        ..lineTo(36, 20.5),
      _line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(20.5, 39)
        ..lineTo(20.5, 31)
        ..lineTo(27.5, 31)
        ..lineTo(27.5, 39),
      _line,
    );

    // Luna creciente arriba a la derecha.
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: const Offset(40, 8), radius: 5.5)),
      Path()..addOval(Rect.fromCircle(center: const Offset(42.6, 5.6), radius: 4.6)),
    );
    canvas.drawPath(moon, _fill());

    if (live) {
      _z(canvas, const Offset(30, 13), 4.2, t);
      _z(canvas, const Offset(33, 8), 3.4, (t + 0.45) % 1);
    }
  }

  // Una "z" que sube en diagonal y se desvanece.
  void _z(Canvas canvas, Offset origin, double s, double phase) {
    final opacity = phase < 0.4 ? phase / 0.4 : (1 - (phase - 0.4) / 0.6);
    final o = origin + Offset(3 * phase, -5 * phase);
    final p = Paint()
      ..color = ink.withValues(alpha: ink.a * opacity.clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(o.dx, o.dy)
        ..lineTo(o.dx + s, o.dy)
        ..lineTo(o.dx, o.dy + s)
        ..lineTo(o.dx + s, o.dy + s),
      p,
    );
  }

  @override
  bool shouldRepaint(_ServicePainter old) =>
      old.t != t ||
      old.ink != ink ||
      old.duotone != duotone ||
      old.live != live ||
      old.service != service;
}

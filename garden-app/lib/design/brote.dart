import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/garden_motion.dart';

// ── BROTE, EL PERSONAJE DE GARDEN ──────────────────────────────────────────
// Un brote con dos hojas que hace de narrador en los momentos sin palabras:
// estados vacíos, carga, celebraciones, errores y ayuda.
//
// Reglas (plan de rediseño, sección 10):
//   • Seis poses y nada más.
//   • NUNCA en pantallas de dinero, pago, disputas ni verificación de
//     identidad: ahí el tono es sereno.
//   • Se anima una vez al aparecer (pop + gesto de la pose) y queda quieto.
//     No hay bucles.
//
// Dibujo provisorio en código para fijar proporciones, colores y API. Cuando
// llegue la versión de ilustración (Rive), se reemplaza el painter y
// `Brote(pose: ...)` sigue igual en todas las pantallas.
enum BrotePose {
  /// Bienvenida, onboarding, saludo del inicio. Saluda con una hoja.
  hola,
  /// Cargando, esperando respuesta. Mira hacia arriba.
  esperando,
  /// Reserva confirmada, servicio terminado, logro. Salta con las hojas arriba.
  celebrando,
  /// Sin actividad, modo noche, hospedaje. Ojos cerrados.
  durmiendo,
  /// Búsquedas sin resultados, ayuda. Mira y señala a un costado.
  buscando,
  /// Errores y sin conexión. Hojas caídas, nunca dramático.
  oops,
}

class Brote extends StatefulWidget {
  final BrotePose pose;
  final double size;
  final String? semanticLabel;

  const Brote({super.key, this.pose = BrotePose.hola, this.size = 120, this.semanticLabel});

  @override
  State<Brote> createState() => _BroteState();
}

class _BroteState extends State<Brote> with TickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: GardenMotion.celebrate);
  // Respiración en reposo: sube y baja apenas, para que no se vea quieto.
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (GardenMotion.reduced(context)) {
        _c.value = 1;
      } else {
        _c.forward();
        // Unas pocas respiraciones y descansa: vivo al llegar, sin bucle eterno
        // (regla del sistema: solo lo que está en vivo se mueve sin parar).
        _breath.repeat(count: 3);
      }
    }
  }

  @override
  void didUpdateWidget(Brote old) {
    super.didUpdateWidget(old);
    if (old.pose != widget.pose && !GardenMotion.reduced(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      image: widget.semanticLabel != null,
      excludeSemantics: widget.semanticLabel == null,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_c, _breath]),
          builder: (context, _) {
            final b = math.sin(_breath.value * 2 * math.pi);
            return Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()
                ..translateByDouble(0.0, -b * widget.size * 0.012, 0.0, 1.0)
                ..scaleByDouble(1 - b * 0.012, 1 + b * 0.018, 1.0, 1.0),
              child: CustomPaint(
                size: Size.square(widget.size),
                painter: _BrotePainter(widget.pose, _c.value),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BrotePainter extends CustomPainter {
  final BrotePose pose;
  final double t;
  _BrotePainter(this.pose, this.t);

  // Colores fijos del personaje (no cambian con el tema: es un personaje,
  // igual que el logo).
  static const _body = Color(0xFFD9EF9F);      // lima GARDEN
  static const _leafA = Color(0xFF778C43);     // oliva
  static const _leafB = Color(0xFF58E262);     // verde vivo
  static const _ink = Color(0xFF1E2D0F);
  static const _cheek = Color(0xFFF2A488);
  static const _confetti = [Color(0xFFFFB020), Color(0xFF58E262), Color(0xFF4F8EF7), Color(0xFFFF6B35)];

  double get _enter => GardenMotion.pop.transform((t / 0.5).clamp(0.0, 1.0));
  double get _gesture => ((t - 0.25) / 0.75).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    // Entrada: pop desde 85 % y fundido.
    final enter = _enter;
    final opacity = (t / 0.3).clamp(0.0, 1.0);
    canvas.saveLayer(const Rect.fromLTWH(-10, -10, 120, 120),
        Paint()..color = Colors.black.withValues(alpha: opacity));
    canvas.translate(50, 92);
    final sc = 0.85 + 0.15 * enter;
    canvas.scale(sc, sc);
    canvas.translate(-50, -92);

    // Salto (solo celebrando).
    final jump = pose == BrotePose.celebrando ? -10 * math.sin(math.pi * _gesture) : 0.0;

    // Sombra: se achica cuando salta.
    final shadowW = 44 + jump * 1.2;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 92), width: shadowW, height: 6),
      Paint()..color = _ink.withValues(alpha: 0.10),
    );

    canvas.translate(0, jump);
    _leaves(canvas);
    _bodyShape(canvas);
    _face(canvas);
    if (pose == BrotePose.celebrando) _confettiBits(canvas);
    if (pose == BrotePose.durmiendo) _zzz(canvas);
    if (pose == BrotePose.buscando) _lens(canvas);

    canvas.restore();
    canvas.restore();
  }

  void _bodyShape(Canvas canvas) {
    final body = Path()
      ..moveTo(50, 36)
      ..cubicTo(72, 36, 80, 56, 79, 70)
      ..cubicTo(78, 84, 66, 90, 50, 90)
      ..cubicTo(34, 90, 22, 84, 21, 70)
      ..cubicTo(20, 56, 28, 36, 50, 36)
      ..close();
    // Plano, de un solo color: sin brillo, degradado ni sombra interna (el
    // estilo de GARDEN es plano; el relieve queda en botones y en los íconos
    // de servicio).
    canvas.drawPath(body, Paint()..color = _body);
  }

  void _leaf(Canvas canvas, Offset base, double angleDeg, double len, Color color) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angleDeg * math.pi / 180);
    final leaf = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(len * 0.45, -len * 0.42, len, 0)
      ..quadraticBezierTo(len * 0.45, len * 0.42, 0, 0)
      ..close();
    canvas.drawPath(leaf, Paint()..color = color);
    canvas.drawLine(
      Offset(len * 0.12, 0),
      Offset(len * 0.78, 0),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  void _leaves(Canvas canvas) {
    const tip = Offset(50, 26);
    // Tallo
    canvas.drawLine(
      const Offset(50, 40),
      tip,
      Paint()
        ..color = _leafA
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.round,
    );

    final g = _gesture;
    double left = -140, right = -40;
    switch (pose) {
      case BrotePose.hola:
        // Dos saludos con la hoja derecha que se van apagando.
        right = -40 + 28 * math.sin(g * 4 * math.pi) * (1 - g);
      case BrotePose.esperando:
        left = -135;
        right = -45;
      case BrotePose.celebrando:
        final up = math.sin(math.pi * g.clamp(0.0, 1.0));
        left = -140 + 30 * up;
        right = -40 - 30 * up;
      case BrotePose.durmiendo:
        left = -168;
        right = -12;
      case BrotePose.buscando:
        right = -40 + 32 * GardenMotion.enter.transform(g);
      case BrotePose.oops:
        left = -140 - 32 * GardenMotion.enter.transform(g);
        right = -40 + 32 * GardenMotion.enter.transform(g);
    }
    _leaf(canvas, tip, left, 26, _leafA);
    _leaf(canvas, tip, right, 26, _leafB);
  }

  void _face(Canvas canvas) {
    final ink = Paint()..color = _ink;
    final line = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    const le = Offset(40, 61), re = Offset(60, 61);

    // Mejillas
    final cheek = Paint()..color = _cheek.withValues(alpha: 0.55);
    canvas.drawOval(Rect.fromCenter(center: const Offset(33, 70), width: 9, height: 5.5), cheek);
    canvas.drawOval(Rect.fromCenter(center: const Offset(67, 70), width: 9, height: 5.5), cheek);

    // Ojos
    switch (pose) {
      case BrotePose.celebrando:
        // Ojos felices ^ ^
        for (final e in [le, re]) {
          canvas.drawPath(
            Path()
              ..moveTo(e.dx - 4, e.dy + 1.5)
              ..quadraticBezierTo(e.dx, e.dy - 5, e.dx + 4, e.dy + 1.5),
            line,
          );
        }
      case BrotePose.durmiendo:
        for (final e in [le, re]) {
          canvas.drawPath(
            Path()
              ..moveTo(e.dx - 4, e.dy)
              ..quadraticBezierTo(e.dx, e.dy + 4, e.dx + 4, e.dy),
            line,
          );
        }
      default:
        final look = switch (pose) {
          BrotePose.esperando => const Offset(0, -1.6),
          BrotePose.buscando => Offset(1.8 * GardenMotion.enter.transform(_gesture), 0),
          _ => Offset.zero,
        };
        for (final e in [le, re]) {
          canvas.drawOval(Rect.fromCenter(center: e + look, width: 7, height: 8.4), ink);
          canvas.drawCircle(e + look + const Offset(1.2, -1.6), 1.3, Paint()..color = Colors.white);
        }
    }

    // Boca
    switch (pose) {
      case BrotePose.hola:
      case BrotePose.buscando:
        canvas.drawPath(
          Path()
            ..moveTo(45, 70)
            ..quadraticBezierTo(50, 75, 55, 70),
          line,
        );
      case BrotePose.celebrando:
        canvas.drawPath(
          Path()
            ..moveTo(44, 69)
            ..quadraticBezierTo(50, 79, 56, 69)
            ..close(),
          ink,
        );
      case BrotePose.esperando:
        canvas.drawLine(const Offset(46.5, 71.5), const Offset(53.5, 71.5), line);
      case BrotePose.durmiendo:
        canvas.drawOval(Rect.fromCenter(center: const Offset(50, 72), width: 4, height: 4.6), ink);
      case BrotePose.oops:
        canvas.drawPath(
          Path()
            ..moveTo(45.5, 73)
            ..quadraticBezierTo(50, 69, 54.5, 73),
          line,
        );
    }
  }

  void _confettiBits(Canvas canvas) {
    final g = _gesture;
    if (g <= 0) return;
    final rnd = math.Random(7);
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + (rnd.nextDouble() - 0.5) * 2.4;
      final dist = 22 + rnd.nextDouble() * 18;
      final p = const Offset(50, 40) + Offset(math.cos(a), math.sin(a)) * dist * g;
      final fade = (1 - (g - 0.6).clamp(0.0, 0.4) / 0.4);
      canvas.save();
      canvas.translate(p.dx, p.dy + 10 * g * g);
      canvas.rotate(a + g * 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-2, -1.2, 4, 2.4), const Radius.circular(1)),
        Paint()..color = _confetti[i % _confetti.length].withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  void _zzz(Canvas canvas) {
    final g = _gesture;
    final p = Paint()
      ..color = _leafA.withValues(alpha: g)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void z(Offset o, double s) => canvas.drawPath(
          Path()
            ..moveTo(o.dx, o.dy)
            ..lineTo(o.dx + s, o.dy)
            ..lineTo(o.dx, o.dy + s)
            ..lineTo(o.dx + s, o.dy + s),
          p,
        );
    z(Offset(70, 38 - 4 * g), 6);
    z(Offset(79, 28 - 6 * g), 4.5);
  }

  void _lens(Canvas canvas) {
    final g = GardenMotion.enter.transform(_gesture);
    if (g <= 0) return;
    final c = Offset(84, 52 - 4 * g);
    final p = Paint()
      ..color = _leafA.withValues(alpha: g)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, 6, p);
    canvas.drawLine(c + const Offset(4.3, 4.3), c + const Offset(9, 9), p);
  }

  @override
  bool shouldRepaint(_BrotePainter old) => old.t != t || old.pose != pose;
}

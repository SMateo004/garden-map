import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/garden_motion.dart';
import 'garden_icons.dart';

/// Profundidad: piezas con volumen (estilo "clay") para que las figuras no
/// se vean planas. Luz arriba a la izquierda, sombra del mismo color abajo,
/// se inclinan hacia el cursor, se aprietan al tocarlas y pueden flotar.
/// Todo el movimiento respeta "reducir movimiento" (GardenMotion.reduced).

Color _lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color _darken(Color c, double t) => Color.lerp(c, Colors.black, t)!;

class GardenClay extends StatefulWidget {
  final Widget child;
  final double size;
  final Color color;
  final bool circle;

  /// Flota suave (para lo seleccionado o lo que pide atención).
  final bool float;

  /// Se inclina hacia el cursor (web/escritorio) y se aprieta al tocar.
  final bool interactive;

  const GardenClay({
    super.key,
    required this.child,
    required this.color,
    this.size = 48,
    this.circle = true,
    this.float = false,
    this.interactive = true,
  });

  @override
  State<GardenClay> createState() => _GardenClayState();
}

class _GardenClayState extends State<GardenClay> with SingleTickerProviderStateMixin {
  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  Offset _tilt = Offset.zero; // -1..1 en x/y
  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFloat();
  }

  @override
  void didUpdateWidget(GardenClay old) {
    super.didUpdateWidget(old);
    _syncFloat();
  }

  void _syncFloat() {
    final run = widget.float && !GardenMotion.reduced(context);
    if (run && !_float.isAnimating) {
      _float.repeat();
    } else if (!run && _float.isAnimating) {
      _float.stop();
      _float.value = 0;
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  void _hover(Offset local) {
    if (!widget.interactive || GardenMotion.reduced(context)) return;
    final s = widget.size;
    setState(() => _tilt = Offset((local.dx / s) * 2 - 1, (local.dy / s) * 2 - 1));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final s = widget.size;
    final radius = widget.circle ? BorderRadius.circular(s / 2) : BorderRadius.circular(s * 0.3);

    final body = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_lighten(c, 0.45), c, _darken(c, 0.10)],
          stops: const [0, 0.55, 1],
        ),
        boxShadow: [
          // sombra de color, lejos y suave (la pieza "está apoyada")
          BoxShadow(color: _darken(c, 0.35).withValues(alpha: 0.35), blurRadius: s * 0.28, offset: Offset(0, s * 0.12)),
          // contacto, cerca y más definida
          BoxShadow(color: _darken(c, 0.45).withValues(alpha: 0.25), blurRadius: 3, offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(alignment: Alignment.center, children: [
        // brillo arriba a la izquierda
        Positioned(
          left: s * 0.14,
          top: s * 0.1,
          child: Container(
            width: s * 0.42,
            height: s * 0.26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(s),
              gradient: RadialGradient(
                colors: [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        // borde inferior un poco más oscuro: da grosor
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, _darken(c, 0.25).withValues(alpha: 0.18)],
                stops: const [0.6, 1],
              ),
            ),
          ),
        ),
        widget.child,
      ]),
    );

    return MouseRegion(
      onHover: (e) => _hover(e.localPosition),
      onExit: (_) => setState(() => _tilt = Offset.zero),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedBuilder(
          animation: _float,
          builder: (context, child) {
            final dy = widget.float ? math.sin(_float.value * 2 * math.pi) * 2.5 : 0.0;
            final m = Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..translate(0.0, dy + (_pressed ? 2.0 : 0.0))
              ..rotateX(-_tilt.dy * 0.22)
              ..rotateY(_tilt.dx * 0.22)
              ..scale(_pressed ? 0.94 : 1.0);
            return Transform(alignment: Alignment.center, transform: m, child: child);
          },
          child: body,
        ),
      ),
    );
  }
}

/// Ícono en relieve: una copia oscura un poco más abajo hace de sombra.
class GardenClayIcon extends StatelessWidget {
  final GIcon icon;
  final Color color;
  final GIconSize size;
  const GardenClayIcon(this.icon, {super.key, required this.color, this.size = GIconSize.lg});

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
      Transform.translate(
        offset: const Offset(0, 1.5),
        child: GardenIcon(icon, size: size, color: Colors.black.withValues(alpha: 0.18)),
      ),
      GardenIcon(icon, size: size, state: GIconState.active, color: color),
    ]);
  }
}

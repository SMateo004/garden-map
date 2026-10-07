import 'package:flutter/material.dart';

import '../theme/garden_motion.dart';
import 'garden_icons.dart';

/// Profundidad: el volumen vive en lo que se toca (botones, píldoras). Los
/// fondos de íconos son planos. El movimiento respeta "reducir movimiento".


/// Fondo de un ícono: círculo o cuadrado redondeado de color, PLANO.
///
/// Octubre 2026: probamos darles volumen (degradado, brillo, sombra de color,
/// inclinación y flotación) y los íconos parecían globos. Se volvió a plano a
/// pedido; el volumen queda solo en botones y piezas tocables (GardenButton,
/// GardenPress). La API se mantiene para no tocar las ~75 pantallas que la usan:
/// [float] e [interactive] ya no hacen nada.
class GardenClay extends StatelessWidget {
  final Widget child;
  final double size;
  final Color? color;

  /// Color tenue (ej. verde al 12 %) sobre la superficie. Se usa en lugar de [color].
  final Color? tint;
  final bool circle;

  /// Radio para las cuadradas (por defecto, 30 % del tamaño).
  final double? radius;

  /// Sin efecto (antes: flotaba).
  final bool float;

  /// Sin efecto (antes: se inclinaba hacia el cursor).
  final bool interactive;

  const GardenClay({
    super.key,
    required this.child,
    this.color,
    this.tint,
    this.size = 48,
    this.circle = true,
    this.radius,
    this.float = false,
    this.interactive = true,
  }) : assert(color != null || tint != null, 'GardenClay necesita color o tint');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? tint,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius ?? size * 0.3),
      ),
      child: child,
    );
  }
}

/// Ícono en el estado activo (duotono), sin sombra debajo.
class GardenClayIcon extends StatelessWidget {
  final GIcon icon;
  final Color color;
  final GIconSize size;
  const GardenClayIcon(this.icon, {super.key, required this.color, this.size = GIconSize.lg});

  @override
  Widget build(BuildContext context) => GardenIcon(icon, size: size, state: GIconState.active, color: color);
}

/// Cualquier pieza tocable con volumen: sombra de apoyo debajo y se hunde
/// (baja y se achica apenas) mientras se presiona.
class GardenPress extends StatefulWidget {
  final Widget child;
  final BorderRadius radius;

  /// Sombra de apoyo (null = sin sombra, solo el hundimiento).
  final Color? shadow;
  const GardenPress({super.key, required this.child, this.radius = const BorderRadius.all(Radius.circular(14)), this.shadow});

  @override
  State<GardenPress> createState() => _GardenPressState();
}

class _GardenPressState extends State<GardenPress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final d = GardenMotion.resolve(context, GardenMotion.instant);
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedContainer(
        duration: d,
        curve: GardenMotion.enter,
        transform: Matrix4.translationValues(0, _down ? 2 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: widget.radius,
          boxShadow: widget.shadow == null
              ? null
              : [BoxShadow(color: widget.shadow!, blurRadius: _down ? 2 : 6, offset: Offset(0, _down ? 1 : 3))],
        ),
        child: AnimatedScale(duration: d, scale: _down ? 0.97 : 1, child: widget.child),
      ),
    );
  }
}

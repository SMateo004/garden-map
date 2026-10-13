import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../theme/garden_motion.dart';

/// La huella de GARDEN (la del ícono de la app) con relieve, para el saludo
/// del inicio. Flota siempre, apenas (sube y baja un 3 % de su tamaño en 3 s,
/// y la sombra del piso se achica cuando sube). Al tocarla da una vuelta
/// completa sobre sí misma.
///
/// Es la marca, no un personaje: Brote sigue en los estados vacíos, la carga
/// y las celebraciones. Con "reducir movimiento" queda quieta y no gira.
class GardenPawMark extends StatefulWidget {
  final double size;
  final String semanticLabel;

  const GardenPawMark({super.key, this.size = 46, this.semanticLabel = 'GARDEN'});

  /// Imagen de la huella (generada con el mismo dibujo que el ícono).
  static const asset = 'assets/images/garden_paw_3d.png';

  @override
  State<GardenPawMark> createState() => _GardenPawMarkState();
}

class _GardenPawMarkState extends State<GardenPawMark> with TickerProviderStateMixin {
  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!GardenMotion.reduced(context)) _float.repeat();
  }

  @override
  void dispose() {
    _float.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _turn() {
    if (GardenMotion.reduced(context) || _spin.isAnimating) return;
    HapticFeedback.selectionClick();
    _spin.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: GestureDetector(
        onTap: _turn,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.square(
          dimension: s,
          child: AnimatedBuilder(
            animation: Listenable.merge([_float, _spin]),
            builder: (context, child) {
              // 0 → 1 → 0 suave: arriba en la mitad del ciclo.
              final up = (1 - math.cos(_float.value * 2 * math.pi)) / 2;
              final turn = GardenMotion.move.transform(_spin.value) * 2 * math.pi;
              return Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // Sombra en el piso: más chica y clara cuando la huella sube.
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: s * (0.62 - 0.08 * up),
                      height: s * 0.09,
                      decoration: BoxDecoration(
                        color: const Color(0xFF463A28).withValues(alpha: 0.20 - 0.07 * up),
                        borderRadius: BorderRadius.all(Radius.elliptical(s, s * 0.09)),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: s * 0.07 + s * 0.03 * up,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateY(turn),
                      child: child,
                    ),
                  ),
                ],
              );
            },
            child: Image.asset(
              GardenPawMark.asset,
              width: s * 0.78,
              height: s * 0.84,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}

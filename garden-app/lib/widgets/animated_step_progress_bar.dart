import 'package:flutter/material.dart';
import '../theme/garden_theme.dart';

/// Barra de progreso para wizards de varios pasos, con transición suave
/// entre valores (en vez del salto abrupto de LinearProgressIndicator) + un
/// leve resplandor mientras avanza. Compartida por los tres flujos de
/// registro de cuidador (individual, profesional, empresa) para que el
/// avance de pasos se sienta igual de agradable en los tres.
class AnimatedStepProgressBar extends StatelessWidget {
  final double value;
  final Color backgroundColor;
  final double height;

  const AnimatedStepProgressBar({
    super.key,
    required this.value,
    required this.backgroundColor,
    this.height = 4,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return Container(
          height: height,
          decoration: BoxDecoration(color: backgroundColor),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: animatedValue.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: GardenColors.primary,
                boxShadow: [
                  BoxShadow(
                    color: GardenColors.primary.withValues(alpha: 0.55),
                    blurRadius: 6,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Transición estándar entre pasos de un wizard: fade + leve deslizamiento
/// vertical — más agradable que el crossfade plano por defecto de
/// AnimatedSwitcher, sin ser una animación llamativa. Usar como
/// `transitionBuilder` de un AnimatedSwitcher, envolviendo el contenido en
/// `KeyedSubtree(key: ValueKey(currentStep), child: ...)`.
Widget stepTransitionBuilder(Widget child, Animation<double> animation) {
  final slide = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(animation);
  return FadeTransition(opacity: animation, child: SlideTransition(position: slide, child: child));
}

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Logo horizontal de Garden pulsando — reemplaza CircularProgressIndicator.
/// Imita el splash de la web: fade in/out cíclico + leve escala.
class GardenLogoLoader extends StatelessWidget {
  final double size;
  final Color? bgColor;

  const GardenLogoLoader({super.key, this.size = 180, this.bgColor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logo = isDark
        ? 'assets/images/logo-horizontal-dark.png'
        : 'assets/images/logo-horizontal.png';

    return Container(
      color: bgColor,
      child: Center(
        child: Image.asset(logo, width: size)
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .fadeIn(duration: 900.ms, curve: Curves.easeInOut)
            .scaleXY(begin: 0.96, end: 1.0, duration: 900.ms, curve: Curves.easeInOut),
      ),
    );
  }
}

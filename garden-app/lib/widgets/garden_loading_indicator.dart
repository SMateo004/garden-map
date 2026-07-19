import 'package:flutter/material.dart';

/// Indicador de carga de marca — huella de Garden animada.
///
/// Reemplazo directo de [CircularProgressIndicator] en toda la app: una
/// huella (paw print) que pulsa suavemente (escala + opacidad) en loop,
/// usando el asset `assets/images/logo-icon.png` (huella aislada, sin fondo).
///
/// Uso:
/// ```dart
/// const GardenLoadingIndicator() // tamaño default, color de marca
/// GardenLoadingIndicator(size: 18) // inline, p.ej. dentro de un botón
/// GardenLoadingIndicator(size: 18, color: Colors.white) // sobre fondo oscuro
/// ```
class GardenLoadingIndicator extends StatefulWidget {
  /// Tamaño del lado del indicador (ancho == alto). Default 32.
  final double size;

  /// Color opcional para teñir la huella (p.ej. blanco sobre un botón
  /// oscuro). Si es null, se usan los colores originales del asset
  /// (verdes de marca Garden).
  final Color? color;

  const GardenLoadingIndicator({super.key, this.size = 32, this.color});

  @override
  State<GardenLoadingIndicator> createState() => _GardenLoadingIndicatorState();
}

class _GardenLoadingIndicatorState extends State<GardenLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/images/logo-icon.png',
      width: widget.size,
      height: widget.size,
      // Sin color explícito: se respetan los verdes originales del asset
      // (huella bicolor de marca). Con color explícito (p.ej. blanco sobre
      // un botón oscuro) se aplica como tinte sólido.
      color: widget.color,
      colorBlendMode: widget.color != null ? BlendMode.srcIn : null,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.scale(scale: _scale.value, child: child),
        );
      },
      child: image,
    );
  }
}

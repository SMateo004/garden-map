import 'package:flutter/material.dart';
import '../theme/garden_theme.dart';

/// Botón deslizante de confirmación.
/// El usuario debe arrastrar el thumb de izquierda a derecha hasta el
/// 85 % del ancho para que se dispare [onConfirmed]. Si lo suelta antes,
/// vuelve al inicio con una animación de rebote.
class SlideToConfirmButton extends StatefulWidget {
  final String label;
  final Color color;
  final Color textColor;
  final IconData icon;
  final VoidCallback? onConfirmed;
  final bool loading;
  final double height;

  const SlideToConfirmButton({
    super.key,
    this.label = 'Desliza para confirmar',
    this.color = GardenColors.success,
    this.textColor = Colors.white,
    this.icon = Icons.check_rounded,
    this.onConfirmed,
    this.loading = false,
    this.height = 60,
  });

  @override
  State<SlideToConfirmButton> createState() => _SlideToConfirmButtonState();
}

class _SlideToConfirmButtonState extends State<SlideToConfirmButton>
    with SingleTickerProviderStateMixin {
  double _position = 0.0; // 0.0 – 1.0
  bool _confirmed = false;
  late AnimationController _snapController;
  late Animation<double> _snapAnimation;

  static const double _thumbSize = 52.0;
  static const double _triggerThreshold = 0.82;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _snapAnimation = CurvedAnimation(
      parent: _snapController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d, double trackWidth) {
    if (_confirmed || widget.loading || widget.onConfirmed == null) return;
    final newPos = (_position + d.delta.dx / trackWidth).clamp(0.0, 1.0);
    setState(() => _position = newPos);
    if (newPos >= _triggerThreshold) _trigger();
  }

  void _onDragEnd(DragEndDetails _) {
    if (_confirmed) return;
    _snapBack();
  }

  void _trigger() {
    if (_confirmed) return;
    setState(() {
      _confirmed = true;
      _position = 1.0;
    });
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) widget.onConfirmed?.call();
      // Reset para próximo uso
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _confirmed = false;
            _position = 0.0;
          });
        }
      });
    });
  }

  void _snapBack() {
    final startPos = _position;
    _snapAnimation = Tween<double>(begin: startPos, end: 0.0).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.elasticOut),
    );
    _snapController.forward(from: 0).then((_) {
      if (mounted) setState(() => _position = 0.0);
    });
    _snapAnimation.addListener(() {
      if (mounted) setState(() => _position = _snapAnimation.value.clamp(0.0, 1.0));
    });
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading || widget.onConfirmed == null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final trackWidth = totalWidth - _thumbSize;
        final thumbX = _position * trackWidth;

        return GestureDetector(
          onHorizontalDragUpdate: disabled ? null : (d) => _onDragUpdate(d, trackWidth),
          onHorizontalDragEnd: disabled ? null : _onDragEnd,
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: _confirmed
                  ? widget.color
                  : widget.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(widget.height / 2),
              border: Border.all(
                color: widget.color.withValues(alpha: disabled ? 0.3 : 0.6),
                width: 1.5,
              ),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // ── Relleno de progreso ────────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 50),
                  width: thumbX + _thumbSize,
                  height: widget.height,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.18 + _position * 0.15),
                    borderRadius: BorderRadius.circular(widget.height / 2),
                  ),
                ),

                // ── Label centrado ─────────────────────────────────────
                Center(
                  child: widget.loading
                      ? SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: widget.color,
                          ),
                        )
                      : AnimatedOpacity(
                          opacity: _confirmed ? 0.0 : (1.0 - _position * 1.4).clamp(0.0, 1.0),
                          duration: const Duration(milliseconds: 80),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chevron_right_rounded,
                                  size: 18, color: widget.color.withValues(alpha: 0.7)),
                              const SizedBox(width: 4),
                              Text(
                                widget.label,
                                style: TextStyle(
                                  color: widget.color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right_rounded,
                                  size: 18, color: widget.color.withValues(alpha: 0.7)),
                            ],
                          ),
                        ),
                ),

                // ── Thumb deslizante ───────────────────────────────────
                Positioned(
                  left: thumbX,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 50),
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: _confirmed || disabled
                          ? widget.color.withValues(alpha: disabled ? 0.4 : 1.0)
                          : widget.color,
                      shape: BoxShape.circle,
                      boxShadow: disabled ? [] : [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.4),
                          blurRadius: 10, offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _confirmed ? Icons.check_rounded : widget.icon,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

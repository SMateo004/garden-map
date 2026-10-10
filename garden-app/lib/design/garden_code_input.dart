import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';

/// Código de verificación (SMS o correo) en cuadros.
///
/// Por dentro es UN solo campo de texto invisible que cubre los cuadros: pegar
/// el código entero, borrar hacia atrás y el autocompletado del SMS funcionan
/// como en cualquier campo. Antes cada pantalla tenía seis campos sueltos con
/// su propio manejo de foco (y el pegado o el borrado fallaban según cuál).
///
/// [onCompleted] se llama una vez al completar los dígitos. Con [error] los
/// cuadros se marcan en rojo; la pantalla suele limpiar [controller] para que
/// se vuelva a escribir.
class GardenCodeInput extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final int length;
  final bool error;
  final bool enabled;
  final bool autofocus;

  const GardenCodeInput({
    super.key,
    required this.controller,
    this.onCompleted,
    this.length = 6,
    this.error = false,
    this.enabled = true,
    this.autofocus = true,
  });

  @override
  State<GardenCodeInput> createState() => _GardenCodeInputState();
}

class _GardenCodeInputState extends State<GardenCodeInput> {
  final _focus = FocusNode();
  String _lastCompleted = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    _focus.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(GardenCodeInput old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onChange() {
    final text = widget.controller.text;
    if (text.length < widget.length) _lastCompleted = '';
    _rebuild();
    // Una sola vez por código completo (antes el auto-envío podía dispararse
    // dos veces con el mismo código).
    if (text.length == widget.length && text != _lastCompleted) {
      _lastCompleted = text;
      widget.onCompleted?.call(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final text = widget.controller.text;
    final focused = _focus.hasFocus;

    return Semantics(
      label: 'Código de ${widget.length} dígitos',
      textField: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.length * 58.0),
        child: Stack(children: [
          Row(children: [
            for (var i = 0; i < widget.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 0.84,
                  child: AnimatedContainer(
                    duration: GardenMotion.resolve(context, GardenMotion.instant),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(GardenRadius.md),
                      border: Border.all(
                        color: widget.error
                            ? GardenColors.error
                            : (focused && i == text.length.clamp(0, widget.length - 1))
                                ? GardenColors.primary
                                : i < text.length
                                    ? GardenColors.primary.withValues(alpha: 0.5)
                                    : border,
                        width: (focused && i == text.length.clamp(0, widget.length - 1)) || widget.error ? 2 : 1.2,
                      ),
                    ),
                    child: Text(
                      i < text.length ? text[i] : '',
                      style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ]),
          // El campo real, invisible, encima de los cuadros: recibe el toque,
          // el teclado numérico, el pegado y el autocompletado.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                enabled: widget.enabled,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: widget.length,
                showCursor: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(color: Colors.transparent),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import '../widgets/garden_loading_indicator.dart';
import 'garden_icons.dart';

/// El cuadro "agregar fotos" de las grillas de fotos.
///
/// Dice cuántas caben todavía ("quedan 4") —desde ahí se eligen varias de una
/// vez (GardenPhotoPicker)— y muestra que está subiendo. Antes era solo un
/// icono, igual con o sin subida en curso.
class GardenAddPhotoTile extends StatelessWidget {
  final int remaining;
  final bool uploading;
  final bool highlight;
  final VoidCallback? onTap;
  final double? size;

  const GardenAddPhotoTile({
    super.key,
    required this.remaining,
    required this.onTap,
    this.uploading = false,
    this.highlight = false,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final color = highlight ? GardenColors.error : GardenColors.primary;
    final enabled = onTap != null && !uploading;

    return Semantics(
      button: true,
      enabled: enabled,
      label: uploading ? 'Subiendo fotos' : 'Agregar fotos, quedan $remaining',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: GardenMotion.resolve(context, GardenMotion.quick),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: uploading ? 0.04 : 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: uploading
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      GardenLoadingIndicator(size: 22, color: color),
                      const SizedBox(height: 6),
                      Text('Subiendo…', style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w700)),
                    ])
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      GardenIcon(GIcon.agregar, color: color, state: GIconState.active),
                      const SizedBox(height: 4),
                      Text('Agregar', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
                      Text(remaining == 1 ? 'queda 1' : 'quedan $remaining',
                          style: TextStyle(color: sub, fontSize: 10.5, fontWeight: FontWeight.w600)),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/garden_theme.dart';
import 'garden_icons.dart';

/// Pregunta de la primera vez: el teléfono está en modo oscuro y GARDEN se ve
/// mejor en claro. Se muestra una sola vez (ver
/// [ThemeNotifier.shouldAskOnFirstLaunch]) y la respuesta queda guardada como
/// la apariencia elegida, que después se cambia en Perfil > Apariencia.
class GardenThemePrompt extends StatelessWidget {
  final ValueChanged<GardenThemeMode> onChoose;

  const GardenThemePrompt({super.key, required this.onChoose});

  /// Abre la ventana y devuelve lo elegido. No se cierra tocando afuera: la
  /// idea es preguntar una sola vez y que la respuesta quede clara.
  static Future<GardenThemeMode?> show(BuildContext context) {
    return showDialog<GardenThemeMode>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => GardenThemePrompt(onChoose: (mode) => Navigator.of(ctx).pop(mode)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: GardenGlassDialog(
        title: const Row(
          children: [
            GardenIcon(GIcon.modoOscuro, state: GIconState.active, color: GardenColors.primary),
            SizedBox(width: 10),
            Expanded(child: Text('¿Cómo prefieres ver GARDEN?')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tu teléfono está en modo oscuro. GARDEN se ve mejor en modo claro, '
              'pero puedes quedarte con el oscuro si te resulta más cómodo.',
            ),
            const SizedBox(height: 6),
            const Text('Puedes cambiarlo cuando quieras en Perfil › Apariencia.'),
            const SizedBox(height: 20),
            GardenButton(
              label: 'Ver en modo claro',
              gIcon: GIcon.modoClaro,
              onPressed: () => onChoose(GardenThemeMode.light),
            ),
            const SizedBox(height: 10),
            GardenButton(
              label: 'Mantener modo oscuro',
              gIcon: GIcon.modoOscuro,
              outline: true,
              onPressed: () => onChoose(GardenThemeMode.dark),
            ),
          ],
        ),
      ),
    );
  }
}

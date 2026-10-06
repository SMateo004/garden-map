import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_depth.dart';
import 'garden_icons.dart';
import 'garden_service.dart';

// ── MOSAICOS DEL INICIO ────────────────────────────────────────────────────
// Las dos piezas "mega app" del inicio: los servicios como mosaicos grandes y
// una fila de accesos con iconos. Mismo radio, mismo tamaño de icono y misma
// tipografía en todos — se aprenden una vez.

/// Mosaico de servicio. [service] null = "Todos".
class GardenServiceTile extends StatelessWidget {
  final GardenService? service;
  final bool selected;
  final VoidCallback onTap;

  const GardenServiceTile({
    super.key,
    required this.service,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final svc = service;
    final ink = svc?.ink(isDark) ?? (isDark ? GardenColors.primaryLight : GardenColors.primary);
    final soft = svc?.soft(isDark) ??
        (isDark ? GardenColors.darkSurfaceElevated : GardenColors.lime.withValues(alpha: 0.6));
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final idleText = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Semantics(
      button: true,
      selected: selected,
      label: svc?.label ?? 'Todos los servicios',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: GardenMotion.resolve(context, GardenMotion.quick),
          curve: GardenMotion.enter,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? soft : surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? ink.withValues(alpha: 0.45) : border, width: selected ? 1.5 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Figura con volumen: la elegida toma el color del servicio y
              // flota; las demás quedan neutras (antes: ícono de línea plano).
              GardenClay(
                size: 46,
                float: selected,
                interactive: false,
                color: selected
                    ? Color.lerp(ink, Colors.white, isDark ? 0.0 : 0.12)!
                    : (isDark ? GardenColors.darkSurfaceElevated : const Color(0xFFF1EEE4)),
                child: GardenClayIcon(
                  svc == null ? GIcon.huella : GIcon.forService(svc),
                  size: GIconSize.lg,
                  color: selected ? Colors.white : idleText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                svc?.label ?? 'Todos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GardenText.labelMedium.copyWith(
                  color: selected ? ink : idleText,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Acceso rápido: icono en círculo suave + etiqueta corta debajo.
class GardenShortcut extends StatelessWidget {
  final GIcon icon;
  final String label;
  final VoidCallback onTap;

  const GardenShortcut({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubble = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurface;
    final text = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Burbuja con volumen (antes: círculo plano con borde).
                GardenClay(
                  size: 50,
                  color: isDark ? GardenColors.darkSurfaceElevated : bubble,
                  child: GardenClayIcon(icon,
                      size: GIconSize.lg, color: isDark ? GardenColors.primaryLight : GardenColors.primary),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: GardenText.caption.copyWith(color: text, fontWeight: FontWeight.w700, height: 1.15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

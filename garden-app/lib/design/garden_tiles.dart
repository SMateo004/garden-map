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

/// Un atajo de [GardenQuickAccess].
class GardenQuickItem {
  final GIcon icon;
  final String label;
  final VoidCallback onTap;
  const GardenQuickItem(this.icon, this.label, this.onTap);
}

/// Atajos del inicio, recogidos en una barra fina: tres íconos chicos
/// superpuestos y "Veterinarias, favoritos y más". Al tocarla se despliega
/// ahí mismo una fila de chips (sin ventanas emergentes); al tocarla otra
/// vez se recoge. Antes eran cinco burbujas grandes con texto que ocupaban
/// una franja entera entre los servicios y la lista de cuidadores.
///
/// Recuerda si quedó abierta mientras dura la sesión.
class GardenQuickAccess extends StatefulWidget {
  final List<GardenQuickItem> items;

  /// Lo que dice la barra cerrada ("Veterinarias, favoritos y más").
  final String summary;

  const GardenQuickAccess({super.key, required this.items, required this.summary});

  @override
  State<GardenQuickAccess> createState() => _GardenQuickAccessState();
}

class _GardenQuickAccessState extends State<GardenQuickAccess> {
  static bool _sessionOpen = false;
  bool _open = _sessionOpen;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _open = _sessionOpen = !_open);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final ink = isDark ? GardenColors.primaryLight : GardenColors.primary;
    final soft = isDark ? GardenColors.darkSurfaceElevated : const Color(0xFFEFF5DD);
    final d = GardenMotion.resolve(context, GardenMotion.standard);
    final preview = widget.items.take(3).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      // ── La barra ──
      Semantics(
        button: true,
        expanded: _open,
        label: _open ? 'Ocultar atajos' : 'Mostrar atajos: ${widget.summary}',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: _toggle,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: d,
            curve: GardenMotion.enter,
            height: 42,
            padding: const EdgeInsets.only(left: 6, right: 12),
            decoration: BoxDecoration(
              color: _open ? soft : surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _open ? ink.withValues(alpha: 0.35) : border),
            ),
            child: Row(children: [
              // Tres íconos chicos superpuestos: identidad sin ocupar lugar.
              SizedBox(
                width: 30.0 + 18.0 * (preview.length - 1),
                height: 30,
                child: Stack(children: [
                  for (var i = preview.length - 1; i >= 0; i--)
                    Positioned(
                      left: 18.0 * i,
                      child: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: soft,
                          shape: BoxShape.circle,
                          border: Border.all(color: _open ? soft : surface, width: 2),
                        ),
                        child: GardenIcon(preview[i].icon, size: GIconSize.xs, state: GIconState.active, color: ink),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: d,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, if (current != null) current],
                  ),
                  child: Text(
                    _open ? 'Atajos' : widget.summary,
                    key: ValueKey(_open),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _open ? text : sub, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: d,
                curve: GardenMotion.move,
                child: GardenIcon(GIcon.desplegar, size: GIconSize.sm, color: _open ? ink : sub),
              ),
            ]),
          ),
        ),
      ),
      // ── Los atajos, ahí mismo ──
      AnimatedSize(
        duration: d,
        curve: GardenMotion.enter,
        alignment: Alignment.topCenter,
        child: !_open
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(children: [
                    for (var i = 0; i < widget.items.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      // Entran uno detrás de otro desde la izquierda.
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: GardenMotion.resolve(context, Duration(milliseconds: 180 + 45 * i)),
                        curve: GardenMotion.enter,
                        builder: (_, v, child) => Opacity(
                          opacity: v,
                          child: Transform.translate(offset: Offset(-12 * (1 - v), 0), child: child),
                        ),
                        child: _QuickChip(item: widget.items[i], ink: ink, text: text, surface: surface, border: border),
                      ),
                    ],
                  ]),
                ),
              ),
      ),
    ]);
  }
}

class _QuickChip extends StatelessWidget {
  final GardenQuickItem item;
  final Color ink, text, surface, border;
  const _QuickChip({required this.item, required this.ink, required this.text, required this.surface, required this.border});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          item.onTap();
        },
        child: GardenPress(
          radius: BorderRadius.circular(999),
          child: Container(
            height: 38,
            padding: const EdgeInsets.only(left: 10, right: 14),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              GardenIcon(item.icon, size: GIconSize.sm, color: ink),
              const SizedBox(width: 7),
              Text(item.label, style: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }
}

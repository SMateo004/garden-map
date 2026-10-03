import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_icons.dart';

// ── CAMBIO DE PERFIL ───────────────────────────────────────────────────────
// Una misma cuenta puede usar Garden de tres maneras (como el cambio de perfil
// de Instagram): dueño de mascota, cuidador por cuenta propia o empleado de una
// empresa. Este componente es el ÚNICO lugar donde se elige — perfil, cuenta del
// empleado y hoja inferior usan el mismo, así se aprende una vez.
//
//   GardenModeSwitcher(options: [...], current: GardenMode.staff, onSelect: ...)
//
// Reglas: el selector se desliza (no salta) con GardenMotion; mientras el
// servidor cambia el rol, la opción elegida muestra un indicador; nunca hay más
// de una opción seleccionada. Las identidades que aún no tiene se ofrecen como
// acciones "agregar" debajo, no como opciones deshabilitadas.

enum GardenMode { owner, independent, staff }

class GardenModeOption {
  final GardenMode mode;
  final String title;
  final String subtitle;

  /// Frase que explica qué significa estar en este modo (se muestra debajo
  /// cuando está seleccionado).
  final String description;
  final GIcon icon;

  const GardenModeOption({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
  });
}

class GardenModeAddAction {
  final String label;
  final VoidCallback onTap;
  const GardenModeAddAction({required this.label, required this.onTap});
}

class GardenModeSwitcher extends StatelessWidget {
  final List<GardenModeOption> options;
  final GardenMode current;

  /// Modo al que se está cambiando ahora mismo (muestra un indicador).
  final GardenMode? switching;
  final ValueChanged<GardenMode> onSelect;
  final List<GardenModeAddAction> addActions;

  /// Sin tarjeta alrededor — para usarlo dentro de una hoja inferior.
  final bool bare;

  const GardenModeSwitcher({
    super.key,
    required this.options,
    required this.current,
    required this.onSelect,
    this.switching,
    this.addActions = const [],
    this.bare = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final subtext = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final ink = isDark ? GardenColors.primaryLight : GardenColors.primary;

    final currentIndex = options.indexWhere((o) => o.mode == current).clamp(0, options.length - 1);
    final currentOption = options[currentIndex];
    final duration = GardenMotion.resolve(context, GardenMotion.standard);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Estás usando Garden como',
            style: GardenText.caption.copyWith(color: subtext, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, c) {
          final segment = c.maxWidth / options.length;
          return SizedBox(
            height: options.length > 2 ? 88 : 100,
            child: Stack(children: [
              // Fondo del selector: se desliza hasta la opción elegida.
              AnimatedPositioned(
                duration: duration,
                curve: GardenMotion.enter,
                left: segment * currentIndex,
                top: 0,
                bottom: 0,
                width: segment,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lime.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(GardenRadius.lg),
                    border: Border.all(color: ink.withValues(alpha: 0.45), width: 1.5),
                  ),
                ),
              ),
              Row(children: [
                for (final o in options)
                  Expanded(
                    child: _Segment(
                      option: o,
                      selected: o.mode == current,
                      busy: o.mode == switching,
                      compact: options.length > 2,
                      ink: ink,
                      idleText: subtext,
                      titleColor: text,
                      onTap: () {
                        if (o.mode == current || switching != null) return;
                        HapticFeedback.selectionClick();
                        onSelect(o.mode);
                      },
                    ),
                  ),
              ]),
            ]),
          );
        }),
        // Con "reducir movimiento" (duración cero) no se anima: AnimatedSize con
        // duración cero falla durante el layout.
        if (duration == Duration.zero)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 2, right: 2),
            child: Text(currentOption.description, style: GardenText.bodySmall.copyWith(color: subtext, height: 1.35)),
          )
        else
          AnimatedSize(
            duration: duration,
            curve: GardenMotion.enter,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: GardenMotion.enter,
              switchOutCurve: GardenMotion.exit,
              child: Padding(
                key: ValueKey(currentOption.mode),
                padding: const EdgeInsets.only(top: 10, left: 2, right: 2),
                child: Text(currentOption.description,
                    style: GardenText.bodySmall.copyWith(color: subtext, height: 1.35)),
              ),
            ),
          ),
        if (addActions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final a in addActions) _AddChip(action: a, ink: ink, border: border)],
          ),
        ],
      ],
    );

    if (bare) return content;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.xl),
        border: Border.all(color: border),
      ),
      child: content,
    );
  }
}

class _Segment extends StatelessWidget {
  final GardenModeOption option;
  final bool selected;
  final bool busy;
  final bool compact;
  final Color ink;
  final Color idleText;
  final Color titleColor;
  final VoidCallback onTap;

  const _Segment({
    required this.option,
    required this.selected,
    required this.busy,
    required this.compact,
    required this.ink,
    required this.idleText,
    required this.titleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final duration = GardenMotion.resolve(context, GardenMotion.quick);
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.title}. ${option.subtitle}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 30,
                child: Center(
                  child: busy
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: ink),
                        )
                      : AnimatedScale(
                          scale: selected ? 1.12 : 1.0,
                          duration: duration,
                          curve: GardenMotion.pop,
                          child: GardenIcon(option.icon,
                              size: GIconSize.lg,
                              state: selected ? GIconState.active : GIconState.idle),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              AnimatedDefaultTextStyle(
                duration: duration,
                style: GardenText.labelMedium.copyWith(
                  color: selected ? ink : titleColor,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                ),
                child: Text(option.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
              ),
              if (!compact) ...[
                const SizedBox(height: 2),
                Text(option.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GardenText.caption.copyWith(color: idleText)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  final GardenModeAddAction action;
  final Color ink;
  final Color border;
  const _AddChip({required this.action, required this.ink, required this.border});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(GardenRadius.full),
        onTap: () {
          HapticFeedback.selectionClick();
          action.onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GardenRadius.full),
            border: Border.all(color: ink.withValues(alpha: 0.5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            GardenIcon(GIcon.agregar, size: GIconSize.sm, color: ink),
            const SizedBox(width: 6),
            Text(action.label, style: GardenText.labelMedium.copyWith(color: ink, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

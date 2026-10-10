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
// Cambiar de perfil es raro, así que NO ocupa lugar: por defecto es una barra
// delgada que solo dice en qué perfil estás ("Usando Garden como Dueño ⌄"). Al
// tocarla —o deslizarla hacia abajo— se despliega ahí mismo (sin ventanas
// emergentes) con las opciones, una frase que explica el perfil actual y los
// extras (unirse a un equipo, salir del equipo). Elegir otro perfil cambia el
// rol en el servidor y navega, así que la barra vuelve plegada sola.
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

class GardenModeSwitcher extends StatefulWidget {
  final List<GardenModeOption> options;
  final GardenMode current;

  /// Modo al que se está cambiando ahora mismo (muestra un indicador).
  final GardenMode? switching;
  final ValueChanged<GardenMode> onSelect;
  final List<GardenModeAddAction> addActions;

  /// Sin tarjeta alrededor — para usarlo dentro de una hoja inferior.
  final bool bare;

  /// Empieza desplegado (p. ej. en la hoja inferior, donde el usuario ya pidió
  /// cambiar de perfil). Por defecto empieza plegado como una barra delgada.
  final bool initiallyExpanded;

  /// Contenido extra al final de la parte desplegada (p. ej. "Salir del equipo").
  final Widget? footer;

  const GardenModeSwitcher({
    super.key,
    required this.options,
    required this.current,
    required this.onSelect,
    this.switching,
    this.addActions = const [],
    this.bare = false,
    this.initiallyExpanded = false,
    this.footer,
  });

  @override
  State<GardenModeSwitcher> createState() => _GardenModeSwitcherState();
}

class _GardenModeSwitcherState extends State<GardenModeSwitcher> {
  late bool _expanded = widget.initiallyExpanded;

  void _setExpanded(bool value) {
    if (value == _expanded) return;
    HapticFeedback.selectionClick();
    setState(() => _expanded = value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final subtext = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final ink = isDark ? GardenColors.primaryLight : GardenColors.primary;

    final options = widget.options;
    final currentIndex = options.indexWhere((o) => o.mode == widget.current).clamp(0, options.length - 1);
    final currentOption = options[currentIndex];
    final duration = GardenMotion.resolve(context, GardenMotion.standard);
    // Mientras se cambia de perfil la parte desplegada no se pliega bajo el dedo.
    final expanded = _expanded || widget.switching != null;

    // Con tarjeta propia la barra y el cuerpo llevan sangría; sin tarjeta (hoja inferior) la pone quien lo contiene.
    final inset = widget.bare ? 0.0 : 12.0;

    final header = _Header(
      option: currentOption,
      inset: inset,
      expanded: expanded,
      ink: ink,
      subtext: subtext,
      text: text,
      duration: duration,
      onToggle: () => _setExpanded(!expanded),
      onPull: (down) => _setExpanded(down),
    );

    final body = Padding(
      padding: EdgeInsets.fromLTRB(inset, 2, inset, widget.bare ? 4 : 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, c) {
            final segment = c.maxWidth / options.length;
            return SizedBox(
              height: 72,
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
                        selected: o.mode == widget.current,
                        busy: o.mode == widget.switching,
                        ink: ink,
                        titleColor: text,
                        onTap: () {
                          if (o.mode == widget.current || widget.switching != null) return;
                          HapticFeedback.selectionClick();
                          widget.onSelect(o.mode);
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
          if (widget.addActions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final a in widget.addActions) _AddChip(action: a, ink: ink, border: border)],
            ),
          ],
          if (widget.footer != null) ...[
            const SizedBox(height: 4),
            widget.footer!,
          ],
        ],
      ),
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (duration == Duration.zero)
          (expanded ? body : const SizedBox.shrink())
        else
          AnimatedSize(
            duration: duration,
            curve: GardenMotion.enter,
            alignment: Alignment.topCenter,
            child: expanded ? body : const SizedBox(width: double.infinity),
          ),
      ],
    );

    if (widget.bare) return content;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        border: Border.all(color: border),
      ),
      child: content,
    );
  }
}

/// La barra delgada: en qué perfil estás + una flecha. Se toca o se desliza.
class _Header extends StatelessWidget {
  final GardenModeOption option;
  final double inset;
  final bool expanded;
  final Color ink;
  final Color subtext;
  final Color text;
  final Duration duration;
  final VoidCallback onToggle;

  /// `true` = deslizó hacia abajo (desplegar), `false` = hacia arriba (plegar).
  final ValueChanged<bool> onPull;

  const _Header({
    required this.option,
    required this.inset,
    required this.expanded,
    required this.ink,
    required this.subtext,
    required this.text,
    required this.duration,
    required this.onToggle,
    required this.onPull,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: expanded,
      label: 'Cambiar de perfil. Estás usando Garden como ${option.title} ${option.subtitle}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v > 150) onPull(true);
          if (v < -150) onPull(false);
        },
        child: InkWell(
          onTap: onToggle,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: Row(children: [
                GardenIcon(option.icon, size: GIconSize.md, state: GIconState.active, color: ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: 'Usando Garden como ',
                        style: GardenText.caption.copyWith(color: subtext),
                      ),
                      TextSpan(
                        text: option.title,
                        style: GardenText.labelMedium.copyWith(color: text, fontWeight: FontWeight.w800),
                      ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: duration,
                  curve: GardenMotion.enter,
                  child: GardenIcon(GIcon.desplegar, size: GIconSize.sm, color: subtext),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final GardenModeOption option;
  final bool selected;
  final bool busy;
  final Color ink;
  final Color titleColor;
  final VoidCallback onTap;

  const _Segment({
    required this.option,
    required this.selected,
    required this.busy,
    required this.ink,
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
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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

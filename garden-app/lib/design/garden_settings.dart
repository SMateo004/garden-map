import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_depth.dart';
import 'garden_icons.dart';

/// Piezas de "Mi perfil" (profile_screen.dart): quién soy arriba y los ajustes
/// agrupados en tarjetas (una por tema) en lugar de una fila suelta por cada
/// opción — se lee como una lista, no como veinte botones iguales.

/// Encabezado: foto, nombre, correo (verificado o "Verificar") y el modo en
/// el que se está usando la app.
class GardenProfileHeader extends StatelessWidget {
  final String name;
  final String email;
  final String? photoUrl;
  final bool emailVerified;
  final VoidCallback? onVerifyEmail;
  final String roleLabel;
  final Color roleColor;

  /// "Desde oct 2026" — null si no se sabe.
  final String? since;

  const GardenProfileHeader({
    super.key,
    required this.name,
    required this.email,
    required this.roleLabel,
    required this.roleColor,
    this.photoUrl,
    this.emailVerified = true,
    this.onVerifyEmail,
    this.since,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GardenRadius.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [GardenColors.primary.withValues(alpha: 0.28), surface]
              : [GardenColors.lime.withValues(alpha: 0.35), surface],
        ),
        boxShadow: GardenShadows.card,
      ),
      child: Row(children: [
        // Foto con aro claro y sombra: se despega del fondo.
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: surface,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12), blurRadius: 12, offset: const Offset(0, 5))],
          ),
          child: GardenAvatar(imageUrl: photoUrl, size: 68, initials: name),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GardenText.h4.copyWith(color: text, fontWeight: FontWeight.w900, height: 1.15)),
            const SizedBox(height: 4),
            Row(children: [
              Flexible(
                child: Text(email,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: GardenText.bodySmall.copyWith(color: sub)),
              ),
              const SizedBox(width: 6),
              if (emailVerified)
                const Tooltip(
                  message: 'Correo verificado',
                  child: GardenIcon(GIcon.verificado, size: GIconSize.xs, state: GIconState.active, color: GardenColors.success),
                )
              else
                GestureDetector(
                  onTap: onVerifyEmail,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: GardenColors.warning.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(GardenRadius.full),
                    ),
                    child: const Text('Verificar',
                        style: TextStyle(color: GardenColors.warning, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: isDark ? 0.22 : 0.13),
                  borderRadius: BorderRadius.circular(GardenRadius.full),
                ),
                child: Text(roleLabel, style: TextStyle(color: roleColor, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              if (since != null)
                Text(since!, style: GardenText.caption.copyWith(color: sub, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Tono de una fila de ajustes.
enum GardenSettingsTone { normal, attention, danger }

/// Una opción dentro de [GardenSettingsGroup].
class GardenSettingsRow extends StatefulWidget {
  final GIcon icon;
  final String title;

  /// Texto chico debajo (ej. "Te falta completar 3 datos").
  final String? subtitle;
  final VoidCallback? onTap;
  final GardenSettingsTone tone;

  /// Reemplaza la flecha (ej. un interruptor o un contador).
  final Widget? trailing;

  const GardenSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.tone = GardenSettingsTone.normal,
    this.trailing,
  });

  @override
  State<GardenSettingsRow> createState() => _GardenSettingsRowState();
}

class _GardenSettingsRowState extends State<GardenSettingsRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final hint = isDark ? GardenColors.darkTextHint : GardenColors.lightTextHint;
    final ink = isDark ? GardenColors.primaryLight : GardenColors.primary;
    final (Color accent, Color titleColor) = switch (widget.tone) {
      GardenSettingsTone.normal => (ink, text),
      GardenSettingsTone.attention => (GardenColors.warning, text),
      GardenSettingsTone.danger => (GardenColors.error, GardenColors.error),
    };
    final attention = widget.tone == GardenSettingsTone.attention;
    final enabled = widget.onTap != null;

    return Semantics(
      button: enabled,
      label: widget.subtitle == null ? widget.title : '${widget.title}. ${widget.subtitle}',
      excludeSemantics: true,
      child: Opacity(
        // Sin acción pero con algo a la derecha (ej. un candado) es informativa, no deshabilitada.
        opacity: enabled || widget.trailing != null ? 1 : 0.5,
        child: InkWell(
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                }
              : null,
          onHighlightChanged: (v) => setState(() => _down = v),
          child: AnimatedContainer(
            duration: GardenMotion.resolve(context, GardenMotion.instant),
            curve: GardenMotion.enter,
            color: attention ? GardenColors.warning.withValues(alpha: isDark ? 0.10 : 0.07) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              AnimatedScale(
                duration: GardenMotion.resolve(context, GardenMotion.instant),
                scale: _down ? 0.9 : 1,
                child: GardenClay(
                  size: 36,
                  circle: false,
                  radius: 11,
                  interactive: false,
                  tint: accent.withValues(alpha: 0.12),
                  child: GardenIcon(widget.icon, size: GIconSize.sm, state: GIconState.active, color: accent),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.title,
                      style: TextStyle(color: titleColor, fontSize: 14, fontWeight: attention ? FontWeight.w800 : FontWeight.w600)),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(widget.subtitle!,
                        style: TextStyle(
                            color: attention ? GardenColors.warning : hint, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ]),
              ),
              if (attention) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: GardenColors.warning, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
              ],
              widget.trailing ??
                  (widget.tone == GardenSettingsTone.danger
                      ? const SizedBox.shrink()
                      : GardenIcon(GIcon.siguiente, size: GIconSize.sm, color: attention ? GardenColors.warning : hint)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta con título que agrupa varias [GardenSettingsRow] separadas por
/// una línea fina.
class GardenSettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const GardenSettingsGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final rows = children.whereType<Widget>().toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title!.toUpperCase(),
                style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9)),
          ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(GardenRadius.lg),
            border: Border.all(color: border),
            boxShadow: GardenShadows.card,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, indent: 64, color: border),
                rows[i],
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Selector de tres opciones con la elegida deslizándose (tema de la app).
class GardenSegmented<T> extends StatelessWidget {
  final List<(T, GIcon, String)> options;
  final T selected;
  final ValueChanged<T> onSelect;
  const GardenSegmented({super.key, required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final track = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final index = options.indexWhere((o) => o.$1 == selected).clamp(0, options.length - 1);
    final d = GardenMotion.resolve(context, GardenMotion.quick);

    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(GardenRadius.md)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / options.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: d,
            curve: GardenMotion.move,
            left: w * index,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                color: GardenColors.primary,
                borderRadius: BorderRadius.circular(GardenRadius.sm),
                boxShadow: [BoxShadow(color: GardenColors.primary.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < options.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == index,
                  label: options[i].$3,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (i == index) return;
                      HapticFeedback.selectionClick();
                      onSelect(options[i].$1);
                    },
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      GardenIcon(options[i].$2,
                          size: GIconSize.sm,
                          state: i == index ? GIconState.active : GIconState.idle,
                          color: i == index ? Colors.white : sub),
                      const SizedBox(width: 6),
                      AnimatedDefaultTextStyle(
                        duration: d,
                        style: TextStyle(
                            color: i == index ? Colors.white : sub,
                            fontSize: 12,
                            fontWeight: i == index ? FontWeight.w800 : FontWeight.w600),
                        child: Text(options[i].$3),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

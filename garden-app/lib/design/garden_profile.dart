import 'package:flutter/material.dart';

import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_icons.dart';

/// Piezas de "Mis datos" (my_data_screen.dart): cuánto falta para tener el
/// perfil completo, a la vista mientras se completa, y el formulario en
/// secciones que dicen si están completas.

/// Encabezado: foto (tocable), nombre, correo y el avance del perfil.
class GardenProfileCompletion extends StatelessWidget {
  final Widget avatar;
  final String name;
  final String? subtitle;
  final int done;
  final int total;

  /// Lo que falta, en el orden del formulario. Se muestran los primeros.
  final List<String> missing;

  const GardenProfileCompletion({
    super.key,
    required this.avatar,
    required this.name,
    this.subtitle,
    required this.done,
    required this.total,
    this.missing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final complete = missing.isEmpty;
    final color = complete ? GardenColors.success : GardenColors.primary;
    final pct = total == 0 ? 1.0 : (done / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: GardenShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            avatar,
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.trim().isEmpty ? 'Tu perfil' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: text, fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sub, fontSize: 13)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: pct),
                        duration: GardenMotion.resolve(context, GardenMotion.standard),
                        curve: GardenMotion.enter,
                        builder: (_, v, __) => LinearProgressIndicator(
                          value: v,
                          minHeight: 6,
                          backgroundColor: color.withValues(alpha: 0.14),
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(complete ? 'Completo' : '${(pct * 100).round()}%',
                      style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w900)),
                ]),
              ]),
            ),
          ]),
          if (!complete) ...[
            const SizedBox(height: 12),
            Text(
              'Te falta: ${missing.take(3).join(', ')}${missing.length > 3 ? ' y ${missing.length - 3} más' : ''}.',
              style: TextStyle(color: sub, fontSize: 12.5, height: 1.35),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Row(children: [
              const GardenIcon(GIcon.verificado, size: GIconSize.xs, state: GIconState.active, color: GardenColors.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Tu perfil está completo: los cuidadores te conocen y tus reservas van más rápido.',
                    style: TextStyle(color: sub, fontSize: 12.5)),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Sección del formulario con su estado: "Completo" o "Falta 2".
class GardenFormSection extends StatelessWidget {
  final GIcon icon;
  final String title;
  final String? hint;
  final int missing;
  final List<Widget> children;

  const GardenFormSection({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.missing = 0,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final ok = missing == 0;
    final chipColor = ok ? GardenColors.success : GardenColors.warning;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GardenIcon(icon, size: GIconSize.sm, state: GIconState.active, color: GardenColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w800))),
            AnimatedSwitcher(
              duration: GardenMotion.resolve(context, GardenMotion.quick),
              child: Container(
                key: ValueKey(missing),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  GardenIcon(ok ? GIcon.confirmado : GIcon.advertencia, size: GIconSize.xs, state: GIconState.active, color: chipColor),
                  const SizedBox(width: 4),
                  Text(ok ? 'Completo' : 'Falta $missing',
                      style: TextStyle(color: chipColor, fontSize: 11.5, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ]),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: TextStyle(color: sub, fontSize: 12, height: 1.35)),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// Barra fija para guardar un formulario, siempre a la vista.
class GardenSaveBar extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  final String? note;
  const GardenSaveBar({super.key, required this.label, this.loading = false, this.onPressed, this.note});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
        border: Border(top: BorderSide(color: border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Row(children: [
                if (note != null) ...[
                  Expanded(flex: 2, child: Text(note!, style: TextStyle(color: sub, fontSize: 12, height: 1.3))),
                  const SizedBox(width: 12),
                ],
                Expanded(flex: 3, child: GardenButton(label: label, loading: loading, onPressed: onPressed, gIcon: GIcon.confirmado)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

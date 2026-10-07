import 'package:flutter/material.dart';

import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_depth.dart';
import 'garden_icons.dart';

// ── PASOS DE LA HISTORIA ───────────────────────────────────────────────────
// "Qué pasó, qué está pasando, qué sigue" en una línea vertical. Principio 2
// del plan: el dueño nunca adivina el próximo paso. El paso actual es el
// único con color fuerte; los hechos llevan check y los que faltan van
// apagados.
enum StoryStepState { done, current, next }

class StoryStepItem {
  final GIcon icon;
  final String title;
  final String? detail;
  final StoryStepState state;
  const StoryStepItem(this.icon, this.title, this.state, {this.detail});
}

class GardenStoryProgress extends StatelessWidget {
  final List<StoryStepItem> steps;
  const GardenStoryProgress({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final line = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final good = isDark ? GardenColors.accent : const Color(0xFF2FA83A);
    final now = isDark ? GardenColors.primaryLight : GardenColors.primary;

    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 36,
                  child: Column(
                    children: [
                      _Dot(step: steps[i], good: good, now: now, sub: sub),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            color: steps[i].state == StoryStepState.done ? good.withValues(alpha: 0.5) : line,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 6, bottom: i < steps.length - 1 ? 16 : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].title,
                          style: GardenText.bodyMedium.copyWith(
                            color: steps[i].state == StoryStepState.next ? sub : text,
                            fontWeight: steps[i].state == StoryStepState.current ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                        if (steps[i].detail != null)
                          Text(steps[i].detail!, style: GardenText.bodySmall.copyWith(color: sub)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final StoryStepItem step;
  final Color good;
  final Color now;
  final Color sub;
  const _Dot({required this.step, required this.good, required this.now, required this.sub});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (step.state) {
      StoryStepState.done => (good.withValues(alpha: 0.14), good, GIcon.confirmado),
      StoryStepState.current => (now.withValues(alpha: 0.16), now, step.icon),
      StoryStepState.next => (sub.withValues(alpha: 0.08), sub.withValues(alpha: 0.7), step.icon),
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: step.state == StoryStepState.current ? 0.7 : 1, end: 1),
      duration: GardenMotion.resolve(context, GardenMotion.expressive),
      curve: GardenMotion.pop,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      // Con volumen; el paso actual flota ("estás aquí").
      child: GardenClay(
        size: 36,
        tint: bg,
        interactive: false,
        child: Center(
          child: GardenIcon(icon,
              size: GIconSize.md,
              color: fg,
              state: step.state == StoryStepState.next ? GIconState.idle : GIconState.active),
        ),
      ),
    );
  }
}

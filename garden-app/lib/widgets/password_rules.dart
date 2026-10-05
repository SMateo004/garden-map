import 'package:flutter/material.dart';

import '../design/garden_icons.dart';
import '../theme/garden_theme.dart';
import '../utils/person_validators.dart';

/// Requisitos de la contraseña que se van marcando mientras se escribe.
/// Mismas reglas que `PersonValidators.password` y el backend.
class PasswordRules extends StatelessWidget {
  const PasswordRules({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (label, met) in PersonValidators.passwordRules(value.text))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: met ? GardenColors.success.withValues(alpha: 0.10) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: met ? GardenColors.success.withValues(alpha: 0.4) : borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GardenIcon(
                    met ? GIcon.confirmado : GIcon.pendiente,
                    size: GIconSize.xs,
                    state: met ? GIconState.active : GIconState.idle,
                    color: met ? GardenColors.success : subtextColor,
                  ),
                  const SizedBox(width: 5),
                  Text(label,
                      style: TextStyle(
                          color: met ? GardenColors.success : subtextColor, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

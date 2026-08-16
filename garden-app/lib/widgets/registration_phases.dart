import 'package:flutter/material.dart';
import '../theme/garden_theme.dart';

/// Agrupa los pasos de un wizard de registro en fases con nombre — mismo
/// patrón que usan Airbnb/Uber en sus onboardings de host/conductor: un
/// registro de 11 pasos se siente mucho más corto mostrado como "Fase 2 de 4"
/// que como "Paso 7 de 11", aunque sea exactamente el mismo recorrido.
class RegistrationPhase {
  final String name;
  final IconData icon;
  final int startStep; // inclusive
  final int endStep; // inclusive

  const RegistrationPhase({
    required this.name,
    required this.icon,
    required this.startStep,
    required this.endStep,
  });

  bool contains(int step) => step >= startStep && step <= endStep;
}

/// Índice (0-based) de la fase a la que pertenece [step]. Si no matchea
/// ninguna (no debería pasar si las fases cubren 0..N-1), devuelve la última.
int phaseIndexForStep(List<RegistrationPhase> phases, int step) {
  final idx = phases.indexWhere((p) => p.contains(step));
  return idx == -1 ? phases.length - 1 : idx;
}

/// "FASE 2 DE 4 · TU SERVICIO" — para el badge/header que reemplaza al
/// "Paso X de N" plano.
String phaseLabel(List<RegistrationPhase> phases, int step) {
  final idx = phaseIndexForStep(phases, step);
  return 'FASE ${idx + 1} DE ${phases.length} · ${phases[idx].name.toUpperCase()}';
}

/// Barra de progreso segmentada por fase — un segmento por fase (no uno por
/// paso). Las fases ya completadas quedan llenas del todo, la fase actual se
/// llena proporcional a cuánto avanzaste dentro de ella, y las futuras
/// quedan vacías. Misma curva/duración que AnimatedStepProgressBar para que
/// se sienta igual de suave.
class PhaseProgressBar extends StatelessWidget {
  final List<RegistrationPhase> phases;
  final int currentStep;
  final Color backgroundColor;
  final double height;

  const PhaseProgressBar({
    super.key,
    required this.phases,
    required this.currentStep,
    required this.backgroundColor,
    this.height = 5,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < phases.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(child: _segment(phases[i])),
        ],
      ],
    );
  }

  Widget _segment(RegistrationPhase phase) {
    double target;
    if (currentStep > phase.endStep) {
      target = 1.0;
    } else if (currentStep < phase.startStep) {
      target = 0.0;
    } else {
      final totalInPhase = phase.endStep - phase.startStep + 1;
      final doneInPhase = currentStep - phase.startStep + 1;
      target = (doneInPhase / totalInPhase).clamp(0.0, 1.0);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(
            height: height,
            color: backgroundColor,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: animatedValue,
              child: Container(color: GardenColors.primary),
            ),
          ),
        );
      },
    );
  }
}

/// Pantalla de bienvenida mostrada una sola vez, antes del paso 0, que
/// enumera las fases del registro — fija expectativas desde el arranque
/// ("esto va a tomar 4 pasos, no una lista interminable"), al estilo de la
/// intro de Airbnb para nuevos hosts. Se salta en modo resume/conversión
/// (el flujo que la usa decide cuándo mostrarla).
class RegistrationPhaseIntro extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<RegistrationPhase> phases;
  final VoidCallback onStart;
  final String buttonLabel;

  const RegistrationPhaseIntro({
    super.key,
    required this.title,
    required this.subtitle,
    required this.phases,
    required this.onStart,
    this.buttonLabel = 'Comenzar',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🌿', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 16),
                  Text(title,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
                  const SizedBox(height: 8),
                  Text(subtitle, style: TextStyle(fontSize: 14.5, color: subtextColor, height: 1.5)),
                  const SizedBox(height: 32),
                  for (int i = 0; i < phases.length; i++) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: GardenColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Icon(phases[i].icon, color: GardenColors.primary, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('${i + 1}. ${phases[i].name}',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
                          ),
                        ),
                      ],
                    ),
                    if (i < phases.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 19),
                        child: Container(width: 2, height: 20, color: surfaceEl),
                      ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: GardenButton(label: buttonLabel, height: 50, onPressed: onStart),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

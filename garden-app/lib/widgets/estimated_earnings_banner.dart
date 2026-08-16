import 'package:flutter/material.dart';
import '../theme/garden_theme.dart';

/// "Gancho" de ingresos estimados — mismo patrón que usa Uber para sostener
/// motivación durante el registro ("ganá hasta $X en tu zona"). Usa los
/// precios máximos ya configurados en AppSettings (los mismos límites que
/// ya se cargan para el paso de precio, ver _loadPriceLimits en los 3
/// flujos de registro) — sin pegarle a ningún endpoint nuevo. Es una
/// proyección aspiracional a partir de una frecuencia de trabajo asumida,
/// no un promedio real; por eso siempre se marca como estimado.
///
/// Se actualiza en vivo a medida que el cuidador elige/saca servicios.
class EstimatedEarningsBanner extends StatelessWidget {
  final List<String> services;
  final double paseoMax;
  final double hospedajeMax;
  final double guarderiaMax;

  const EstimatedEarningsBanner({
    super.key,
    required this.services,
    required this.paseoMax,
    required this.hospedajeMax,
    required this.guarderiaMax,
  });

  // Frecuencia mensual asumida para un cuidador activo — conservadora a
  // propósito (menos que "todos los días") para no prometer de más.
  static const int _paseosPorMes = 16;
  static const int _nochesHospedajePorMes = 6;
  static const int _diasGuarderiaPorMes = 8;

  double get _estimatedMonthly {
    double total = 0;
    if (services.contains('PASEO')) total += paseoMax * _paseosPorMes;
    if (services.contains('HOSPEDAJE')) total += hospedajeMax * _nochesHospedajePorMes;
    if (services.contains('GUARDERIA')) total += guarderiaMax * _diasGuarderiaPorMes;
    return total;
  }

  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) return const SizedBox.shrink();
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final amount = _estimatedMonthly.round();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [GardenColors.primary.withValues(alpha: 0.14), GardenColors.primary.withValues(alpha: 0.05)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: GardenColors.primary, borderRadius: BorderRadius.circular(11)),
            alignment: Alignment.center,
            child: const Text('💰', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(color: textColor, fontSize: 14, height: 1.35),
                    children: [
                      const TextSpan(text: 'Con Garden, podrías ganar hasta '),
                      TextSpan(
                        text: 'Bs $amount/mes',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: GardenColors.primary),
                      ),
                      const TextSpan(text: ' con los servicios que elegiste.'),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text('Estimado según tu disponibilidad — vos decidís cuánto trabajar.',
                    style: TextStyle(color: subtextColor, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

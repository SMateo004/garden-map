import 'package:flutter/material.dart';

import '../theme/garden_theme.dart';
import 'garden_icons.dart';

/// Resumen de la disponibilidad del cuidador (pestaña Disponibilidad), en
/// lenguaje simple, a partir de defaultSchedule tal como lo guarda la API.

const _blockDefaults = {
  'morning': ('Mañana', '08:00', '11:00'),
  'afternoon': ('Tarde', '13:00', '17:00'),
  'night': ('Noche', '19:00', '22:00'),
};

({String headline, String? hours, bool off}) availabilitySummary(Map<dynamic, dynamic>? schedule) {
  final s = schedule ?? const {};
  final wd = s['weekdays'] as bool? ?? true;
  final we = s['weekends'] as bool? ?? true;
  final hol = s['holidays'] as bool? ?? true;

  if (!wd && !we) {
    return (
      headline: hol ? 'Solo recibes reservas en feriados' : 'No estás recibiendo reservas',
      hours: null,
      off: !hol,
    );
  }
  final days = wd && we
      ? 'todos los días'
      : wd
          ? 'de lunes a viernes'
          : 'los fines de semana';
  final headline = 'Recibes reservas $days${hol ? ', también feriados' : ', sin feriados'}';

  final raw = s['paseoTimeBlocks'];
  final blocks = raw is Map ? raw : const {};
  final parts = <String>[];
  _blockDefaults.forEach((key, def) {
    final b = blocks[key];
    final enabled = b is Map ? b['enabled'] == true : true;
    if (!enabled) return;
    final start = b is Map ? (b['start'] ?? def.$2) : def.$2;
    final end = b is Map ? (b['end'] ?? def.$3) : def.$3;
    parts.add('${def.$1} $start–$end');
  });
  return (headline: headline, hours: parts.isEmpty ? 'Sin horarios de paseo activos' : parts.join(' · '), off: false);
}

class GardenAvailabilitySummary extends StatelessWidget {
  final Map<dynamic, dynamic>? schedule;

  /// Mes que muestra el calendario ("Octubre") y sus conteos.
  final String monthLabel;
  final int available;
  final int blocked;
  final int booked;

  const GardenAvailabilitySummary({
    super.key,
    required this.schedule,
    required this.monthLabel,
    required this.available,
    required this.blocked,
    required this.booked,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final sum = availabilitySummary(schedule);
    final ink = sum.off ? (isDark ? const Color(0xFFFFC24D) : const Color(0xFFB87800)) : (isDark ? const Color(0xFF4FD18A) : GardenColors.forest);
    Widget stat(String n, String label, Color c) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n, style: TextStyle(color: c, fontSize: 20, fontWeight: FontWeight.w900)),
            Text(label, style: TextStyle(color: sub, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ink.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GardenIcon(sum.off ? GIcon.advertencia : GIcon.disponibilidad, size: GIconSize.md, state: GIconState.active, color: ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sum.headline, style: TextStyle(color: text, fontSize: 15.5, fontWeight: FontWeight.w800, height: 1.3)),
              if (sum.hours != null) ...[
                const SizedBox(height: 3),
                Text(sum.hours!, style: TextStyle(color: sub, fontSize: 12.5, height: 1.35)),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Divider(height: 1, color: ink.withValues(alpha: 0.18)),
        const SizedBox(height: 12),
        Text(monthLabel.toUpperCase(), style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        Row(children: [
          stat('$available', 'disponibles', GardenColors.success),
          stat('$blocked', 'bloqueados', GardenColors.error),
          stat('$booked', 'reservados', GardenColors.primary),
        ]),
      ]),
    );
  }
}

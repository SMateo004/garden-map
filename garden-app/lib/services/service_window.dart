/// Ventana previa al inicio de un servicio: el cuidador no puede avisar "voy en camino" ni
/// "ya llegué" mucho antes de la hora (no tendría sentido llegar antes de tiempo). El servidor
/// es quien decide y manda la hora exacta en la reserva (`enRouteOpensAt`, `arrivalOpensAt`);
/// la app solo la muestra y deshabilita el botón hasta entonces.
class ServiceWindow {
  ServiceWindow._();

  /// Hora local a partir de la que se habilita el aviso, o null si no hay restricción.
  static DateTime? opensAt(Map<String, dynamic>? booking, String key) {
    final raw = booking?[key] as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  /// Mensaje listo para mostrar mientras el aviso aún no se puede hacer, o null si ya se puede.
  /// [action]: lo que el cuidador va a hacer, ej. "avisar que vas en camino".
  static String? blockReason(Map<String, dynamic>? booking, String key, String action, {DateTime? now}) {
    final at = opensAt(booking, key);
    final current = now ?? DateTime.now();
    if (at == null || !current.isBefore(at)) return null;
    final sameDay = at.year == current.year && at.month == current.month && at.day == current.day;
    final dd = at.day.toString().padLeft(2, '0');
    final mm = at.month.toString().padLeft(2, '0');
    // Hospedaje no tiene hora: abre al empezar el día, así que no se muestra "00:00".
    final dayOnly = at.hour == 0 && at.minute == 0;
    final hhmm = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final when = dayOnly ? 'el $dd/$mm' : (sameDay ? 'desde las $hhmm' : 'el $dd/$mm desde las $hhmm');
    return 'Podrás $action $when.';
  }

  /// Próxima hora (futura) en que se habilita alguno de los avisos, para refrescar la pantalla.
  static DateTime? nextOpening(Map<String, dynamic>? booking, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final times = <DateTime>[
      for (final k in const ['enRouteOpensAt', 'arrivalOpensAt'])
        if (opensAt(booking, k) case final t? when t.isAfter(current)) t,
    ]..sort();
    return times.isEmpty ? null : times.first;
  }
}

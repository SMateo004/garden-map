import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/services/service_window.dart';

void main() {
  // El servidor manda la hora en ISO (UTC); la app la muestra en hora local.
  Map<String, dynamic> booking(DateTime opens) => {'enRouteOpensAt': opens.toUtc().toIso8601String()};

  group('ServiceWindow', () {
    test('antes de la hora: bloquea y dice desde cuándo (mismo día)', () {
      final now = DateTime(2026, 10, 12, 7, 0);
      final reason = ServiceWindow.blockReason(
          booking(DateTime(2026, 10, 12, 8, 30)), 'enRouteOpensAt', 'avisar que vas en camino', now: now);
      expect(reason, 'Podrás avisar que vas en camino desde las 08:30.');
    });

    test('otro día: incluye la fecha', () {
      final now = DateTime(2026, 10, 11, 20, 0);
      final reason = ServiceWindow.blockReason(
          booking(DateTime(2026, 10, 12, 8, 30)), 'enRouteOpensAt', 'avisar que vas en camino', now: now);
      expect(reason, 'Podrás avisar que vas en camino el 12/10 desde las 08:30.');
    });

    test('hospedaje (abre a medianoche): solo el día, sin "00:00"', () {
      final now = DateTime(2026, 10, 11, 20, 0);
      final reason = ServiceWindow.blockReason(
          booking(DateTime(2026, 10, 12)), 'enRouteOpensAt', 'avisar que vas en camino', now: now);
      expect(reason, 'Podrás avisar que vas en camino el 12/10.');
    });

    test('desde la hora de apertura ya no bloquea', () {
      final b = booking(DateTime(2026, 10, 12, 8, 30));
      expect(ServiceWindow.blockReason(b, 'enRouteOpensAt', 'x', now: DateTime(2026, 10, 12, 8, 30)), isNull);
      expect(ServiceWindow.blockReason(b, 'enRouteOpensAt', 'x', now: DateTime(2026, 10, 12, 10, 0)), isNull);
    });

    test('sin dato del servidor no restringe', () {
      expect(ServiceWindow.blockReason({}, 'enRouteOpensAt', 'x'), isNull);
      expect(ServiceWindow.blockReason(null, 'enRouteOpensAt', 'x'), isNull);
    });

    test('nextOpening devuelve la próxima apertura futura', () {
      final now = DateTime(2026, 10, 12, 7, 0);
      final b = {
        'enRouteOpensAt': DateTime(2026, 10, 12, 8, 30).toUtc().toIso8601String(),
        'arrivalOpensAt': DateTime(2026, 10, 12, 9, 0).toUtc().toIso8601String(),
      };
      expect(ServiceWindow.nextOpening(b, now: now), DateTime(2026, 10, 12, 8, 30));
      expect(ServiceWindow.nextOpening(b, now: DateTime(2026, 10, 12, 8, 45)), DateTime(2026, 10, 12, 9, 0));
      expect(ServiceWindow.nextOpening(b, now: DateTime(2026, 10, 12, 9, 30)), isNull);
    });
  });
}

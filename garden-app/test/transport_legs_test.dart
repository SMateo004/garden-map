import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/screens/service/transport_leg_card.dart';

void main() {
  Map<String, dynamic> booking(List<Map<String, dynamic>> legs) => {
        'transport': {'amount': 25, 'legs': legs},
      };

  test('sin transporte no hay viajes', () {
    expect(TransportLegs.all(null), isEmpty);
    expect(TransportLegs.all({'transport': null}), isEmpty);
    expect(TransportLegs.all({'transport': {'legs': 'x'}}), isEmpty);
    expect(TransportLegs.pending({}, 'PICKUP'), isNull);
  });

  test('un viaje cancelado no cuenta como pendiente ni vigente', () {
    final b = booking([
      {'kind': 'PICKUP', 'status': 'CANCELLED'},
      {'kind': 'DROPOFF', 'status': 'SCHEDULED'},
    ]);
    expect(TransportLegs.of(b, 'PICKUP'), isNull);
    expect(TransportLegs.pending(b, 'PICKUP'), isNull);
    expect(TransportLegs.pending(b, 'DROPOFF')?['status'], 'SCHEDULED');
  });

  test('pendiente = programado, en camino o llegó; hecho ya no', () {
    for (final s in ['SCHEDULED', 'EN_ROUTE', 'ARRIVED']) {
      expect(TransportLegs.pending(booking([{'kind': 'PICKUP', 'status': s}]), 'PICKUP'), isNotNull, reason: s);
    }
    final done = booking([{'kind': 'PICKUP', 'status': 'DONE'}]);
    expect(TransportLegs.pending(done, 'PICKUP'), isNull);
    expect(TransportLegs.of(done, 'PICKUP'), isNotNull);
  });

  test('viaje en vivo y precios', () {
    final b = booking([
      {'kind': 'PICKUP', 'status': 'DONE', 'live': false},
      {'kind': 'DROPOFF', 'status': 'EN_ROUTE', 'live': true},
    ]);
    expect(TransportLegs.live(b)?['kind'], 'DROPOFF');
    expect(TransportLegs.feeLabel(0), 'Gratis');
    expect(TransportLegs.feeLabel(null), 'Gratis');
    expect(TransportLegs.feeLabel(15), 'Bs 15');
    expect(TransportLegs.feeLabel(12.5), 'Bs 12.50');
  });

  test('hora del viaje: hoy / mañana', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 30);
    expect(TransportLegs.whenLabel({'scheduledAt': today.toUtc().toIso8601String()}), 'hoy 23:30');
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9, 0);
    expect(TransportLegs.whenLabel({'scheduledAt': tomorrow.toUtc().toIso8601String()}), 'mañana 09:00');
    expect(TransportLegs.whenLabel({'time': '18:00'}), '18:00');
  });
}

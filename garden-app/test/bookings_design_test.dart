import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_bookings.dart';

void main() {
  final now = DateTime(2026, 10, 5, 10);

  test('Mis reservas: en curso, próximas (la más cercana primero) y pasadas por mes', () {
    final groups = groupBookings([
      {'id': 'pasada-sep', 'status': 'COMPLETED', 'walkDate': '2026-09-15'},
      {'id': 'lejos', 'status': 'CONFIRMED', 'walkDate': '2026-10-20'},
      {'id': 'ahora', 'status': 'IN_PROGRESS', 'walkDate': '2026-10-05'},
      {'id': 'cerca', 'status': 'WAITING_CAREGIVER_APPROVAL', 'walkDate': '2026-10-06'},
      {'id': 'pasada-oct', 'status': 'CANCELLED', 'walkDate': '2026-10-01'},
      {'id': 'pasada-ago-2025', 'status': 'COMPLETED', 'startDate': '2025-08-02'},
    ], now: now);

    expect(groups.map((g) => g.title).toList(), ['En curso', 'Próximas', 'Octubre', 'Septiembre', 'Agosto 2025']);
    expect(groups.first.emphasis, isTrue);
    expect(groups[1].bookings.map((b) => b['id']).toList(), ['cerca', 'lejos']);
    expect(groups[2].bookings.single['id'], 'pasada-oct');
  });

  test('cuidador: las solicitudes por responder van aparte y primero', () {
    final groups = groupBookings([
      {'id': 'conf', 'status': 'CONFIRMED', 'walkDate': '2026-10-07'},
      {'id': 'pedido', 'status': 'WAITING_CAREGIVER_APPROVAL', 'walkDate': '2026-10-09'},
      {'id': 'ahora', 'status': 'IN_PROGRESS', 'walkDate': '2026-10-05'},
    ], now: now, caregiverView: true);
    expect(groups.map((g) => g.title).toList(), ['Por responder', 'En curso', 'Próximas']);
    expect(groups.first.bookings.single['id'], 'pedido');
    expect(groups.last.bookings.single['id'], 'conf');
  });

  test('línea de servicio corta', () {
    expect(bookingServiceLine({'serviceType': 'PASEO', 'duration': 60}), 'Paseo · 60 min');
    expect(bookingServiceLine({'serviceType': 'GUARDERIA', 'duration': 240}), 'Guardería · 4 h');
    expect(bookingServiceLine({'serviceType': 'GUARDERIA', 'duration': 90}), 'Guardería · 1 h 30 min');
    expect(bookingServiceLine({'serviceType': 'HOSPEDAJE', 'totalDays': 1}), 'Hospedaje · 1 noche');
    expect(bookingServiceLine({'serviceType': 'HOSPEDAJE'}), 'Hospedaje');
  });
}

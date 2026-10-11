import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_booking_carousel.dart';
import 'package:garden_app/narrative/booking_story.dart';
import 'package:garden_app/theme/garden_theme.dart';

void main() {
  final now = DateTime(2026, 10, 11, 9);
  String day(int add) => DateTime(2026, 10, 11 + add).toIso8601String().substring(0, 10);
  Map<String, dynamic> b(String id, String status, {int inDays = 1}) => {
        'id': id,
        'status': status,
        'serviceType': 'PASEO',
        'petName': 'Toby',
        'caregiverName': 'Andrea Rojas',
        'walkDate': day(inDays),
        'startTime': '10:00',
      };

  test('pickHeroBookings: en curso primero y el resto en orden de prioridad', () {
    final list = pickHeroBookings([
      b('c1', 'CONFIRMED'),
      b('w1', 'WAITING_CAREGIVER_APPROVAL'),
      b('p1', 'IN_PROGRESS', inDays: 0),
      b('x1', 'CANCELLED'),
    ], now: now);
    expect(list.map((e) => e['id']), ['p1', 'c1', 'w1']);
    expect(pickHeroBooking([b('c1', 'CONFIRMED'), b('p1', 'IN_PROGRESS')], now: now)?['id'], 'p1');
  });

  Widget host(List<Map<String, dynamic>> items, {bool reduced = false}) => MaterialApp(
        theme: gardenTheme(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Scaffold(
            body: GardenBookingCarousel(
              bookings: items,
              interval: const Duration(seconds: 2),
              itemBuilder: (_, x) => GardenBookingMiniCard(booking: x),
            ),
          ),
        ),
      );

  testWidgets('una sola reserva: la tarjeta, sin carrusel', (t) async {
    await t.pumpWidget(host([b('c1', 'CONFIRMED')]));
    expect(find.byType(GardenBookingMiniCard), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('varias: se ve una y pasa sola a la siguiente', (t) async {
    await t.pumpWidget(host([b('c1', 'CONFIRMED'), b('w1', 'WAITING_CAREGIVER_APPROVAL', inDays: 3)]));
    expect(find.bySemanticsLabel('Reserva 1 de 2'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Reserva 2 de 2'), findsOneWidget);
  });

  testWidgets('con "reducir movimiento" no se mueve sola', (t) async {
    await t.pumpWidget(host([b('c1', 'CONFIRMED'), b('w1', 'WAITING_CAREGIVER_APPROVAL')], reduced: true));
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Reserva 1 de 2'), findsOneWidget);
  });
}

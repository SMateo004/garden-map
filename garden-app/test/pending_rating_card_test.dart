import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_ratings.dart';
import 'package:garden_app/design/garden_service.dart';

/// Ficha temporal del inicio del marketplace: "¿Cómo te fue con …?" + plazo + Calificar.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 380, child: child))));

  testWidgets('muestra cuidador, mascota, plazo y califica', (tester) async {
    var rated = 0;
    final deadline = DateTime.now().add(const Duration(hours: 5));
    await tester.pumpWidget(host(GardenPendingRatingCard(
      caregiverName: 'Andrea',
      petName: 'Toby',
      service: GardenService.paseo,
      deadline: deadline,
      onRate: () => rated++,
    )));
    expect(find.text('¿Cómo te fue con Andrea?'), findsOneWidget);
    expect(find.textContaining('de Toby'), findsOneWidget);
    expect(find.text('Puedes calificar hasta ${gardenDeadlineLabel(deadline)}'), findsOneWidget);
    // Sin onDismiss (Mis calificaciones) no hay X.
    expect(find.byTooltip('Ahora no'), findsNothing);
    await tester.tap(find.text('Calificar'));
    expect(rated, 1);
  });

  testWidgets('con onDismiss se puede ocultar ("ahora no")', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(host(GardenPendingRatingCard(
      caregiverName: 'Andrea',
      onRate: () {},
      onDismiss: () => dismissed = true,
    )));
    await tester.tap(find.byTooltip('Ahora no'));
    expect(dismissed, isTrue);
  });

  testWidgets('versión compacta del inicio: una fila, plazo corto y toda la ficha abre la encuesta', (tester) async {
    var rated = 0;
    var dismissed = false;
    final deadline = DateTime.now().add(const Duration(hours: 5));
    await tester.pumpWidget(host(GardenPendingRatingCard(
      caregiverName: 'Andrea',
      petName: 'Toby',
      service: GardenService.paseo,
      deadline: deadline,
      compact: true,
      onRate: () => rated++,
      onDismiss: () => dismissed = true,
    )));
    expect(find.text('¿Cómo te fue con Andrea?'), findsOneWidget);
    expect(find.text('Hasta ${gardenDeadlineLabel(deadline)}'), findsOneWidget);
    expect(find.textContaining('de Toby'), findsNothing);
    expect(tester.getSize(find.byType(GardenPendingRatingCard)).height, lessThan(64));
    await tester.tap(find.text('Calificar'));
    await tester.tap(find.text('¿Cómo te fue con Andrea?'));
    expect(rated, 2);
    await tester.tap(find.byTooltip('Ahora no'));
    expect(dismissed, isTrue);
    expect(rated, 2);
  });

  test('plazo en palabras: hoy / mañana / fecha', () {
    final now = DateTime(2026, 10, 12, 10);
    expect(gardenDeadlineLabel(DateTime(2026, 10, 12, 18, 5), now: now), 'hoy a las 18:05');
    expect(gardenDeadlineLabel(DateTime(2026, 10, 13, 9, 30), now: now), 'mañana a las 09:30');
    expect(gardenDeadlineLabel(DateTime(2026, 10, 15, 8), now: now), 'el 15 oct a las 08:00');
  });
}

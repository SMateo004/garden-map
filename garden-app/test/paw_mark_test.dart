import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_paw_mark.dart';

/// Ángulo de giro (eje vertical) del Transform de la huella.
double _turn(WidgetTester tester) {
  final t = tester.widget<Transform>(
    find.descendant(of: find.byType(GardenPawMark), matching: find.byType(Transform)).last,
  );
  return math.atan2(-t.transform.entry(2, 0), t.transform.entry(0, 0));
}

double _bottom(WidgetTester tester) => tester.getBottomLeft(find.byType(Image)).dy;

void main() {
  testWidgets('flota apenas y al tocarla da una vuelta completa', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: GardenPawMark(size: 100))));
    final low = _bottom(tester);
    await tester.pump(const Duration(milliseconds: 1500)); // mitad del ciclo: arriba
    final high = _bottom(tester);
    expect(low - high, inInclusiveRange(2, 4), reason: 'sube ~3 % de su tamaño, poco');

    expect(_turn(tester), closeTo(0, 0.01));
    await tester.tap(find.byType(GardenPawMark));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450)); // a mitad de la vuelta
    expect(_turn(tester).abs(), closeTo(math.pi, 0.2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_turn(tester), closeTo(0, 0.01), reason: 'termina de frente');
  });

  testWidgets('con reducir movimiento queda quieta y no gira', (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: Center(child: GardenPawMark(size: 100))),
    ));
    final y = _bottom(tester);
    await tester.tap(find.byType(GardenPawMark));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(_bottom(tester), y);
    expect(_turn(tester), closeTo(0, 0.01));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/theme/garden_theme.dart';

void main() {
  // "Anterior" en el registro de cuidador se partía en dos renglones ("Anterio" / "r") en el botón angosto.
  for (final scale in [1.0, 1.3, 1.6, 2.0]) {
    testWidgets('el botón angosto mantiene "Anterior" en un solo renglón (letra x$scale)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 110,
                child: GardenButton(label: 'Anterior', outline: true, height: 48, onPressed: () {}),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final text = tester.widget<Text>(find.text('Anterior'));
      expect(text.maxLines, 1);
      expect(text.softWrap, false);
      // Una sola línea: el texto no es más alto que dos renglones de su tamaño.
      expect(tester.getSize(find.text('Anterior')).height, lessThan(15 * scale * 1.9));
      expect(tester.takeException(), isNull);
    });
  }
}

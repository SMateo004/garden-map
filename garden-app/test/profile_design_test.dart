import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_icons.dart';
import 'package:garden_app/design/garden_profile.dart';
import 'package:garden_app/theme/garden_theme.dart';

void main() {
  setUpAll(() => GardenText.useGoogleFonts = false);
  Widget wrap(Widget c) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: c)));

  testWidgets('el avance dice cuánto y qué falta', (tester) async {
    await tester.pumpWidget(wrap(const GardenProfileCompletion(
      avatar: SizedBox(width: 40, height: 40),
      name: 'Sofía Rojas',
      done: 12,
      total: 15,
      missing: ['Ciudad', 'Zona', 'Calle', 'Referencia de la dirección'],
    )));
    await tester.pumpAndSettle();
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('Te falta: Ciudad, Zona, Calle y 1 más.'), findsOneWidget);

    await tester.pumpWidget(wrap(const GardenProfileCompletion(
        avatar: SizedBox(width: 40, height: 40), name: 'Sofía', done: 15, total: 15)));
    await tester.pumpAndSettle();
    expect(find.text('Completo'), findsOneWidget);
  });

  testWidgets('cada sección dice si está completa', (tester) async {
    await tester.pumpWidget(wrap(const Column(children: [
      GardenFormSection(icon: GIcon.perfil, title: 'Contacto', missing: 0, children: []),
      GardenFormSection(icon: GIcon.perfil, title: 'Dirección', missing: 2, children: []),
    ])));
    expect(find.text('Completo'), findsOneWidget);
    expect(find.text('Falta 2'), findsOneWidget);
  });
}

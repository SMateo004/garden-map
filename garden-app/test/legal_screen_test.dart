import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/screens/legal/legal_screen.dart';
import 'package:garden_app/theme/garden_theme.dart';

void main() {
  testWidgets('el índice salta a la sección 30 y el buscador filtra', (t) async {
    t.view.physicalSize = const Size(390, 760);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(MaterialApp(theme: gardenTheme(), home: const TermsOfServiceScreen()));
    await t.pumpAndSettle();
    const title30 = '30. Naturaleza voluntaria e independiente del Cuidador — sin relación laboral';
    await t.tap(find.text('Contenido'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text(title30).first);
    await t.pumpAndSettle();
    await t.tap(find.text(title30).first);
    await t.pumpAndSettle();
    final y = t.getTopLeft(find.text(title30)).dy;
    expect(y, inInclusiveRange(0, 200));

    await t.enterText(find.byType(TextField), 'aguinaldo');
    await t.pumpAndSettle();
    expect(find.textContaining('1 sección menciona'), findsOneWidget);
  });
}

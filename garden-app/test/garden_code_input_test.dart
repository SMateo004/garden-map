import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_code_input.dart';
import 'package:garden_app/theme/garden_theme.dart';

void main() {
  Future<(TextEditingController, List<String>)> pump(WidgetTester t) async {
    final ctrl = TextEditingController();
    final done = <String>[];
    await t.pumpWidget(MaterialApp(
      theme: gardenTheme(),
      home: Scaffold(body: Center(child: SizedBox(width: 340, child: GardenCodeInput(controller: ctrl, onCompleted: done.add)))),
    ));
    return (ctrl, done);
  }

  testWidgets('pegar el código entero lo reparte en los cuadros y envía una vez', (t) async {
    final (ctrl, done) = await pump(t);
    await t.enterText(find.byType(TextField), '482913');
    await t.pump();
    for (final d in '482913'.split('')) {
      expect(find.text(d), findsWidgets);
    }
    expect(done, ['482913']);
    // Un rebuild con el mismo código no lo vuelve a enviar.
    ctrl.text = '482913';
    await t.pump();
    expect(done, ['482913']);
  });

  testWidgets('solo acepta dígitos y como máximo 6', (t) async {
    final (ctrl, done) = await pump(t);
    await t.enterText(find.byType(TextField), '12a3-45678');
    await t.pump();
    expect(ctrl.text, '123456');
    expect(done, ['123456']);
  });

  testWidgets('después de borrar, el mismo código se puede volver a enviar', (t) async {
    final (ctrl, done) = await pump(t);
    await t.enterText(find.byType(TextField), '111111');
    await t.pump();
    ctrl.clear();
    await t.pump();
    await t.enterText(find.byType(TextField), '111111');
    await t.pump();
    expect(done, ['111111', '111111']);
  });
}

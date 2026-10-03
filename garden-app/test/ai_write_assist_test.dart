import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/widgets/ai_write_assist.dart';

Widget _host(TextEditingController c) => MaterialApp(
      home: Scaffold(body: AiWriteAssist(controller: c, field: 'bio')),
    );

void main() {
  testWidgets('sin texto ofrece redactar; con texto ofrece mejorar', (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(_host(c));
    expect(find.text('Redactar con IA'), findsOneWidget);

    c.text = 'Soy paseador con experiencia en perros grandes';
    await tester.pump();
    expect(find.text('Mejorar con IA'), findsOneWidget);
  });

  testWidgets('sin texto, al tocar pide unas notas antes de llamar a la IA', (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(_host(c));
    await tester.tap(find.text('Redactar con IA'));
    await tester.pumpAndSettle();
    expect(find.text('Cuéntame en pocas palabras'), findsOneWidget);

    // Cancelar no cambia el texto ni deja el botón cargando.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(c.text, isEmpty);
    expect(find.text('Redactar con IA'), findsOneWidget);
  });
}

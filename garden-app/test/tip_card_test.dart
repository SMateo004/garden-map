import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/theme/garden_theme.dart';
import 'package:garden_app/widgets/tip_card.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  setUpAll(() => GardenText.useGoogleFonts = false);

  test('parte de la propina que queda como deuda', () {
    expect(tipDebtPart(20, 50), 0);
    expect(tipDebtPart(20, 5), 15);
    expect(tipDebtPart(20, 0), 20);
    expect(tipDebtPart(20, -10), 20, reason: 'con saldo negativo, todo es deuda');
    expect(tipDebtPart(20, null), isNull);
    expect(tipBs(15), 'Bs 15');
    expect(tipBs(12.5), 'Bs 12,50');
  });

  testWidgets('arranca en Bs 0, se ajusta con − / + y avisa la deuda', (tester) async {
    final client = MockClient((req) async => http.Response(
        jsonEncode({'success': true, 'data': {'availableBalance': 5}}), 200,
        headers: {'content-type': 'application/json'}));
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const GardenTipCard(
        bookingId: 'b1', baseUrl: 'https://x/api', token: 't', caregiverFirstName: 'Andrea',
      )));
      await tester.pumpAndSettle();
    }, () => client);

    expect(find.text('Un extra para Andrea'), findsOneWidget);
    expect(find.text('Bs 0'), findsOneWidget);
    expect(find.text('Propina · 100 % para tu cuidador, una sola vez'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Más'));
    await tester.tap(find.bySemanticsLabel('Más'));
    await tester.pump();
    expect(find.text('Bs 10'), findsOneWidget);
    expect(find.bySemanticsLabel('Dar Bs 10 de propina'), findsOneWidget);
    expect(find.text('Bs 5 se cobran en tu próxima reserva'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Menos'));
    await tester.pump();
    expect(find.text('Bs 5'), findsOneWidget);
    expect(find.textContaining('se cobran en tu próxima reserva'), findsNothing);
  });

  testWidgets('si ya dio propina, solo lo muestra', (tester) async {
    await tester.pumpWidget(_app(const GardenTipCard(
      bookingId: 'b1', baseUrl: 'https://x/api', token: 't', caregiverFirstName: 'Andrea', tipAmount: 15,
    )));
    expect(find.textContaining('Le diste Bs 15 de propina a Andrea', findRichText: true), findsOneWidget);
    expect(find.bySemanticsLabel('Más'), findsNothing);
  });
}

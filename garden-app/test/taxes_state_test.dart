// Impuestos en pausa en la app: TaxesState (textos), Términos y el interruptor del admin.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:garden_app/screens/admin/admin_taxes_switch_card.dart';
import 'package:garden_app/services/taxes_state.dart';

void main() {
  tearDown(() => TaxesState.active.value = false);

  group('TaxesState', () {
    test('arranca apagado: ante la duda no se mencionan impuestos', () {
      expect(TaxesState.active.value, isFalse);
    });

    test('solo taxesActive == true los activa', () {
      TaxesState.applySettings({'taxesActive': true});
      expect(TaxesState.active.value, isTrue);
      for (final data in <Map<String, dynamic>?>[
        {'taxesActive': false},
        {'taxesActive': 'true'},
        {},
        null,
      ]) {
        TaxesState.applySettings(data);
        expect(TaxesState.active.value, isFalse, reason: '$data');
      }
    });
  });

  group('Términos (legal_screen.dart)', () {
    final source = File('lib/screens/legal/legal_screen.dart').readAsStringSync();
    final section6 = () {
      final start = source.indexOf("'6. Comisiones, precios y estructura de pagos'");
      final end = source.indexOf("'7.", start);
      return source.substring(start, end);
    }();

    test('cada frase con impuestos existe en el texto (si se edita, esta prueba avisa)', () {
      for (final (from, _) in TaxesState.termsReplacements) {
        expect(section6.contains(from), isTrue, reason: from);
      }
    });

    test('en pausa la sección 6 no habla de impuestos, IVA, IT ni del 16 %', () {
      final paused = TaxesState.withoutTaxMentions(section6);
      expect(RegExp(r'impuesto|\bIVA\b|\bIT\b|16 ?%|Bs\. 128|Bs\. 18\b', caseSensitive: false).hasMatch(paused), isFalse);
      expect(paused.contains('Bs. 110'), isTrue);
    });

    test('activos: el texto queda intacto', () {
      TaxesState.active.value = true;
      expect(TaxesState.terms(section6), section6);
      TaxesState.active.value = false;
      expect(TaxesState.terms(section6), isNot(section6));
    });
  });

  group('AdminTaxesSwitchCard', () {
    Future<void> pump(WidgetTester tester, Map<String, dynamic> taxes, {List<http.Request>? puts}) async {
      final client = MockClient((req) async {
        if (req.method == 'PUT') {
          puts?.add(req);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'taxes': {...taxes, 'enabled': false, 'active': false},
                'unpaidBookingsAdjusted': {'bookings': 2, 'totalRemoved': 36},
              },
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'success': true, 'data': {'taxes': taxes}}), 200);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: AdminTaxesSwitchCard(adminToken: 't'))),
        ));
        await tester.pumpAndSettle();
      }, () => client);
    }

    testWidgets('en pausa: lo dice y el interruptor siempre se puede aprobar (no depende de nada más)', (tester) async {
      await pump(tester, {
        'enabled': false,
        'active': false,
        'configuredRatePct': 16,
        'effectiveRatePct': 0,
      });
      expect(find.text('En pausa — pendiente de tu aprobación'), findsOneWidget);
      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.value, isFalse);
      expect(sw.onChanged, isNotNull);
    });

    testWidgets('activos: muestra la tasa y pausar pide confirmación antes de llamar al servidor', (tester) async {
      final puts = <http.Request>[];
      final client = MockClient((req) async {
        if (req.method == 'PUT') {
          puts.add(req);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'taxes': {'enabled': false, 'active': false, 'configuredRatePct': 16},
                'unpaidBookingsAdjusted': {'bookings': 2, 'totalRemoved': 36},
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'taxes': {'enabled': true, 'active': true, 'configuredRatePct': 16},
            },
          }),
          200,
        );
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: AdminTaxesSwitchCard(adminToken: 't'))),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Activos — se cobra 16 % (IVA + IT)'), findsOneWidget);

        // Rechazar: no se llama al servidor.
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rechazar'));
        await tester.pumpAndSettle();
        expect(puts, isEmpty);

        // Aprobar la pausa: PUT con confirm:true y el estado global queda apagado.
        TaxesState.active.value = true;
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pausar'));
        await tester.pumpAndSettle();
      }, () => client);
      expect(puts, hasLength(1));
      expect(jsonDecode(puts.single.body), {'enabled': false, 'confirm': true});
      expect(TaxesState.active.value, isFalse);
      expect(find.text('En pausa — pendiente de tu aprobación'), findsOneWidget);
    });
  });
}

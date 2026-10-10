// Funciones de negocio que solo el admin habilita: lectura en la app y tarjeta del admin.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:garden_app/screens/admin/admin_business_features_card.dart';
import 'package:garden_app/services/business_features.dart';

void main() {
  group('BusinessFeatures.has', () {
    test('solo true literal dentro de businessFeatures', () {
      expect(BusinessFeatures.has({'businessFeatures': {'RECEPTION': true}}, BusinessFeatures.reception), isTrue);
      for (final src in <Map?>[
        null,
        {},
        {'isCompany': true},
        {'businessFeatures': {'RECEPTION': 'true'}},
        {'businessFeatures': {'STAFF_TEAM': true}},
        {'businessFeatures': ['RECEPTION']},
      ]) {
        expect(BusinessFeatures.has(src, BusinessFeatures.reception), isFalse, reason: '$src');
      }
    });
  });

  group('AdminBusinessFeaturesCard', () {
    Map<String, dynamic> view(bool reception) => {
          'kind': 'COMPANY',
          'features': [
            {'key': 'RECEPTION', 'label': 'Recepción', 'description': 'd', 'requires': null, 'enabled': reception, 'effective': reception},
            {'key': 'STAFF_TEAM', 'label': 'Equipo', 'description': 'd', 'requires': null, 'enabled': false, 'effective': false},
            {'key': 'STAFF_CLIENT_CHAT', 'label': 'Equipo: chat con clientes', 'description': 'd', 'requires': 'STAFF_TEAM', 'enabled': true, 'effective': false},
          ],
        };

    Widget card() => const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminBusinessFeaturesCard(caregiverProfileId: 'p1', adminToken: 't', baseUrl: 'https://x/api'),
            ),
          ),
        );

    testWidgets('cuidador individual: no aplica ninguna, no se muestra nada', (tester) async {
      final client = MockClient((_) async => http.Response(jsonEncode({'success': true, 'data': {'kind': 'INDIVIDUAL', 'features': []}}), 200));
      await http.runWithClient(() async {
        await tester.pumpWidget(card());
        await tester.pumpAndSettle();
      }, () => client);
      expect(find.text('Funciones del negocio'), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('habilitar pide confirmación y manda solo esa función', (tester) async {
      final puts = <http.Request>[];
      final client = MockClient((req) async {
        if (req.method == 'PUT') {
          puts.add(req);
          return http.Response(jsonEncode({'success': true, 'data': view(true)}), 200);
        }
        expect(req.url.toString(), 'https://x/api/admin/caregivers/p1/features');
        return http.Response(jsonEncode({'success': true, 'data': view(false)}), 200);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(card());
        await tester.pumpAndSettle();
        expect(find.byType(Switch), findsNWidgets(3));
        expect(find.text('Sin efecto hasta habilitar "Equipo".'), findsOneWidget);

        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(puts, isEmpty);

        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Habilitar'));
        await tester.pumpAndSettle();
      }, () => client);
      expect(puts, hasLength(1));
      expect(jsonDecode(puts.single.body), {'features': {'RECEPTION': true}});
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    });
  });
}

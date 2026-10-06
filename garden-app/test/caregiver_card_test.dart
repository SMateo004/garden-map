import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_caregiver_card.dart';
import 'package:garden_app/design/garden_service.dart';
import 'package:garden_app/theme/garden_theme.dart';

void main() {
  setUpAll(() => GardenText.useGoogleFonts = false);

  test('precio por servicio: solo lo que ofrece, con su unidad', () {
    final c = {
      'services': ['PASEO', 'HOSPEDAJE'],
      'pricePerWalk60': 35, 'pricePerDay': 150,
      'pricePerGuarderia': 90, // guardado pero no ofrecido: no se muestra
    };
    final p = caregiverPrices(c);
    expect(p.map((e) => (e.service, e.amount, e.unit)).toList(), [
      (GardenService.paseo, 35, '1 h'),
      (GardenService.hospedaje, 150, 'noche'),
    ]);
    expect(caregiverPrices({...c, 'pricePerWalk30': 20}).first.unit, '30 min');
    expect(caregiverPrices(c, only: 'hospedaje').single.service, GardenService.hospedaje);
    expect(caregiverPrices(c, only: 'guarderia'), isEmpty);
  });

  test('zona legible aunque no hayan cargado los nombres', () {
    expect(humanZone('LAS_PALMAS'), 'Las Palmas');
    expect(humanZone('EQUIPETROL'), 'Equipetrol');
  });

  testWidgets('cuidador nuevo y sellos de confianza', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GardenCaregiverCard(
          caregiver: const {
            'id': 'x', 'firstName': 'Diego', 'lastName': 'Suárez', 'verified': true, 'antecedentesVerified': true,
            'reviewCount': 0, 'zone': 'NORTE', 'services': ['PASEO'], 'pricePerWalk30': 20,
          },
          onTap: () {},
        ),
      ),
    ));
    expect(find.text('Nuevo en GARDEN'), findsOneWidget);
    expect(find.text('Identidad verificada'), findsOneWidget);
    expect(find.text('Antecedentes revisados'), findsOneWidget);
    expect(find.text('Norte'), findsOneWidget);
  });

  testWidgets('cifras del perfil en recuadros', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GardenStatTiles(tiles: [('4,9', '3 reseñas'), ('41', 'servicios'), ('mar 2026', 'en GARDEN')], highlightFirst: true)),
    ));
    expect(find.text('4,9'), findsOneWidget);
    expect(find.text('mar 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

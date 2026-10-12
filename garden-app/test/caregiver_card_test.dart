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
    // La tarjeta compacta junta datos y sellos en un renglón cada uno.
    Finder has(String t) => find.textContaining(t, findRichText: true);
    expect(has('Nuevo en GARDEN'), findsOneWidget);
    expect(has('ID verificada'), findsOneWidget);
    expect(has('Antecedentes revisados'), findsOneWidget);
    expect(has('Norte'), findsOneWidget);
  });

  testWidgets('precios en una sola fila que se desliza, aunque no entren', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GardenCaregiverCard(
          caregiver: const {
            'id': 'y', 'firstName': 'Patitas', 'lastName': 'SRL', 'verified': true, 'reviewCount': 58, 'rating': 4.8,
            'services': ['PASEO', 'GUARDERIA', 'HOSPEDAJE'], 'pricePerWalk60': 40, 'pricePerGuarderia': 100, 'pricePerDay': 180,
          },
          onTap: () => taps++,
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    final ys = {for (final t in ['Bs 40', 'Bs 100']) tester.getTopLeft(find.text(t)).dy};
    expect(ys, hasLength(1), reason: 'los precios no bajan a otro renglón');
    expect(find.byType(ListView), findsOneWidget);
    await tester.tap(find.text('Reservar'));
    expect(taps, 1, reason: 'Reservar abre el perfil, como el resto de la tarjeta');
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

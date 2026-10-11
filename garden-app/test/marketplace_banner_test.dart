import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_caregiver_card.dart';
import 'package:garden_app/design/garden_marketplace_banner.dart';
import 'package:garden_app/theme/garden_theme.dart';

void main() {
  Future<void> narrow(WidgetTester t, Widget child, {double width = 320}) async {
    t.view.physicalSize = Size(width, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: gardenTheme(), home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: Align(alignment: Alignment.topCenter, child: child)))));
  }

  testWidgets('el banner mide 96 px y no se desborda con textos largos', (t) async {
    await narrow(
      t,
      const GardenMarketplaceBanner(
        title: 'Un título larguísimo que el admin escribió sin pensar en el espacio disponible',
        subtitle: 'Y un subtítulo igual de largo que tampoco debería romper nada en un teléfono angosto',
        buttonText: 'Quiero saber más',
      ),
    );
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(GardenMarketplaceBanner)).height, GardenMarketplaceBanner.height);
  });

  testWidgets('la tarjeta de cuidador compacta entra en un teléfono angosto', (t) async {
    await narrow(
      t,
      GardenCaregiverCard(
        onTap: () {},
        caregiver: const {
          'id': 'c1', 'firstName': 'Andrea', 'lastName': 'Rojas Villarroel', 'verified': true, 'antecedentesVerified': true,
          'isCompany': true, 'companyName': 'Patitas Felices SRL', 'reviewCount': 37, 'rating': 4.9, 'experienceYears': 12,
          'zone': 'LAS_PALMAS', 'services': ['PASEO', 'GUARDERIA', 'HOSPEDAJE'],
          'pricePerWalk30': 35, 'pricePerGuarderia': 90, 'pricePerDay': 180,
        },
      ),
    );
    expect(t.takeException(), isNull, reason: 'en 320 px no se desborda');
  });

  testWidgets('en un teléfono normal la tarjeta de cuidador no se desborda', (t) async {
    await narrow(t, width: 375, GardenCaregiverCard(onTap: () {}, caregiver: const {
      'id': 'c2', 'firstName': 'Andrea', 'lastName': 'Rojas', 'verified': true, 'antecedentesVerified': true,
      'reviewCount': 37, 'rating': 4.9, 'experienceYears': 2, 'zone': 'EQUIPETROL',
      'services': ['PASEO', 'GUARDERIA'], 'pricePerWalk30': 35, 'pricePerGuarderia': 90,
    }));
    // La altura real se mira en la vista previa: la fuente de prueba de
    // Flutter dibuja cada letra como un cuadrado y agranda todo.
    expect(t.takeException(), isNull);
  });
}

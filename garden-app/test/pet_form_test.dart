import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/screens/client/pet_form_sheet.dart';
import 'package:garden_app/theme/garden_theme.dart';

void main() {
  setUpAll(() => GardenText.useGoogleFonts = false);

  group('Validaciones de la mascota', () {
    test('nombre: obligatorio, 2 a 40 caracteres y con alguna letra', () {
      expect(PetFormSheet.validateName(''), isNotNull);
      expect(PetFormSheet.validateName('   '), isNotNull);
      expect(PetFormSheet.validateName('L'), isNotNull);
      expect(PetFormSheet.validateName('123'), isNotNull);
      expect(PetFormSheet.validateName('x' * 41), isNotNull);
      expect(PetFormSheet.validateName('Luna'), isNull);
      expect(PetFormSheet.validateName('Ñandú 2'), isNull);
    });

    test('peso: opcional, acepta coma y punto, entre 0,1 y 120 kg', () {
      expect(PetFormSheet.validateWeight(''), isNull);
      expect(PetFormSheet.parseWeight('4,5'), 4.5);
      expect(PetFormSheet.parseWeight('4.5'), 4.5);
      expect(PetFormSheet.validateWeight('4,5'), isNull);
      expect(PetFormSheet.validateWeight('0'), isNotNull);
      expect(PetFormSheet.validateWeight('121'), isNotNull);
      expect(PetFormSheet.validateWeight('4,,5'), isNotNull);
    });

    test('el tamaño sugerido por el peso usa los rangos del cuidador', () {
      expect(PetFormSheet.sizeForWeight(3), 'SMALL');
      expect(PetFormSheet.sizeForWeight(5), 'MEDIUM');
      expect(PetFormSheet.sizeForWeight(19.9), 'MEDIUM');
      expect(PetFormSheet.sizeForWeight(20), 'LARGE');
      expect(PetFormSheet.sizeForWeight(40), 'GIANT');
    });

    test('microchip: opcional, de 9 a 15 números', () {
      expect(PetFormSheet.validateMicrochip(''), isNull);
      expect(PetFormSheet.validateMicrochip('985 112 000 123 456'), isNull);
      expect(PetFormSheet.validateMicrochip('12345'), isNotNull);
      expect(PetFormSheet.validateMicrochip('ABC123456789'), isNotNull);
    });
  });

  group('Flujo por pasos', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(420, 900), disableAnimations: true),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PetFormSheet(token: 't', baseUrl: 'http://localhost', onSaved: () {}),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('no avanza sin nombre ni especie, y con ambos pasa al paso 2', (tester) async {
      await open(tester);
      expect(find.text('Presenta a tu mascota'), findsOneWidget);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('¿Cómo se llama?'), findsWidgets);
      expect(find.text('Elige si es perro o gato'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'Luna');
      await tester.tap(find.text('Perro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(find.text('¿De qué tamaño es Luna?'), findsOneWidget);
      // Sin tamaño no avanza al paso 3.
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Elige un tamaño'), findsOneWidget);
    });

    testWidgets('el peso elige el tamaño solo, y se puede cambiar', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Toby');
      await tester.tap(find.text('Perro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      final weight = find.widgetWithText(TextFormField, 'Ej: 4,5');
      await tester.enterText(weight, '25');
      await tester.pumpAndSettle();
      expect(find.text('Lo elegimos por el peso que escribiste. Puedes cambiarlo.'), findsOneWidget);
      await tester.tap(find.text('Mediano'));
      await tester.pumpAndSettle();
      expect(find.text('Lo elegimos por el peso que escribiste. Puedes cambiarlo.'), findsNothing);
    });
  });
}

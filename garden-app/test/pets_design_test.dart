import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_pets.dart';
import 'package:garden_app/theme/garden_theme.dart';

void main() {
  setUpAll(() => GardenText.useGoogleFonts = false);

  test('la ficha dice qué falta, empezando por lo que impide reservar', () {
    expect(petCompleteness({'name': 'Toby'}).next, 'Elige si es perro o gato y su tamaño');
    final luna = petCompleteness({'animalType': 'DOGS', 'size': 'MEDIUM', 'age': 3, 'weight': 18.5, 'breed': 'Lab', 'vaccinePhotos': ['v']});
    expect((luna.done, luna.total, luna.next), (5, 6, 'Sube una foto'));
    final full = petCompleteness({'animalType': 'CATS', 'size': 'SMALL', 'photoUrl': 'u', 'age': 0, 'weight': 3, 'breed': 'Siamés', 'vaccinePhotos': ['v']});
    expect((full.done, full.next), (6, null));
    expect(petCompleteness({'animalType': 'DOGS', 'size': 'SMALL', 'breed': '  ', 'vaccinePhotos': []}).done, 1);
  });

  test('subtítulo corto', () {
    expect(petSubtitle({'animalType': 'DOGS', 'breed': 'Labrador', 'age': 3}), 'Perro · Labrador · 3 años');
    expect(petSubtitle({'animalType': 'CATS', 'age': 0}), 'Gato · menos de 1 año');
    expect(petSubtitle({}), 'Completa su ficha');
  });

  testWidgets('la ficha avisa si no se puede reservar y ofrece quitarla desde el menú', (tester) async {
    var deleted = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: GardenPetCard(pet: const {'id': 'p', 'name': 'Toby', 'weight': 30}, onTap: () {}, onDelete: () => deleted++))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Falta especie y tamaño: no se puede reservar'), findsOneWidget);
    expect(find.text('30 kg'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitar mascota'));
    await tester.pumpAndSettle();
    expect(deleted, 1);
  });
}

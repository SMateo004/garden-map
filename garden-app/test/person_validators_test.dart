import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/theme/garden_theme.dart';
import 'package:garden_app/utils/person_validators.dart';
import 'package:garden_app/widgets/password_rules.dart';

// Mismas reglas que auth.validation.ts (registro de cuidador, profesional y empresa).
void main() {
  setUpAll(() => GardenText.useGoogleFonts = false);

  test('nombre: obligatorio y con letras', () {
    expect(PersonValidators.name(''), isNotNull);
    expect(PersonValidators.name('A'), isNotNull);
    expect(PersonValidators.name('Ana'), isNull);
    expect(PersonValidators.name('Ñu'), isNull);
    expect(PersonValidators.name('', label: 'apellido'), contains('apellido'));
  });

  test('correo con formato real', () {
    expect(PersonValidators.email(''), isNotNull);
    expect(PersonValidators.email('ana@'), isNotNull);
    expect(PersonValidators.email('ana@correo'), isNotNull);
    expect(PersonValidators.email(' ana@correo.com '), isNull);
  });

  test('contraseña: dice exactamente qué le falta', () {
    expect(PersonValidators.password(''), isNotNull);
    expect(PersonValidators.password('abcdefgh'), 'A tu contraseña le falta: 1 mayúscula, 1 número, 1 símbolo');
    expect(PersonValidators.password('Abcdef1!'), isNull);
  });

  test('celular boliviano, acepta espacios y +591', () {
    expect(PersonValidators.normalizeBoPhone('+591 7654 3210'), '76543210');
    expect(PersonValidators.boPhone('+591 7654 3210'), isNull);
    expect(PersonValidators.boPhone('3341234'), isNotNull);
    expect(PersonValidators.boPhone('86543210'), isNotNull);
  });

  test('mayor de 18, contando el día exacto', () {
    final now = DateTime(2026, 10, 5);
    expect(PersonValidators.adultBirthDate(null, now: now), isNotNull);
    expect(PersonValidators.adultBirthDate(DateTime(2008, 10, 5), now: now), isNull);
    expect(PersonValidators.adultBirthDate(DateTime(2008, 10, 6), now: now), isNotNull);
  });

  testWidgets('los requisitos de la contraseña se marcan mientras se escribe', (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PasswordRules(controller: ctrl))));
    for (final label in ['8+ caracteres', '1 mayúscula', '1 número', '1 símbolo']) {
      expect(find.text(label), findsOneWidget);
    }
    Color colorOf(String label) => tester.widget<Text>(find.text(label)).style!.color!;
    expect(colorOf('1 mayúscula'), isNot(GardenColors.success));
    ctrl.text = 'Abc';
    await tester.pump();
    expect(colorOf('1 mayúscula'), GardenColors.success);
    expect(colorOf('1 número'), isNot(GardenColors.success));
  });
}

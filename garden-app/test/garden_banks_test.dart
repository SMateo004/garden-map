import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/utils/garden_banks.dart';

// Mismas reglas que tests/unit/bank-info.test.ts en garden-api.
void main() {
  test('normaliza espacios, guiones y el +591 de las billeteras', () {
    expect(GardenBanks.normalizeAccount('CUENTA_AHORRO', '1000-234 567.8'), '10002345678');
    expect(GardenBanks.normalizeAccount('YAPE', '+591 700 12345'), '70012345');
  });

  test('cuenta bancaria: solo números, de 6 a 20', () {
    expect(GardenBanks.validateAccount('CUENTA_AHORRO', '1000-2345-678'), isNull);
    expect(GardenBanks.validateAccount('CUENTA_AHORRO', ''), isNotNull);
    expect(GardenBanks.validateAccount('CUENTA_AHORRO', 'ABC12345'), contains('solo lleva números'));
    expect(GardenBanks.validateAccount('CUENTA_AHORRO', '12345'), contains('entre 6 y 20'));
  });

  test('billetera: celular boliviano de 8 dígitos', () {
    expect(GardenBanks.validateAccount('YAPE', '+591 70012345'), isNull);
    expect(GardenBanks.validateAccount('YAPE', '3341234'), isNotNull);
    expect(GardenBanks.validateAccount('ZAS', '50012345'), isNotNull);
  });

  test('titular: nombre real', () {
    expect(GardenBanks.validateHolder('Ana Pérez'), isNull);
    expect(GardenBanks.validateHolder(' '), isNotNull);
    expect(GardenBanks.validateHolder('12'), isNotNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/screens/caregiver/walkin_clients_screen.dart';

void main() {
  test('cliente presencial: nombre obligatorio, correo opcional pero real', () {
    expect(walkInClientError('', ''), isNotNull);
    expect(walkInClientError('Ana', ''), isNull);
    expect(walkInClientError('Ana', 'ana@'), isNotNull);
    expect(walkInClientError('Ana', 'ana@correo.com'), isNull);
  });

  test('errores sin "Exception:" y conexión con mensaje claro', () {
    expect(friendlyError(Exception('Cliente walk-in no encontrado')), 'Cliente walk-in no encontrado');
    expect(friendlyError(const FormatException('<html>')), contains('Sin conexión'));
  });
}

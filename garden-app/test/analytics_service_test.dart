import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/services/analytics_service.dart';

void main() {
  group('sanitizeRoute — nunca filtra ids ni tokens', () {
    test('rutas sin parámetros quedan igual', () {
      expect(sanitizeRoute('/marketplace'), '/marketplace');
    });
    test('uuid → :id', () {
      expect(sanitizeRoute('/caregiver/3f2a9c1e-7b44-4d0e-9a11-2c5d8e6f0b77'), '/caregiver/:id');
    });
    test('token de seguimiento público → :id', () {
      expect(sanitizeRoute('/track/abc12345-6789/Zx9Kq2LmN0pQ'), '/track/:id/:id');
    });
    test('patrón ya parametrizado se respeta y se ignora el query', () {
      expect(sanitizeRoute('/booking/:caregiverId?x=1'), '/booking/:caregiverId');
    });
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/services/social_auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Inicio de sesión con Google: el servidor puede estar dormido y tardar en despertar. Estas pruebas fijan que la
/// app espera con límite, reintenta una vez y muestra un mensaje claro, en vez de un spinner sin fin o un error genérico.
const _data = SocialUserData(
  idToken: 'id-token',
  email: 'ana@test.com',
  firstName: 'Ana',
  lastName: 'Rojas',
  provider: SocialProvider.google,
);

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  late List<String> calls;

  setUp(() {
    calls = [];
    SocialAuthService.requestTimeout = const Duration(milliseconds: 80);
    SocialAuthService.retryDelay = Duration.zero;
    SocialAuthService.resetWarmUpForTest();
  });

  tearDown(() {
    SocialAuthService.client = http.Client();
    SocialAuthService.requestTimeout = const Duration(seconds: 25);
    SocialAuthService.retryDelay = const Duration(milliseconds: 600);
  });

  void mock(FutureOr<http.Response> Function(http.Request) handler) {
    SocialAuthService.client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      return handler(req);
    });
  }

  group('loginWithBackend — servidor despertando', () {
    test('si el servidor no responde a tiempo, reintenta UNA vez y luego muestra un mensaje claro', () async {
      mock((_) => Completer<http.Response>().future); // nunca responde
      final result = await SocialAuthService.loginWithBackend(_data);

      expect(result.success, isFalse);
      expect(result.error, contains('tardando en responder'));
      expect(calls.where((c) => c == 'POST /api/auth/social/login').length, 2);
    });

    test('un 503 (servidor arrancando) se reintenta y, si sigue igual, también da el mensaje claro', () async {
      mock((_) => http.Response('<html>Service Unavailable</html>', 503));
      final result = await SocialAuthService.loginWithBackend(_data);

      expect(result.success, isFalse);
      expect(result.error, contains('tardando en responder'));
      expect(calls.length, 2);
    });

    test('si el primer intento falla y el segundo ya responde, sigue el flujo normal (sin error)', () async {
      var n = 0;
      mock((req) {
        n++;
        if (n == 1) return http.Response('', 503);
        // 2.º intento: la cuenta no existe → la app intenta crearla y ahí el servidor la rechaza
        if (req.url.path.endsWith('/social/login')) return _json(404, {'success': false});
        return _json(403, {'success': false, 'error': {'code': 'REGISTRATIONS_DISABLED', 'message': 'Los registros están temporalmente deshabilitados.'}});
      });
      final result = await SocialAuthService.loginWithBackend(_data);

      expect(result.success, isFalse);
      expect(result.error, 'Los registros están temporalmente deshabilitados.');
      expect(calls, ['POST /api/auth/social/login', 'POST /api/auth/social/login', 'POST /api/auth/social/register-client']);
    });

    test('un error de red también se reintenta una vez', () async {
      mock((_) => throw http.ClientException('sin conexión'));
      final result = await SocialAuthService.loginWithBackend(_data);
      expect(result.error, contains('tardando en responder'));
      expect(calls.length, 2);
    });
  });

  group('loginWithBackend — respuestas del servidor que NO se reintentan', () {
    test('token de Google inválido (401): un solo intento y el mensaje del servidor', () async {
      mock((_) => _json(401, {
            'success': false,
            'error': {'code': 'INVALID_SOCIAL_TOKEN', 'message': 'Tu sesión de Google no es válida o expiró. Intenta de nuevo.'},
          }));
      final result = await SocialAuthService.loginWithBackend(_data);

      expect(result.success, isFalse);
      expect(result.error, 'Tu sesión de Google no es válida o expiró. Intenta de nuevo.');
      expect(calls.length, 1);
    });

    test('una respuesta que no es JSON no revienta: mensaje claro', () async {
      mock((_) => http.Response('no soy json', 200));
      final result = await SocialAuthService.loginWithBackend(_data);
      expect(result.success, isFalse);
      expect(result.error, contains('inesperado'));
    });

    test('sin idToken ni siquiera llama al servidor', () async {
      mock((_) => http.Response('{}', 200));
      final result = await SocialAuthService.loginWithBackend(
        const SocialUserData(email: 'a@b.c', firstName: '', lastName: '', provider: SocialProvider.google),
      );
      expect(result.success, isFalse);
      expect(calls, isEmpty);
    });
  });

  group('warmUpBackend — despertar el servidor mientras se elige la cuenta de Google', () {
    test('hace un GET a /health (raíz, no /api) sin bloquear', () async {
      mock((_) => http.Response('ok', 200));
      SocialAuthService.warmUpBackend();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, ['GET /health']);
    });

    test('no se repite si ya se llamó hace poco (abrir el login y tocar el botón = una sola llamada)', () async {
      mock((_) => http.Response('ok', 200));
      SocialAuthService.warmUpBackend();
      SocialAuthService.warmUpBackend();
      SocialAuthService.warmUpBackend();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls.length, 1);
    });

    test('si el servidor falla, no lanza ni deja un error sin atrapar', () async {
      mock((_) => throw http.ClientException('caído'));
      expect(SocialAuthService.warmUpBackend, returnsNormally);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });
}

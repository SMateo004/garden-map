import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:garden_app/services/deep_link_service.dart';

/// Toque en un widget del home screen con la app cerrada: el destino no puede perderse por el
/// arranque (/ → /splash → inicio), que navega con `go` y reemplaza la pila.
void main() {
  GoRouter buildRouter(String initial) => GoRouter(
        initialLocation: initial,
        routes: [
          for (final p in ['/', '/splash', '/home', '/marketplace', '/my-bookings-tab', '/favorites'])
            GoRoute(path: p, builder: (_, __) => Text('screen:$p')),
        ],
      );

  String locationOf(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

  testWidgets('durante el arranque guarda el destino y lo abre al llegar al inicio', (tester) async {
    final router = buildRouter('/splash');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    DeepLinkService.handleForTest(router, '/marketplace', null);
    await tester.pumpAndSettle();
    expect(locationOf(router), '/splash', reason: 'todavía arrancando: no navega');

    router.go('/home'); // el splash termina y manda al inicio
    await tester.pumpAndSettle();
    // Se empuja encima del inicio (atrás vuelve al inicio, no al splash).
    expect(find.text('screen:/marketplace'), findsOneWidget);
  });

  testWidgets('con la app ya abierta navega al instante', (tester) async {
    final router = buildRouter('/home');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    DeepLinkService.handleForTest(router, '/favorites', null);
    await tester.pumpAndSettle();
    expect(find.text('screen:/favorites'), findsOneWidget);
  });

  // Todos los toques de todos los widgets (Android: servicio activo, buscar cuidador, próxima
  // reserva, resumen del mes; iOS: Live Activity y buscar cuidador) × cada tipo de sesión.
  group('resolve: destino de cada toque según la sesión', () {
    ({String location, bool push})? r(String route, {bool session = true, String role = 'CLIENT', bool staff = false}) =>
        DeepLinkService.resolve(route, hasSession: session, effectiveRole: role, isStaff: staff);

    test('servicio en curso: abre la pantalla del servicio (dueño y cuidador)', () {
      expect(r('/service/abc-123'), (location: '/service/abc-123', push: true));
      expect(r('/service/abc-123', role: 'CAREGIVER'), (location: '/service/abc-123', push: true));
    });

    test('servicio sin id (dato viejo del widget): va a las reservas, no a una pantalla rota', () {
      expect(r('/service/'), (location: '/my-bookings-tab', push: false));
      expect(r('/service'), (location: '/my-bookings-tab', push: false)); // así llega desde iOS
      expect(r('/service/', role: 'CAREGIVER'), (location: '/caregiver/home?tab=reservas', push: false));
    });

    test('servicio sin sesión: no navega (el login decide después)', () {
      expect(r('/service/abc', session: false), isNull);
    });

    test('próxima reserva: dueño → mis reservas; cuidador → su pestaña de reservas; equipo → su inicio', () {
      expect(r('/my-bookings-tab'), (location: '/my-bookings-tab', push: false));
      expect(r('/my-bookings-tab', role: 'CAREGIVER'), (location: '/caregiver/home?tab=reservas', push: false));
      expect(r('/my-bookings-tab', role: 'CAREGIVER', staff: true), (location: '/caregiver-staff/home', push: false));
      expect(r('/my-bookings-tab', session: false), (location: '/login', push: false));
    });

    test('buscar cuidador / resumen del mes: dueño e invitado → marketplace; cuidador → su inicio', () {
      expect(r('/marketplace'), (location: '/marketplace', push: false));
      expect(r('/marketplace', session: false), (location: '/marketplace', push: false));
      expect(r('/marketplace', role: 'CAREGIVER'), (location: '/caregiver/home', push: false));
      expect(r('/marketplace', role: 'CAREGIVER', staff: true), (location: '/caregiver-staff/home', push: false));
    });
  });
}

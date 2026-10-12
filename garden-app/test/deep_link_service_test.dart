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
          for (final p in ['/', '/splash', '/home', '/marketplace', '/my-bookings-tab'])
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

    DeepLinkService.handleForTest(router, '/my-bookings-tab', null);
    await tester.pumpAndSettle();
    expect(find.text('screen:/my-bookings-tab'), findsOneWidget);
  });
}

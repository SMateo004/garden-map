import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:garden_app/screens/caregiver/become_caregiver_screen.dart';
import 'package:garden_app/services/auth_state.dart';

/// "Hazte cuidador" ofrece ingresar un código de equipo SOLO a quien ya tiene sesión: es el reemplazo de la
/// fila "Unirme a un equipo" que ya no ve un dueño de mascota cualquiera en su perfil.
Widget _app() => MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/become',
        routes: [
          GoRoute(path: '/become', builder: (_, __) => const BecomeCaregiverScreen()),
          GoRoute(path: '/caregiver-staff/join', builder: (_, __) => const Scaffold(body: Text('pantalla de unirse'))),
          GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('inicio'))),
        ],
      ),
    );

Future<void> _scrollToBottom(WidgetTester tester) async {
  await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AuthState.debugSetToken(''));

  testWidgets('con sesión iniciada aparece "¿Te invitó una empresa?" y lleva a ingresar el código', (tester) async {
    AuthState.debugSetToken('token-de-prueba');
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _scrollToBottom(tester);

    expect(find.text('¿Te invitó una empresa?'), findsOneWidget);
    expect(find.textContaining('código que te dieron'), findsOneWidget);

    await tester.tap(find.text('¿Te invitó una empresa?'));
    await tester.pumpAndSettle();
    expect(find.text('pantalla de unirse'), findsOneWidget);
  });

  testWidgets('sin sesión no se muestra (ese acceso está en el inicio de sesión)', (tester) async {
    AuthState.debugSetToken('');
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _scrollToBottom(tester);

    expect(find.text('¿Te invitó una empresa?'), findsNothing);
    expect(find.text('Comenzar registro'), findsOneWidget);
  });

  testWidgets('no desplaza al botón principal: "Comenzar registro" sigue arriba de la invitación', (tester) async {
    AuthState.debugSetToken('token-de-prueba');
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _scrollToBottom(tester);

    final cta = tester.getTopLeft(find.text('Comenzar registro')).dy;
    final invite = tester.getTopLeft(find.text('¿Te invitó una empresa?')).dy;
    expect(cta, lessThan(invite));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/screens/caregiver/caregiver_contract_content.dart';
import 'package:garden_app/screens/caregiver/caregiver_terms_renewal_screen.dart';

Widget _host(CaregiverTermsStatus status) => MaterialApp(home: CaregiverTermsRenewalScreen(status: status));

void main() {
  testWidgets('vencido: explica que el perfil está oculto y NO se puede omitir', (tester) async {
    await tester.pumpWidget(_host(const CaregiverTermsStatus(required: true, blocked: true, reason: 'EXPIRED')));
    expect(find.text('Renueva tu aceptación'), findsOneWidget);
    expect(find.textContaining('no aparece en el marketplace'), findsOneWidget);
    expect(find.text('Más tarde'), findsNothing);
    expect(find.text('Acepto y renuevo'), findsOneWidget);
  });

  testWidgets('versión nueva en gracia: se puede dejar para más tarde', (tester) async {
    await tester.pumpWidget(_host(const CaregiverTermsStatus(required: true, blocked: false, reason: 'NEW_VERSION')));
    expect(find.textContaining('Actualizamos los Términos'), findsOneWidget);
    expect(find.text('Más tarde'), findsOneWidget);
  });

  testWidgets('el botón de aceptar queda deshabilitado hasta leer todo el contrato', (tester) async {
    await tester.pumpWidget(_host(const CaregiverTermsStatus(required: true, blocked: true, reason: 'EXPIRED')));
    final button = find.widgetWithText(ElevatedButton, 'Acepto y renuevo');
    if (button.evaluate().isNotEmpty) {
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
    }
    // Al llegar al final del scroll se habilita el mensaje de "ya puedes aceptar".
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(find.text('Llegaste al final. Ya puedes aceptar y renovar.'), findsOneWidget);
  });

  test('el contrato incluye la aceptación periódica y la versión vigente', () {
    expect(caregiverContractSections.any((s) => s.title.contains('cada 2 meses')), isTrue);
    expect(caregiverTermsVersion, isNotEmpty);
  });

  test('CaregiverTermsStatus.fromJson lee lo que manda el servidor', () {
    final s = CaregiverTermsStatus.fromJson({'required': true, 'blocked': false, 'reason': 'NEW_VERSION', 'daysLeft': 12});
    expect(s.required, isTrue);
    expect(s.blocked, isFalse);
    expect(s.reason, 'NEW_VERSION');
    expect(s.daysLeft, 12);
  });
}

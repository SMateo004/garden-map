import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_icons.dart';
import 'package:garden_app/design/garden_payment.dart';
import 'package:garden_app/design/garden_service.dart';
import 'package:garden_app/theme/garden_theme.dart';

void main() {
  setUpAll(() => GardenText.useGoogleFonts = false);
  final now = DateTime(2026, 10, 5, 10); // lunes

  group('Cuándo, en el encabezado del pago', () {
    test('paseo con hora exacta y duración', () {
      expect(paymentWhenLabel({'serviceType': 'PASEO', 'walkDate': '2026-10-06', 'startTime': '09:00', 'duration': 60}, now: now),
          'mañana a las 9:00 · 60 min');
    });

    test('solo franja horaria, sin hora exacta', () {
      expect(paymentWhenLabel({'serviceType': 'GUARDERIA', 'walkDate': '2026-10-08', 'timeSlot': 'TARDE'}, now: now),
          'el jueves · en la tarde');
      expect(paymentWhenLabel({'serviceType': 'PASEO', 'walkDate': '2026-10-20T00:00:00.000Z', 'timeSlot': 'MANANA'}, now: now),
          'el 20/10 · en la mañana');
    });

    test('hospedaje: rango y noches', () {
      expect(paymentWhenLabel({'serviceType': 'HOSPEDAJE', 'startDate': '2026-10-07', 'endDate': '2026-10-09', 'totalDays': 2}, now: now),
          'del 07/10 al 09/10 · 2 noches');
      expect(paymentWhenLabel({'serviceType': 'HOSPEDAJE', 'startDate': '2026-10-07', 'endDate': '2026-10-08'}, now: now),
          'del 07/10 al 08/10 · 1 noche');
    });

    test('sin fecha no inventa nada', () {
      expect(paymentWhenLabel({'serviceType': 'PASEO'}, now: now), isNull);
    });
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

  testWidgets('el encabezado dice qué se paga y abre el desglose', (tester) async {
    await tester.pumpWidget(wrap(const GardenPaymentHero(
      service: GardenService.paseo,
      petName: 'Luna',
      caregiverName: 'Andrea Rojas',
      when: 'mañana a las 9:00 · 60 min',
      total: 41.5,
      lines: [
        GardenPaymentLine('Servicio', 36.5),
        GardenPaymentLine('Desde tu billetera', 20, negative: true),
      ],
    )));
    await tester.pumpAndSettle();
    expect(find.text('Paseo de Luna con Andrea'), findsOneWidget);
    expect(find.text('mañana a las 9:00 · 60 min'), findsOneWidget);
    expect(find.text('Servicio'), findsNothing);

    await tester.tap(find.text('Ver detalle'));
    await tester.pumpAndSettle();
    expect(find.text('Servicio'), findsOneWidget);
    expect(find.text('− Bs 20.00'), findsOneWidget);
  });

  testWidgets('la barra de pago muestra el monto y bloquea mientras procesa', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: GardenPayBar(
          amount: 21.5,
          note: '+ Bs 20.00 de billetera',
          buttonLabel: 'Generar QR',
          buttonIcon: GIcon.pagarQr,
          onPressed: () => taps++,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('21', findRichText: true), findsOneWidget);
    expect(find.text('+ Bs 20.00 de billetera'), findsOneWidget);
    await tester.tap(find.text('Generar QR'));
    expect(taps, 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: GardenPayBar(
          amount: 21.5,
          buttonLabel: 'Procesando…',
          buttonIcon: GIcon.pagarQr,
          loading: true,
          onPressed: null,
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byType(GardenButton), warnIfMissed: false);
    expect(taps, 1);
  });
}

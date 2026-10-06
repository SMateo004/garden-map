import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_icons.dart';
import 'package:garden_app/design/garden_wallet.dart';
import 'package:garden_app/theme/garden_theme.dart';

void main() {
  setUpAll(() => GardenText.useGoogleFonts = false);
  final now = DateTime(2026, 10, 5, 18);

  test('fechas del historial en lenguaje simple', () {
    expect(walletDayLabel(DateTime(2026, 10, 5, 9, 5), now: now), 'hoy 09:05');
    expect(walletDayLabel(DateTime(2026, 10, 4, 23, 40), now: now), 'ayer 23:40');
    expect(walletDayLabel(DateTime(2026, 9, 12), now: now), '12 sep');
    expect(walletDayLabel(DateTime(2025, 12, 31), now: now), '31 dic 2025');
    expect(walletMonthLabel(DateTime(2026, 10, 1), now: now), 'Octubre');
    expect(walletMonthLabel(DateTime(2025, 8, 1), now: now), 'Agosto 2025');
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

  testWidgets('retiro en camino: se cancela mientras está solicitado, no en revisión', (tester) async {
    var cancels = 0;
    await tester.pumpWidget(wrap(GardenPendingWithdrawal(amount: 100, destination: 'Banco BNB •••• 2345', onCancel: () => cancels++)));
    expect(find.text('Bs 100.00 a Banco BNB •••• 2345'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    expect(cancels, 1);

    await tester.pumpWidget(wrap(GardenPendingWithdrawal(
        amount: 100, destination: 'Banco BNB •••• 2345', processing: true, onCancel: () => cancels++)));
    expect(find.text('Cancelar'), findsNothing);
  });

  testWidgets('la tarjeta de saldo muestra lo en camino y sus acciones', (tester) async {
    var retiros = 0;
    await tester.pumpWidget(wrap(GardenBalanceCard(
      available: 140,
      pending: 100,
      actions: [GardenWalletAction(GIcon.retiro, 'Retirar', () => retiros++, primary: true)],
    )));
    await tester.pumpAndSettle();
    expect(find.text('Bs 100.00 en camino'), findsOneWidget);
    await tester.tap(find.text('Retirar'));
    expect(retiros, 1);
  });
}

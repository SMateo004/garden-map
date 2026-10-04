import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/main.dart';

void main() {
  testWidgets('GardenApp smoke test — renders without crashing',
      (WidgetTester tester) async {
    // GardenApp reemplaza ErrorWidget.builder al construirse; el binding de
    // test exige que quede como estaba al terminar.
    final originalErrorBuilder = ErrorWidget.builder;
    await tester.pumpWidget(const GardenApp());
    expect(find.byType(GardenApp), findsOneWidget);
    ErrorWidget.builder = originalErrorBuilder;
  });
}

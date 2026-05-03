import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/main.dart';

void main() {
  testWidgets('GardenApp smoke test — renders without crashing',
      (WidgetTester tester) async {
    await tester.pumpWidget(const GardenApp());
    // The app should at least render a Scaffold-based widget tree
    expect(find.byType(GardenApp), findsOneWidget);
  });
}

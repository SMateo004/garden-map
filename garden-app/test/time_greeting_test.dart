import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/utils/time_greeting.dart';

void main() {
  DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 13, h, m);

  test('saludo según la hora local', () {
    expect(timeGreeting(at(5)), 'Buen día');
    expect(timeGreeting(at(11, 59)), 'Buen día');
    expect(timeGreeting(at(12)), 'Buenas tardes');
    expect(timeGreeting(at(18, 59)), 'Buenas tardes');
    expect(timeGreeting(at(19)), 'Buenas noches');
    expect(timeGreeting(at(2)), 'Buenas noches');
    expect(timeGreeting(at(4, 59)), 'Buenas noches');
  });
}

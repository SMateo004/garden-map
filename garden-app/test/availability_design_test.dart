import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_availability.dart';

void main() {
  test('resumen de disponibilidad en lenguaje simple', () {
    final a = availabilitySummary({
      'weekdays': true, 'weekends': false, 'holidays': true,
      'paseoTimeBlocks': {
        'morning': {'enabled': true, 'start': '07:30', 'end': '11:00'},
        'night': {'enabled': false},
      },
    });
    expect(a.headline, 'Recibes reservas de lunes a viernes, también feriados');
    expect(a.hours, 'Mañana 07:30–11:00 · Tarde 13:00–17:00');
    expect(a.off, isFalse);
  });

  test('sin datos guardados usa los mismos valores por defecto que la pantalla', () {
    final a = availabilitySummary(null);
    expect(a.headline, 'Recibes reservas todos los días, también feriados');
    expect(a.hours, 'Mañana 08:00–11:00 · Tarde 13:00–17:00 · Noche 19:00–22:00');
  });

  test('todo apagado avisa que no recibe reservas', () {
    final a = availabilitySummary({'weekdays': false, 'weekends': false, 'holidays': false});
    expect(a.headline, 'No estás recibiendo reservas');
    expect(a.off, isTrue);
    expect(availabilitySummary({'weekdays': false, 'weekends': true, 'holidays': false}).headline,
        'Recibes reservas los fines de semana, sin feriados');
  });
}

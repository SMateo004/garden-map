import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_icons.dart';
import 'package:garden_app/narrative/notification_kind.dart';

void main() {
  test('el título se muestra sin los emojis del backend', () {
    expect(NotificationKind.clean('\u{1F697} Tu cuidador va en camino'), 'Tu cuidador va en camino');
    expect(NotificationKind.clean('Servicio finalizado \u2705 — Califica ahora'), 'Servicio finalizado — Califica ahora');
    expect(NotificationKind.clean('\u2696\uFE0F Resultado de tu apelación'), 'Resultado de tu apelación');
    expect(NotificationKind.clean('¡Hola!'), '¡Hola!');
  });

  test('todos los tipos que crea el backend tienen icono propio', () {
    // Lee los `type: '...'` de garden-api para que un tipo nuevo sin icono
    // se note acá y no como una campana genérica en el buzón.
    final api = Directory('../garden-api/src');
    if (!api.existsSync()) return; // CI de la app sin el backend al lado
    final types = <String>{};
    for (final f in api.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.ts'))) {
      for (final m in RegExp(r"type: '([A-Z_]+)'").allMatches(f.readAsStringSync())) {
        types.add(m.group(1)!);
      }
    }
    // Mismo campo `type` en otras tablas: eventos del servicio, movimientos
    // de billetera y avisos del panel admin (AdminNotification). No llegan al buzón.
    const notNotifications = {
      'HOSPEDAJE_OVERDUE_NOTIFIED', 'EXPIRY_WARNING_END', 'CLIENT_SOS', 'HOURLY_PING', 'END', // eventos del servicio
      'DONATION', 'FINE', // movimientos de billetera
      'ANTECEDENTES_FLAGGED', 'AUDIT_LOG_FAILURE', // AdminNotification
    };
    final missing = types
        .difference(notNotifications)
        .where((t) => NotificationKind.of(t).icon == GIcon.notificaciones)
        .toList();
    expect(missing, isEmpty, reason: 'Tipos sin icono en notification_kind.dart: $missing');
  });
}

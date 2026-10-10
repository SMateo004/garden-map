import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_icons.dart';
import 'package:garden_app/narrative/notification_kind.dart';
import 'package:garden_app/widgets/notification_bell.dart';

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
    final files = api.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.ts')).toList();
    // Constantes exportadas ("export const WALLET_TX_PAYMENT_NOT_RECEIVED = 'PAYMENT_NOT_RECEIVED'"):
    // algunos tipos se usan así en vez de con el texto literal.
    final consts = <String, String>{};
    for (final f in files) {
      for (final m in RegExp(r"export const ([A-Z_]+)\s*=\s*'([A-Z_]+)'").allMatches(f.readAsStringSync())) {
        consts[m.group(1)!] = m.group(2)!;
      }
    }
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final m in RegExp(r"type: '([A-Z_]+)'").allMatches(src)) {
        types.add(m.group(1)!);
      }
      // `type: CONSTANTE` dentro de un notification.create(...)
      for (final m in RegExp(r'\.notification\.create(?:Many)?\(').allMatches(src)) {
        final seg = src.substring(m.start, (m.start + 1600).clamp(0, src.length));
        for (final c in RegExp(r'type:\s*([A-Z_]{4,})\b').allMatches(seg)) {
          final v = consts[c.group(1)!];
          if (v != null) types.add(v);
        }
      }
    }
    expect(types, contains('PAYMENT_NOT_RECEIVED'), reason: 'el test debe ver los tipos que vienen de constantes');
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

  group('a dónde lleva (dueño)', () {
    test('lo del servicio con reserva abre ese servicio', () {
      final d = notificationDestination('SERVICE_STARTED', bookingId: 'b1')!;
      expect(d.route, '/service/b1');
      expect(d.extra?['role'], 'CLIENT');
    });
    test('una cancelación con reserva la resalta en Mis reservas', () {
      final d = notificationDestination('BOOKING_CANCELLED', bookingId: 'b1')!;
      expect(d.route, '/my-bookings');
      expect(d.highlight, 'b1');
      expect(d.label, 'Ver la reserva');
    });
    test('las viejas, sin reserva, llevan a la lista', () {
      final d = notificationDestination('SERVICE_STARTED')!;
      expect(d.route, '/my-bookings');
      expect(d.highlight, isNull);
    });
    test('un mensaje del chat abre esa conversación', () {
      final d = notificationDestination('CHAT_MESSAGE', bookingId: 'b1')!;
      expect(d.route, '/chat/b1');
      expect(d.label, 'Abrir el chat');
    });
    test('la plata va a la billetera aunque tenga reserva', () {
      expect(notificationDestination('REFUND', bookingId: 'b1')!.route, '/wallet');
    });
  });
}

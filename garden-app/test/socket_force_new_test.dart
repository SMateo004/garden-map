import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

/// El chat recibía el socket de presencia ya abierto (misma URL) y por eso
/// nunca se unía a la sala: sin mensajes en vivo, sin "escribiendo…" y la
/// otra persona "desconectada" al cerrar el chat.
void main() {
  const url = 'https://ejemplo.invalid';

  test('sin forceNew, dos sockets a la misma URL son EL MISMO (el error)', () {
    final a = IO.io(url, <String, dynamic>{'autoConnect': false});
    final b = IO.io(url, <String, dynamic>{'autoConnect': false});
    expect(identical(a, b), isTrue);
    a.dispose();
  });

  test('con forceNew cada pantalla tiene su propia conexión', () {
    final a = IO.io(url, <String, dynamic>{'autoConnect': false, 'forceNew': true});
    final b = IO.io(url, <String, dynamic>{'autoConnect': false, 'forceNew': true});
    expect(identical(a, b), isFalse);
    a.dispose();
    b.dispose();
  });

  test('todos los sockets de la app piden conexión propia', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    final missing = <String>[];
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final m in RegExp(r'IO\.io\(').allMatches(src)) {
        final call = src.substring(m.start, (m.start + 700).clamp(0, src.length));
        if (!call.contains("'forceNew': true") && !call.contains('enableForceNew()')) {
          missing.add(f.path);
        }
      }
    }
    expect(missing, isEmpty, reason: 'IO.io sin forceNew en: $missing');
  });
}

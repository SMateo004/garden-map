/// PresenceService — mantiene un socket liviano y persistente para que el
/// backend sepa que este usuario está "en línea" mientras usa la app, sin
/// depender de tener una pantalla de chat específica abierta.
///
/// Antes, `ChatService` (el socket que usa la pantalla de chat) solo se
/// conectaba mientras esa pantalla exacta estaba en pantalla — si el otro
/// participante estaba usando la app en cualquier otra pantalla (ej. el
/// cuidador paseando a la mascota, sin el chat abierto), su socket de chat
/// no existía, así que `isUserOnline()` en el backend correctamente lo veía
/// como desconectado aunque estuviera activamente usando la app. El chat
/// del otro lado siempre mostraba "Desconectado".
///
/// Este servicio resuelve eso: se conecta apenas hay sesión activa y se
/// mantiene conectado mientras la app está en primer plano (independiente
/// de qué pantalla se esté mirando), dando una señal de presencia real. No
/// necesita unirse a ninguna sala de booking — el backend ya cuenta
/// cualquier socket autenticado como "en línea" apenas se conecta.
library;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'auth_state.dart';

class PresenceService {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  IO.Socket? _socket;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  /// Conecta el socket de presencia si hay sesión activa y todavía no está
  /// conectado. Llamar al iniciar la app (si ya hay sesión), justo después
  /// de un login exitoso, y al volver del background.
  void connect() {
    if (kIsWeb) return; // presencia solo tiene sentido en mobile por ahora
    if (!AuthState.hasSession) return;
    if (_socket?.connected == true) return;

    try {
      _socket?.dispose();
      final wsUrl = _baseUrl.replaceAll('/api', '');
      _socket = IO.io(wsUrl, <String, dynamic>{
        'transports': ['polling', 'websocket'],
        'autoConnect': false,
        'auth': {'token': AuthState.token},
        'reconnection': true,
        'reconnectionDelay': 2000,
      });
      _socket!.onConnect((_) => debugPrint('Presence: socket connected'));
      _socket!.onConnectError((data) => debugPrint('Presence: connect error: $data'));
      _socket!.connect();
    } catch (e) {
      debugPrint('Presence: failed to connect: $e');
    }
  }

  /// Desconecta el socket de presencia — llamar al pasar la app a background
  /// (para que el resto de usuarios vean "desconectado" con precisión, igual
  /// que WhatsApp) y en logout.
  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}

/// Chat de soporte cliente↔admin — reemplaza el enlace directo a WhatsApp
/// del Centro de Ayuda (ver help_center_screen.dart).
///
/// El hilo real vive completo en el backend para siempre (un solo
/// SupportThread por cliente, ver comentario en prisma/schema.prisma), pero
/// del lado del cliente la conversación "empieza de cero" cada vez que abre
/// la app: [SupportChatSession.startedAt] es un DateTime en memoria (NO
/// persistido en disco) calculado una sola vez por arranque del proceso —
/// cerrar la app de verdad (no solo pasarla a segundo plano) lo reinicia
/// solo, sin necesidad de ningún estado especial de "cierre".
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SupportChatSession {
  SupportChatSession._();
  static DateTime? _startedAt;

  /// La primera vez que se pide (por proceso), queda fijado — llamadas
  /// posteriores devuelven siempre el mismo valor mientras la app siga viva.
  static DateTime get startedAt => _startedAt ??= DateTime.now().toUtc();
}

class SupportChatMessage {
  final String id;
  final String senderRole; // 'CLIENT' | 'ADMIN'
  final String message;
  final DateTime createdAt;

  SupportChatMessage({required this.id, required this.senderRole, required this.message, required this.createdAt});

  factory SupportChatMessage.fromJson(Map<String, dynamic> json) => SupportChatMessage(
        id: json['id'] as String,
        senderRole: json['senderRole'] as String,
        message: json['message'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );
}

class SupportChatService extends ChangeNotifier {
  final String _baseUrl;
  final String _token;
  IO.Socket? _socket;
  bool _isDisposed = false;

  List<SupportChatMessage> _messages = [];
  List<SupportChatMessage> get messages => _messages;
  bool loading = true;
  bool sending = false;

  SupportChatService({required String baseUrl, required String token}) : _baseUrl = baseUrl, _token = token;

  Future<void> init() async {
    await loadSession();
    _connectSocket();
  }

  Future<void> loadSession() async {
    try {
      final since = SupportChatSession.startedAt.toIso8601String();
      final res = await http.get(
        Uri.parse('$_baseUrl/support/chat?since=$since'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        _messages = (data['data']['messages'] as List)
            .map((m) => SupportChatMessage.fromJson(m as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('SupportChat: error cargando sesión: $e');
    } finally {
      loading = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  void _connectSocket() {
    try {
      final wsUrl = _baseUrl.replaceAll('/api', '');
      _socket = IO.io(wsUrl, <String, dynamic>{
        'transports': ['polling', 'websocket'],
        'autoConnect': false,
        'auth': {'token': _token},
        'reconnection': true,
        'reconnectionDelay': 2000,
      });
      _socket!.on('support_admin_reply', (data) {
        if (_isDisposed) return;
        try {
          final raw = (data is List && data.isNotEmpty) ? data.first : data;
          final map = Map<String, dynamic>.from(raw as Map);
          final msg = SupportChatMessage(
            id: 'live_${DateTime.now().microsecondsSinceEpoch}',
            senderRole: 'ADMIN',
            message: map['message'] as String,
            createdAt: DateTime.parse(map['createdAt'] as String).toLocal(),
          );
          _messages.add(msg);
          notifyListeners();
        } catch (e) {
          debugPrint('SupportChat: error parseando respuesta del admin: $e');
        }
      });
      _socket!.connect();
    } catch (e) {
      debugPrint('SupportChat: no se pudo conectar el socket: $e');
    }
  }

  /// true si el envío funcionó — la UI decide qué hacer si falla (mostrar el
  /// diálogo de error y dejar el texto en el campo para reintentar).
  Future<bool> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || sending) return false;
    sending = true;
    if (!_isDisposed) notifyListeners();
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/support/chat'),
            headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
            body: jsonEncode({'message': trimmed}),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        _messages.add(SupportChatMessage(
          id: data['data']['id'] as String,
          senderRole: 'CLIENT',
          message: trimmed,
          createdAt: DateTime.parse(data['data']['createdAt'] as String).toLocal(),
        ));
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('SupportChat: error enviando mensaje: $e');
      return false;
    } finally {
      sending = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }
}

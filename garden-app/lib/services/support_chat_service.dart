/// Chat de soporte cliente↔admin. Primera línea la atiende un bot (Claude,
/// grounded en el centro de ayuda); si el caso se sale de lo que el bot
/// puede resolver, escala a un admin humano — recién ahí, nunca antes.
///
/// El hilo real vive completo en el backend para siempre (un solo
/// SupportThread por cliente, ver prisma/schema.prisma). Ya no "empieza de
/// cero" al abrir la app: la conversación persiste hasta que un admin la
/// marca resuelta desde su panel — eso es lo único que la reinicia.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SupportChatMessage {
  final String id;
  final String senderRole; // 'CLIENT' | 'BOT' | 'ADMIN'
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
  /// 'BOT' | 'ESCALATED' | 'RESOLVED' — la UI usa esto para mostrar el
  /// banner de "esperando a un asesor" cuando corresponde.
  String status = 'BOT';

  SupportChatService({required String baseUrl, required String token}) : _baseUrl = baseUrl, _token = token;

  Future<void> init() async {
    await loadSession();
    _connectSocket();
  }

  Future<void> loadSession() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/support/chat'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        _messages = (data['data']['messages'] as List)
            .map((m) => SupportChatMessage.fromJson(m as Map<String, dynamic>))
            .toList();
        status = data['data']['status'] as String? ?? 'BOT';
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
          final senderRole = map['senderRole'] as String? ?? 'ADMIN';
          final msg = SupportChatMessage(
            id: 'live_${DateTime.now().microsecondsSinceEpoch}',
            senderRole: senderRole,
            message: map['message'] as String,
            createdAt: DateTime.parse(map['createdAt'] as String).toLocal(),
          );
          _messages.add(msg);
          // Un mensaje real de ADMIN en vivo significa que un asesor ya
          // entró a la conversación.
          if (senderRole == 'ADMIN') status = 'ESCALATED';
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
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        _messages.add(SupportChatMessage(
          id: data['data']['id'] as String,
          senderRole: 'CLIENT',
          message: trimmed,
          createdAt: DateTime.parse(data['data']['createdAt'] as String).toLocal(),
        ));
        // La respuesta del bot (si respondió) viaja en el mismo POST — no
        // hace falta esperar al socket para verla en la propia pantalla que
        // acaba de mandar el mensaje.
        final botMessageJson = data['data']['botMessage'] as Map<String, dynamic>?;
        if (botMessageJson != null) {
          _messages.add(SupportChatMessage(
            id: botMessageJson['id'] as String,
            senderRole: 'BOT',
            message: botMessageJson['message'] as String,
            createdAt: DateTime.parse(botMessageJson['createdAt'] as String).toLocal(),
          ));
        }
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

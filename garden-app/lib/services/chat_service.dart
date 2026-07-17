import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'local_notification_service.dart';

class ChatMessage {
  final String id;
  final String bookingId;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String message;
  final bool read;
  final bool isSystem;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.bookingId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.message,
    required this.read,
    this.isSystem = false,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      bookingId: json['bookingId'] as String,
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? 'Sistema',
      senderRole: json['senderRole'] as String? ?? '',
      message: json['message'] as String,
      read: json['read'] as bool? ?? false,
      isSystem: json['isSystem'] as bool? ?? false,
      // El backend manda el timestamp en UTC (sufijo Z). Sin .toLocal() acá,
      // cualquier lugar que lea msg.createdAt.hour/.minute (ej. chat_screen.dart)
      // mostraba la hora UTC directamente — en Bolivia (UTC-4) un mensaje de
      // las 16:00 se veía como "20:00". Convertir una sola vez acá evita tener
      // que acordarse de hacerlo en cada punto de la UI que use createdAt.
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    );
  }
}

class ChatService extends ChangeNotifier {
  IO.Socket? _socket;
  final String _baseUrl;
  final String _token;
  final String _currentUserId;

  List<ChatMessage> _messages = [];
  bool _connected = false;
  int _unreadCount = 0;
  bool _isDisposed = false;
  String? _pendingBookingId;
  // El ChatScreen setea esto en didChangeAppLifecycleState — evita mostrar una
  // notificación local por un mensaje que ya se ve en pantalla porque el chat
  // está abierto y en primer plano ahora mismo.
  bool isForeground = true;

  List<ChatMessage> get messages => _messages;
  bool get connected => _connected;
  int get unreadCount => _unreadCount;
  // true si el último intento de envío falló porque alguna de las partes bloqueó a la otra.
  bool blockedError = false;

  // Presencia de la otra persona en el chat ("en línea"). Se setea el userId
  // del otro participante desde ChatScreen apenas se conoce (via
  // GET /chat/:bookingId/other-participant) y se actualiza en vivo con los
  // eventos de socket user_online/user_offline emitidos por el backend.
  String? _otherUserId;
  bool otherOnline = false;

  void setOtherUserId(String userId, {required bool initialOnline}) {
    _otherUserId = userId;
    otherOnline = initialOnline;
    if (!_isDisposed) notifyListeners();
  }

  ChatService({
    required String baseUrl,
    required String token,
    required String currentUserId,
  })  : _baseUrl = baseUrl,
        _token = token,
        _currentUserId = currentUserId;

  void connect() {
    try {
      final wsUrl = _baseUrl.replaceAll('/api', '');
      _socket = IO.io(wsUrl, <String, dynamic>{
        'transports': ['polling', 'websocket'],
        'autoConnect': false,
        'auth': {'token': _token},
        'timeout': 10000,
      });

      _socket!.onConnect((_) {
        _connected = true;
        debugPrint('Chat: Socket connected');
        // Auto-join the room if joinBooking was called before connection was ready
        if (_pendingBookingId != null) {
          _socket!.emit('join_booking', _pendingBookingId!);
          debugPrint('Chat: Auto-joined room $_pendingBookingId on connect');
        }
        if (!_isDisposed) notifyListeners();
      });

      _socket!.onDisconnect((_) {
        _connected = false;
        debugPrint('Chat: Socket disconnected');
        if (!_isDisposed) notifyListeners();
      });

      _socket!.onConnectError((data) {
        debugPrint('Chat: Connect error: $data');
        _connected = false;
      });

      _socket!.onError((data) {
        debugPrint('Chat: Socket error: $data');
      });

      _socket!.on('new_message', (data) {
        if (_isDisposed) return;
        try {
          // socket_io_client v2 may wrap the payload in a List — unwrap if needed
          final raw = (data is List && data.isNotEmpty) ? data.first : data;
          final msg = ChatMessage.fromJson(Map<String, dynamic>.from(raw as Map));
          // Deduplicar: puede que ya esté si se envió por HTTP
          if (_messages.any((m) => m.id == msg.id)) return;
          _messages.add(msg);
          if (msg.senderId != _currentUserId) {
            _unreadCount++;
            // Solo notificar si el chat NO está en primer plano — si está
            // abierto y visible el mensaje ya aparece en la lista, una
            // notificación local ahí encima es puro ruido duplicado.
            if (!isForeground) {
              LocalNotificationService.show(
                title: msg.senderName,
                body: msg.message,
              );
            }
          }
          notifyListeners();
        } catch (e) {
          debugPrint('Chat: Error parsing message: $e');
        }
      });

      _socket!.on('messages_read', (data) {
        if (_isDisposed) return;
        _unreadCount = 0;
        notifyListeners();
      });

      _socket!.on('user_online', (data) {
        if (_isDisposed) return;
        final raw = (data is List && data.isNotEmpty) ? data.first : data;
        final userId = (raw is Map) ? raw['userId'] as String? : null;
        if (userId != null && userId == _otherUserId) {
          otherOnline = true;
          notifyListeners();
        }
      });

      _socket!.on('user_offline', (data) {
        if (_isDisposed) return;
        final raw = (data is List && data.isNotEmpty) ? data.first : data;
        final userId = (raw is Map) ? raw['userId'] as String? : null;
        if (userId != null && userId == _otherUserId) {
          otherOnline = false;
          notifyListeners();
        }
      });

      _socket!.on('error', (data) {
        debugPrint('Chat error: $data');
      });

      _socket!.connect();
    } catch (e) {
      debugPrint('Chat: Failed to initialize socket: $e');
    }
  }

  void joinBooking(String bookingId) {
    _pendingBookingId = bookingId;
    if (_connected) {
      _socket?.emit('join_booking', bookingId);
    }
    // If not yet connected, onConnect will auto-join using _pendingBookingId
  }

  // Envía siempre por HTTP (confiable), el backend broadcastea via socket al receptor.
  // Devuelve true/false para que la UI pueda avisar al usuario y permitir reintentar
  // en vez de que el mensaje simplemente desaparezca si falla (sin conexión, timeout, etc).
  Future<bool> sendMessage(String bookingId, String message) async {
    if (message.trim().isEmpty) return false;
    blockedError = false;
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/chat/$bookingId/messages'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'message': message.trim()}),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final msg = ChatMessage.fromJson(Map<String, dynamic>.from(data['data'] as Map));
        // Agregar al historial local (el socket también lo recibirá, deduplicamos por id)
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages.add(msg);
          if (!_isDisposed) notifyListeners();
        }
        return true;
      }
      if (response.statusCode == 403 && data['error']?['code'] == 'USER_BLOCKED') {
        blockedError = true;
      }
      return false;
    } catch (e) {
      debugPrint('Chat: Error enviando mensaje: $e');
      return false;
    }
  }

  void markRead(String bookingId) {
    _socket?.emit('mark_read', bookingId);
    _unreadCount = 0;
    notifyListeners();
  }

  Future<void> loadHistory(String bookingId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/chat/$bookingId/messages'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        _messages = (data['data'] as List)
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading chat history: $e');
    }
  }

  Future<int> getUnreadCount() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/chat/unread-count'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        _unreadCount = data['data']['count'] as int? ?? 0;
        notifyListeners();
        return _unreadCount;
      }
    } catch (e) {
      debugPrint('Error getting unread count: $e');
    }
    return 0;
  }

  void clearMessages() {
    _messages = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }
}

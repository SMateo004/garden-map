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
      createdAt: DateTime.parse(json['createdAt'] as String),
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

  List<ChatMessage> get messages => _messages;
  bool get connected => _connected;
  int get unreadCount => _unreadCount;

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
          final msg = ChatMessage.fromJson(Map<String, dynamic>.from(data as Map));
          _messages.add(msg);
          if (msg.senderId != _currentUserId) {
            _unreadCount++;
            LocalNotificationService.show(
              title: msg.senderName,
              body: msg.message,
            );
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

  void sendMessage(String bookingId, String message) {
    if (message.trim().isEmpty) return;
    _socket?.emit('send_message', {
      'bookingId': bookingId,
      'message': message.trim(),
    });
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

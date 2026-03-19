import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

class ChatMessage {
  final String id;
  final String bookingId;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String message;
  final bool read;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.bookingId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.message,
    required this.read,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      bookingId: json['bookingId'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String? ?? 'Usuario',
      senderRole: json['senderRole'] as String? ?? '',
      message: json['message'] as String,
      read: json['read'] as bool? ?? false,
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
    final wsUrl = _baseUrl.replaceAll('/api', '');
    _socket = IO.io(wsUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'token': _token},
    });

    _socket!.onConnect((_) {
      _connected = true;
      debugPrint('Chat: Socket connected');
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      _connected = false;
      debugPrint('Chat: Socket disconnected');
      notifyListeners();
    });

    _socket!.on('new_message', (data) {
      final msg = ChatMessage.fromJson(data as Map<String, dynamic>);
      _messages.add(msg);
      if (msg.senderId != _currentUserId) _unreadCount++;
      notifyListeners();
    });

    _socket!.on('messages_read', (data) {
      _unreadCount = 0;
      notifyListeners();
    });

    _socket!.on('error', (data) {
      debugPrint('Chat error: $data');
    });

    _socket!.connect();
  }

  void joinBooking(String bookingId) {
    _socket?.emit('join_booking', bookingId);
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
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'secure_storage_service.dart';

/// In-app notification polling service for web.
/// On mobile, FCM handles push — this service only activates on kIsWeb.
/// Polls /notifications/my every 20 seconds, shows an overlay toast for each new notification.
class WebNotificationService {
  static final _controller = StreamController<_NotificationItem>.broadcast();
  static Stream<_NotificationItem> get stream => _controller.stream;

  static Timer? _timer;
  static int _lastSeenId = 0; // track highest notification id seen
  static bool _running = false;

  static String get _baseUrl => const String.fromEnvironment(
        'API_URL',
        defaultValue: 'https://api.gardenbo.com/api',
      );

  static void start() {
    if (!kIsWeb || _running) return;
    _running = true;
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _poll());
    _poll(); // immediate first check
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  static Future<void> _poll() async {
    try {
      final token = await SecureStorageService.getAccessToken();
      if (token == null || token.isEmpty) return;

      final res = await http.get(
        Uri.parse('$_baseUrl/notifications/my?limit=5&page=1'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      if (data['success'] != true) return;

      final items = (data['data'] as List?) ?? [];
      if (items.isEmpty) return;

      final newestId = items.first['id'] as int? ?? 0;
      if (newestId <= _lastSeenId) return; // nothing new

      // Emit only truly new (unread) notifications
      for (final item in items) {
        final id = item['id'] as int? ?? 0;
        final isRead = item['isRead'] as bool? ?? true;
        if (id > _lastSeenId && !isRead) {
          _controller.add(_NotificationItem(
            title: item['title'] as String? ?? 'GARDEN',
            body: item['body'] as String? ?? '',
          ));
        }
      }
      _lastSeenId = newestId;
    } catch (_) {
      // Fail silently — polling, not critical path
    }
  }

  /// Reset state on logout so the next user starts fresh.
  static void reset() {
    _lastSeenId = 0;
    stop();
  }
}

class _NotificationItem {
  final String title;
  final String body;
  const _NotificationItem({required this.title, required this.body});
}

/// Mixin for the root app widget to listen and show web toasts.
/// Usage: add [WebNotificationOverlay] above MaterialApp's home.
class WebNotificationOverlay extends StatefulWidget {
  final Widget child;
  const WebNotificationOverlay({super.key, required this.child});

  @override
  State<WebNotificationOverlay> createState() => _WebNotificationOverlayState();
}

class _WebNotificationOverlayState extends State<WebNotificationOverlay> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _sub = WebNotificationService.stream.listen(_showToast);
      WebNotificationService.start();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _showToast(_NotificationItem item) {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _WebToast(
        title: item.title,
        body: item.body,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
    // Auto-dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (entry.mounted) entry.remove();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _WebToast extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onDismiss;
  const _WebToast({required this.title, required this.body, required this.onDismiss});

  @override
  State<_WebToast> createState() => _WebToastState();
}

class _WebToastState extends State<_WebToast> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      right: 16,
      width: 320,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🌿', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(widget.body,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12, height: 1.4),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.5), size: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

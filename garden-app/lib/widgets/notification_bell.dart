import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/garden_theme.dart';

/// Notificación individual tal como la devuelve el backend.
class AppNotification {
  final String id;
  final String title;
  final String message;
  final String type;
  final bool read;
  final String createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        message: j['message'] as String? ?? '',
        type: j['type'] as String? ?? '',
        read: j['read'] as bool? ?? false,
        createdAt: j['createdAt'] as String? ?? '',
      );

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        message: message,
        type: type,
        read: read ?? this.read,
        createdAt: createdAt,
      );
}

// ─────────────────────────────────────────────
// Buzón: botón campana reutilizable
// ─────────────────────────────────────────────

class NotificationBell extends StatefulWidget {
  final String token;
  final String baseUrl;
  /// Si se pasa, se ejecuta cuando cambió el unread count (para que el padre actualice su UI).
  final ValueChanged<int>? onUnreadChanged;

  const NotificationBell({
    super.key,
    required this.token,
    required this.baseUrl,
    this.onUnreadChanged,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.token.isEmpty) return;
    try {
      final resp = await http.get(
        Uri.parse('${widget.baseUrl}/notifications/my'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          final list = (data['data'] as List)
              .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
              .toList();
          if (mounted) {
            setState(() {
              _notifications = list;
              _unreadCount = list.where((n) => !n.read).length;
            });
            widget.onUnreadChanged?.call(_unreadCount);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _markRead(String id) async {
    await http.patch(
      Uri.parse('${widget.baseUrl}/notifications/$id/read'),
      headers: {'Authorization': 'Bearer ${widget.token}'},
    );
    if (mounted) {
      setState(() {
        _notifications = _notifications
            .map((n) => n.id == id ? n.copyWith(read: true) : n)
            .toList();
        _unreadCount = _notifications.where((n) => !n.read).length;
      });
      widget.onUnreadChanged?.call(_unreadCount);
    }
  }

  Future<void> _markAllRead() async {
    await http.patch(
      Uri.parse('${widget.baseUrl}/notifications/read-all'),
      headers: {'Authorization': 'Bearer ${widget.token}'},
    );
    if (mounted) {
      setState(() {
        _notifications = _notifications.map((n) => n.copyWith(read: true)).toList();
        _unreadCount = 0;
      });
      widget.onUnreadChanged?.call(0);
    }
  }

  void _openSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsSheet(
        notifications: _notifications,
        token: widget.token,
        baseUrl: widget.baseUrl,
        onMarkRead: _markRead,
        onMarkAllRead: _markAllRead,
        onRefresh: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final iconColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(Icons.notifications_outlined, color: iconColor),
          tooltip: 'Notificaciones',
          onPressed: _openSheet,
        ),
        if (_unreadCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: Color(0xFFE53935),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _unreadCount > 9 ? '9+' : '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Hoja de buzón (bottom sheet)
// ─────────────────────────────────────────────

class _NotificationsSheet extends StatefulWidget {
  final List<AppNotification> notifications;
  final String token;
  final String baseUrl;
  final Future<void> Function(String id) onMarkRead;
  final Future<void> Function() onMarkAllRead;
  final Future<void> Function() onRefresh;

  const _NotificationsSheet({
    required this.notifications,
    required this.token,
    required this.baseUrl,
    required this.onMarkRead,
    required this.onMarkAllRead,
    required this.onRefresh,
  });

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  late List<AppNotification> _notifs;

  @override
  void initState() {
    super.initState();
    _notifs = List.from(widget.notifications);
  }

  int get _unread => _notifs.where((n) => !n.read).length;

  Future<void> _markRead(String id) async {
    await widget.onMarkRead(id);
    if (mounted) {
      setState(() {
        _notifs = _notifs.map((n) => n.id == id ? n.copyWith(read: true) : n).toList();
      });
    }
  }

  Future<void> _markAll() async {
    await widget.onMarkAllRead();
    if (mounted) {
      setState(() {
        _notifs = _notifs.map((n) => n.copyWith(read: true)).toList();
      });
    }
  }

  void _openDetail(AppNotification notif) {
    if (!notif.read) _markRead(notif.id);
    showDialog(
      context: context,
      builder: (_) => _NotificationDetailDialog(notif: notif),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: GardenColors.primary.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.inbox_outlined, color: GardenColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Buzón',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_unread > 0)
                  TextButton(
                    onPressed: _markAll,
                    child: const Text(
                      'Marcar todo leído',
                      style: TextStyle(
                        color: GardenColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: borderColor),
          // Lista
          Expanded(
            child: _notifs.isEmpty
                ? _EmptyNotifications(textColor: textColor, subtextColor: subtextColor)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _notifs.length,
                    itemBuilder: (ctx, i) {
                      final n = _notifs[i];
                      return _NotificationRow(
                        notif: n,
                        borderColor: borderColor,
                        textColor: textColor,
                        subtextColor: subtextColor,
                        onTap: () => _openDetail(n),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Fila de notificación en la lista
// ─────────────────────────────────────────────

class _NotificationRow extends StatelessWidget {
  final AppNotification notif;
  final Color borderColor;
  final Color textColor;
  final Color subtextColor;
  final VoidCallback onTap;

  const _NotificationRow({
    required this.notif,
    required this.borderColor,
    required this.textColor,
    required this.subtextColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = !notif.read;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUnread
              ? GardenColors.primary.withOpacity(0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUnread
                ? GardenColors.primary.withOpacity(0.22)
                : borderColor,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ícono tipo
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _typeColor(notif.type).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _typeIcon(notif.type),
                color: _typeColor(notif.type),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Contenido
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notif.title,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (isUnread)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: GardenColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notif.message,
                    style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _relativeTime(notif.createdAt),
                    style: TextStyle(
                      color: subtextColor.withOpacity(0.65),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: subtextColor.withOpacity(0.4),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _typeIcon(String type) {
    switch (type) {
      case 'NEW_BOOKING': return Icons.calendar_today_outlined;
      case 'BOOKING_ACCEPTED': return Icons.check_circle_outline_rounded;
      case 'BOOKING_REJECTED': return Icons.cancel_outlined;
      case 'BOOKING_CANCELLED': return Icons.event_busy_outlined;
      case 'PAYMENT_RECEIVED': return Icons.payments_outlined;
      case 'REVIEW_RECEIVED': return Icons.star_outline_rounded;
      case 'SERVICE_STARTED': return Icons.play_circle_outline_rounded;
      case 'SERVICE_COMPLETED': return Icons.task_alt_rounded;
      case 'CHAT_MESSAGE': return Icons.chat_bubble_outline_rounded;
      case 'SYSTEM': return Icons.info_outline_rounded;
      case 'PROFILE_APPROVED': return Icons.verified_outlined;
      case 'PROFILE_REJECTED': return Icons.gpp_bad_outlined;
      case 'WALLET_RECHARGE': return Icons.account_balance_wallet_outlined;
      case 'DISPUTE': return Icons.gavel_rounded;
      default: return Icons.notifications_outlined;
    }
  }

  static Color _typeColor(String type) {
    switch (type) {
      case 'NEW_BOOKING': return GardenColors.primary;
      case 'BOOKING_ACCEPTED': return GardenColors.success;
      case 'BOOKING_REJECTED': return GardenColors.error;
      case 'BOOKING_CANCELLED': return GardenColors.warning;
      case 'PAYMENT_RECEIVED': return GardenColors.accent;
      case 'REVIEW_RECEIVED': return const Color(0xFFFFB300);
      case 'SERVICE_STARTED': return GardenColors.accent;
      case 'SERVICE_COMPLETED': return GardenColors.success;
      case 'CHAT_MESSAGE': return GardenColors.primary;
      case 'SYSTEM': return GardenColors.lightTextSecondary;
      case 'PROFILE_APPROVED': return GardenColors.success;
      case 'PROFILE_REJECTED': return GardenColors.error;
      case 'WALLET_RECHARGE': return GardenColors.accent;
      case 'DISPUTE': return GardenColors.warning;
      default: return GardenColors.primary;
    }
  }

  static String _relativeTime(String isoString) {
    if (isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return 'Ahora mismo';
      if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
      if (diff.inDays == 1) return 'Ayer';
      if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }
}

// ─────────────────────────────────────────────
// Diálogo de detalle de notificación
// ─────────────────────────────────────────────

class _NotificationDetailDialog extends StatelessWidget {
  final AppNotification notif;

  const _NotificationDetailDialog({required this.notif});

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final iconColor = _NotificationRow._typeColor(notif.type);
    final iconData = _NotificationRow._typeIcon(notif.type);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassBox(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabecera con color de tipo
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(iconData, color: iconColor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      notif.title,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Cuerpo del mensaje
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                notif.message,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            ),
            // Timestamp
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _formatFull(notif.createdAt),
                  style: TextStyle(
                    color: subtextColor.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
            // Botón cerrar
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GardenColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatFull(String isoString) {
    if (isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      const months = [
        '', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
        'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
      ];
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} de ${months[dt.month]} de ${dt.year}, $h:$m';
    } catch (_) {
      return '';
    }
  }
}

// ─────────────────────────────────────────────
// Estado vacío
// ─────────────────────────────────────────────

class _EmptyNotifications extends StatelessWidget {
  final Color textColor;
  final Color subtextColor;

  const _EmptyNotifications({required this.textColor, required this.subtextColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: GardenColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 36,
                color: GardenColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Todo tranquilo por aquí',
              style: TextStyle(
                color: textColor,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Cuando recibas mensajes o actualizaciones de tus reservas, aparecerán aquí.',
              style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

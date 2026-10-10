import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../design/garden_depth.dart';
import '../design/garden_icons.dart';
import '../design/garden_wallet.dart' show GardenFilterPills;
import '../narrative/booking_story.dart';
import '../narrative/notification_kind.dart';
import '../services/auth_state.dart';
import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_empty_state.dart';

/// Notificación individual tal como la devuelve el backend.
class AppNotification {
  final String id;
  final String title;
  final String message;
  final String type;
  final bool read;
  final String createdAt;

  /// Reserva a la que se refiere (null en avisos de cuenta, retiros,
  /// anuncios y en las notificaciones anteriores al 7 de octubre de 2026).
  final String? bookingId;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.read,
    required this.createdAt,
    this.bookingId,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        message: j['message'] as String? ?? '',
        type: j['type'] as String? ?? '',
        read: j['read'] as bool? ?? false,
        createdAt: j['createdAt'] as String? ?? '',
        bookingId: j['bookingId'] as String?,
      );

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        message: message,
        type: type,
        read: read ?? this.read,
        createdAt: createdAt,
        bookingId: bookingId,
      );
}

/// A dónde lleva una notificación según su tema y quién la mira. Desde el 7
/// de octubre de 2026 traen la reserva (Notification.bookingId): lo del
/// servicio abre ese servicio y lo de reservas resalta esa reserva en la
/// lista. Las anteriores, sin reserva, llevan a la lista.
({String label, String route, Map<String, dynamic>? extra, String? highlight})? notificationDestination(
  String type, {
  String? bookingId,
}) {
  final kind = NotificationKind.of(type);
  final role = AuthState.effectiveRole;
  final staff = AuthState.isCaregiverStaff;
  if (role == 'ADMIN' && (kind.topic == NotificationTopic.problem || kind.topic == NotificationTopic.account)) {
    return (label: 'Abrir panel admin', route: '/admin', extra: null, highlight: null);
  }
  // Mensaje del chat: abre esa conversación (el nombre lo trae el chat).
  if (bookingId != null && kind.topic == NotificationTopic.chat) {
    return (
      label: 'Abrir el chat',
      route: '/chat/$bookingId',
      extra: {'role': role == 'CAREGIVER' ? 'CAREGIVER' : 'CLIENT'},
      highlight: null,
    );
  }
  // Servicio en curso o recién terminado: directo a esa reserva.
  if (bookingId != null && kind.topic == NotificationTopic.service && !staff) {
    return (
      label: 'Ver el servicio',
      route: '/service/$bookingId',
      extra: {'role': role == 'CAREGIVER' ? 'CAREGIVER' : 'CLIENT', 'token': AuthState.token},
      highlight: null,
    );
  }
  String bookings() => role == 'CAREGIVER'
      ? (staff ? '/caregiver-staff/home' : '/caregiver/home?tab=reservas')
      : '/my-bookings';
  switch (type) {
    case 'CAREGIVER_WELCOME':
      return (label: 'Ver la guía del cuidador', route: '/guia-cuidador', extra: null, highlight: null);
    case 'TRAINING_REMINDER':
      return (label: 'Ir a capacitaciones', route: '/caregiver/trainings', extra: null, highlight: null);
    case 'ZONE_NOW_AVAILABLE':
      return (label: 'Buscar cuidadores', route: '/marketplace', extra: null, highlight: null);
  }
  switch (kind.topic) {
    case NotificationTopic.booking:
    case NotificationTopic.service:
    case NotificationTopic.problem:
      // El dueño ve esa reserva resaltada en la lista (mismo mecanismo que
      // usa el pago al terminar: highlight_booking_id).
      final ownerList = role != 'CAREGIVER';
      return (
        label: bookingId != null && ownerList ? 'Ver la reserva' : 'Ver mis reservas',
        route: bookings(),
        extra: null,
        highlight: ownerList ? bookingId : null,
      );
    case NotificationTopic.money:
      return staff ? null : (label: 'Ir a mi billetera', route: '/wallet', extra: null, highlight: null);
    case NotificationTopic.review:
    case NotificationTopic.chat:
    case NotificationTopic.account:
    case NotificationTopic.news:
      return null;
  }
}

// ─────────────────────────────────────────────
// Campana con contador
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
  /// La hoja abierta escucha esto: si llega algo nuevo mientras está abierta,
  /// aparece (antes la hoja mostraba una copia fija del momento de abrirla).
  final _items = ValueNotifier<List<AppNotification>>(const []);
  Timer? _timer;

  int get _unread => _items.value.where((n) => !n.read).length;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _items.dispose();
    super.dispose();
  }

  void _set(List<AppNotification> list) {
    final before = _unread;
    _items.value = list;
    if (mounted) setState(() {});
    if (before != _unread) widget.onUnreadChanged?.call(_unread);
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
        if (data['success'] == true && mounted) {
          _set((data['data'] as List).map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList());
          widget.onUnreadChanged?.call(_unread);
        }
      }
    } catch (_) {}
  }

  /// Se marca al instante; si el servidor falla, se recarga lo real (antes
  /// un error de red al marcar tiraba una excepción sin manejar).
  Future<void> _markRead(String id) async {
    _set(_items.value.map((n) => n.id == id ? n.copyWith(read: true) : n).toList());
    try {
      final r = await http.patch(
        Uri.parse('${widget.baseUrl}/notifications/$id/read'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (r.statusCode != 200) unawaited(_load());
    } catch (_) {
      unawaited(_load());
    }
  }

  Future<void> _markAllRead() async {
    _set(_items.value.map((n) => n.copyWith(read: true)).toList());
    try {
      final r = await http.patch(
        Uri.parse('${widget.baseUrl}/notifications/read-all'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (r.statusCode != 200) unawaited(_load());
    } catch (_) {
      unawaited(_load());
    }
  }

  void _openSheet() {
    HapticFeedback.selectionClick();
    _load();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsSheet(
        items: _items,
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
    final unread = _unread;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: GardenIcon(GIcon.notificaciones,
              color: unread > 0 ? (isDark ? GardenColors.primaryLight : GardenColors.primary) : iconColor,
              state: unread > 0 ? GIconState.active : GIconState.idle,
              size: GIconSize.lg),
          tooltip: unread > 0 ? 'Notificaciones ($unread sin leer)' : 'Notificaciones',
          onPressed: _openSheet,
        ),
        if (unread > 0)
          Positioned(
            right: 4,
            top: 4,
            child: IgnorePointer(
              // Aparece con un pequeño salto cuando cambia el número.
              child: TweenAnimationBuilder<double>(
                key: ValueKey(unread),
                tween: Tween(begin: 0.6, end: 1),
                duration: GardenMotion.resolve(context, GardenMotion.standard),
                curve: GardenMotion.pop,
                builder: (_, s, child) => Transform.scale(scale: s, child: child),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: GardenColors.error,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, height: 1),
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
// Hoja de notificaciones
// ─────────────────────────────────────────────

class _NotificationsSheet extends StatefulWidget {
  final ValueNotifier<List<AppNotification>> items;
  final Future<void> Function(String id) onMarkRead;
  final Future<void> Function() onMarkAllRead;
  final Future<void> Function() onRefresh;

  const _NotificationsSheet({
    required this.items,
    required this.onMarkRead,
    required this.onMarkAllRead,
    required this.onRefresh,
  });

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  bool _onlyUnread = false;
  String? _expanded;

  void _tap(AppNotification n) {
    HapticFeedback.selectionClick();
    if (!n.read) widget.onMarkRead(n.id);
    setState(() => _expanded = _expanded == n.id ? null : n.id);
  }

  Future<void> _go(({String label, String route, Map<String, dynamic>? extra, String? highlight}) dest) async {
    if (dest.highlight != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('highlight_booking_id', dest.highlight!);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    context.push(dest.route, extra: dest.extra);
  }

  /// Hoy / Ayer / Esta semana / Antes.
  static String _group(DateTime? d, DateTime now) {
    if (d == null) return 'Antes';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    if (diff < 7) return 'Esta semana';
    return 'Antes';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, -4))],
      ),
      child: ValueListenableBuilder<List<AppNotification>>(
        valueListenable: widget.items,
        builder: (context, all, _) {
          final unread = all.where((n) => !n.read).length;
          final list = _onlyUnread ? all.where((n) => !n.read || n.id == _expanded).toList() : all;
          final now = DateTime.now();
          final rows = <Widget>[];
          String? last;
          for (final n in list) {
            final g = _group(DateTime.tryParse(n.createdAt)?.toLocal(), now);
            if (g != last) {
              rows.add(Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Text(g.toUpperCase(),
                    style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9)),
              ));
              last = g;
            }
            final dest = notificationDestination(n.type, bookingId: n.bookingId);
            rows.add(_NotificationRow(
              notif: n,
              expanded: _expanded == n.id,
              onTap: () => _tap(n),
              actionLabel: dest?.label,
              onAction: dest == null ? null : () => _go(dest),
            ));
          }

          return Column(children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Notificaciones', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(unread == 0 ? 'Estás al día' : unread == 1 ? '1 sin leer' : '$unread sin leer',
                        style: TextStyle(color: subtextColor, fontSize: 13)),
                  ]),
                ),
                if (unread > 0)
                  TextButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      widget.onMarkAllRead();
                    },
                    child: Text('Marcar todo como leído',
                        style: TextStyle(
                            color: isDark ? GardenColors.primaryLight : GardenColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
            if (all.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GardenFilterPills<bool>(
                    options: [(false, 'Todas'), (true, unread > 0 ? 'Sin leer ($unread)' : 'Sin leer')],
                    selected: _onlyUnread,
                    onSelect: (v) => setState(() => _onlyUnread = v),
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                color: GardenColors.primary,
                onRefresh: widget.onRefresh,
                child: list.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 40),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: _onlyUnread
                              ? const GardenEmptyState(
                                  type: GardenEmptyType.notifications,
                                  compact: true,
                                  title: 'Leíste todo',
                                  subtitle: 'No tienes notificaciones sin leer.',
                                )
                              : const GardenEmptyState(
                                  type: GardenEmptyType.notifications,
                                  title: 'Todo tranquilo por aquí',
                                  subtitle: 'Cuando haya novedades de tus reservas, pagos o mensajes, aparecerán aquí.',
                                ),
                        ),
                      ])
                    : ListView(padding: const EdgeInsets.only(bottom: 24), children: rows),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Fila: se abre ahí mismo con el texto completo y a dónde ir
// ─────────────────────────────────────────────

class _NotificationRow extends StatelessWidget {
  final AppNotification notif;
  final bool expanded;
  final VoidCallback onTap;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _NotificationRow({
    required this.notif,
    required this.expanded,
    required this.onTap,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final kind = NotificationKind.of(notif.type);
    final colors = StoryColors.of(kind.tone, isDark: isDark);
    final unread = !notif.read;
    final date = DateTime.tryParse(notif.createdAt)?.toLocal();
    final d = GardenMotion.resolve(context, GardenMotion.standard);

    return Semantics(
      button: true,
      expanded: expanded,
      label: '${unread ? 'Sin leer. ' : ''}${NotificationKind.clean(notif.title)}',
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: d,
          curve: GardenMotion.enter,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.fromLTRB(10, 12, 12, 12),
          decoration: BoxDecoration(
            color: unread
                ? (isDark ? GardenColors.primary.withValues(alpha: 0.14) : GardenColors.primary.withValues(alpha: 0.06))
                : expanded
                    ? (isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GardenClay(
              size: 42,
              circle: false,
              radius: 13,
              interactive: false,
              tint: colors.ink.withValues(alpha: 0.14),
              child: GardenIcon(kind.icon, color: colors.ink, state: GIconState.active),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(
                      NotificationKind.clean(notif.title),
                      style: TextStyle(
                          color: text, fontWeight: unread ? FontWeight.w800 : FontWeight.w600, fontSize: 14, height: 1.3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_relativeTime(date), style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w600)),
                  if (unread) ...[
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                AnimatedSize(
                  duration: d,
                  curve: GardenMotion.enter,
                  alignment: Alignment.topCenter,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      NotificationKind.clean(notif.message),
                      style: TextStyle(color: expanded ? text : sub, fontSize: 13, height: 1.45),
                      maxLines: expanded ? null : 2,
                      overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    ),
                    if (expanded) ...[
                      if (date != null) ...[
                        const SizedBox(height: 8),
                        Text(_fullDate(date), style: TextStyle(color: sub, fontSize: 12)),
                      ],
                      if (onAction != null) ...[
                        const SizedBox(height: 12),
                        GardenButton(label: actionLabel!, height: 44, onPressed: onAction),
                      ],
                    ],
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  static String _relativeTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays == 1) return 'ayer';
    if (diff.inDays < 7) return '${diff.inDays} d';
    const m = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${dt.day} ${m[dt.month - 1]}';
  }

  static String _fullDate(DateTime dt) {
    const months = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} de ${months[dt.month - 1]} de ${dt.year}, $h:$m';
  }
}

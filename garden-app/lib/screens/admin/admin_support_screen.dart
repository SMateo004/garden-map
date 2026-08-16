import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Panel admin: chat de soporte — inbox estilo WhatsApp. Lista de
/// conversaciones a la izquierda (todas persistentes, ver comentario en
/// prisma/schema.prisma sobre SupportThread), detalle con historial COMPLETO
/// a la derecha (a diferencia del cliente, que solo ve su sesión actual).
class AdminSupportScreen extends StatefulWidget {
  final String adminToken;
  const AdminSupportScreen({super.key, required this.adminToken});

  @override
  State<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends State<AdminSupportScreen> {
  List<Map<String, dynamic>> _threads = [];
  bool _loadingThreads = true;
  String? _selectedThreadId;
  IO.Socket? _socket;
  // Empuja el mensaje entrante a la conversación abierta (ver _ThreadDetail) —
  // sin esto, support_new_message solo refrescaba la lista de la izquierda y
  // el admin tenía que cerrar/reabrir el hilo (o recargar la página entera)
  // para ver el mensaje nuevo mientras lo estaba mirando.
  final ValueNotifier<Map<String, dynamic>?> _incomingMessage = ValueNotifier(null);

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _loadThreads();
    _connectSocket();
  }

  void _connectSocket() {
    try {
      final wsUrl = _baseUrl.replaceAll('/api', '');
      _socket = IO.io(wsUrl, <String, dynamic>{
        'transports': ['polling', 'websocket'],
        'autoConnect': false,
        'auth': {'token': widget.adminToken},
        'reconnection': true,
        'reconnectionDelay': 2000,
      });
      // Un cliente nuevo escribió — refrescar la lista para que aparezca
      // arriba con su preview, sin que el admin tenga que recargar la página.
      _socket!.on('support_new_message', (data) {
        _loadThreads(silent: true);
        final raw = (data is List && data.isNotEmpty) ? data.first : data;
        if (raw is Map) _incomingMessage.value = Map<String, dynamic>.from(raw);
      });
      _socket!.on('support_thread_updated', (_) => _loadThreads(silent: true));
      _socket!.connect();
    } catch (e) {
      debugPrint('AdminSupport: socket error: $e');
    }
  }

  Future<void> _loadThreads({bool silent = false}) async {
    if (!silent) setState(() => _loadingThreads = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/support/threads'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() => _threads = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (e) {
      debugPrint('AdminSupport: error cargando threads: $e');
    } finally {
      if (mounted) setState(() => _loadingThreads = false);
    }
  }

  void _selectThread(String threadId) {
    setState(() => _selectedThreadId = threadId);
    // Optimista: apaga el punto de "no leído" apenas se abre, sin esperar la
    // confirmación del servidor — si falla, el próximo _loadThreads lo corrige.
    setState(() {
      final idx = _threads.indexWhere((t) => t['threadId'] == threadId);
      if (idx != -1) _threads[idx]['unreadByAdmin'] = false;
    });
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _incomingMessage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : Colors.white;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtext = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final matches = _threads.where((t) => t['threadId'] == _selectedThreadId);
    final selected = matches.isEmpty ? null : matches.first;

    return Row(
      children: [
        // ── Lista de conversaciones (estilo WhatsApp) ──────────────────────
        Container(
          width: 320,
          decoration: BoxDecoration(border: Border(right: BorderSide(color: border))),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text('Soporte', style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    IconButton(icon: Icon(Icons.refresh_rounded, color: subtext), onPressed: () => _loadThreads()),
                  ],
                ),
              ),
              Expanded(
                child: _loadingThreads
                    ? const Center(child: GardenLoadingIndicator())
                    : _threads.isEmpty
                        ? Center(
                            child: Text('Sin conversaciones todavía', style: TextStyle(color: subtext, fontSize: 13)),
                          )
                        : ListView.builder(
                            itemCount: _threads.length,
                            itemBuilder: (_, i) {
                              final t = _threads[i];
                              final isSelected = t['threadId'] == _selectedThreadId;
                              final unread = t['unreadByAdmin'] == true;
                              return Material(
                                color: isSelected ? GardenColors.primary.withValues(alpha: 0.08) : Colors.transparent,
                                child: InkWell(
                                  onTap: () => _selectThread(t['threadId'] as String),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        GardenAvatar(imageUrl: t['clientPhoto'] as String?, size: 42),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      t['clientName'] as String? ?? 'Cliente',
                                                      style: TextStyle(color: text, fontSize: 14, fontWeight: unread ? FontWeight.w800 : FontWeight.w600),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (unread)
                                                    Container(
                                                      width: 9,
                                                      height: 9,
                                                      margin: const EdgeInsets.only(left: 6),
                                                      decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                t['lastMessagePreview'] as String? ?? '',
                                                style: TextStyle(color: subtext, fontSize: 12.5),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                              const SizedBox(height: 4),
                                              _StatusChip(status: t['status'] as String? ?? 'BOT'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
        // ── Detalle del hilo seleccionado ───────────────────────────────────
        Expanded(
          child: selected == null
              ? Center(
                  child: Text('Elegí una conversación', style: TextStyle(color: subtext, fontSize: 14)),
                )
              : _ThreadDetail(
                  key: ValueKey(_selectedThreadId),
                  threadId: _selectedThreadId!,
                  clientName: selected['clientName'] as String? ?? 'Cliente',
                  clientPhoto: selected['clientPhoto'] as String?,
                  adminToken: widget.adminToken,
                  baseUrl: _baseUrl,
                  onSent: () => _loadThreads(silent: true),
                  incomingMessage: _incomingMessage,
                ),
        ),
      ],
    );
  }
}

/// Chip de estado del hilo — mismo vocabulario en toda la pantalla: bot
/// atendiendo solo, necesita a un asesor, o ya se cerró el caso.
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'ESCALATED' => ('🧑‍💼 Necesita atención', const Color(0xFFE58A00)),
      'RESOLVED' => ('✅ Resuelto', GardenColors.success),
      _ => ('🌿 Bot atendiendo', GardenColors.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
    );
  }
}

class _ThreadDetail extends StatefulWidget {
  final String threadId;
  final String clientName;
  final String? clientPhoto;
  final String adminToken;
  final String baseUrl;
  final VoidCallback onSent;
  final ValueNotifier<Map<String, dynamic>?> incomingMessage;

  const _ThreadDetail({
    super.key,
    required this.threadId,
    required this.clientName,
    required this.clientPhoto,
    required this.adminToken,
    required this.baseUrl,
    required this.onSent,
    required this.incomingMessage,
  });

  @override
  State<_ThreadDetail> createState() => _ThreadDetailState();
}

class _ThreadDetailState extends State<_ThreadDetail> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _resolving = false;
  String _status = 'BOT';
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    widget.incomingMessage.addListener(_onIncomingMessage);
  }

  void _onIncomingMessage() {
    final data = widget.incomingMessage.value;
    if (data == null || data['threadId'] != widget.threadId) return;
    setState(() => _messages.add({
          'id': 'live_${DateTime.now().microsecondsSinceEpoch}',
          'senderRole': 'CLIENT',
          'message': data['message'],
          'createdAt': data['createdAt'],
        }));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    // El admin ya está mirando este hilo — marcarlo leído sin esperar a que
    // vuelva a abrirlo.
    http.post(
      Uri.parse('${widget.baseUrl}/admin/support/threads/${widget.threadId}/read'),
      headers: {'Authorization': 'Bearer ${widget.adminToken}'},
    ).catchError((_) => http.Response('', 500));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/admin/support/threads/${widget.threadId}/messages'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() {
          _messages = (data['data']['messages'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _status = data['data']['status'] as String? ?? 'BOT';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
      // Marcar como leído — no bloquea la UI si falla.
      http.post(
        Uri.parse('${widget.baseUrl}/admin/support/threads/${widget.threadId}/read'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      ).catchError((_) => http.Response('', 500));
    } catch (e) {
      debugPrint('AdminSupport: error cargando historial: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/admin/support/threads/${widget.threadId}/reply'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}', 'Content-Type': 'application/json'},
        body: jsonEncode({'message': text}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        _controller.clear();
        setState(() {
          _messages.add({
            'id': data['data']['id'],
            'senderRole': 'ADMIN',
            'message': text,
            'createdAt': data['data']['createdAt'],
          });
          // El backend escala a ESCALATED en cuanto un admin responde (salvo
          // que ya esté RESOLVED) — sin esto, si el admin le escribe a un
          // hilo que seguía en 'BOT' (todavía no había escalado), el chip
          // se quedaba mostrando "Bot atendiendo" hasta el próximo refresh.
          if (_status != 'RESOLVED') _status = 'ESCALATED';
        });
        widget.onSent();
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      } else if (mounted) {
        GardenErrorDialog.show(context, data['error']?['message'] ?? 'No se pudo enviar la respuesta');
      }
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, 'Error de conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Cierra el caso — recién acá el cliente "empieza de cero" en su próximo
  /// mensaje. Hasta entonces, aunque el admin no toque nada más, la
  /// conversación sigue completa y visible de su lado (puede haber
  /// diligencias pendientes).
  Future<void> _resolve() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Marcar como resuelto?'),
        content: const Text('El cliente va a ver esta conversación completa hasta que la resuelvas. Después de esto, su próximo mensaje empieza un caso nuevo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Marcar como resuelto')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _resolving = true);
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/admin/support/threads/${widget.threadId}/resolve'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => _status = 'RESOLVED');
        widget.onSent();
      } else if (mounted) {
        GardenErrorDialog.show(context, 'No se pudo marcar como resuelto. Intenta de nuevo.');
      }
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, 'Error de conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  void dispose() {
    widget.incomingMessage.removeListener(_onIncomingMessage);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : const Color(0xFFF7F9F4);
    final surface = isDark ? GardenColors.darkSurface : Colors.white;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtext = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Container(
      color: bg,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: surface, border: Border(bottom: BorderSide(color: border))),
            child: Row(
              children: [
                GardenAvatar(imageUrl: widget.clientPhoto, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.clientName, style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      _StatusChip(status: _status),
                    ],
                  ),
                ),
                if (_status != 'RESOLVED')
                  TextButton.icon(
                    onPressed: _resolving ? null : _resolve,
                    icon: _resolving
                        ? const SizedBox(width: 14, height: 14, child: GardenLoadingIndicator(size: 14))
                        : const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: const Text('Marcar resuelto', style: TextStyle(fontSize: 12.5)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: GardenLoadingIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final role = m['senderRole'] as String? ?? 'CLIENT';
                      final isAdmin = role == 'ADMIN';
                      final isBot = role == 'BOT';
                      final aligned = isAdmin || isBot; // "nuestro lado" de la conversación
                      final createdAt = DateTime.tryParse(m['createdAt'] as String? ?? '')?.toLocal();
                      final hh = createdAt == null ? '' : '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
                      final label = isBot ? '🌿 Asistente' : isAdmin ? '🧑‍💼 Vos' : null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: aligned ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (label != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(label, style: TextStyle(color: subtext, fontSize: 10.5, fontWeight: FontWeight.w700)),
                              ),
                            Row(
                              mainAxisAlignment: aligned ? MainAxisAlignment.end : MainAxisAlignment.start,
                              children: [
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isAdmin ? GardenColors.primary : (isBot ? GardenColors.primary.withValues(alpha: 0.55) : surface),
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(18),
                                        topRight: const Radius.circular(18),
                                        bottomLeft: Radius.circular(aligned ? 18 : 4),
                                        bottomRight: Radius.circular(aligned ? 4 : 18),
                                      ),
                                      border: aligned ? null : Border.all(color: border),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(m['message'] as String? ?? '', style: TextStyle(color: aligned ? Colors.white : text, fontSize: 14, height: 1.35)),
                                        const SizedBox(height: 3),
                                        Text(hh, style: TextStyle(color: aligned ? Colors.white70 : text.withValues(alpha: 0.45), fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: surface, border: Border(top: BorderSide(color: border))),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    style: TextStyle(color: text, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Responder…',
                      hintStyle: TextStyle(color: subtext, fontSize: 14),
                      filled: true,
                      fillColor: isDark ? GardenColors.darkBackground : const Color(0xFFF2F5EE),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: GardenColors.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _sending ? null : _send,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: _sending
                          ? const SizedBox(width: 20, height: 20, child: GardenLoadingIndicator(size: 20, color: Colors.white))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/chat_service.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_empty_state.dart';

class ChatScreen extends StatefulWidget {
  final String bookingId;
  final String otherPersonName;
  final String? otherPersonPhoto;
  final String? token;
  final String? meetAndGreetNote;
  final String? role; // 'CLIENT' | 'CAREGIVER'
  final String? bookingStatus;

  const ChatScreen({
    super.key,
    required this.bookingId,
    required this.otherPersonName,
    this.otherPersonPhoto,
    this.token,
    this.meetAndGreetNote,
    this.role,
    this.bookingStatus,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  ChatService? _chatService;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  String _currentUserId = '';
  String _token = '';
  bool _initialized = false;
  Map<String, dynamic>? _mg;
  bool _mgLoading = false;

  String get _baseUrl => const String.fromEnvironment(
    'API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token') ?? '';
    _currentUserId = prefs.getString('user_id') ?? '';

    // Fallback: usar token pasado por el caller si SharedPreferences está vacío
    if (_token.isEmpty && widget.token != null && widget.token!.isNotEmpty) {
      _token = widget.token!;
    }

    if (!mounted) return;

    _chatService = ChatService(
      baseUrl: _baseUrl,
      token: _token,
      currentUserId: _currentUserId,
    );

    _chatService!.addListener(_onChatUpdate);

    // Conectar y unirse a la sala ANTES de cargar historial para no perder mensajes
    _chatService!.joinBooking(widget.bookingId); // se auto-une cuando conecte
    _chatService!.connect();

    await _chatService!.loadHistory(widget.bookingId);
    await _loadMG();

    if (!mounted) return;

    _chatService!.markRead(widget.bookingId);
    setState(() => _initialized = true);
    _scrollToBottom();
  }

  Future<void> _loadMG() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/meet-and-greet/${widget.bookingId}'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      if (mounted && data['success'] == true) {
        setState(() => _mg = data['data'] as Map<String, dynamic>?);
      }
    } catch (_) {}
  }

  Future<void> _acceptMG() async {
    setState(() => _mgLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/meet-and-greet/${widget.bookingId}/accept'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
      );
      final data = jsonDecode(response.body);
      if (mounted) {
        if (data['success'] == true) {
          await _loadMG();
          await _chatService!.loadHistory(widget.bookingId);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Error'), backgroundColor: Colors.red.shade700),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _mgLoading = false);
    }
  }

  Future<void> _proposeMG({Map<String, dynamic>? prefill}) async {
    final isDark = themeNotifier.isDark;
    DateTime? selectedDate = prefill != null ? DateTime.tryParse(prefill['proposedDate'] ?? '') : null;
    final timeCtrl = TextEditingController(
      text: prefill != null && prefill['proposedDate'] != null
          ? (prefill['proposedDate'] as String).split('T').elementAtOrNull(1)?.substring(0, 5) ?? ''
          : '',
    );
    final placeCtrl = TextEditingController(text: prefill?['meetingPoint'] ?? '');
    String modalidad = prefill?['modalidad'] ?? 'IN_PERSON';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
          final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
          final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
          final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(
                    color: borderColor, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text('Proponer Meet & Greet', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  // Modalidad toggle
                  Row(
                    children: [
                      Expanded(child: _sheetToggleBtn('Presencial', modalidad == 'IN_PERSON', () => setSheet(() => modalidad = 'IN_PERSON'))),
                      const SizedBox(width: 8),
                      Expanded(child: _sheetToggleBtn('Videollamada', modalidad == 'VIDEO_CALL', () => setSheet(() => modalidad = 'VIDEO_CALL'))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Date
                  GestureDetector(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate ?? now.add(const Duration(days: 1)),
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 60)),
                        builder: (c, child) => Theme(
                          data: Theme.of(c).copyWith(colorScheme: const ColorScheme.dark(primary: GardenColors.primary)),
                          child: child!,
                        ),
                      );
                      if (picked != null) setSheet(() => selectedDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Icon(Icons.calendar_today, size: 16, color: GardenColors.primary),
                        const SizedBox(width: 10),
                        Text(
                          selectedDate != null ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}' : 'Seleccionar fecha',
                          style: TextStyle(color: selectedDate != null ? textColor : subtextColor, fontSize: 14),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: timeCtrl,
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Hora (ej: 15:00)',
                      hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                      prefixIcon: Icon(Icons.access_time, color: GardenColors.primary, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: placeCtrl,
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Punto de encuentro',
                      hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                      prefixIcon: Icon(Icons.location_on, color: GardenColors.primary, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GardenColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        if (selectedDate == null || placeCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Completa fecha y lugar'), backgroundColor: Colors.orange),
                          );
                          return;
                        }
                        final timeStr = timeCtrl.text.trim().isNotEmpty ? timeCtrl.text.trim() : '10:00';
                        final dateStr = selectedDate!.toIso8601String().split('T')[0];
                        Navigator.pop(ctx);
                        setState(() => _mgLoading = true);
                        try {
                          final res = await http.post(
                            Uri.parse('$_baseUrl/meet-and-greet/${widget.bookingId}/propose'),
                            headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
                            body: jsonEncode({
                              'modalidad': modalidad,
                              'proposedDate': '${dateStr}T$timeStr:00',
                              'meetingPoint': placeCtrl.text.trim(),
                            }),
                          );
                          final d = jsonDecode(res.body);
                          if (mounted) {
                            if (d['success'] == true) {
                              await _loadMG();
                              await _chatService!.loadHistory(widget.bookingId);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(d['message'] ?? 'Error'), backgroundColor: Colors.red.shade700),
                              );
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade700),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _mgLoading = false);
                        }
                      },
                      child: const Text('Enviar propuesta', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    timeCtrl.dispose();
    placeCtrl.dispose();
  }

  Widget _sheetToggleBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? GardenColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? GardenColors.primary : GardenColors.darkBorder),
        ),
        child: Center(child: Text(label, style: TextStyle(color: active ? Colors.white : GardenColors.darkTextSecondary, fontWeight: FontWeight.w600, fontSize: 13))),
      ),
    );
  }

  void _onChatUpdate() {
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear(); // Limpiar inmediatamente para mejor UX
    _chatService?.sendMessage(widget.bookingId, text);
  }

  @override
  void dispose() {
    _chatService?.removeListener(_onChatUpdate);
    _chatService?.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: surface,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: textColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                GardenAvatar(
                  imageUrl: widget.otherPersonPhoto,
                  size: 36,
                  initials: widget.otherPersonName.isNotEmpty
                    ? widget.otherPersonName[0] : 'U',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.otherPersonName,
                        style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                      Row(
                        children: [
                          Container(
                            width: 7, height: 7,
                            decoration: BoxDecoration(
                              color: !_initialized
                                  ? subtextColor
                                  : (_chatService?.connected ?? false)
                                      ? GardenColors.success
                                      : GardenColors.warning,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            !_initialized
                                ? 'Cargando...'
                                : (_chatService?.connected ?? false)
                                    ? 'En línea'
                                    : 'Disponible',
                            style: TextStyle(color: subtextColor, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: !_initialized
            ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
            : Column(
                children: [
                  // Banner Meet & Greet (cuando está ACCEPTED)
                  if (widget.meetAndGreetNote != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: GardenColors.success.withValues(alpha: 0.1),
                        border: Border(bottom: BorderSide(color: GardenColors.success.withValues(alpha: 0.25))),
                      ),
                      child: Row(
                        children: [
                          const Text('🤝', style: TextStyle(fontSize: 15)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.meetAndGreetNote!,
                              style: const TextStyle(color: GardenColors.success, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Lista de mensajes
                  Expanded(
                    child: (_chatService?.messages ?? []).isEmpty
                      ? GardenEmptyState(
                          type: GardenEmptyType.chat,
                          title: 'Empieza la conversación',
                          subtitle: 'Envía un mensaje a ${widget.otherPersonName} para coordinar el servicio.',
                          compact: true,
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: _chatService!.messages.length,
                          itemBuilder: (context, index) {
                            final msg = _chatService!.messages[index];
                            final isMe = msg.senderId == _currentUserId;
                            return _buildMessageBubble(msg, isMe, textColor, subtextColor);
                          },
                        ),
                  ),
                  // Proponer M&G button (caregiver only, when no active M&G)
                  if (widget.role == 'CAREGIVER' &&
                      (widget.bookingStatus == 'WAITING_CAREGIVER_APPROVAL' || widget.bookingStatus == 'CONFIRMED') &&
                      (_mg == null || _mg!['status'] == 'CANCELLED'))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _mgLoading ? null : () => _proposeMG(),
                          icon: const Icon(Icons.handshake_outlined, size: 16),
                          label: const Text('Proponer Meet & Greet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GardenColors.primary,
                            side: const BorderSide(color: GardenColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ),
                  // Input de mensaje
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    decoration: BoxDecoration(
                      color: surface,
                      border: Border(top: BorderSide(color: borderColor)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            style: TextStyle(color: textColor),
                            maxLines: 3,
                            minLines: 1,
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: InputDecoration(
                              hintText: 'Escribe un mensaje...',
                              hintStyle: TextStyle(color: subtextColor),
                              filled: true,
                              fillColor: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _sendMessage,
                          child: Container(
                            width: 46, height: 46,
                            decoration: const BoxDecoration(
                              color: GardenColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        );
      },
    );
  }

  Widget _buildMGProposalCard(ChatMessage msg, Color textColor, Color subtextColor) {
    final isDark = themeNotifier.isDark;
    final lines = msg.message.split('\n');
    // Parse lines: skip first (header), rest are emoji-prefixed info
    final infoLines = lines.skip(1).toList();

    // Only the most recent proposal card should show action buttons
    final mgStatus = _mg?['status'] as String?;
    final mgProposedBy = _mg?['proposedBy'] as String?;
    final isLatestProposal = mgStatus == 'PROPOSED';
    final canAct = isLatestProposal && mgProposedBy != _currentUserId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: isDark
                ? GardenColors.primary.withValues(alpha: 0.08)
                : GardenColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: GardenColors.primary.withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Text('🤝', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text('Meet & Greet Propuesto',
                        style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
              // Info lines
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: infoLines.map((line) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(line, style: TextStyle(color: textColor, fontSize: 13)),
                  )).toList(),
                ),
              ),
              // Action buttons (only on latest PROPOSED card that user didn't propose)
              if (canAct) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: _mgLoading
                      ? const Center(child: SizedBox(height: 28, width: 28, child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.primary)))
                      : Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _proposeMG(prefill: _mg),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: subtextColor,
                                  side: BorderSide(color: subtextColor.withValues(alpha: 0.5)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                child: const Text('Otra fecha', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _acceptMG,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: GardenColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                child: const Text('Confirmar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe, Color textColor, Color subtextColor) {
    // Mensaje de sistema (M&G events)
    if (msg.isSystem) {
      // Special M&G proposal card
      if (msg.message.startsWith('📋 MEET & GREET PROPUESTO')) {
        return _buildMGProposalCard(msg, textColor, subtextColor);
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: msg.message.startsWith('✅')
                  ? GardenColors.success.withValues(alpha: 0.1)
                  : msg.message.startsWith('❌')
                      ? GardenColors.error.withValues(alpha: 0.08)
                      : GardenColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: msg.message.startsWith('✅')
                    ? GardenColors.success.withValues(alpha: 0.3)
                    : msg.message.startsWith('❌')
                        ? GardenColors.error.withValues(alpha: 0.25)
                        : GardenColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              msg.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: msg.message.startsWith('✅')
                    ? GardenColors.success
                    : msg.message.startsWith('❌')
                        ? GardenColors.error
                        : GardenColors.primary,
              ),
            ),
          ),
        ),
      );
    }

    final isDark = themeNotifier.isDark;
    final time = '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            GardenAvatar(
              imageUrl: widget.otherPersonPhoto,
              size: 28,
              initials: msg.senderName.isNotEmpty ? msg.senderName[0] : 'U',
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: const BoxConstraints(maxWidth: 280),
                  decoration: BoxDecoration(
                    color: isMe
                      ? GardenColors.primary
                      : (isDark ? GardenColors.darkSurface : GardenColors.lightSurface),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    border: isMe ? null : Border.all(
                      color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder,
                    ),
                    boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )],
                  ),
                  child: Text(
                    msg.message,
                    style: TextStyle(
                      color: isMe ? Colors.white : textColor,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(time, style: TextStyle(color: subtextColor, fontSize: 10)),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        msg.read ? Icons.done_all : Icons.done,
                        size: 12,
                        color: msg.read ? GardenColors.primary : subtextColor,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

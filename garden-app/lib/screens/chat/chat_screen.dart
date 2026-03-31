import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/chat_service.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_empty_state.dart';

class ChatScreen extends StatefulWidget {
  final String bookingId;
  final String otherPersonName;
  final String? otherPersonPhoto;
  final String? token;
  final String? meetAndGreetNote; // Banner fijo: fecha/hora del M&G cuando está ACCEPTED

  const ChatScreen({
    super.key,
    required this.bookingId,
    required this.otherPersonName,
    this.otherPersonPhoto,
    this.token,
    this.meetAndGreetNote,
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

  String get _baseUrl => const String.fromEnvironment(
    'API_URL', defaultValue: 'http://localhost:3000/api');

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

    if (!mounted) return;

    _chatService!.markRead(widget.bookingId);
    setState(() => _initialized = true);
    _scrollToBottom();
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
    _chatService?.sendMessage(widget.bookingId, text);
    _messageController.clear();
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
                              color: _initialized && (_chatService?.connected ?? false) ? GardenColors.success : subtextColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _initialized && (_chatService?.connected ?? false) ? 'En línea' : 'Conectando...',
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

  Widget _buildMessageBubble(ChatMessage msg, bool isMe, Color textColor, Color subtextColor) {
    // Mensaje de sistema (M&G events)
    if (msg.isSystem) {
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

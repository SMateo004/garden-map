import 'package:flutter/material.dart';
import '../../services/auth_state.dart';
import '../../services/support_chat_service.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Chat de soporte de Garden — reemplaza el botón de WhatsApp del Centro de
/// Ayuda. Responde un asistente automático (Claude, grounded en el centro
/// de ayuda); si el caso se sale de lo que puede resolver, escala a un
/// asesor humano — recién ahí. La conversación persiste hasta que un admin
/// la marca resuelta, no se reinicia sola al reabrir la app.
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  late final SupportChatService _service;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _service = SupportChatService(baseUrl: _baseUrl, token: AuthState.token ?? '');
    _service.addListener(_onServiceUpdate);
    _service.init();
  }

  void _onServiceUpdate() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    final ok = await _service.send(text);
    if (!ok && mounted) {
      _controller.text = text; // devolvemos el texto para que no se pierda lo escrito
      GardenErrorDialog.show(context, 'No se pudo enviar tu mensaje. Revisa tu conexión e intenta de nuevo.');
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _service.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : const Color(0xFFF7F9F4);
    final surface = isDark ? GardenColors.darkSurface : Colors.white;
    final text = isDark ? GardenColors.darkTextPrimary : const Color(0xFF1A2E0A);
    final subtext = isDark ? GardenColors.darkTextSecondary : const Color(0xFF5A7040);
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Soporte Garden', style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w800)),
                Text(
                  _service.status == 'ESCALATED' ? 'Un asesor va a revisar tu caso' : 'El asistente te responde al instante',
                  style: TextStyle(color: subtext, fontSize: 11.5),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _service.loading
                ? const Center(child: GardenLoadingIndicator())
                : _service.messages.isEmpty
                    ? _EmptyState(text: text, subtext: subtext)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        itemCount: _service.messages.length,
                        itemBuilder: (_, i) {
                          final msg = _service.messages[i];
                          final isMe = msg.senderRole == 'CLIENT';
                          return _Bubble(isMe: isMe, senderRole: msg.senderRole, message: msg.message, time: msg.createdAt, isDark: isDark, text: text, subtext: subtext, surface: surface, border: border);
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
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
                        hintText: 'Escribe tu consulta…',
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
                      onTap: _service.sending ? null : _send,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _service.sending
                            ? const SizedBox(width: 20, height: 20, child: GardenLoadingIndicator(size: 20, color: Colors.white))
                            : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Color text;
  final Color subtext;
  const _EmptyState({required this.text, required this.subtext});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👋', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text('¡Hola! ¿En qué te ayudamos?', style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'Escribinos tu consulta — el asistente te responde al instante, y si hace falta, avisa a un asesor real.',
              style: TextStyle(color: subtext, fontSize: 12.5, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool isMe;
  final String senderRole; // 'CLIENT' | 'BOT' | 'ADMIN'
  final String message;
  final DateTime time;
  final bool isDark;
  final Color text;
  final Color subtext;
  final Color surface;
  final Color border;

  const _Bubble({
    required this.isMe,
    required this.senderRole,
    required this.message,
    required this.time,
    required this.isDark,
    required this.text,
    required this.subtext,
    required this.surface,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final label = senderRole == 'BOT' ? '🌿 Asistente' : senderRole == 'ADMIN' ? '🧑‍💼 Asesor Garden' : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text(label, style: TextStyle(color: subtext, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ),
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? GardenColors.primary : surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    border: isMe ? null : Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(message, style: TextStyle(color: isMe ? Colors.white : text, fontSize: 14, height: 1.35)),
                      const SizedBox(height: 3),
                      Text('$hh:$mm', style: TextStyle(color: isMe ? Colors.white70 : text.withValues(alpha: 0.45), fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

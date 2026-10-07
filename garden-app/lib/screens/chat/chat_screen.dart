import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/chat_service.dart';
import 'package:go_router/go_router.dart';
import '../../design/brote.dart';
import '../../design/garden_icons.dart';
import '../../design/garden_pet_avatar.dart';
import '../../design/garden_status_pill.dart';
import '../../narrative/booking_story.dart';
import '../../narrative/chat_event.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../theme/garden_motion.dart';
import '../../design/garden_chat.dart';
import '../../design/garden_depth.dart';

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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  ChatService? _chatService;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  String _currentUserId = '';
  String _token = '';
  bool _initialized = false;
  Map<String, dynamic>? _mg;
  bool _mgLoading = false;

  // Foto de la otra persona: arranca con la que pasó el caller (si la pasó) y se
  // sobreescribe apenas responde GET /chat/:bookingId/other-participant, que
  // siempre trae la foto actual desde la DB — así el chat muestra la foto
  // correcta aunque el caller no la haya pasado (bug histórico: casi ningún
  // call site de ChatScreen pasaba otherPersonPhoto).
  String? _otherPersonPhoto;

  // Reserva de este chat (mascota, servicio, estado): da el contexto de la
  // conversación y personaliza las respuestas rápidas. Null si no cargó.
  Map<String, dynamic>? _booking;

  bool get _isCaregiver => widget.role == 'CAREGIVER';
  String? get _status => (_booking?['status'] as String?) ?? widget.bookingStatus;

  /// Mensajes que llegaron mientras se leía más arriba (píldora "nuevos").
  int _unseen = 0;
  int _lastCount = 0;

  // Bloqueo/reporte de chat
  String? _otherPersonId;
  bool _iBlockedThem = false;
  bool _theyBlockedMe = false;
  bool _sendBlockedByServer = false; // se activa si un envío devuelve 403 USER_BLOCKED

  String get _baseUrl => const String.fromEnvironment(
    'API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messageController.addListener(_onTyping);
    _scrollController.addListener(_onScroll);
    _initChat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_chatService == null) return;
    if (state == AppLifecycleState.resumed) {
      _chatService!.isForeground = true;
      // Un socket desconectado (fondo/red) no reintenta el historial perdido
      // al reconectar — sin esto, mensajes enviados mientras la app estaba en
      // segundo plano quedaban ausentes hasta cerrar y reabrir la pantalla.
      _chatService!.loadHistory(widget.bookingId).then((_) {
        if (mounted) {
          _chatService!.markRead(widget.bookingId);
          _scrollToBottom();
        }
      });
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _chatService!.isForeground = false;
    }
  }

  Future<void> _initChat() async {
    _otherPersonPhoto = widget.otherPersonPhoto;
    final prefs = await SharedPreferences.getInstance();
    _token = AuthState.token;
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
    await Future.wait([_loadOtherParticipant(), _loadBooking()]);

    if (!mounted) return;

    _chatService!.markRead(widget.bookingId);
    _lastCount = _chatService!.messages.length;
    setState(() => _initialized = true);
    _scrollToBottom();
  }

  Future<void> _loadBooking() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      if (mounted && data['success'] == true && data['data'] is Map<String, dynamic>) {
        setState(() => _booking = data['data'] as Map<String, dynamic>);
      }
    } catch (_) {
      // Sin contexto el chat funciona igual, solo sin la franja de la reserva.
    }
  }

  Future<void> _loadOtherParticipant() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/chat/${widget.bookingId}/other-participant'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      if (mounted && data['success'] == true) {
        final d = data['data'] as Map<String, dynamic>;
        setState(() {
          _otherPersonId = d['userId'] as String?;
          _iBlockedThem = d['blockedByMe'] as bool? ?? false;
          _theyBlockedMe = d['blockedMe'] as bool? ?? false;
          final fetchedPhoto = d['photo'] as String?;
          if (fetchedPhoto != null && fetchedPhoto.isNotEmpty) {
            _otherPersonPhoto = fetchedPhoto;
          }
        });
        if (_otherPersonId != null) {
          _chatService?.setOtherUserId(_otherPersonId!, initialOnline: d['isOnline'] as bool? ?? false);
        }
      }
    } catch (_) {}
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
          GardenErrorDialog.show(context, data['message'] ?? 'Error');
        }
      }
    } catch (e) {
      if (mounted) {
        GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _mgLoading = false);
    }
  }

  Future<void> _proposeMG({Map<String, dynamic>? prefill}) async {
    final isDark = themeNotifier.isDark;
    DateTime? selectedDate = prefill != null ? DateTime.tryParse(prefill['proposedDate'] ?? '') : null;
    final placeCtrl = TextEditingController(text: prefill?['meetingPoint'] ?? '');
    String modalidad = prefill?['modalidad'] ?? 'IN_PERSON';
    List<Map<String, dynamic>> locationSuggestions = [];
    double? selLat;
    double? selLng;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        TimeOfDay? selectedTime;
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
                      );
                      if (picked != null) setSheet(() => selectedDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const GardenIcon(GIcon.calendario, size: GIconSize.sm, color: GardenColors.primary),
                        const SizedBox(width: 10),
                        Text(
                          selectedDate != null ? _longDate(selectedDate!) : 'Elegir fecha',
                          style: TextStyle(color: selectedDate != null ? textColor : subtextColor, fontSize: 14),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Time picker row
                  GestureDetector(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: selectedTime ?? const TimeOfDay(hour: 10, minute: 0),
                      );
                      if (picked != null) setSheet(() => selectedTime = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const GardenIcon(GIcon.reloj, size: GIconSize.sm, color: GardenColors.primary),
                        const SizedBox(width: 10),
                        Text(
                          selectedTime != null
                              ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                              : 'Elegir hora',
                          style: TextStyle(color: selectedTime != null ? textColor : subtextColor, fontSize: 14),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Place with autocomplete
                  TextField(
                    controller: placeCtrl,
                    style: TextStyle(color: textColor, fontSize: 14),
                    onChanged: (query) async {
                      if (query.trim().length < 3) {
                        setSheet(() => locationSuggestions = []);
                        return;
                      }
                      try {
                        final uri = Uri.parse('https://nominatim.openstreetmap.org/search').replace(queryParameters: {
                          'q': query,
                          'format': 'json',
                          'limit': '5',
                          'countrycodes': 'bo',
                          'accept-language': 'es',
                        });
                        final res = await http.get(uri, headers: {'User-Agent': 'GardenApp/1.0'});
                        final list = jsonDecode(res.body) as List;
                        setSheet(() => locationSuggestions = list.cast<Map<String, dynamic>>());
                      } catch (_) {}
                    },
                    decoration: InputDecoration(
                      hintText: 'Punto de encuentro',
                      hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                      prefixIcon: const GardenIcon(GIcon.ubicacion, size: GIconSize.sm, state: GIconState.active, color: GardenColors.primary),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary)),
                    ),
                  ),
                  if (locationSuggestions.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: borderColor),
                        borderRadius: BorderRadius.circular(12),
                        color: bg,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: locationSuggestions.length,
                        itemBuilder: (_, i) {
                          final s = locationSuggestions[i];
                          return ListTile(
                            dense: true,
                            title: Text(s['display_name'] ?? '', style: TextStyle(color: textColor, fontSize: 12)),
                            onTap: () {
                              setSheet(() {
                                placeCtrl.text = s['display_name'] ?? '';
                                selLat = double.tryParse(s['lat']?.toString() ?? '');
                                selLng = double.tryParse(s['lon']?.toString() ?? '');
                                locationSuggestions = [];
                              });
                            },
                          );
                        },
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
                            const SnackBar(content: Text('Completa fecha y lugar'), backgroundColor: GardenColors.warning),
                          );
                          return;
                        }
                        final timeStr = selectedTime != null
                            ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                            : '10:00';
                        final dateStr = selectedDate!.toIso8601String().split('T')[0];
                        final capturedLat = selLat;
                        final capturedLng = selLng;
                        final capturedPlace = placeCtrl.text.trim();
                        Navigator.pop(ctx);
                        setState(() => _mgLoading = true);
                        try {
                          final body = <String, dynamic>{
                            'modalidad': modalidad,
                            'proposedDate': '${dateStr}T$timeStr:00',
                            'meetingPoint': capturedPlace,
                            if (capturedLat != null && capturedLng != null) ...{
                              'meetingPointLat': capturedLat,
                              'meetingPointLng': capturedLng,
                            },
                          };
                          final res = await http.post(
                            Uri.parse('$_baseUrl/meet-and-greet/${widget.bookingId}/propose'),
                            headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
                            body: jsonEncode(body),
                          );
                          final d = jsonDecode(res.body);
                          if (mounted) {
                            if (d['success'] == true) {
                              if (capturedLat != null && capturedLng != null) {
                                final mapsUrl = 'https://www.google.com/maps?q=$capturedLat,$capturedLng';
                                _chatService?.sendMessage(widget.bookingId, '📍 Ubicación del Meet & Greet: $mapsUrl');
                              }
                              await _loadMG();
                              await _chatService!.loadHistory(widget.bookingId);
                            } else {
                              GardenErrorDialog.show(context, d['message'] ?? 'Error');
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
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

    placeCtrl.dispose();
  }

  /// "martes 7 de octubre" (antes: 7/10/2026).
  static String _longDate(DateTime d) {
    const days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    const months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    return '${days[d.weekday - 1]} ${d.day} de ${months[d.month - 1]}';
  }

  Widget _sheetToggleBtn(String label, bool active, VoidCallback onTap) {
    // Antes usaba siempre los colores del modo oscuro (borde y texto).
    final isDark = themeNotifier.isDark;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: GardenMotion.resolve(context, GardenMotion.quick),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? GardenColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? GardenColors.primary : border),
        ),
        child: Center(child: Text(label, style: TextStyle(color: active ? Colors.white : sub, fontWeight: FontWeight.w700, fontSize: 13))),
      ),
    );
  }

  bool get _nearBottom =>
      !_scrollController.hasClients ||
      _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 120;

  /// Antes cada mensaje nuevo bajaba hasta el final aunque uno estuviera
  /// leyendo más arriba. Ahora baja solo si ya estaba abajo o si lo mandó uno;
  /// si no, aparece "N mensajes nuevos".
  void _onChatUpdate() {
    if (!mounted) return;
    final msgs = _chatService?.messages ?? const <ChatMessage>[];
    final added = msgs.length - _lastCount;
    final mine = msgs.isNotEmpty && msgs.last.senderId == _currentUserId;
    _lastCount = msgs.length;
    setState(() {
      if (added > 0 && !_nearBottom && !mine) _unseen += added;
    });
    if (added > 0 && (_nearBottom || mine)) _scrollToBottom();
  }

  void _onScroll() {
    if (_unseen > 0 && _nearBottom) setState(() => _unseen = 0);
  }

  void _onTyping() => setState(() {});

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: GardenMotion.resolve(context, GardenMotion.standard),
          curve: GardenMotion.enter,
        );
      }
      if (_unseen > 0 && mounted) setState(() => _unseen = 0);
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear(); // Limpiar inmediatamente para mejor UX

    final ok = await _chatService?.sendMessage(widget.bookingId, text) ?? false;
    if (!ok && mounted) {
      // Restaurar el texto — sin esto el mensaje simplemente desaparecía si
      // fallaba el envío (sin conexión, timeout), sin ninguna señal ni forma
      // de reintentar salvo volver a escribirlo de memoria.
      _messageController.text = text;
      _messageController.selection = TextSelection.collapsed(offset: text.length);
      if (_chatService?.blockedError == true) {
        setState(() => _sendBlockedByServer = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo enviar el mensaje. Revisa tu conexión e intenta de nuevo.')),
        );
      }
    }
  }

  bool get _conversationBlocked => _iBlockedThem || _theyBlockedMe || _sendBlockedByServer;

  /// Plantillas de coordinación contextuales según quién está escribiendo y en
  /// qué momento del booking — para no tener que tipear a mano lo mismo que
  /// escribe casi todo el mundo antes/durante el servicio. Vacío fuera de
  /// CONFIRMED/IN_PROGRESS (antes de aceptar o después de terminar no aplican).
  List<String> get _quickReplies {
    final pet = (_booking?['petName'] as String?)?.trim();
    final name = (pet == null || pet.isEmpty) ? null : pet;
    switch (_status) {
      case 'WAITING_CAREGIVER_APPROVAL':
      case 'PENDING_MG':
        return _isCaregiver
            ? ['¡Hola! Me encantaría conocer a ${name ?? 'tu mascota'}', '¿Tiene alguna necesidad especial?']
            : ['¡Hola! ${name ?? 'Mi mascota'} es muy tranquilo/a', '¿Tienes disponibilidad?'];
      case 'CONFIRMED':
        return _isCaregiver
            ? const ['Ya salí', 'Llego en 5 min', '¿Dónde te espero?']
            : ['¿Ya saliste?', 'Te espero en la puerta', '${name ?? 'Mi mascota'} está listo/a'];
      case 'IN_PROGRESS':
        return _isCaregiver
            ? ['${name ?? 'Tu mascota'} está feliz', 'Todo tranquilo', 'Ya casi terminamos']
            : ['¿Cómo está ${name ?? 'mi mascota'}?', '¿Me mandas una foto?', '¡Gracias!'];
      case 'COMPLETED':
        return _isCaregiver
            ? ['Gracias por confiar en mí', 'Fue un gusto cuidar a ${name ?? 'tu mascota'}']
            : ['¡Gracias por cuidar a ${name ?? 'mi mascota'}!'];
    }
    return const [];
  }

  void _sendQuickReply(String text) {
    _messageController.text = text;
    _sendMessage();
  }

  Future<void> _confirmBlockUser() async {
    if (_otherPersonId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => GardenGlassDialog(
        title: Text('¿Bloquear a ${widget.otherPersonName}?'),
        content: const Text('Ya no podrá enviarte mensajes en esta conversación. Puedes desbloquearlo más tarde desde tu perfil.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bloquear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/block'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _otherPersonId}),
      );
      final data = jsonDecode(response.body);
      if (mounted && data['success'] == true) {
        setState(() => _iBlockedThem = true);
        GardenSnackBar.success(context, '${widget.otherPersonName} ha sido bloqueado.');
      } else if (mounted) {
        GardenSnackBar.error(context, 'No se pudo bloquear al usuario.');
      }
    } catch (_) {
      if (mounted) GardenSnackBar.error(context, 'No se pudo bloquear al usuario.');
    }
  }

  Future<void> _showReportSheet() async {
    if (_otherPersonId == null) return;
    const reasons = <String, String>{
      'HARASSMENT': 'Acoso',
      'INAPPROPRIATE_CONTENT': 'Contenido inapropiado',
      'SPAM': 'Spam',
      'SCAM_OR_FRAUD': 'Estafa o fraude',
      'THREATS': 'Amenazas',
      'OTHER': 'Otro',
    };
    String? selectedReason;
    final detailsCtrl = TextEditingController();
    bool submitting = false;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = themeNotifier.isDark;
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
                  Text('Reportar a ${widget.otherPersonName}', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Nuestro equipo revisará esta conversación.', style: TextStyle(color: subtextColor, fontSize: 13)),
                  const SizedBox(height: 16),
                  ...reasons.entries.map((e) => RadioListTile<String>(
                        value: e.key,
                        groupValue: selectedReason,
                        onChanged: (v) => setSheet(() => selectedReason = v),
                        activeColor: GardenColors.primary,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(e.value, style: TextStyle(color: textColor, fontSize: 14)),
                      )),
                  const SizedBox(height: 8),
                  TextField(
                    controller: detailsCtrl,
                    style: TextStyle(color: textColor, fontSize: 14),
                    maxLines: 3,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      hintText: 'Detalles adicionales (opcional)',
                      hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GardenColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: (selectedReason == null || submitting) ? null : () async {
                        setSheet(() => submitting = true);
                        try {
                          final response = await http.post(
                            Uri.parse('$_baseUrl/chat/report'),
                            headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
                            body: jsonEncode({
                              'bookingId': widget.bookingId,
                              'reason': selectedReason,
                              if (detailsCtrl.text.trim().isNotEmpty) 'details': detailsCtrl.text.trim(),
                            }),
                          );
                          final data = jsonDecode(response.body);
                          if (data['success'] == true) {
                            Navigator.pop(ctx, true);
                          } else {
                            setSheet(() => submitting = false);
                            if (ctx.mounted) {
                              GardenSnackBar.error(ctx, data['error']?['message'] ?? 'No se pudo enviar el reporte.');
                            }
                          }
                        } catch (_) {
                          setSheet(() => submitting = false);
                          if (ctx.mounted) GardenSnackBar.error(ctx, 'No se pudo enviar el reporte.');
                        }
                      },
                      child: submitting
                          ? const GardenLoadingIndicator(size: 20, color: Colors.white)
                          : const Text('Enviar reporte', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    detailsCtrl.dispose();

    if (submitted == true && mounted) {
      GardenSnackBar.success(context, 'Reporte enviado — nuestro equipo lo revisará.');
      // Ofrecer bloquear también, como acción relacionada pero separada.
      final wantsBlock = await showDialog<bool>(
        context: context,
        builder: (ctx) => GardenGlassDialog(
          title: const Text('¿También quieres bloquear a esta persona?'),
          content: Text('${widget.otherPersonName} ya no podrá enviarte mensajes si la bloqueas.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, gracias')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Bloquear', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (wantsBlock == true) {
        await _confirmBlockUser();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.removeListener(_onTyping);
    _scrollController.removeListener(_onScroll);
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
          appBar: kIsWeb ? null : AppBar(
            backgroundColor: surface,
            elevation: 0,
            leading: IconButton(
              icon: GardenIcon(GIcon.atras, color: textColor, semanticLabel: 'Volver'),
              onPressed: () => Navigator.pop(context),
            ),
            titleSpacing: 0,
            title: _headerTitle(textColor, subtextColor),
            actions: [if (_otherPersonId != null) _moreMenu(textColor)],
          ),
          body: !_initialized
            ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
            : Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kIsWeb ? 780.0 : double.infinity),
                child: Column(
                  children: [
                    // Web: mismo encabezado que en celular, sin AppBar.
                    if (kIsWeb)
                      Container(
                        height: 60,
                        decoration: BoxDecoration(color: surface, border: Border(bottom: BorderSide(color: borderColor))),
                        padding: const EdgeInsets.only(left: 4, right: 8),
                        child: Row(children: [
                          IconButton(
                              icon: GardenIcon(GIcon.atras, color: textColor, semanticLabel: 'Volver'),
                              onPressed: () => Navigator.pop(context)),
                          Expanded(child: _headerTitle(textColor, subtextColor)),
                          if (_otherPersonId != null) _moreMenu(textColor),
                        ]),
                      ),
                    if (_booking != null) _buildContextStrip(surface, borderColor, textColor),
                    Expanded(child: Column(
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
                          const GardenIcon(GIcon.meetGreet, color: GardenColors.success, size: GIconSize.sm),
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
                      ? Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Brote(pose: BrotePose.hola, size: 110),
                                const SizedBox(height: 12),
                                Text('Saluda a ${widget.otherPersonName.split(' ').first}',
                                    textAlign: TextAlign.center,
                                    style: GardenText.h4.copyWith(color: textColor)),
                                const SizedBox(height: 6),
                                Text(
                                  _isCaregiver
                                      ? 'Preséntate y pregunta lo que necesites saber de ${_booking?['petName'] ?? 'la mascota'}.'
                                      : 'Cuéntale cómo es ${_booking?['petName'] ?? 'tu mascota'} y coordinen el servicio.',
                                  textAlign: TextAlign.center,
                                  style: GardenText.bodyMedium.copyWith(color: subtextColor),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Stack(children: [
                          ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            itemCount: _chatService!.messages.length,
                            itemBuilder: (context, index) {
                              final msgs = _chatService!.messages;
                              final msg = msgs[index];
                              final prev = index > 0 ? msgs[index - 1] : null;
                              final next = index + 1 < msgs.length ? msgs[index + 1] : null;
                              final newDay = prev == null || !_sameDay(prev.createdAt, msg.createdAt);
                              // Último de una racha: el siguiente es de otra persona, de
                              // sistema, de otro día o llega más de 5 min después.
                              final last = next == null ||
                                  next.isSystem ||
                                  next.senderId != msg.senderId ||
                                  !_sameDay(next.createdAt, msg.createdAt) ||
                                  next.createdAt.difference(msg.createdAt).inMinutes >= 5;
                              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                if (newDay) GardenChatDaySeparator(msg.createdAt),
                                _buildMessageBubble(msg, msg.senderId == _currentUserId, textColor, subtextColor, last: last),
                              ]);
                            },
                          ),
                          if (_unseen > 0)
                            Positioned(
                              bottom: 12,
                              left: 0,
                              right: 0,
                              child: Center(child: GardenNewMessagesPill(count: _unseen, onTap: _scrollToBottom)),
                            ),
                        ]),
                  ),
                  // Proponer M&G button (caregiver only, when no active M&G)
                  // Estado actual de la reserva (antes usaba el que se pasó al abrir).
                  if (widget.role == 'CAREGIVER' &&
                      (_status == 'WAITING_CAREGIVER_APPROVAL' || _status == 'CONFIRMED') &&
                      (_mg == null || _mg!['status'] == 'CANCELLED'))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _mgLoading ? null : () => _proposeMG(),
                          icon: const GardenIcon(GIcon.meetGreet, size: GIconSize.sm, color: GardenColors.primary),
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
                  // Input de mensaje — o aviso de conversación bloqueada
                  if (_conversationBlocked)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      decoration: BoxDecoration(
                        color: surface,
                        border: Border(top: BorderSide(color: borderColor)),
                      ),
                      child: Row(
                        children: [
                          GardenIcon(GIcon.bloqueado, color: subtextColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _iBlockedThem
                                  ? 'Has bloqueado a esta persona.'
                                  : 'No puedes enviar mensajes en esta conversación.',
                              style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    decoration: BoxDecoration(
                      color: surface,
                      border: Border(top: BorderSide(color: borderColor)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_quickReplies.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GardenQuickReplies(replies: _quickReplies, onTap: _sendQuickReply),
                          ),
                        Row(
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
                        // Apagado mientras no hay texto: antes parecía activo y no hacía nada.
                        Semantics(
                          button: true,
                          enabled: _messageController.text.trim().isNotEmpty,
                          label: 'Enviar',
                          excludeSemantics: true,
                          child: GestureDetector(
                            onTap: _messageController.text.trim().isEmpty ? null : _sendMessage,
                            child: AnimatedOpacity(
                              duration: GardenMotion.resolve(context, GardenMotion.quick),
                              opacity: _messageController.text.trim().isEmpty ? 0.45 : 1,
                              child: const GardenClay(
                                size: 46,
                                color: GardenColors.primary,
                                interactive: false,
                                child: Center(child: GardenIcon(GIcon.enviar, color: Colors.white, state: GIconState.active)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                      ],
                    ),
                  ),
                ],
              )),
                  ],
                ),
              )),
        );
      },
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Foto con el punto de "en línea" encima, nombre y estado. El mismo en
  /// celular (AppBar) y web (barra propia): antes eran dos copias.
  Widget _headerTitle(Color textColor, Color subtextColor) {
    final online = _initialized && (_chatService?.otherOnline ?? false);
    return Row(children: [
      Stack(clipBehavior: Clip.none, children: [
        GardenAvatar(
          imageUrl: _otherPersonPhoto,
          size: 38,
          initials: widget.otherPersonName.isNotEmpty ? widget.otherPersonName : 'U',
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: AnimatedContainer(
            duration: GardenMotion.resolve(context, GardenMotion.quick),
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: online ? GardenColors.success : subtextColor.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              border: Border.all(color: themeNotifier.isDark ? GardenColors.darkSurface : GardenColors.lightSurface, width: 2),
            ),
          ),
        ),
      ]),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.otherPersonName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
          Text(
            !_initialized ? 'Conectando…' : online ? 'En línea' : 'No está en línea ahora',
            style: TextStyle(color: online ? GardenColors.success : subtextColor, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    ]);
  }

  Widget _moreMenu(Color textColor) => PopupMenuButton<String>(
        icon: GardenIcon(GIcon.masOpciones, color: textColor, semanticLabel: 'Más opciones'),
        onSelected: (value) {
          if (value == 'report') _showReportSheet();
          if (value == 'block') _confirmBlockUser();
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(value: 'report', child: Text('Reportar')),
          if (!_iBlockedThem) PopupMenuItem(value: 'block', child: Text('Bloquear a ${widget.otherPersonName}')),
        ],
      );

  /// De quién y de qué habla este chat: la mascota con su anillo de estado y
  /// la frase de BookingStory. Toca para abrir el servicio.
  Widget _buildContextStrip(Color surface, Color borderColor, Color textColor) {
    final b = _booking!;
    final ctx = BookingStoryContext.fromBooking(b, caregiverView: _isCaregiver);
    final story = BookingStory.of(b['status'] as String?, ctx);
    return Material(
      color: surface,
      child: InkWell(
        onTap: () => context.push('/service/${widget.bookingId}', extra: {
          'role': _isCaregiver ? 'CAREGIVER' : 'CLIENT',
          'token': _token,
        }),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor))),
          child: Row(
            children: [
              GardenPetAvatar(
                name: ctx.pet,
                size: 36,
                tone: story.tone,
                service: ctx.service,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GardenStatusPill(story, service: ctx.service, dense: true),
                    const SizedBox(height: 3),
                    Text(
                      story.headlineFor(caregiverView: _isCaregiver),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GardenText.bodySmall.copyWith(color: textColor, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const GardenIcon(GIcon.siguiente),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMGProposalCard(ChatMessage msg, Color textColor, Color subtextColor) {
    final isDark = themeNotifier.isDark;
    // Detalles en el orden en que los arma el backend: fecha, lugar, modalidad.
    final infoLines = ChatEvent.from(msg.message, eventType: msg.eventType).details;
    const infoIcons = [GIcon.calendario, GIcon.ubicacion, GIcon.meetGreet];

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
                child: const Row(
                  children: [
                    GardenIcon(GIcon.meetGreet, state: GIconState.active),
                    SizedBox(width: 8),
                    Text('Meet & Greet propuesto',
                        style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
              // Info lines
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var k = 0; k < infoLines.length; k++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          GardenIcon(k < infoIcons.length ? infoIcons[k] : GIcon.nota,
                              size: GIconSize.sm, color: subtextColor),
                          const SizedBox(width: 8),
                          Expanded(child: Text(infoLines[k], style: TextStyle(color: textColor, fontSize: 13))),
                        ]),
                      ),
                  ],
                ),
              ),
              // Action buttons (only on latest PROPOSED card that user didn't propose)
              if (canAct) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: _mgLoading
                      ? const Center(child: GardenLoadingIndicator(size: 28, color: GardenColors.primary))
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

  Widget _buildMessageBubble(ChatMessage msg, bool isMe, Color textColor, Color subtextColor, {bool last = true}) {
    // Mensaje de sistema: ChatEvent decide icono y tono (nunca el emoji).
    if (msg.isSystem) {
      final event = ChatEvent.from(msg.message, eventType: msg.eventType);
      if (event.kind == ChatEventKind.meetProposed) {
        return _buildMGProposalCard(msg, textColor, subtextColor);
      }
      final c = StoryColors.of(event.tone, isDark: themeNotifier.isDark);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GardenIcon(event.icon, state: GIconState.active, size: GIconSize.sm, color: c.ink),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    [event.text, ...event.details].join(' · '),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.ink, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GardenChatBubble(
      text: msg.message,
      isMe: isMe,
      time: msg.createdAt,
      read: msg.read,
      last: last,
      avatarUrl: _otherPersonPhoto,
      initials: msg.senderName.isNotEmpty ? msg.senderName : widget.otherPersonName,
    );
  }
}

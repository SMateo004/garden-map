import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';

class AdminNotificationsScreen extends StatefulWidget {
  final String adminToken;
  const AdminNotificationsScreen({super.key, required this.adminToken});

  @override
  State<AdminNotificationsScreen> createState() => _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen>
    with SingleTickerProviderStateMixin {
  static const _baseUrl = String.fromEnvironment('API_URL',
      defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  late TabController _tabCtrl;

  // — Formulario —
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _target = 'ALL'; // ALL | CUIDADORES | DUENOS
  String _type = 'SYSTEM';
  bool _scheduleMode = false;
  DateTime? _scheduledAt;
  bool _sending = false;

  // — Datos —
  List<Map<String, dynamic>> _scheduled = [];
  List<Map<String, dynamic>> _history = [];
  bool _loadingScheduled = true;
  bool _loadingHistory = true;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.adminToken}',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 1 && _loadingScheduled) _loadScheduled();
      if (_tabCtrl.index == 2 && _loadingHistory) _loadHistory();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadScheduled() async {
    setState(() => _loadingScheduled = true);
    try {
      final res = await http.get(
          Uri.parse('$_baseUrl/admin/notifications/scheduled'),
          headers: _headers);
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() =>
            _scheduled = (data['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingScheduled = false);
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final res = await http.get(
          Uri.parse('$_baseUrl/admin/notifications/history?limit=50'),
          headers: _headers);
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() =>
            _history = (data['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingHistory = false);
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final message = _messageCtrl.text.trim();
    if (title.isEmpty || message.isEmpty) {
      _snack('Completa título y mensaje', GardenColors.error);
      return;
    }
    if (_scheduleMode && _scheduledAt == null) {
      _snack('Selecciona la fecha y hora de envío', GardenColors.error);
      return;
    }

    // Confirmación
    final targetLabel = _target == 'ALL'
        ? 'todos los usuarios'
        : _target == 'CUIDADORES'
            ? 'todos los cuidadores'
            : 'todos los dueños';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.send_rounded, color: GardenColors.primary),
          const SizedBox(width: 8),
          Text(_scheduleMode ? 'Programar notificación' : 'Enviar notificación'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _previewRow('Título', title),
            const SizedBox(height: 4),
            _previewRow('Mensaje', message),
            const SizedBox(height: 4),
            _previewRow('Destinatarios', targetLabel),
            if (_scheduleMode && _scheduledAt != null) ...[
              const SizedBox(height: 4),
              _previewRow('Envío programado', _formatDate(_scheduledAt!)),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: GardenColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_scheduleMode ? 'Programar' : 'Enviar ahora'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _sending = true);
    try {
      final endpoint = _scheduleMode
          ? '$_baseUrl/admin/notifications/schedule'
          : '$_baseUrl/admin/notifications/send';

      final body = {
        'title': title,
        'message': message,
        'target': _target,
        'type': _type,
        if (_scheduleMode && _scheduledAt != null)
          'scheduledAt': _scheduledAt!.toIso8601String(),
      };

      final res = await http.post(Uri.parse(endpoint),
          headers: _headers, body: jsonEncode(body));
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        _titleCtrl.clear();
        _messageCtrl.clear();
        setState(() {
          _scheduleMode = false;
          _scheduledAt = null;
          _loadingScheduled = true;
          _loadingHistory = true;
        });
        _snack(
          _scheduleMode
              ? 'Notificación programada'
              : 'Notificación enviada a ${data['data']?['sentCount'] ?? '?'} usuarios',
          GardenColors.success,
        );
      } else {
        _snack(
            data['error']?['message'] ?? 'Error al enviar', GardenColors.error);
      }
    } catch (e) {
      _snack('Error: $e', GardenColors.error);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _cancelScheduled(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar notificación'),
        content:
            const Text('¿Seguro que quieres cancelar esta notificación programada?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await http.delete(
          Uri.parse('$_baseUrl/admin/notifications/scheduled/$id'),
          headers: _headers);
      await _loadScheduled();
      _snack('Notificación cancelada', GardenColors.success);
    } catch (e) {
      _snack('Error: $e', GardenColors.error);
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.now());
    if (time == null || !mounted) return;
    setState(() {
      _scheduledAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 3)));
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _previewRow(String label, String value) => RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          children: [
            TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg =
        isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface =
        isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor =
        isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark
        ? GardenColors.darkTextSecondary
        : GardenColors.lightTextSecondary;
    final borderColor =
        isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Column(
      children: [
        // Header
        Container(
          color: surface,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.campaign_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Notificaciones',
                      style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  Text('Envía mensajes a todos o segmentos específicos',
                      style: TextStyle(color: subtextColor, fontSize: 12)),
                ]),
              ]),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabCtrl,
                indicatorColor: GardenColors.primary,
                labelColor: GardenColors.primary,
                unselectedLabelColor: subtextColor,
                labelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
                tabs: const [
                  Tab(icon: Icon(Icons.send_rounded, size: 16), text: 'Enviar'),
                  Tab(
                      icon: Icon(Icons.schedule_rounded, size: 16),
                      text: 'Programadas'),
                  Tab(
                      icon: Icon(Icons.history_rounded, size: 16),
                      text: 'Historial'),
                ],
              ),
            ],
          ),
        ),

        // Tabs
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildComposeTab(bg, surface, textColor, subtextColor, borderColor),
              _buildScheduledTab(bg, surface, textColor, subtextColor, borderColor),
              _buildHistoryTab(bg, surface, textColor, subtextColor, borderColor),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  TAB 1: COMPONER Y ENVIAR
  // ─────────────────────────────────────────────────────────────────

  Widget _buildComposeTab(Color bg, Color surface, Color textColor,
      Color subtextColor, Color borderColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plantillas rápidas
          _sectionLabel('Plantillas rápidas', textColor),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _templateChip('🎉 Bienvenida', 'Bienvenido a GARDEN',
                    'Gracias por unirte a GARDEN. Explora los mejores cuidadores cerca de ti.', subtextColor),
                _templateChip('🐾 Recordatorio', 'Recuerda amar a tu mascota',
                    'Las mascotas necesitan amor y cuidado todos los días. ¡Agenda un paseo hoy!', subtextColor),
                _templateChip('🔥 Promo', '¡Oferta especial!',
                    'Aprovecha los mejores precios de cuidadores en tu zona esta semana.', subtextColor),
                _templateChip('⚠️ Sistema', 'Aviso de mantenimiento',
                    'El sistema estará en mantenimiento por 30 minutos. Disculpa las molestias.', subtextColor),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Título
          _sectionLabel('Título *', textColor),
          const SizedBox(height: 8),
          TextField(
            controller: _titleCtrl,
            maxLength: 100,
            style: TextStyle(color: textColor),
            decoration: _inputDecor('Ej: ¡Nueva función disponible!', subtextColor, borderColor, surface),
          ),
          const SizedBox(height: 16),

          // Mensaje
          _sectionLabel('Mensaje *', textColor),
          const SizedBox(height: 8),
          TextField(
            controller: _messageCtrl,
            maxLines: 4,
            maxLength: 300,
            style: TextStyle(color: textColor),
            decoration: _inputDecor(
                'Escribe el mensaje que recibirán los usuarios...', subtextColor, borderColor, surface),
          ),
          const SizedBox(height: 16),

          // Destinatarios
          _sectionLabel('Destinatarios', textColor),
          const SizedBox(height: 8),
          _buildTargetSelector(surface, textColor, subtextColor, borderColor),
          const SizedBox(height: 16),

          // Tipo
          _sectionLabel('Tipo de notificación', textColor),
          const SizedBox(height: 8),
          _buildTypeSelector(surface, textColor, subtextColor, borderColor),
          const SizedBox(height: 16),

          // Programar
          _sectionLabel('Envío', textColor),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Switch(
                      value: _scheduleMode,
                      onChanged: (v) => setState(() {
                        _scheduleMode = v;
                        if (!v) _scheduledAt = null;
                      }),
                      activeColor: GardenColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Programar envío',
                            style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        Text('Envío inmediato si está desactivado',
                            style:
                                TextStyle(color: subtextColor, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
                if (_scheduleMode) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _pickDateTime,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: GardenColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: GardenColors.primary.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              color: GardenColors.primary, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            _scheduledAt != null
                                ? _formatDate(_scheduledAt!)
                                : 'Seleccionar fecha y hora',
                            style: TextStyle(
                              color: _scheduledAt != null
                                  ? GardenColors.primary
                                  : subtextColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.arrow_drop_down,
                              color: GardenColors.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Preview
          _buildPreviewCard(surface, textColor, subtextColor, borderColor),
          const SizedBox(height: 24),

          // Botón
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: GardenColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(
                      _scheduleMode
                          ? Icons.schedule_send_rounded
                          : Icons.send_rounded),
              label: Text(
                _sending
                    ? 'Enviando...'
                    : _scheduleMode
                        ? 'Programar notificación'
                        : 'Enviar ahora',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _templateChip(String label, String title, String message, Color subtextColor) {
    return GestureDetector(
      onTap: () {
        _titleCtrl.text = title;
        _messageCtrl.text = message;
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: GardenColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: GardenColors.primary.withOpacity(0.3)),
        ),
        child: Text(label,
            style: const TextStyle(
                color: GardenColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildTargetSelector(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final options = [
      ('ALL', '🌍 Todos', 'Cuidadores y dueños'),
      ('CUIDADORES', '🐕 Cuidadores', 'Solo cuidadores aprobados'),
      ('DUENOS', '🏠 Dueños', 'Solo dueños de mascotas'),
    ];
    return Row(
      children: options.map((opt) {
        final selected = _target == opt.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _target = opt.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.only(
                  right: opt.$1 != 'DUENOS' ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: selected
                    ? GardenColors.primary
                    : surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? GardenColors.primary
                      : borderColor,
                ),
              ),
              child: Column(
                children: [
                  Text(opt.$2,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : textColor)),
                  const SizedBox(height: 2),
                  Text(opt.$3,
                      style: TextStyle(
                          fontSize: 10,
                          color: selected
                              ? Colors.white70
                              : subtextColor),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTypeSelector(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final types = [
      ('SYSTEM', Icons.info_outline_rounded, Colors.blue, 'Sistema'),
      ('PROMO', Icons.local_offer_outlined, Colors.orange, 'Promoción'),
      ('ALERT', Icons.warning_amber_rounded, Colors.red, 'Alerta'),
      ('NEWS', Icons.newspaper_rounded, Colors.green, 'Novedad'),
    ];
    return Row(
      children: types.map((t) {
        final selected = _type == t.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _type = t.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.only(right: t.$1 != 'NEWS' ? 6 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? t.$3.withOpacity(0.15) : surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected ? t.$3 : borderColor),
              ),
              child: Column(
                children: [
                  Icon(t.$2, color: selected ? t.$3 : subtextColor, size: 18),
                  const SizedBox(height: 4),
                  Text(t.$4,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: selected ? t.$3 : subtextColor)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPreviewCard(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final title = _titleCtrl.text.trim().isEmpty ? 'Título de la notificación' : _titleCtrl.text.trim();
    final message = _messageCtrl.text.trim().isEmpty
        ? 'Aquí aparecerá tu mensaje...'
        : _messageCtrl.text.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.phone_android_rounded, size: 14, color: GardenColors.primary),
            const SizedBox(width: 6),
            Text('Vista previa de notificación',
                style: TextStyle(
                    color: GardenColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: GardenColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.pets, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('GARDEN',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text('ahora',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  TAB 2: PROGRAMADAS
  // ─────────────────────────────────────────────────────────────────

  Widget _buildScheduledTab(Color bg, Color surface, Color textColor,
      Color subtextColor, Color borderColor) {
    if (_loadingScheduled) {
      return const Center(child: CircularProgressIndicator(color: GardenColors.primary));
    }
    return RefreshIndicator(
      onRefresh: _loadScheduled,
      color: GardenColors.primary,
      child: _scheduled.isEmpty
          ? ListView(children: [
              const SizedBox(height: 80),
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.schedule_rounded,
                      size: 48, color: subtextColor.withOpacity(0.5)),
                  const SizedBox(height: 12),
                  Text('Sin notificaciones programadas',
                      style: TextStyle(color: subtextColor, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Crea una en la pestaña "Enviar" activando el modo programar',
                      style: TextStyle(color: subtextColor, fontSize: 12),
                      textAlign: TextAlign.center),
                ]),
              ),
            ])
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _scheduled.length,
              itemBuilder: (_, i) =>
                  _buildScheduledCard(_scheduled[i], surface, textColor, subtextColor, borderColor),
            ),
    );
  }

  Widget _buildScheduledCard(Map<String, dynamic> item, Color surface,
      Color textColor, Color subtextColor, Color borderColor) {
    final scheduledAt = item['scheduledAt'] != null
        ? DateTime.parse(item['scheduledAt'] as String).toLocal()
        : null;
    final target = item['target'] as String? ?? 'ALL';
    final targetLabel = target == 'ALL'
        ? '🌍 Todos'
        : target == 'CUIDADORES'
            ? '🐕 Cuidadores'
            : '🏠 Dueños';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.schedule_rounded, color: Colors.orange, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(item['title'] as String? ?? '',
                  style: TextStyle(
                      color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            GestureDetector(
              onTap: () => _cancelScheduled(item['id'] as String),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: GardenColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: GardenColors.error.withOpacity(0.4)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.cancel_outlined, color: GardenColors.error, size: 14),
                  SizedBox(width: 4),
                  Text('Cancelar',
                      style: TextStyle(color: GardenColors.error, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(item['message'] as String? ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: subtextColor, fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            _chip(targetLabel, Colors.blue),
            const SizedBox(width: 6),
            if (scheduledAt != null)
              _chip('📅 ${_formatDate(scheduledAt)}', Colors.orange),
          ]),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  TAB 3: HISTORIAL
  // ─────────────────────────────────────────────────────────────────

  Widget _buildHistoryTab(Color bg, Color surface, Color textColor,
      Color subtextColor, Color borderColor) {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator(color: GardenColors.primary));
    }
    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: GardenColors.primary,
      child: _history.isEmpty
          ? ListView(children: [
              const SizedBox(height: 80),
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.history_rounded,
                      size: 48, color: subtextColor.withOpacity(0.5)),
                  const SizedBox(height: 12),
                  Text('Sin historial todavía',
                      style: TextStyle(color: subtextColor, fontSize: 14)),
                ]),
              ),
            ])
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _history.length,
              itemBuilder: (_, i) =>
                  _buildHistoryCard(_history[i], surface, textColor, subtextColor, borderColor),
            ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> item, Color surface,
      Color textColor, Color subtextColor, Color borderColor) {
    final sentAt = item['sentAt'] != null
        ? DateTime.parse(item['sentAt'] as String).toLocal()
        : (item['createdAt'] != null
            ? DateTime.parse(item['createdAt'] as String).toLocal()
            : null);
    final target = item['target'] as String? ?? 'ALL';
    final targetLabel = target == 'ALL'
        ? '🌍 Todos'
        : target == 'CUIDADORES'
            ? '🐕 Cuidadores'
            : '🏠 Dueños';
    final sentCount = item['sentCount'] as int? ?? 0;
    final status = item['status'] as String? ?? 'SENT';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(item['title'] as String? ?? '',
                style: TextStyle(
                    color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          _chip(status == 'SENT' ? '✅ Enviada' : '❌ Cancelada',
              status == 'SENT' ? Colors.green : Colors.red),
        ]),
        const SizedBox(height: 4),
        Text(item['message'] as String? ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: subtextColor, fontSize: 12)),
        const SizedBox(height: 8),
        Row(children: [
          _chip(targetLabel, Colors.blue),
          const SizedBox(width: 6),
          _chip('👥 $sentCount usuarios', Colors.purple),
          const Spacer(),
          if (sentAt != null)
            Text(_formatDate(sentAt),
                style: TextStyle(color: subtextColor, fontSize: 10)),
        ]),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  Helpers de UI
  // ─────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String label, Color textColor) => Text(label,
      style: TextStyle(
          color: textColor, fontSize: 13, fontWeight: FontWeight.w700));

  InputDecoration _inputDecor(String hint, Color subtextColor,
      Color borderColor, Color surface) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: subtextColor, fontSize: 13),
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: GardenColors.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      );
}

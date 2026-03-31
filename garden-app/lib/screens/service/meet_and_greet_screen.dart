import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../chat/chat_screen.dart';

class MeetAndGreetScreen extends StatefulWidget {
  final String bookingId;
  final String role; // 'CLIENT' | 'CAREGIVER'

  const MeetAndGreetScreen({
    super.key,
    required this.bookingId,
    required this.role,
  });

  @override
  State<MeetAndGreetScreen> createState() => _MeetAndGreetScreenState();
}

class _MeetAndGreetScreenState extends State<MeetAndGreetScreen> {
  Map<String, dynamic>? _mg;
  bool _loading = true;
  String _token = '';
  String _userId = '';
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  // Proposal form state
  String _modalidad = 'IN_PERSON';
  DateTime? _proposedDate;
  TimeOfDay? _proposedTime;
  final _noteCtrl = TextEditingController();
  final _meetingPointCtrl = TextEditingController();
  bool _submitting = false;

  // Complete form state
  final _notesCtrl = TextEditingController();
  bool? _approved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _meetingPointCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token') ?? '';
    _userId = prefs.getString('user_id') ?? '';
    await _loadMg();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMg() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/meet-and-greet/${widget.bookingId}'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        if (mounted) setState(() => _mg = data['data'] as Map<String, dynamic>?);
      }
    } catch (_) {}
  }

  Future<void> _propose() async {
    if (_proposedDate == null || _proposedTime == null) {
      _snack('Selecciona fecha y hora', isError: true);
      return;
    }
    if (_meetingPointCtrl.text.trim().isEmpty) {
      _snack('El punto de encuentro es obligatorio', isError: true);
      return;
    }
    final dt = DateTime(
      _proposedDate!.year, _proposedDate!.month, _proposedDate!.day,
      _proposedTime!.hour, _proposedTime!.minute,
    );
    if (mounted) setState(() => _submitting = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/meet-and-greet/${widget.bookingId}/propose'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'modalidad': _modalidad,
          'proposedDate': dt.toIso8601String(),
          'meetingPoint': _meetingPointCtrl.text.trim(),
          'note': _noteCtrl.text.trim(),
        }),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        if (mounted) setState(() => _mg = data['data'] as Map<String, dynamic>);
        if (mounted) Navigator.pop(context);
        _snack('Propuesta enviada');
      } else {
        _snack(data['error']?['message'] ?? 'Error', isError: true);
      }
    } catch (_) {
      _snack('Error de conexión', isError: true);
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _accept() async {
    if (mounted) setState(() => _submitting = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/meet-and-greet/${widget.bookingId}/accept'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        if (mounted) setState(() => _mg = data['data'] as Map<String, dynamic>);
        _snack('¡Meet & Greet confirmado!');
      } else {
        _snack(data['error']?['message'] ?? 'Error', isError: true);
      }
    } catch (_) {
      _snack('Error de conexión', isError: true);
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Meet & Greet'),
        content: const Text('¿Seguro que quieres cancelar el Meet & Greet?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cancelar')),
        ],
      ),
    );
    if (confirm != true) return;
    if (mounted) setState(() => _submitting = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/meet-and-greet/${widget.bookingId}/cancel'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        if (mounted) setState(() => _mg = data['data'] as Map<String, dynamic>);
        _snack('Meet & Greet cancelado');
      } else {
        _snack(data['error']?['message'] ?? 'Error', isError: true);
      }
    } catch (_) {
      _snack('Error de conexión', isError: true);
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _complete() async {
    if (_approved == null) {
      _snack('Indica si el hospedaje es compatible', isError: true);
      return;
    }
    if (mounted) setState(() => _submitting = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/meet-and-greet/${widget.bookingId}/complete'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'caregiverNotes': _notesCtrl.text.trim(),
          'approved': _approved,
        }),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        if (mounted) setState(() => _mg = data['data'] as Map<String, dynamic>);
        _snack(_approved! ? '¡Hospedaje confirmado!' : 'Reserva cancelada. El cliente recibirá reembolso.');
      } else {
        _snack(data['error']?['message'] ?? 'Error', isError: true);
      }
    } catch (_) {
      _snack('Error de conexión', isError: true);
    }
    if (mounted) setState(() => _submitting = false);
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? GardenColors.error : GardenColors.success,
    ));
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      const months = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
      const days = ['lun','mar','mié','jue','vie','sáb','dom'];
      final dayName = days[d.weekday - 1];
      final hour = d.hour.toString().padLeft(2, '0');
      final min = d.minute.toString().padLeft(2, '0');
      return '$dayName ${d.day} ${months[d.month - 1]} · $hour:$min';
    } catch (_) {
      return iso;
    }
  }

  String _countdown(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      final diff = d.difference(DateTime.now());
      if (diff.isNegative) return 'Ya pasó';
      if (diff.inDays > 0) return 'en ${diff.inDays} día${diff.inDays > 1 ? 's' : ''}';
      if (diff.inHours > 0) return 'en ${diff.inHours} hora${diff.inHours > 1 ? 's' : ''}';
      return 'en ${diff.inMinutes} min';
    } catch (_) {
      return '';
    }
  }

  void _showProposalSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProposalSheet(
        modalidad: _modalidad,
        proposedDate: _proposedDate,
        proposedTime: _proposedTime,
        noteCtrl: _noteCtrl,
        meetingPointCtrl: _meetingPointCtrl,
        submitting: _submitting,
        onModalidadChanged: (v) => setState(() => _modalidad = v),
        onDateChanged: (v) => setState(() => _proposedDate = v),
        onTimeChanged: (v) => setState(() => _proposedTime = v),
        onSubmit: _propose,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Meet & Greet', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: GardenColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: _buildBody(surface, textColor, subtextColor, borderColor),
              ),
            ),
    );
  }

  Widget _buildBody(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final status = _mg?['status'] as String? ?? 'PENDING_PROPOSAL';

    switch (status) {
      case 'PROPOSED':
        return _buildProposed(surface, textColor, subtextColor, borderColor);
      case 'ACCEPTED':
        return _buildAccepted(surface, textColor, subtextColor, borderColor);
      case 'COMPLETED':
        return _buildCompleted(surface, textColor, subtextColor, borderColor);
      case 'CANCELLED':
        return _buildCancelled(surface, textColor, subtextColor, borderColor);
      default:
        return _buildPendingProposal(surface, textColor, subtextColor, borderColor);
    }
  }

  // ── PENDING_PROPOSAL ──────────────────────────────────────────────────────
  Widget _buildPendingProposal(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            color: GardenColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Center(child: Text('🤝', style: TextStyle(fontSize: 48))),
        ),
        const SizedBox(height: 24),
        Text('Coordina el Meet & Greet',
          textAlign: TextAlign.center,
          style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text(
          'Reúnete con el ${widget.role == 'CAREGIVER' ? 'dueño' : 'cuidador'} antes del hospedaje para conocer a la mascota y verificar que todo sea compatible.',
          textAlign: TextAlign.center,
          style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8, runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _benefitChip('🐾 Conoce a la mascota'),
            _benefitChip('🏠 ${widget.role == 'CAREGIVER' ? 'El dueño ve tu espacio' : 'Verifica el espacio'}'),
            _benefitChip('✅ Confirma compatibilidad'),
          ],
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: GardenColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Text('💡', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('El Meet & Greet es opcional pero muy recomendado para hospedajes. Protege tanto al cuidador como a la mascota.',
                  style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        GardenButton(
          label: 'Proponer reunión',
          icon: Icons.event_rounded,
          height: 52,
          color: GardenColors.primary,
          onPressed: _showProposalSheet,
        ),
      ],
    );
  }

  // ── PROPOSED ──────────────────────────────────────────────────────────────
  Widget _buildProposed(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final proposedDate = _mg?['proposedDate'] as String?;
    final modalidad = _mg?['modalidad'] as String? ?? 'IN_PERSON';
    final proposedBy = _mg?['proposedBy'] as String?;
    final isProposer = _userId.isNotEmpty && _userId == proposedBy;

    // Label: "Propuesto por ti" si fui yo, sino "Propuesto por el cuidador/dueño"
    final String proposerLabel;
    if (isProposer) {
      proposerLabel = 'Propuesto por ti';
    } else if (widget.role == 'CLIENT') {
      proposerLabel = 'Propuesto por el cuidador';
    } else {
      proposerLabel = 'Propuesto por el dueño';
    }

    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: GardenColors.warning.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Center(child: Text('📅', style: TextStyle(fontSize: 36))),
        ),
        const SizedBox(height: 20),
        Text('Propuesta pendiente', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Hay una propuesta de Meet & Greet esperando confirmación',
          textAlign: TextAlign.center,
          style: TextStyle(color: subtextColor, fontSize: 13)),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: GardenColors.warning.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: modalidad == 'IN_PERSON'
                          ? GardenColors.primary.withValues(alpha: 0.1)
                          : GardenColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      modalidad == 'IN_PERSON' ? '📍 En persona' : '📹 Videollamada',
                      style: TextStyle(
                        color: modalidad == 'IN_PERSON' ? GardenColors.primary : GardenColors.accent,
                        fontWeight: FontWeight.w700, fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(_formatDate(proposedDate),
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(proposerLabel, style: TextStyle(color: subtextColor, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (isProposer) ...[
          // Quien propuso: solo puede cancelar su propuesta
          GardenButton(
            label: 'Cancelar propuesta',
            icon: Icons.close_rounded,
            height: 48,
            color: GardenColors.error,
            outline: true,
            onPressed: _submitting ? null : _cancel,
          ),
        ] else ...[
          // El otro: puede aceptar, contraproponer o cancelar
          GardenButton(
            label: 'Aceptar',
            icon: Icons.check_rounded,
            height: 52,
            color: GardenColors.success,
            onPressed: _submitting ? null : _accept,
          ),
          const SizedBox(height: 10),
          GardenButton(
            label: 'Proponer otra fecha',
            icon: Icons.edit_calendar_rounded,
            height: 48,
            color: GardenColors.primary,
            outline: true,
            onPressed: _showProposalSheet,
          ),
          const SizedBox(height: 10),
          GardenButton(
            label: 'Cancelar',
            icon: Icons.close_rounded,
            height: 44,
            color: GardenColors.error,
            outline: true,
            onPressed: _submitting ? null : _cancel,
          ),
        ],
      ],
    );
  }

  // ── ACCEPTED ──────────────────────────────────────────────────────────────
  Widget _buildAccepted(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final confirmedDate = _mg?['confirmedDate'] as String?;
    final modalidad = _mg?['modalidad'] as String? ?? 'IN_PERSON';
    final meetingPoint = _mg?['meetingPoint'] as String?;
    final countdown = _countdown(confirmedDate);

    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: GardenColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: GardenColors.success.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Text('🎉', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('¡Meet & Greet confirmado!',
                      style: TextStyle(color: GardenColors.success, fontWeight: FontWeight.w800, fontSize: 14)),
                    if (countdown.isNotEmpty)
                      Text(countdown, style: TextStyle(color: subtextColor, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Fecha confirmada', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(_formatDate(confirmedDate),
                style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (modalidad == 'IN_PERSON' ? GardenColors.primary : GardenColors.accent).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Text(modalidad == 'IN_PERSON' ? '📍' : '📹', style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(modalidad == 'IN_PERSON' ? 'En persona' : 'Videollamada',
                            style: TextStyle(
                              color: modalidad == 'IN_PERSON' ? GardenColors.primary : GardenColors.accent,
                              fontWeight: FontWeight.w700, fontSize: 13)),
                          if (meetingPoint != null && meetingPoint.isNotEmpty)
                            Text(meetingPoint, style: TextStyle(color: subtextColor, fontSize: 11))
                          else
                            Text(
                              modalidad == 'IN_PERSON'
                                  ? 'El cuidador compartirá su dirección por el chat'
                                  : 'Se coordinará el link por el chat',
                              style: TextStyle(color: subtextColor, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Botón principal: ir al chat con banner de la fecha
        GardenButton(
          label: 'Abrir chat',
          icon: Icons.chat_bubble_outline_rounded,
          height: 52,
          color: GardenColors.primary,
          onPressed: () {
            final confirmedDate = _mg?['confirmedDate'] as String?;
            final note = confirmedDate != null
                ? 'Meet & Greet · ${_formatDate(confirmedDate)}'
                : 'Meet & Greet confirmado';
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  bookingId: widget.bookingId,
                  otherPersonName: widget.role == 'CAREGIVER' ? 'Dueño de mascota' : 'Cuidador',
                  token: _token,
                  meetAndGreetNote: note,
                ),
              ),
            );
          },
        ),
        if (widget.role == 'CAREGIVER') ...[
          const SizedBox(height: 10),
          GardenButton(
            label: 'Marcar como completado',
            icon: Icons.check_circle_outline_rounded,
            height: 48,
            color: GardenColors.success,
            onPressed: _submitting ? null : _showCompleteSheet,
          ),
        ],
        const SizedBox(height: 10),
        GardenButton(
          label: 'Cancelar Meet & Greet',
          icon: Icons.close_rounded,
          height: 44,
          color: GardenColors.error,
          outline: true,
          onPressed: _submitting ? null : _cancel,
        ),
      ],
    );
  }

  // ── COMPLETED ─────────────────────────────────────────────────────────────
  Widget _buildCompleted(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final approved = _mg?['approved'] as bool?;
    final caregiverNotes = _mg?['caregiverNotes'] as String?;

    if (approved == null) {
      return Column(
        children: [
          const SizedBox(height: 32),
          const Text('⏳', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text('Meet & Greet completado', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('El cuidador está evaluando la compatibilidad. Te notificaremos pronto.',
            textAlign: TextAlign.center,
            style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5)),
        ],
      );
    }

    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (approved ? GardenColors.success : GardenColors.error).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: (approved ? GardenColors.success : GardenColors.error).withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Text(approved ? '✅' : '❌', style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      approved ? '¡Todo listo! Hospedaje confirmado' : 'Incompatibilidad detectada',
                      style: TextStyle(
                        color: approved ? GardenColors.success : GardenColors.error,
                        fontWeight: FontWeight.w800, fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      approved ? 'El cuidador confirmó que todo es compatible.' : 'La reserva fue cancelada. Recibirás reembolso completo.',
                      style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (caregiverNotes != null && caregiverNotes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notas del cuidador', style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(caregiverNotes, style: TextStyle(color: textColor, fontSize: 14, height: 1.5)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── CANCELLED ─────────────────────────────────────────────────────────────
  Widget _buildCancelled(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Column(
      children: [
        const SizedBox(height: 40),
        const Text('❌', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 20),
        Text('Meet & Greet cancelado', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Puedes proponer uno nuevo si lo necesitas.', style: TextStyle(color: subtextColor, fontSize: 13)),
        const SizedBox(height: 28),
        GardenButton(
          label: 'Proponer nuevo Meet & Greet',
          icon: Icons.event_rounded,
          height: 52,
          color: GardenColors.primary,
          onPressed: _showProposalSheet,
        ),
      ],
    );
  }

  // ── BENEFIT CHIP ──────────────────────────────────────────────────────────
  Widget _benefitChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: GardenColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
      ),
      child: Text(label, style: const TextStyle(color: GardenColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  void _showCompleteSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateSheet) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? GardenColors.darkSurface : GardenColors.lightSurface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                const Text('Completar Meet & Greet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Notas (opcional)',
                    hintText: 'Comportamiento, detalles...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('¿Todo listo para el hospedaje?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GardenButton(
                        label: '✅ Sí, confirmado',
                        height: 48,
                        color: GardenColors.success,
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() => _approved = true);
                          _complete();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GardenButton(
                        label: '❌ No compatible',
                        height: 48,
                        color: GardenColors.error,
                        outline: true,
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() => _approved = false);
                          _complete();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── PROPOSAL SHEET ─────────────────────────────────────────────────────────
class _ProposalSheet extends StatefulWidget {
  final String modalidad;
  final DateTime? proposedDate;
  final TimeOfDay? proposedTime;
  final TextEditingController noteCtrl;
  final TextEditingController meetingPointCtrl;
  final bool submitting;
  final ValueChanged<String> onModalidadChanged;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<TimeOfDay> onTimeChanged;
  final VoidCallback onSubmit;

  const _ProposalSheet({
    required this.modalidad,
    required this.proposedDate,
    required this.proposedTime,
    required this.noteCtrl,
    required this.meetingPointCtrl,
    required this.submitting,
    required this.onModalidadChanged,
    required this.onDateChanged,
    required this.onTimeChanged,
    required this.onSubmit,
  });

  @override
  State<_ProposalSheet> createState() => _ProposalSheetState();
}

class _ProposalSheetState extends State<_ProposalSheet> {
  late String _modalidad;
  DateTime? _date;
  TimeOfDay? _time;

  @override
  void initState() {
    super.initState();
    _modalidad = widget.modalidad;
    _date = widget.proposedDate;
    _time = widget.proposedTime;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final dateLabel = _date == null ? 'Seleccionar fecha' : '${_date!.day}/${_date!.month}/${_date!.year}';
    final timeLabel = _time == null ? 'Seleccionar hora' : '${_time!.hour.toString().padLeft(2,'0')}:${_time!.minute.toString().padLeft(2,'0')}';

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Proponer Meet & Greet', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),

          Text('Modalidad', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _modalChip('IN_PERSON', '📍 En persona', textColor, borderColor)),
              const SizedBox(width: 10),
              Expanded(child: _modalChip('VIDEO_CALL', '📹 Videollamada', textColor, borderColor)),
            ],
          ),
          const SizedBox(height: 16),

          Text('Fecha', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now().add(const Duration(days: 1)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 60)),
              );
              if (picked != null) {
                setState(() => _date = picked);
                widget.onDateChanged(picked);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 16, color: GardenColors.primary),
                  const SizedBox(width: 10),
                  Text(dateLabel, style: TextStyle(color: _date == null ? subtextColor : textColor, fontSize: 14)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Text('Hora', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 10, minute: 0),
              );
              if (picked != null) {
                setState(() => _time = picked);
                widget.onTimeChanged(picked);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 16, color: GardenColors.primary),
                  const SizedBox(width: 10),
                  Text(timeLabel, style: TextStyle(color: _time == null ? subtextColor : textColor, fontSize: 14)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Text('Punto de encuentro', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: GardenColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Obligatorio', style: TextStyle(color: GardenColors.error, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: widget.meetingPointCtrl,
            maxLines: 2,
            style: TextStyle(color: textColor, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Ej: Parque Central, entrada principal / Calle 45 #12-30',
              hintStyle: TextStyle(color: subtextColor, fontSize: 13),
              filled: true,
              fillColor: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
              contentPadding: const EdgeInsets.all(12),
              prefixIcon: const Icon(Icons.location_on_rounded, color: GardenColors.primary, size: 18),
            ),
          ),
          const SizedBox(height: 12),

          Text('Nota (opcional)', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: widget.noteCtrl,
            maxLines: 2,
            style: TextStyle(color: textColor, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Cualquier detalle adicional...',
              hintStyle: TextStyle(color: subtextColor, fontSize: 13),
              filled: true,
              fillColor: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 20),

          GardenButton(
            label: 'Enviar propuesta',
            icon: Icons.send_rounded,
            height: 52,
            color: GardenColors.primary,
            onPressed: widget.submitting ? null : widget.onSubmit,
          ),
        ],
      ),
    );
  }

  Widget _modalChip(String value, String label, Color textColor, Color borderColor) {
    final selected = _modalidad == value;
    return GestureDetector(
      onTap: () {
        setState(() => _modalidad = value);
        widget.onModalidadChanged(value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? GardenColors.primary.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? GardenColors.primary : borderColor, width: selected ? 2 : 1),
        ),
        child: Center(child: Text(label, style: TextStyle(
          color: selected ? GardenColors.primary : textColor,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 13))),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';

/// Panel admin: reportes de chat (acoso, spam, contenido inapropiado, etc.)
/// enviados por clientes/cuidadores. Requerido por App Store 1.2 (UGC) y
/// Google Play — mecanismo de revisión y acción sobre contenido reportado.
class AdminChatReportsScreen extends StatefulWidget {
  final String adminToken;
  const AdminChatReportsScreen({super.key, required this.adminToken});

  @override
  State<AdminChatReportsScreen> createState() => _AdminChatReportsScreenState();
}

class _AdminChatReportsScreenState extends State<AdminChatReportsScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;
  String _statusFilter = 'PENDING';

  static const _statusChips = <(String, String)>[
    ('PENDING', 'Pendientes'),
    ('REVIEWED', 'Revisados'),
    ('ACTION_TAKEN', 'Con acción'),
    ('DISMISSED', 'Descartados'),
    ('', 'Todos'),
  ];

  static const _reasonLabels = <String, String>{
    'HARASSMENT': 'Acoso',
    'INAPPROPRIATE_CONTENT': 'Contenido inapropiado',
    'SPAM': 'Spam',
    'SCAM_OR_FRAUD': 'Estafa o fraude',
    'THREATS': 'Amenazas',
    'OTHER': 'Otro',
  };

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final uri = Uri.parse('$_baseUrl/admin/chat-reports').replace(
        queryParameters: _statusFilter.isNotEmpty ? {'status': _statusFilter} : null,
      );
      final res = await http.get(uri, headers: {'Authorization': 'Bearer ${widget.adminToken}'});
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() => _reports = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (e) {
      debugPrint('AdminChatReports load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openDetail(Map<String, dynamic> report) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChatReportDetailSheet(
        report: report,
        adminToken: widget.adminToken,
        baseUrl: _baseUrl,
        reasonLabels: _reasonLabels,
        onResolved: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _statusChips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final (value, label) = _statusChips[i];
                  final selected = _statusFilter == value;
                  return ChoiceChip(
                    label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : textColor)),
                    selected: selected,
                    selectedColor: GardenColors.primary,
                    backgroundColor: surface,
                    side: BorderSide(color: selected ? GardenColors.primary : borderColor),
                    onSelected: (_) {
                      setState(() => _statusFilter = value);
                      _load();
                    },
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
                : _reports.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.shield_outlined, size: 64, color: subtextColor.withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            Text('Sin reportes de chat', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text('No hay reportes en este estado.', style: TextStyle(color: subtextColor, fontSize: 13)),
                          ]),
                        ),
                      )
                    : RefreshIndicator(
                        color: GardenColors.primary,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _reports.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final r = _reports[i];
                            final status = r['status'] as String? ?? 'PENDING';
                            final reason = _reasonLabels[r['reason']] ?? r['reason'] as String? ?? '';
                            final reporter = r['reporter'] as Map<String, dynamic>? ?? {};
                            final reported = r['reportedUser'] as Map<String, dynamic>? ?? {};

                            Color statusColor;
                            switch (status) {
                              case 'ACTION_TAKEN': statusColor = GardenColors.error; break;
                              case 'DISMISSED': statusColor = Colors.grey; break;
                              case 'REVIEWED': statusColor = GardenColors.info; break;
                              default: statusColor = GardenColors.warning;
                            }

                            return Material(
                              color: surface,
                              borderRadius: BorderRadius.circular(GardenRadius.lg),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(GardenRadius.lg),
                                onTap: () => _openDetail(r),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(GardenRadius.lg),
                                    border: Border.all(color: status == 'PENDING' ? GardenColors.warning.withValues(alpha: 0.4) : borderColor),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(GardenRadius.full),
                                              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                            ),
                                            child: Text(status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w800)),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(reason, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w800)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text('Reportado: ${reported['name'] ?? '—'}', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text('Por: ${reporter['name'] ?? '—'}', style: TextStyle(color: subtextColor, fontSize: 12)),
                                      if ((r['details'] as String?)?.isNotEmpty == true) ...[
                                        const SizedBox(height: 6),
                                        Text(r['details'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: subtextColor, fontSize: 12)),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DETALLE + RESOLUCIÓN
// ─────────────────────────────────────────────────────────────────────────────

class _ChatReportDetailSheet extends StatefulWidget {
  final Map<String, dynamic> report;
  final String adminToken;
  final String baseUrl;
  final Map<String, String> reasonLabels;
  final VoidCallback onResolved;

  const _ChatReportDetailSheet({
    required this.report,
    required this.adminToken,
    required this.baseUrl,
    required this.reasonLabels,
    required this.onResolved,
  });

  @override
  State<_ChatReportDetailSheet> createState() => _ChatReportDetailSheetState();
}

class _ChatReportDetailSheetState extends State<_ChatReportDetailSheet> {
  final _notesCtrl = TextEditingController();
  bool _suspendUser = false;
  bool _submitting = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolve(String status) async {
    if (_notesCtrl.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe una nota antes de resolver el reporte.'), backgroundColor: GardenColors.warning),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/admin/chat-reports/${widget.report['id']}/resolve'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': status,
          'adminNotes': _notesCtrl.text.trim(),
          'suspendUser': status == 'ACTION_TAKEN' ? _suspendUser : false,
        }),
      );
      final data = jsonDecode(res.body);
      if (mounted) {
        if (data['success'] == true) {
          Navigator.pop(context);
          widget.onResolved();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(status == 'ACTION_TAKEN' ? '✅ Reporte marcado con acción tomada' : '✅ Reporte descartado'), backgroundColor: GardenColors.success),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error']?['message'] ?? 'Error al resolver'), backgroundColor: GardenColors.error),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión'), backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final r = widget.report;
    final status = r['status'] as String? ?? 'PENDING';
    final reason = widget.reasonLabels[r['reason']] ?? r['reason'] as String? ?? '';
    final reporter = r['reporter'] as Map<String, dynamic>? ?? {};
    final reported = r['reportedUser'] as Map<String, dynamic>? ?? {};
    final snapshot = (r['messagesSnapshot'] as List?) ?? [];
    final isPending = status == 'PENDING' || status == 'REVIEWED';

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Reporte de chat — $reason', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('Reserva ${(r['bookingId'] as String? ?? '').substring(0, 8).toUpperCase()}', style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(height: 16),
            _infoRow('Reportado', reported['name'] as String? ?? '—', textColor, subtextColor),
            _infoRow('Email reportado', reported['email'] as String? ?? '—', textColor, subtextColor),
            _infoRow('Reportado por', reporter['name'] as String? ?? '—', textColor, subtextColor),
            if ((r['details'] as String?)?.isNotEmpty == true) _infoRow('Detalles', r['details'] as String, textColor, subtextColor),
            const SizedBox(height: 16),
            Text('MENSAJES (evidencia)', style: TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated, borderRadius: BorderRadius.circular(GardenRadius.md)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: snapshot.isEmpty
                    ? [Text('Sin mensajes.', style: TextStyle(color: subtextColor, fontSize: 12))]
                    : snapshot.map((m) {
                        final msg = Map<String, dynamic>.from(m as Map);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${msg['senderRole'] ?? ''}: ${msg['message'] ?? ''}',
                            style: TextStyle(color: textColor, fontSize: 12.5, height: 1.4),
                          ),
                        );
                      }).toList(),
              ),
            ),
            if (!isPending) ...[
              const SizedBox(height: 16),
              _infoRow('Estado', status, textColor, subtextColor),
              if ((r['adminNotes'] as String?)?.isNotEmpty == true) _infoRow('Notas admin', r['adminNotes'] as String, textColor, subtextColor),
            ],
            if (isPending) ...[
              const SizedBox(height: 20),
              Text('RESOLVER REPORTE', style: TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              TextField(
                controller: _notesCtrl,
                style: TextStyle(color: textColor, fontSize: 14),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Nota de resolución (obligatoria)',
                  hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary)),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _suspendUser,
                onChanged: (v) => setState(() => _suspendUser = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeColor: GardenColors.error,
                title: Text('Suspender cuenta del usuario reportado (solo aplica con "Acción tomada")', style: TextStyle(color: textColor, fontSize: 12.5)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : () => _resolve('DISMISSED'),
                      style: OutlinedButton.styleFrom(foregroundColor: subtextColor, side: BorderSide(color: borderColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: const Text('Descartar', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submitting ? null : () => _resolve('ACTION_TAKEN'),
                      style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: _submitting
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Acción tomada', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, Color textColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(color: subtextColor, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: textColor, fontSize: 13.5)),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Invitaciones de registro profesional: un código por persona, de un solo uso y con
/// vencimiento (reemplaza al antiguo código compartido). El código en claro solo se
/// muestra al crearlo — en el servidor solo queda su hash.
class ProfessionalInvitesCard extends StatefulWidget {
  final String adminToken;
  final Color textColor;
  final Color subtextColor;
  final Color borderColor;

  const ProfessionalInvitesCard({
    super.key,
    required this.adminToken,
    required this.textColor,
    required this.subtextColor,
    required this.borderColor,
  });

  @override
  State<ProfessionalInvitesCard> createState() => _ProfessionalInvitesCardState();
}

class _ProfessionalInvitesCardState extends State<ProfessionalInvitesCard> {
  static const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  final _labelCtrl = TextEditingController();
  List<Map<String, dynamic>> _invites = [];
  bool _loading = true;
  bool _creating = false;
  bool _forCompany = false;
  String? _error;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.adminToken}',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/admin/professional-invites'), headers: _headers);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _invites = ((body['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _error = body['success'] == true ? null : 'No se pudieron cargar las invitaciones';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _error = 'No se pudieron cargar las invitaciones'; _loading = false; });
    }
  }

  Future<void> _create() async {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) return;
    setState(() => _creating = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/admin/professional-invites'),
        headers: _headers,
        body: jsonEncode({'label': label, 'kind': _forCompany ? 'COMPANY' : 'PROFESSIONAL'}),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (body['success'] == true) {
        _labelCtrl.clear();
        final code = (body['data'] as Map<String, dynamic>)['code'] as String;
        await _showCode(label, code);
        await _load();
      } else {
        _snack(body['error']?['message'] as String? ?? 'No se pudo crear la invitación');
      }
    } catch (_) {
      _snack('No se pudo crear la invitación');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _revoke(String id) async {
    try {
      await http.delete(Uri.parse('$_baseUrl/admin/professional-invites/$id'), headers: _headers);
    } catch (_) {
      _snack('No se pudo revocar la invitación');
    }
    await _load();
  }

  Future<void> _showCode(String label, String code) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Código generado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Para: $label'),
            const SizedBox(height: 12),
            SelectableText(code, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            const SizedBox(height: 12),
            const Text('Cópialo ahora: no se puede volver a ver. Sirve una sola vez y vence en 7 días.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: code)),
            child: const Text('Copiar'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo')),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _statusLabel(String s) => switch (s) {
        'ACTIVE' => 'Vigente',
        'USED' => 'Usada',
        'EXPIRED' => 'Vencida',
        'REVOKED' => 'Revocada',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invitaciones de registro (profesional o empresa)',
              style: TextStyle(color: widget.textColor, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('Un código por persona o empresa, de un solo uso. Igual deben verificar su identidad.',
              style: TextStyle(color: widget.subtextColor, fontSize: 12)),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Profesional')),
              ButtonSegment(value: true, label: Text('Empresa')),
            ],
            selected: {_forCompany},
            onSelectionChanged: (v) => setState(() => _forCompany = v.first),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _labelCtrl,
                  decoration: InputDecoration(hintText: _forCompany ? 'Nombre de la empresa' : 'Para quién es (nombre)', isDense: true),
                  onSubmitted: (_) => _create(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _creating ? null : _create, child: Text(_creating ? '...' : 'Generar')),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))
          else if (_invites.isEmpty)
            Text('Aún no hay invitaciones.', style: TextStyle(color: widget.subtextColor, fontSize: 12))
          else
            ..._invites.take(20).map((i) {
              final status = i['status'] as String? ?? '';
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: widget.borderColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${i['kind'] == 'COMPANY' ? 'Empresa · ' : ''}${i['label'] ?? ''}',
                          style: TextStyle(color: widget.textColor, fontSize: 13), overflow: TextOverflow.ellipsis),
                    ),
                    Text(_statusLabel(status), style: TextStyle(color: widget.subtextColor, fontSize: 12)),
                    if (status == 'ACTIVE')
                      TextButton(onPressed: () => _revoke(i['id'] as String), child: const Text('Revocar')),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

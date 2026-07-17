import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';

/// Panel admin de capacitaciones de cuidadores. Dos categorías: AMATEUR
/// (obligatoria para cuidadores con 0 años de experiencia, una por servicio)
/// y EXPERIENCE (visible para todos, nunca obligatoria). Cada tema tiene un
/// video de YouTube, una introducción y exactamente 3 preguntas de opción
/// múltiple.
class AdminTrainingsScreen extends StatefulWidget {
  final String adminToken;
  const AdminTrainingsScreen({super.key, required this.adminToken});

  @override
  State<AdminTrainingsScreen> createState() => _AdminTrainingsScreenState();
}

class _AdminTrainingsScreenState extends State<AdminTrainingsScreen> {
  List<Map<String, dynamic>> _topics = [];
  bool _isLoading = true;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  Map<String, String> get _headers => {'Authorization': 'Bearer ${widget.adminToken}', 'Content-Type': 'application/json'};

  static const _serviceLabels = {'PASEO': 'Paseo', 'HOSPEDAJE': 'Hospedaje', 'GUARDERIA': 'Guardería'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse('$_baseUrl/admin/trainings'), headers: _headers);
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => _topics = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (e) {
      debugPrint('AdminTrainings load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete(String topicId) async {
    await http.delete(Uri.parse('$_baseUrl/admin/trainings/$topicId'), headers: _headers);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final amateur = _topics.where((t) => t['audience'] == 'AMATEUR').toList();
    final experience = _topics.where((t) => t['audience'] == 'EXPERIENCE').toList();

    return Scaffold(
      backgroundColor: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(context, MaterialPageRoute(
            builder: (_) => _TrainingEditScreen(adminToken: widget.adminToken, existingServices: _topics.map((t) => '${t['service']}_${t['audience']}').toSet()),
          ));
          if (created == true) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuevo tema'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('Capacitaciones', style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Un tema por servicio, máximo 3 preguntas cada uno.', style: TextStyle(color: subtextColor, fontSize: 13)),
                  const SizedBox(height: 20),
                  Text('AMATEUR — obligatoria para cuidadores nuevos', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 10),
                  if (amateur.isEmpty)
                    Text('Sin temas todavía.', style: TextStyle(color: subtextColor, fontSize: 13))
                  else
                    ...amateur.map((t) => _topicCard(t, textColor, subtextColor, surface, borderColor)),
                  const SizedBox(height: 24),
                  Text('EXPERIENCIA — visible para todos, opcional', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 10),
                  if (experience.isEmpty)
                    Text('Sin temas todavía.', style: TextStyle(color: subtextColor, fontSize: 13))
                  else
                    ...experience.map((t) => _topicCard(t, textColor, subtextColor, surface, borderColor)),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _topicCard(Map<String, dynamic> t, Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final isActive = t['isActive'] == true;
    final hasVideo = (t['videoUrl'] as String? ?? '').isNotEmpty;
    final questionCount = (t['questions'] as List).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(t['title'] as String, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            if (!isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: GardenColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: const Text('Inactivo', style: TextStyle(color: GardenColors.error, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 4),
          Text(_serviceLabels[t['service']] ?? t['service'] as String, style: TextStyle(color: subtextColor, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            Icon(hasVideo ? Icons.check_circle_outline : Icons.error_outline, size: 14, color: hasVideo ? GardenColors.success : GardenColors.error),
            const SizedBox(width: 4),
            Text(hasVideo ? 'Video cargado' : 'Falta video', style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(width: 16),
            Icon(questionCount == 3 ? Icons.check_circle_outline : Icons.error_outline, size: 14, color: questionCount == 3 ? GardenColors.success : GardenColors.error),
            const SizedBox(width: 4),
            Text('$questionCount/3 preguntas', style: TextStyle(color: subtextColor, fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            TextButton.icon(
              onPressed: () async {
                final updated = await Navigator.push<bool>(context, MaterialPageRoute(
                  builder: (_) => _TrainingEditScreen(adminToken: widget.adminToken, existing: t),
                ));
                if (updated == true) _load();
              },
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Editar'),
            ),
            TextButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => GardenGlassDialog(
                    title: const Text('¿Eliminar este tema?'),
                    content: const Text('Esta acción no se puede deshacer.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Eliminar', style: TextStyle(color: GardenColors.error, fontWeight: FontWeight.w700))),
                    ],
                  ),
                );
                if (confirmed == true) _delete(t['id'] as String);
              },
              icon: const Icon(Icons.delete_outline, size: 16, color: GardenColors.error),
              label: const Text('Eliminar', style: TextStyle(color: GardenColors.error)),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _TrainingEditScreen extends StatefulWidget {
  final String adminToken;
  final Map<String, dynamic>? existing;
  final Set<String>? existingServices; // solo al crear — para avisar de duplicados (service_audience)
  const _TrainingEditScreen({required this.adminToken, this.existing, this.existingServices});

  @override
  State<_TrainingEditScreen> createState() => _TrainingEditScreenState();
}

class _TrainingEditScreenState extends State<_TrainingEditScreen> {
  static const _services = ['PASEO', 'HOSPEDAJE', 'GUARDERIA'];
  static const _serviceLabels = {'PASEO': 'Paseo', 'HOSPEDAJE': 'Hospedaje', 'GUARDERIA': 'Guardería'};

  late String _service;
  late String _audience;
  late bool _isActive;
  final _titleCtrl = TextEditingController();
  final _introCtrl = TextEditingController();
  final _videoCtrl = TextEditingController();
  late List<_QuestionForm> _questions;
  bool _saving = false;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  Map<String, String> get _headers => {'Authorization': 'Bearer ${widget.adminToken}', 'Content-Type': 'application/json'};

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _service = e?['service'] as String? ?? _services.first;
    _audience = e?['audience'] as String? ?? 'AMATEUR';
    _isActive = e?['isActive'] as bool? ?? true;
    _titleCtrl.text = e?['title'] as String? ?? '';
    _introCtrl.text = e?['introduction'] as String? ?? '';
    _videoCtrl.text = e?['videoUrl'] as String? ?? '';
    final existingQuestions = (e?['questions'] as List?) ?? [];
    _questions = List.generate(3, (i) {
      if (i < existingQuestions.length) {
        final q = existingQuestions[i] as Map<String, dynamic>;
        return _QuestionForm.fromExisting(q);
      }
      return _QuestionForm.empty();
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _introCtrl.dispose();
    _videoCtrl.dispose();
    for (final q in _questions) {
      q.dispose();
    }
    super.dispose();
  }

  bool get _canSave {
    if (_titleCtrl.text.trim().isEmpty || _videoCtrl.text.trim().isEmpty) return false;
    for (final q in _questions) {
      if (!q.isValid) return false;
    }
    return true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = {
      'service': _service,
      'audience': _audience,
      'title': _titleCtrl.text.trim(),
      'introduction': _introCtrl.text.trim(),
      'videoUrl': _videoCtrl.text.trim(),
      'isActive': _isActive,
      'questions': _questions.map((q) => q.toJson()).toList(),
    };
    try {
      final res = widget.existing == null
          ? await http.post(Uri.parse('$_baseUrl/admin/trainings'), headers: _headers, body: jsonEncode(body))
          : await http.patch(Uri.parse('$_baseUrl/admin/trainings/${widget.existing!['id']}'), headers: _headers, body: jsonEncode(body));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        if (mounted) Navigator.pop(context, true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error']?['message'] as String? ?? 'Error al guardar')));
        }
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error de conexión')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    InputDecoration deco(String label) => InputDecoration(labelText: label, border: const OutlineInputBorder());

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(widget.existing == null ? 'Nuevo tema' : 'Editar tema', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: textColor),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _service,
                decoration: deco('Servicio'),
                items: _services.map((s) => DropdownMenuItem(value: s, child: Text(_serviceLabels[s]!))).toList(),
                onChanged: (v) => setState(() => _service = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _audience,
                decoration: deco('Categoría'),
                items: const [
                  DropdownMenuItem(value: 'AMATEUR', child: Text('Amateur (obligatoria)')),
                  DropdownMenuItem(value: 'EXPERIENCE', child: Text('Experiencia (opcional)')),
                ],
                onChanged: (v) => setState(() => _audience = v!),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          TextField(controller: _titleCtrl, decoration: deco('Título del tema')),
          const SizedBox(height: 16),
          TextField(controller: _introCtrl, decoration: deco('Introducción (se muestra antes del video)'), maxLines: 3),
          const SizedBox(height: 16),
          TextField(controller: _videoCtrl, decoration: deco('Link de YouTube')),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
            title: Text('Activo (visible para cuidadores)', style: TextStyle(color: textColor, fontSize: 14)),
            contentPadding: EdgeInsets.zero,
            activeColor: GardenColors.primary,
          ),
          const SizedBox(height: 16),
          Text('Quiz — exactamente 3 preguntas', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 10),
          ...List.generate(_questions.length, (i) => _questionEditor(i, textColor, subtextColor, surface, borderColor)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: GardenButton(label: _saving ? 'Guardando...' : 'Guardar', loading: _saving, onPressed: (_saving || !_canSave) ? null : _save),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _questionEditor(int i, Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final q = _questions[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Pregunta ${i + 1}', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: q.textCtrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Enunciado', border: OutlineInputBorder(), isDense: true),
          maxLines: 2,
        ),
        const SizedBox(height: 10),
        ...List.generate(q.choiceCtrls.length, (ci) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Radio<int>(
                  value: ci,
                  groupValue: q.correctIndex,
                  onChanged: (v) => setState(() => q.correctIndex = v),
                  activeColor: GardenColors.primary,
                ),
                Expanded(
                  child: TextField(
                    controller: q.choiceCtrls[ci],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: 'Opción ${ci + 1}', border: const OutlineInputBorder(), isDense: true),
                  ),
                ),
              ]),
            )),
        Text('Marca el círculo de la respuesta correcta.', style: TextStyle(color: subtextColor, fontSize: 11)),
      ]),
    );
  }
}

class _QuestionForm {
  final TextEditingController textCtrl;
  final List<TextEditingController> choiceCtrls;
  int? correctIndex;

  _QuestionForm({required this.textCtrl, required this.choiceCtrls, this.correctIndex});

  factory _QuestionForm.empty() => _QuestionForm(
        textCtrl: TextEditingController(),
        choiceCtrls: [TextEditingController(), TextEditingController(), TextEditingController()],
      );

  factory _QuestionForm.fromExisting(Map<String, dynamic> q) {
    final choices = List<String>.from(q['choices'] as List);
    while (choices.length < 3) {
      choices.add('');
    }
    return _QuestionForm(
      textCtrl: TextEditingController(text: q['text'] as String? ?? ''),
      choiceCtrls: choices.map((c) => TextEditingController(text: c)).toList(),
      correctIndex: q['correctIndex'] as int?,
    );
  }

  bool get isValid =>
      textCtrl.text.trim().isNotEmpty &&
      choiceCtrls.every((c) => c.text.trim().isNotEmpty) &&
      correctIndex != null;

  Map<String, dynamic> toJson() => {
        'text': textCtrl.text.trim(),
        'choices': choiceCtrls.map((c) => c.text.trim()).toList(),
        'correctIndex': correctIndex,
      };

  void dispose() {
    textCtrl.dispose();
    for (final c in choiceCtrls) {
      c.dispose();
    }
  }
}

/// Diálogo (abierto desde el detalle de un cuidador en admin) con el
/// progreso de sus capacitaciones y un switch por tema para eximirlo,
/// aunque sea obligatorio para su categoría.
class CaregiverTrainingsDialog extends StatefulWidget {
  final String caregiverId;
  final String token;
  final String baseUrl;
  final bool isDark;
  const CaregiverTrainingsDialog({required this.caregiverId, required this.token, required this.baseUrl, required this.isDark});

  @override
  State<CaregiverTrainingsDialog> createState() => CaregiverTrainingsDialogState();
}

class CaregiverTrainingsDialogState extends State<CaregiverTrainingsDialog> {
  List<Map<String, dynamic>> _topics = [];
  bool _loading = true;
  final Set<String> _updating = {};

  Map<String, String> get _headers => {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'};

  static const _serviceLabels = {'PASEO': 'Paseo', 'HOSPEDAJE': 'Hospedaje', 'GUARDERIA': 'Guardería'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/admin/caregivers/${widget.caregiverId}/trainings'), headers: _headers);
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => _topics = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleExemption(String topicId, bool exempted) async {
    setState(() => _updating.add(topicId));
    try {
      await http.patch(
        Uri.parse('${widget.baseUrl}/admin/caregivers/${widget.caregiverId}/trainings/$topicId/exempt'),
        headers: _headers,
        body: jsonEncode({'exempted': exempted}),
      );
      await _load();
    } catch (_) {}
    if (mounted) setState(() => _updating.remove(topicId));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return GardenGlassDialog(
      title: const Text('Capacitaciones del cuidador'),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
            : _topics.isEmpty
                ? Text('Este cuidador no ofrece ningún servicio con capacitaciones todavía.', style: TextStyle(color: subtextColor))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _topics.map((t) {
                      final completed = t['completedAt'] != null;
                      final exempted = t['exemptedByAdmin'] == true;
                      final mandatory = t['mandatory'] == true;
                      final updating = _updating.contains(t['id']);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(t['title'] as String, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13))),
                            Icon(completed ? Icons.check_circle : Icons.radio_button_unchecked, size: 16,
                                color: completed ? GardenColors.success : subtextColor),
                          ]),
                          Text('${_serviceLabels[t['service']] ?? t['service']} · ${mandatory ? 'Obligatoria' : 'Opcional'}',
                              style: TextStyle(color: subtextColor, fontSize: 11)),
                          if (mandatory) ...[
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(child: Text('Eximir de esta capacitación', style: TextStyle(color: textColor, fontSize: 12))),
                              if (updating)
                                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              else
                                Switch(
                                  value: exempted,
                                  onChanged: (v) => _toggleExemption(t['id'] as String, v),
                                  activeColor: GardenColors.primary,
                                ),
                            ]),
                          ],
                        ]),
                      );
                    }).toList(),
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
    );
  }
}

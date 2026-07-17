import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';

const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

class TrainingsScreen extends StatefulWidget {
  const TrainingsScreen({super.key});

  @override
  State<TrainingsScreen> createState() => _TrainingsScreenState();
}

class _TrainingsScreenState extends State<TrainingsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _amateur = [];
  List<Map<String, dynamic>> _experience = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/caregiver/trainings'),
        headers: {'Authorization': 'Bearer ${AuthState.token}'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() {
          _amateur = List<Map<String, dynamic>>.from(data['data']['amateur'] as List);
          _experience = List<Map<String, dynamic>>.from(data['data']['experience'] as List);
          _loading = false;
        });
      } else {
        setState(() { _error = 'No se pudieron cargar las capacitaciones'; _loading = false; });
      }
    } catch (_) {
      setState(() { _error = 'No se pudieron cargar las capacitaciones'; _loading = false; });
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

    // Obligatorias: temas amateur donde mandatory=true y todavía no completados/eximidos.
    final mandatoryPending = _amateur.where((t) => t['mandatory'] == true && t['completedAt'] == null).toList();
    // El resto (amateur ya no mandatory, o completado) se ve junto con experience como opcional.
    final optional = [
      ..._amateur.where((t) => !(t['mandatory'] == true && t['completedAt'] == null)),
      ..._experience,
    ];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Capacitaciones', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: textColor),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: subtextColor)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (mandatoryPending.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: GardenColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.info_outline_rounded, color: GardenColors.primary, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Completa estas capacitaciones obligatorias para poder recibir reservas.',
                                style: TextStyle(color: textColor, fontSize: 13),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        Text('Obligatorias', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        ...mandatoryPending.map((t) => _topicCard(t, textColor, subtextColor, surface, borderColor, mandatory: true)),
                        const SizedBox(height: 24),
                      ],
                      Text('De experiencia', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('No son obligatorias — te ayudan a mejorar tu servicio.',
                          style: TextStyle(color: subtextColor, fontSize: 12)),
                      const SizedBox(height: 10),
                      if (optional.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text('Todavía no hay capacitaciones de experiencia para tus servicios.',
                              style: TextStyle(color: subtextColor, fontSize: 13)),
                        )
                      else
                        ...optional.map((t) => _topicCard(t, textColor, subtextColor, surface, borderColor, mandatory: false)),
                    ],
                  ),
                ),
    );
  }

  static const _serviceLabels = {'PASEO': '🐕 Paseo', 'HOSPEDAJE': '🏠 Hospedaje', 'GUARDERIA': '🐾 Guardería'};

  Widget _topicCard(Map<String, dynamic> t, Color textColor, Color subtextColor, Color surface, Color borderColor, {required bool mandatory}) {
    final completed = t['completedAt'] != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final changed = await Navigator.push<bool>(context, MaterialPageRoute(
              builder: (_) => _TrainingTopicScreen(topic: t, mandatory: mandatory),
            ));
            if (changed == true) _load();
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: (completed ? GardenColors.success : GardenColors.primary).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(completed ? Icons.check_rounded : Icons.play_circle_outline_rounded,
                    color: completed ? GardenColors.success : GardenColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t['title'] as String, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(_serviceLabels[t['service']] ?? t['service'] as String,
                      style: TextStyle(color: subtextColor, fontSize: 12)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: subtextColor),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TrainingTopicScreen extends StatefulWidget {
  final Map<String, dynamic> topic;
  final bool mandatory;
  const _TrainingTopicScreen({required this.topic, required this.mandatory});

  @override
  State<_TrainingTopicScreen> createState() => _TrainingTopicScreenState();
}

class _TrainingTopicScreenState extends State<_TrainingTopicScreen> {
  late YoutubePlayerController _controller;
  bool _videoEnded = false;
  bool _markingWatched = false;
  bool _showQuiz = false;
  bool _submitting = false;
  final List<int?> _answers = [];
  Map<String, dynamic>? _result; // { passed, correctCount, total }

  @override
  void initState() {
    super.initState();
    _videoEnded = widget.topic['videoWatched'] == true;
    final questions = widget.topic['questions'] as List;
    _answers.addAll(List<int?>.filled(questions.length, null));

    final videoId = YoutubePlayerController.convertUrlToId(widget.topic['videoUrl'] as String) ?? widget.topic['videoUrl'] as String;
    _controller = YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(showControls: true, showFullscreenButton: true),
    );
    _controller.listen((value) {
      if (value.playerState == PlayerState.ended && !_videoEnded) {
        setState(() => _videoEnded = true);
        _markWatched();
      }
    });
  }

  Future<void> _markWatched() async {
    if (_markingWatched) return;
    _markingWatched = true;
    try {
      await http.post(
        Uri.parse('$_baseUrl/caregiver/trainings/${widget.topic['id']}/watched'),
        headers: {'Authorization': 'Bearer ${AuthState.token}'},
      );
    } catch (_) {}
  }

  Future<void> _submitQuiz() async {
    if (_answers.any((a) => a == null)) return;
    setState(() => _submitting = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/caregiver/trainings/${widget.topic['id']}/quiz'),
        headers: {'Authorization': 'Bearer ${AuthState.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({'answers': _answers}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() { _result = data['data'] as Map<String, dynamic>; _submitting = false; });
      } else {
        setState(() => _submitting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(data['error']?['message'] as String? ?? 'Error al enviar el quiz')));
        }
      }
    } catch (_) {
      setState(() => _submitting = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error de conexión')));
    }
  }

  void _retry() {
    setState(() {
      _result = null;
      for (var i = 0; i < _answers.length; i++) {
        _answers[i] = null;
      }
    });
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final passed = _result?['passed'] == true;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          title: Text(widget.topic['title'] as String, style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 16)),
          iconTheme: IconThemeData(color: textColor),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (passed) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: GardenColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(children: [
                  const Icon(Icons.check_circle_rounded, color: GardenColors.success, size: 48),
                  const SizedBox(height: 12),
                  Text('¡Capacitación completada!', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('Respondiste ${_result!['correctCount']}/${_result!['total']} correctamente.',
                      style: TextStyle(color: subtextColor, fontSize: 13)),
                  const SizedBox(height: 16),
                  GardenButton(label: 'Volver', onPressed: () => Navigator.pop(context, true)),
                ]),
              ),
            ] else ...[
              if ((widget.topic['introduction'] as String?)?.isNotEmpty == true) ...[
                Text(widget.topic['introduction'] as String, style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5)),
                const SizedBox(height: 16),
              ],
              if (!_showQuiz) ...[
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: YoutubePlayer(controller: _controller),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _videoEnded ? '✓ Video visto completo' : 'Mira el video completo para continuar',
                  style: TextStyle(color: _videoEnded ? GardenColors.success : subtextColor, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                GardenButton(
                  label: 'Continuar',
                  onPressed: _videoEnded ? () => setState(() => _showQuiz = true) : null,
                ),
              ] else ...[
                if (_result != null && !passed) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: GardenColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.close_rounded, color: GardenColors.error, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Respondiste ${_result!['correctCount']}/${_result!['total']} correctamente. Intenta de nuevo.',
                            style: TextStyle(color: textColor, fontSize: 13)),
                      ),
                    ]),
                  ),
                ],
                Text('Quiz — 3 preguntas', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 12),
                ...List.generate((widget.topic['questions'] as List).length, (i) {
                  final q = (widget.topic['questions'] as List)[i] as Map<String, dynamic>;
                  final choices = List<String>.from(q['choices'] as List);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${i + 1}. ${q['text']}', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 8),
                      ...List.generate(choices.length, (ci) => RadioListTile<int>(
                            value: ci,
                            groupValue: _answers[i],
                            onChanged: (v) => setState(() => _answers[i] = v),
                            title: Text(choices[ci], style: TextStyle(color: textColor, fontSize: 13)),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            activeColor: GardenColors.primary,
                            tileColor: surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: borderColor)),
                          )),
                    ]),
                  );
                }),
                const SizedBox(height: 8),
                GardenButton(
                  label: 'Enviar respuestas',
                  loading: _submitting,
                  onPressed: (_submitting || _answers.any((a) => a == null)) ? null : (_result != null ? _retry : _submitQuiz),
                ),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}

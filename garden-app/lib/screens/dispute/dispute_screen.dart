import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';

class DisputeScreen extends StatefulWidget {
  final String bookingId;
  final String role; // 'CLIENT' o 'CAREGIVER'
  final List<String>? clientReasons; // para el cuidador, las razones del cliente
  // true cuando se llega desde una reserva CANCELADA por no-show (en vez del
  // flujo normal de calificación baja en un servicio COMPLETADO). Cambia el
  // copy de la encuesta inicial, que de otro modo asume un pago retenido.
  final bool isNoShowDispute;

  const DisputeScreen({
    super.key,
    required this.bookingId,
    required this.role,
    this.clientReasons,
    this.isNoShowDispute = false,
  });

  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen> {
  String _token = '';
  int _step = 0; // 0: encuesta, 1: procesando IA, 2: resultado, 3: formulario de apelación
  final List<String> _selectedReasons = [];
  Map<String, dynamic>? _resolution;

  // Estado de la disputa fetched de GET /disputes/:bookingId — null mientras
  // no se conoce todavía (carga inicial). Determina, junto con widget.role,
  // qué encuesta bidireccional mostrar (ver _buildBody).
  String? _disputeStatus;
  bool _statusLoaded = false;

  // true mientras el paso 1 (processing) corresponde a una acción de
  // "reportar/iniciar" (client-report, caregiver-report — solo notifica a la
  // otra parte, sin IA todavía); false cuando corresponde a una acción de
  // "responder" (caregiver-response, client-response — dispara la IA). Usado
  // por _buildProcessing para mostrar el copy correcto en ambas direcciones.
  bool _isInitiatingAction = true;

  // Estado persistido de la disputa (incluye campos de apelación) — se carga
  // al entrar a la pantalla para saber si ya hay un veredicto, si se puede
  // apelar, o si ya está en apelación / resuelta por un admin humano.
  Map<String, dynamic>? _fullDispute;
  final TextEditingController _appealReasonCtrl = TextEditingController();
  final TextEditingController _appealEvidenceCtrl = TextEditingController();
  bool _submittingAppeal = false;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  // Opciones para el cliente
  static const List<Map<String, dynamic>> _clientOptions = [
    {'id': 'late', 'label': 'El cuidador no llegó a tiempo', 'icon': '⏰'},
    {'id': 'noshow', 'label': 'El cuidador nunca llegó / no inició el servicio', 'icon': '🚫'},
    {'id': 'injured', 'label': 'Mi mascota se lastimó o enfermó', 'icon': '🤕'},
    {'id': 'different', 'label': 'El servicio fue diferente a lo prometido', 'icon': '📋'},
    {'id': 'irresponsible', 'label': 'El cuidador fue irresponsable', 'icon': '😤'},
    {'id': 'space', 'label': 'El espacio no era adecuado', 'icon': '🏠'},
    {'id': 'nocommunication', 'label': 'No hubo comunicación durante el servicio', 'icon': '📵'},
  ];

  // Opciones de respuesta para el cuidador (basadas en lo que dijo el cliente)
  static const List<Map<String, dynamic>> _caregiverOptions = [
    {'id': 'agree', 'label': 'Reconozco el problema y me disculpo', 'icon': '🙏'},
    {'id': 'circumstances', 'label': 'Hubo circunstancias fuera de mi control', 'icon': '⚡'},
    {'id': 'disagree', 'label': 'No es correcto lo que dice el dueño', 'icon': '❌'},
    {'id': 'partial', 'label': 'Hubo un malentendido entre ambas partes', 'icon': '🤝'},
    {'id': 'emergency', 'label': 'Tuve una emergencia y no pude comunicarme', 'icon': '🚨'},
    {'id': 'evidence', 'label': 'Tengo fotos/evidencia que demuestra mi trabajo', 'icon': '📸'},
  ];

  // Opciones para el cliente cuando RESPONDE a un reporte del cuidador
  // (caregiver-report → PENDING_CLIENT). Distintas de _clientOptions porque
  // acá el cliente está replicando a un reclamo específico, no abriendo uno.
  static const List<Map<String, dynamic>> _clientResponseOptions = [
    {'id': 'i_was_there', 'label': 'Sí estuve, esperando en la dirección acordada', 'icon': '📍'},
    {'id': 'tried_contact', 'label': 'Intenté contactar al cuidador y no respondió', 'icon': '📵'},
    {'id': 'confusion', 'label': 'Hubo una confusión de horario o dirección', 'icon': '🕐'},
    {'id': 'disagree', 'label': 'No es correcto lo que dice el cuidador', 'icon': '❌'},
  ];

  // Opciones para el cuidador cuando INICIA un reporte (caregiver-report,
  // sin disputa previa) — simétrico a _clientOptions pero desde su lado.
  static const List<Map<String, dynamic>> _caregiverReportOptions = [
    {'id': 'no_answer', 'label': 'El cliente no contestó ni WhatsApp ni llamadas', 'icon': '📵'},
    {'id': 'nobody_home', 'label': 'No había nadie en la dirección acordada', 'icon': '🚪'},
    {'id': 'bad_address', 'label': 'La dirección no era correcta o no existía', 'icon': '📍'},
    {'id': 'other', 'label': 'Otro motivo', 'icon': '❓'},
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _appealReasonCtrl.dispose();
    _appealEvidenceCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadToken();
    await _checkDisputeStatus();
  }

  Future<void> _loadToken() async {
    setState(() => _token = AuthState.token);
  }

  /// Carga el estado persistido de la disputa. Si ya tiene un veredicto de la
  /// IA (RESOLVED) o está en apelación (APPEALED), salta directo a la
  /// pantalla de resultado en vez de mostrar la encuesta de nuevo.
  Future<void> _checkDisputeStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/disputes/${widget.bookingId}'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['data'] != null) {
        final dispute = data['data'] as Map<String, dynamic>;
        final status = dispute['status'] as String?;
        if (!mounted) return;
        setState(() {
          _fullDispute = dispute;
          _disputeStatus = status;
          _statusLoaded = true;
          if (status == 'RESOLVED' || status == 'APPEALED') {
            List<String> recs = [];
            try {
              recs = (jsonDecode(dispute['aiRecommendations'] as String? ?? '[]') as List).cast<String>();
            } catch (_) {}
            _resolution = {
              'verdict': dispute['aiVerdict'],
              'analysis': dispute['aiAnalysis'],
              'recommendations': recs,
            };
            _step = 2;
          } else if (status == 'PENDING_AI') {
            _step = 1;
          }
          // PENDING_CLIENT / PENDING_CAREGIVER: se mantiene la encuesta (step 0)
        });
        return;
      }
      // 404 con success:false (sin disputa todavía) — igual marcamos que la
      // consulta ya se resolvió, para no dejar el spinner de carga infinito.
      if (!mounted) return;
      setState(() { _statusLoaded = true; });
    } catch (_) {
      // Error de red: se mantiene la encuesta inicial, marcamos igual como
      // "consultado" para no bloquear la UI indefinidamente.
      if (!mounted) return;
      setState(() { _statusLoaded = true; });
    }
  }

  /// Fecha límite para apelar: 5 días hábiles después de `updatedAt` (el
  /// momento en que se resolvió la disputa), saltando sábados y domingos.
  bool _isWithinAppealWindow() {
    final updatedAtStr = _fullDispute?['updatedAt'] as String?;
    if (updatedAtStr == null) return false;
    DateTime deadline;
    try {
      deadline = DateTime.parse(updatedAtStr);
    } catch (_) {
      return false;
    }
    int added = 0;
    while (added < 5) {
      deadline = deadline.add(const Duration(days: 1));
      if (deadline.weekday != DateTime.saturday && deadline.weekday != DateTime.sunday) {
        added++;
      }
    }
    return !DateTime.now().isAfter(deadline);
  }

  Future<void> _submitAppeal() async {
    final reason = _appealReasonCtrl.text.trim();
    if (reason.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Explica tu apelación con al menos algunas frases.'), backgroundColor: GardenColors.error),
      );
      return;
    }
    setState(() => _submittingAppeal = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/disputes/${widget.bookingId}/appeal'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'reason': reason,
          if (_appealEvidenceCtrl.text.trim().isNotEmpty) 'newEvidence': _appealEvidenceCtrl.text.trim(),
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _checkDisputeStatus();
        if (!mounted) return;
        setState(() { _step = 2; });
      } else {
        throw Exception(data['error']?['message'] ?? 'No se pudo enviar la apelación');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: GardenColors.error),
      );
    } finally {
      if (mounted) setState(() => _submittingAppeal = false);
    }
  }

  Future<void> _submitClientReport() async {
    if (_selectedReasons.isEmpty) return;
    setState(() { _step = 1; _isInitiatingAction = true; });
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/disputes/${widget.bookingId}/client-report'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'reasons': _selectedReasons}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() { _step = 2; });
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      setState(() { _step = 0; });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error),
      );
    }
  }

  Future<void> _submitCaregiverResponse() async {
    if (_selectedReasons.isEmpty) return;
    setState(() { _step = 1; _isInitiatingAction = false; });
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/disputes/${widget.bookingId}/caregiver-response'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'responses': _selectedReasons}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _resolution = data['data'];
          _step = 2;
        });
        // Refresca el registro persistido (updatedAt, id, etc.) para que la
        // ventana de apelación se calcule sobre la fecha real de resolución.
        await _checkDisputeStatus();
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      setState(() { _step = 0; });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error),
      );
    }
  }

  /// El CUIDADOR reporta que el cliente nunca apareció (dirección simétrica
  /// de _submitClientReport). Solo alcanzable cuando aún no existe disputa.
  Future<void> _submitCaregiverReport() async {
    if (_selectedReasons.isEmpty) return;
    setState(() { _step = 1; _isInitiatingAction = true; });
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/disputes/${widget.bookingId}/caregiver-report'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'reasons': _selectedReasons}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _disputeStatus = 'PENDING_CLIENT';
          _step = 2;
        });
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      setState(() { _step = 0; });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: GardenColors.error),
      );
    }
  }

  /// El CLIENTE responde a un reporte que el cuidador ya inició
  /// (caregiver-report → PENDING_CLIENT). Dispara la resolución por IA igual
  /// que _submitCaregiverResponse.
  Future<void> _submitClientResponse() async {
    if (_selectedReasons.isEmpty) return;
    setState(() { _step = 1; _isInitiatingAction = false; });
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/disputes/${widget.bookingId}/client-response'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'responses': _selectedReasons}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _resolution = data['data'];
          _step = 2;
        });
        await _checkDisputeStatus();
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      setState(() { _step = 0; });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: GardenColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            elevation: 0,
            title: Text('Resolución de disputa', style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: textColor),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: _buildBody(),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_step == 1) return _buildProcessing();
    if (_step == 3) return _buildAppealForm();
    if (_step == 2) {
      // Ambos lados de un reporte "inicial" (sin veredicto todavía, paso
      // síncrono) ven una confirmación genérica en vez del resultado. Una vez
      // que la disputa ya tiene un veredicto (RESOLVED/APPEALED, cargado por
      // _checkDisputeStatus) o se acaba de resolver (client-response /
      // caregiver-response), ambas partes ven la misma pantalla de resultado.
      if (_resolution == null) {
        if (widget.role == 'CLIENT') return _buildClientConfirmation();
        return _buildCaregiverReportConfirmation();
      }
      return _buildResolution();
    }

    // Encuesta inicial (step 0) — esperar a conocer el estado real de la
    // disputa antes de decidir cuál encuesta mostrar, para no mostrar
    // brevemente la encuesta equivocada mientras carga.
    if (!_statusLoaded) {
      return const Center(child: GardenLoadingIndicator(color: GardenColors.primary));
    }

    if (widget.role == 'CLIENT') {
      if (_disputeStatus == 'PENDING_CLIENT') return _buildClientResponseSurvey();
      if (_disputeStatus == 'PENDING_CAREGIVER') {
        return _buildWaitingState('Ya enviaste tu reclamo — esperando la respuesta del cuidador.');
      }
      return _buildClientSurvey();
    }

    // role == CAREGIVER
    if (_disputeStatus == 'PENDING_CAREGIVER') return _buildCaregiverSurvey();
    if (_disputeStatus == 'PENDING_CLIENT') {
      return _buildWaitingState('Ya reportaste este caso — esperando la respuesta del dueño.');
    }
    return _buildCaregiverReportSurvey();
  }

  Widget _buildWaitingState(String message) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('⏳', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 20),
            Text('Esperando respuesta', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(message, style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5), textAlign: TextAlign.center),
            const SizedBox(height: 28),
            GardenButton(
              label: 'Volver al inicio',
              outline: true,
              onPressed: () => context.go('/marketplace'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientSurvey() {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Column(
      children: [
        // Banner de advertencia
        Container(
          padding: const EdgeInsets.all(16),
          color: GardenColors.warning.withValues(alpha: 0.08),
          child: Row(
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isNoShowDispute ? 'Reserva cancelada por no presentación' : 'Calificación baja detectada',
                      style: const TextStyle(color: GardenColors.warning, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    Text(
                      widget.isNoShowDispute
                          ? 'Si crees que la cancelación no fue tu responsabilidad, cuéntanos qué pasó.'
                          : 'El pago al cuidador está retenido. Cuéntanos qué pasó.',
                      style: TextStyle(color: subtextColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('¿Qué salió mal?', style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Selecciona todo lo que aplique. Tu respuesta es confidencial.', style: TextStyle(color: subtextColor, fontSize: 13)),
                const SizedBox(height: 20),

                // Opciones seleccionables
                ...(_clientOptions.map((option) {
                  final selected = _selectedReasons.contains(option['id'] as String);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _selectedReasons.remove(option['id'] as String);
                      } else {
                        _selectedReasons.add(option['id'] as String);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selected ? GardenColors.error.withValues(alpha: 0.08) : surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? GardenColors.error : borderColor,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(option['icon'] as String, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(option['label'] as String,
                              style: TextStyle(
                                color: selected ? GardenColors.error : textColor,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                fontSize: 14,
                              )),
                          ),
                          if (selected)
                            const Icon(Icons.check_circle_rounded, color: GardenColors.error, size: 20),
                        ],
                      ),
                    ),
                  );
                })),

                const SizedBox(height: 24),

                // Info del smart contract
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: GardenColors.polygon.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GardenColors.polygon.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    children: [
                      Text('⬡', style: TextStyle(color: GardenColors.polygon, fontSize: 16)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'La IA de GARDEN analizará ambas versiones y decidirá automáticamente. El smart contract ejecutará el veredicto.',
                          style: TextStyle(color: GardenColors.polygon, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),

        // Botón sticky
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: BoxDecoration(
            color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: GardenButton(
            label: 'Enviar reporte',
            icon: Icons.send_rounded,
            color: GardenColors.error,
            onPressed: _selectedReasons.isEmpty ? null : _submitClientReport,
          ),
        ),
      ],
    );
  }

  Widget _buildCaregiverSurvey() {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final clientReasonsLabels = (widget.clientReasons ?? []).map((id) {
      final option = _clientOptions.firstWhere((o) => o['id'] == id, orElse: () => {'label': id, 'icon': '❓'});
      return '${option['icon']} ${option['label']}';
    }).toList();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Lo que dijo el cliente
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: GardenColors.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: GardenColors.error.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('El dueño reportó:', style: TextStyle(color: GardenColors.error, fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      ...clientReasonsLabels.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $r', style: TextStyle(color: subtextColor, fontSize: 13)),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Text('¿Cuál es tu versión?', style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Selecciona la opción que mejor describe tu situación.', style: TextStyle(color: subtextColor, fontSize: 13)),
                const SizedBox(height: 16),

                ...(_caregiverOptions.map((option) {
                  final selected = _selectedReasons.contains(option['id'] as String);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _selectedReasons.remove(option['id'] as String);
                      } else {
                        _selectedReasons.add(option['id'] as String);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selected ? GardenColors.primary.withValues(alpha: 0.08) : surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? GardenColors.primary : borderColor,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(option['icon'] as String, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(option['label'] as String,
                              style: TextStyle(
                                color: selected ? GardenColors.primary : textColor,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                fontSize: 14,
                              )),
                          ),
                          if (selected)
                            const Icon(Icons.check_circle_rounded, color: GardenColors.primary, size: 20),
                        ],
                      ),
                    ),
                  );
                })),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: BoxDecoration(
            color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: GardenButton(
            label: 'Enviar mi versión',
            icon: Icons.send_rounded,
            onPressed: _selectedReasons.isEmpty ? null : _submitCaregiverResponse,
          ),
        ),
      ],
    );
  }

  /// El CLIENTE responde a un reporte que el cuidador ya inició
  /// (caregiver-report → PENDING_CLIENT). Simétrico de _buildCaregiverSurvey,
  /// mostrando las razones que dio el cuidador (dispute.caregiverResponse).
  Widget _buildClientResponseSurvey() {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final caregiverReasonIds = ((_fullDispute?['caregiverResponse'] as List?) ?? []).cast<String>();
    final caregiverReasonsLabels = caregiverReasonIds.map((id) {
      final option = _caregiverReportOptions.firstWhere((o) => o['id'] == id, orElse: () => {'label': id, 'icon': '❓'});
      return '${option['icon']} ${option['label']}';
    }).toList();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Lo que dijo el cuidador
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: GardenColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: GardenColors.warning.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tu cuidador reportó:', style: TextStyle(color: GardenColors.warning, fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      ...caregiverReasonsLabels.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $r', style: TextStyle(color: subtextColor, fontSize: 13)),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Text('¿Cuál es tu versión?', style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Selecciona la opción que mejor describe lo que pasó. La IA de GARDEN evaluará ambas versiones por igual.', style: TextStyle(color: subtextColor, fontSize: 13)),
                const SizedBox(height: 16),

                ...(_clientResponseOptions.map((option) {
                  final selected = _selectedReasons.contains(option['id'] as String);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _selectedReasons.remove(option['id'] as String);
                      } else {
                        _selectedReasons.add(option['id'] as String);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selected ? GardenColors.primary.withValues(alpha: 0.08) : surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? GardenColors.primary : borderColor,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(option['icon'] as String, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(option['label'] as String,
                              style: TextStyle(
                                color: selected ? GardenColors.primary : textColor,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                fontSize: 14,
                              )),
                          ),
                          if (selected)
                            const Icon(Icons.check_circle_rounded, color: GardenColors.primary, size: 20),
                        ],
                      ),
                    ),
                  );
                })),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: BoxDecoration(
            color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: GardenButton(
            label: 'Enviar mi versión',
            icon: Icons.send_rounded,
            onPressed: _selectedReasons.isEmpty ? null : _submitClientResponse,
          ),
        ),
      ],
    );
  }

  /// El CUIDADOR inicia un reporte de no-show (dirección simétrica de
  /// _buildClientSurvey) — solo alcanzable cuando aún no existe disputa.
  Widget _buildCaregiverReportSurvey() {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: GardenColors.warning.withValues(alpha: 0.08),
          child: Row(
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reportar cliente ausente',
                      style: TextStyle(color: GardenColors.warning, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    Text(
                      'El dueño todavía puede dar su versión — la IA de GARDEN evaluará ambas antes de decidir.',
                      style: TextStyle(color: subtextColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('¿Qué pasó?', style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Selecciona todo lo que aplique.', style: TextStyle(color: subtextColor, fontSize: 13)),
                const SizedBox(height: 20),

                ...(_caregiverReportOptions.map((option) {
                  final selected = _selectedReasons.contains(option['id'] as String);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _selectedReasons.remove(option['id'] as String);
                      } else {
                        _selectedReasons.add(option['id'] as String);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selected ? GardenColors.error.withValues(alpha: 0.08) : surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? GardenColors.error : borderColor,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(option['icon'] as String, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(option['label'] as String,
                              style: TextStyle(
                                color: selected ? GardenColors.error : textColor,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                fontSize: 14,
                              )),
                          ),
                          if (selected)
                            const Icon(Icons.check_circle_rounded, color: GardenColors.error, size: 20),
                        ],
                      ),
                    ),
                  );
                })),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: BoxDecoration(
            color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: GardenButton(
            label: 'Enviar reporte',
            icon: Icons.send_rounded,
            color: GardenColors.error,
            onPressed: _selectedReasons.isEmpty ? null : _submitCaregiverReport,
          ),
        ),
      ],
    );
  }

  Widget _buildCaregiverReportConfirmation() {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📋', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 20),
            Text('Reporte enviado', style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(
              'Notificamos al dueño para que dé su versión. Una vez que responda, la IA de GARDEN analizará el caso y tomará una decisión. Te notificaremos el resultado.',
              style: TextStyle(color: subtextColor, fontSize: 14, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            GardenButton(
              label: 'Volver al inicio',
              onPressed: () => context.go('/marketplace'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessing() {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const GardenLoadingIndicator(color: GardenColors.primary),
            const SizedBox(height: 32),
            Text(
              _isInitiatingAction
                ? 'Reporte enviado'
                : 'Analizando con IA...',
              style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              _isInitiatingAction
                ? (widget.role == 'CLIENT'
                    ? 'Notificamos al cuidador para que dé su versión. Te avisaremos del resultado.'
                    : 'Notificamos al dueño para que dé su versión. Te avisaremos del resultado.')
                : 'El agente de GARDEN está analizando ambas versiones para emitir un veredicto justo.',
              style: TextStyle(color: subtextColor, fontSize: 14, height: 1.6),
              textAlign: TextAlign.center,
            ),
            if (!_isInitiatingAction) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: GardenColors.polygon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('⬡ Consultando smart contract en Polygon...',
                  style: TextStyle(color: GardenColors.polygon, fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClientConfirmation() {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📋', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 20),
            Text('Reporte recibido', style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(
              'Notificamos al cuidador. Una vez que responda, la IA de GARDEN analizará el caso y tomará una decisión. Te notificaremos el resultado.',
              style: TextStyle(color: subtextColor, fontSize: 14, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            GardenButton(
              label: 'Volver al inicio',
              onPressed: () => context.go('/marketplace'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResolution() {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final verdict = _resolution?['verdict'] as String? ?? 'PARTIAL';
    final analysis = _resolution?['analysis'] as String? ?? '';
    final recommendations = (_resolution?['recommendations'] as List? ?? []).cast<String>();

    final isWin = verdict == 'CAREGIVER_WINS';
    final isLoss = verdict == 'CLIENT_WINS';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Veredicto
          Text(isWin ? '✅' : isLoss ? '❌' : '⚖️', style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            isWin ? '¡Disputa resuelta a tu favor!' : isLoss ? 'Disputa resuelta a favor del cliente' : 'Resolución parcial',
            style: TextStyle(
              color: isWin ? GardenColors.success : isLoss ? GardenColors.error : GardenColors.warning,
              fontSize: 20, fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isWin ? 'El pago fue depositado en tu billetera.' : isLoss ? 'El cliente recibirá un reembolso completo.' : 'Se aplicó una resolución parcial.',
            style: TextStyle(color: subtextColor, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Análisis de la IA
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: GardenColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.auto_awesome, color: GardenColors.primary, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Text('Análisis de GARDEN IA', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(analysis, style: TextStyle(color: subtextColor, fontSize: 13, height: 1.6)),
              ],
            ),
          ),

          // Recomendaciones del agente (siempre para el cuidador)
          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: GardenColors.secondary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: GardenColors.secondary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: GardenColors.secondary, size: 18),
                      SizedBox(width: 8),
                      Text('Recomendaciones para mejorar', style: TextStyle(color: GardenColors.secondary, fontWeight: FontWeight.w700, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...recommendations.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: GardenColors.secondary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: GardenColors.secondary, fontSize: 11, fontWeight: FontWeight.w700))),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(e.value, style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4))),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ],

          // Badge blockchain
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: GardenColors.polygon.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: GardenColors.polygon.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('⬡', style: TextStyle(color: GardenColors.polygon, fontSize: 14)),
                SizedBox(width: 8),
                Text('Veredicto registrado en Polygon Amoy', style: TextStyle(color: GardenColors.polygon, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildAppealSection(textColor, subtextColor, surface, borderColor),
          const SizedBox(height: 24),

          GardenButton(
            label: 'Ver mi billetera',
            icon: Icons.account_balance_wallet_outlined,
            onPressed: () => context.push('/wallet'),
          ),
          const SizedBox(height: 12),
          GardenButton(
            label: 'Ir al inicio',
            outline: true,
            onPressed: () => context.go('/marketplace'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Sección de apelación en la pantalla de resultado — depende del estado
  /// persistido de la disputa (`_fullDispute`), no solo del veredicto en
  /// memoria, porque necesita `status`, `appealedAt`, `appealResolution`, etc.
  Widget _buildAppealSection(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final d = _fullDispute;
    if (d == null) return const SizedBox.shrink();

    final status = d['status'] as String?;
    final appealResolution = d['appealResolution'] as String?;
    final appealVerdict = d['appealVerdict'] as String?;
    final appealedAt = d['appealedAt'] as String?;

    // 1) Ya hay una decisión final de un admin humano sobre la apelación.
    if (appealResolution != null) {
      final isWin = appealVerdict == 'CAREGIVER_WINS';
      final isLoss = appealVerdict == 'CLIENT_WINS';
      final color = isWin ? GardenColors.success : isLoss ? GardenColors.error : GardenColors.warning;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.verified_user_rounded, color: color, size: 18),
              const SizedBox(width: 8),
              Text('Resultado de la apelación', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
            ]),
            const SizedBox(height: 4),
            Text('Revisado por una persona del equipo de Garden — decisión definitiva.',
              style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(height: 12),
            Text(appealResolution, style: TextStyle(color: textColor, fontSize: 13, height: 1.5)),
          ],
        ),
      );
    }

    // 2) La disputa está en apelación, esperando revisión humana.
    if (status == 'APPEALED') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GardenColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.gavel_rounded, color: GardenColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'En apelación — un miembro de nuestro equipo está revisando tu caso.',
              style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
        ]),
      );
    }

    // 3) Aún se puede apelar (no apelada, dentro del plazo de 5 días hábiles).
    if (status == 'RESOLVED' && appealedAt == null && _isWithinAppealWindow()) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '¿No estás de acuerdo con esta decisión? Puedes apelarla dentro de los 5 días hábiles siguientes.',
            style: TextStyle(color: subtextColor, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          GardenButton(
            label: 'Apelar esta decisión',
            icon: Icons.gavel_rounded,
            outline: true,
            color: GardenColors.warning,
            onPressed: () => setState(() { _step = 3; }),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildAppealForm() {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.gavel_rounded, color: GardenColors.warning, size: 24),
            const SizedBox(width: 10),
            Expanded(child: Text('Apelar la decisión', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 8),
          Text(
            'Una persona del equipo de Garden (no el sistema automatizado) revisará tu caso con la nueva información que envíes. Esta decisión será definitiva.',
            style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),

          Text('¿Por qué apelas?', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: TextField(
              controller: _appealReasonCtrl,
              maxLines: 5,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Explica por qué crees que el veredicto no fue justo...',
                contentPadding: EdgeInsets.all(14),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text('Nueva evidencia (opcional)', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: TextField(
              controller: _appealEvidenceCtrl,
              maxLines: 4,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Describe fotos, mensajes u otra evidencia nueva que quieras que se considere...',
                contentPadding: EdgeInsets.all(14),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 28),

          GardenButton(
            label: 'Enviar apelación',
            icon: Icons.send_rounded,
            color: GardenColors.warning,
            loading: _submittingAppeal,
            onPressed: _submittingAppeal ? null : _submitAppeal,
          ),
          const SizedBox(height: 12),
          GardenButton(
            label: 'Cancelar',
            outline: true,
            onPressed: _submittingAppeal ? null : () => setState(() { _step = 2; }),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class DisputeScreen extends StatefulWidget {
  final String bookingId;
  final String role; // 'CLIENT' o 'CAREGIVER'
  final List<String>? clientReasons; // para el cuidador, las razones del cliente

  const DisputeScreen({
    super.key,
    required this.bookingId,
    required this.role,
    this.clientReasons,
  });

  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen> {
  String _token = '';
  bool _isLoading = false;
  int _step = 0; // 0: encuesta, 1: procesando IA, 2: resultado
  final List<String> _selectedReasons = [];
  Map<String, dynamic>? _resolution;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  // Opciones para el cliente
  static const List<Map<String, dynamic>> _clientOptions = [
    {'id': 'late', 'label': 'El cuidador no llegó a tiempo', 'icon': '⏰'},
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

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _token = prefs.getString('access_token') ?? '');
  }

  Future<void> _submitClientReport() async {
    if (_selectedReasons.isEmpty) return;
    setState(() { _isLoading = true; _step = 1; });
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/disputes/${widget.bookingId}/client-report'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'reasons': _selectedReasons}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() { _step = 2; _isLoading = false; });
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      setState(() { _step = 0; _isLoading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error),
      );
    }
  }

  Future<void> _submitCaregiverResponse() async {
    if (_selectedReasons.isEmpty) return;
    setState(() { _isLoading = true; _step = 1; });
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
          _isLoading = false;
        });
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      setState(() { _step = 0; _isLoading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error),
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
    if (_step == 2) {
      if (widget.role == 'CLIENT') return _buildClientConfirmation();
      return _buildResolution();
    }
    if (widget.role == 'CLIENT') return _buildClientSurvey();
    return _buildCaregiverSurvey();
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
          color: GardenColors.warning.withOpacity(0.08),
          child: Row(
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Calificación baja detectada', style: TextStyle(color: GardenColors.warning, fontWeight: FontWeight.w700, fontSize: 14)),
                    Text('El pago al cuidador está retenido. Cuéntanos qué pasó.', style: TextStyle(color: subtextColor, fontSize: 12)),
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
                        color: selected ? GardenColors.error.withOpacity(0.08) : surface,
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
                    color: GardenColors.polygon.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GardenColors.polygon.withOpacity(0.2)),
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
                    color: GardenColors.error.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: GardenColors.error.withOpacity(0.2)),
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
                        color: selected ? GardenColors.primary.withOpacity(0.08) : surface,
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
            const CircularProgressIndicator(color: GardenColors.primary, strokeWidth: 3),
            const SizedBox(height: 32),
            Text(
              widget.role == 'CLIENT'
                ? 'Reporte enviado'
                : 'Analizando con IA...',
              style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              widget.role == 'CLIENT'
                ? 'Notificamos al cuidador para que dé su versión. Te avisaremos del resultado.'
                : 'El agente de GARDEN está analizando ambas versiones para emitir un veredicto justo.',
              style: TextStyle(color: subtextColor, fontSize: 14, height: 1.6),
              textAlign: TextAlign.center,
            ),
            if (widget.role == 'CAREGIVER') ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: GardenColors.polygon.withOpacity(0.08),
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
                        color: GardenColors.primary.withOpacity(0.1),
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
                color: GardenColors.secondary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: GardenColors.secondary.withOpacity(0.2)),
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
                            color: GardenColors.secondary.withOpacity(0.15),
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
              color: GardenColors.polygon.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: GardenColors.polygon.withOpacity(0.3)),
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
}

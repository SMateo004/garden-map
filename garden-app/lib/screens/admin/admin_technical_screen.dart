import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';

class AdminTechnicalScreen extends StatefulWidget {
  final String adminToken;
  const AdminTechnicalScreen({super.key, required this.adminToken});

  @override
  State<AdminTechnicalScreen> createState() => _AdminTechnicalScreenState();
}

class _AdminTechnicalScreenState extends State<AdminTechnicalScreen>
    with TickerProviderStateMixin {
  static const _baseUrl = String.fromEnvironment('API_URL',
      defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  // Valores por defecto para cada setting (se usan si la API no devuelve el valor)
  static const Map<String, bool> _boolDefaults = {
    'marketplaceEnabled':      true,
    'paymentsEnabled':         true,
    'newRegistrationsEnabled': true,
    'maintenanceMode':         false,
    'walk30Enabled':           false,
    'hospedajeEnabled':        true,
    'paseoEnabled':            true,
    'retirosEnabled':          true,
    'disputasEnabled':         true,
    'preciosDinamicosEnabled': true,
    'meetGreetEnabled':        true,
  };

  static const Map<String, num> _numericDefaults = {
    'platformCommissionPct':   10,
    'montoMinimoRetiro':       50,
    'qrValidityHours':         24,
    'qrValidityMinutes':       15,
    'autoReleasePaymentHoras': 24,
    'hospedajeRefundAdminFeeBS': 10,
    'hospedajeRefund100Horas': 48,
    'hospedajeRefund50Horas':  24,
    'paseoRefund100Horas':     12,
    'paseoRefund50Horas':      6,
  };

  // Settings
  Map<String, dynamic> _settings = {};
  bool _loadingSettings = true;
  bool _savingSetting = false;

  // Agent monitor
  List<Map<String, dynamic>> _agentLogs = [];
  Map<String, dynamic> _agentStats = {};
  bool _loadingLogs = true;
  bool _loadingStats = true;
  bool _liveMode = false;
  Timer? _refreshTimer;
  String _selectedAgentType = 'ALL';
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  int _lastLogCount = 0;
  bool _newLogsArrived = false;
  String? _expandedLogId;

  // Instructions
  final _instructionController = TextEditingController();
  final _logsScrollController = ScrollController();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.adminToken}',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadSettings();
    _loadStats();
    _loadLogs();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pulseCtrl.dispose();
    _instructionController.dispose();
    _logsScrollController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  //  Data loading
  // ─────────────────────────────────────────────

  Future<void> _loadSettings() async {
    setState(() => _loadingSettings = true);
    try {
      final res = await http.get(
          Uri.parse('$_baseUrl/admin/settings'), headers: _headers);
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(
            () => _settings = Map<String, dynamic>.from(data['data'] as Map));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingSettings = false);
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    try {
      final res = await http.get(
          Uri.parse('$_baseUrl/admin/agent-stats'), headers: _headers);
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() =>
            _agentStats = Map<String, dynamic>.from(data['data'] as Map));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingStats = false);
  }

  Future<void> _loadLogs() async {
    setState(() => _loadingLogs = true);
    try {
      final typeParam = _selectedAgentType == 'ALL'
          ? ''
          : '&type=$_selectedAgentType';
      final res = await http.get(
          Uri.parse('$_baseUrl/admin/agent-logs?limit=100$typeParam'),
          headers: _headers);
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        final newLogs =
            (data['data'] as List).cast<Map<String, dynamic>>();
        if (newLogs.length > _lastLogCount && _lastLogCount > 0) {
          setState(() => _newLogsArrived = true);
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _newLogsArrived = false);
          });
        }
        setState(() {
          _agentLogs = newLogs;
          _lastLogCount = newLogs.length;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingLogs = false);
  }

  void _toggleLiveMode() {
    setState(() => _liveMode = !_liveMode);
    if (_liveMode) {
      _refreshTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _loadLogs());
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    setState(() => _savingSetting = true);
    try {
      final res = await http.patch(
        Uri.parse('$_baseUrl/admin/settings/$key'),
        headers: _headers,
        body: jsonEncode({'value': value}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => _settings[key] = value);
        _snack('Guardado: $key = $value', GardenColors.success);
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', GardenColors.error);
    }
    if (mounted) setState(() => _savingSetting = false);
  }

  Future<void> _emergencyAction(String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          const Text('Acción de emergencia'),
        ]),
        content: Text(
            'Confirmas ejecutar: "$action"?\n\nEsta acción afecta a TODOS los usuarios activos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: GardenColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    switch (action) {
      case 'pause_payments':
        await _updateSetting('paymentsEnabled', false);
        break;
      case 'maintenance':
        await _updateSetting('maintenanceMode', true);
        break;
      case 'disable_marketplace':
        await _updateSetting('marketplaceEnabled', false);
        break;
      case 'disable_registrations':
        await _updateSetting('newRegistrationsEnabled', false);
        break;
    }
  }

  Future<void> _sendInstruction() async {
    final instruction = _instructionController.text.trim();
    if (instruction.isEmpty) return;
    try {
      await http.post(
        Uri.parse('$_baseUrl/admin/agent-logs'),
        headers: _headers,
        body: jsonEncode({
          'agentType': 'CUSTOM',
          'action': 'ADMIN_INSTRUCTION',
          'input': {'instruction': instruction},
        }),
      );
      _instructionController.clear();
      await Future.wait([_loadLogs(), _loadStats()]);
      _snack('Instrucción registrada en el log', GardenColors.success);
    } catch (e) {
      _snack('Error: $e', GardenColors.error);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2)));
  }

  // ─────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────

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

    return Container(
      color: bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF3F51B5)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.developer_mode_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Panel Técnico',
                    style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                Text('Control del sistema en tiempo real',
                    style: TextStyle(color: subtextColor, fontSize: 12)),
              ]),
            ]),
            const SizedBox(height: 24),

            // ── CONFIGURACIÓN DEL SISTEMA ──────────────────
            _sectionTitle('Configuración del Sistema', textColor),
            const SizedBox(height: 4),
            Text('Los cambios se aplican al instante para todos los usuarios.',
                style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(height: 12),

            if (_loadingSettings)
              const Center(child: CircularProgressIndicator(color: GardenColors.primary))
            else
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Categoría: Servicios ───────────────────
                _categoryHeader('🐾 Servicios', subtextColor),
                _settingsCard(surface, borderColor, [
                  _buildBoolTile(icon: Icons.store_mall_directory_outlined, iconColor: GardenColors.primary,
                    title: 'Marketplace activo', subtitle: 'Cuidadores visibles para dueños',
                    settingKey: 'marketplaceEnabled', surface: surface, textColor: textColor,
                    subtextColor: subtextColor, borderColor: borderColor),
                  _buildBoolTile(icon: Icons.home_outlined, iconColor: Colors.indigo,
                    title: 'Hospedaje habilitado', subtitle: 'Permite reservas de hospedaje',
                    settingKey: 'hospedajeEnabled', surface: surface, textColor: textColor,
                    subtextColor: subtextColor, borderColor: borderColor),
                  _buildBoolTile(icon: Icons.pets_outlined, iconColor: Colors.teal,
                    title: 'Paseos habilitados', subtitle: 'Permite reservas de paseos',
                    settingKey: 'paseoEnabled', surface: surface, textColor: textColor,
                    subtextColor: subtextColor, borderColor: borderColor),
                  _buildBoolTile(icon: Icons.handshake_outlined, iconColor: Colors.amber,
                    title: 'Meet & Greet activo', subtitle: 'Reuniones de presentación',
                    settingKey: 'meetGreetEnabled', surface: surface, textColor: textColor,
                    subtextColor: subtextColor, borderColor: borderColor),
                  _buildBoolTile(icon: Icons.directions_walk_rounded, iconColor: Colors.blue,
                    title: 'Paseos de 30 min', subtitle: 'Deshabilitado por política actual',
                    settingKey: 'walk30Enabled', enabled: false, surface: surface, textColor: textColor,
                    subtextColor: subtextColor, borderColor: borderColor),
                  _buildBoolTile(icon: Icons.trending_up_rounded, iconColor: Colors.deepOrange,
                    title: 'Precios dinámicos', subtitle: 'Ajuste automático por demanda/temporada',
                    settingKey: 'preciosDinamicosEnabled', surface: surface, textColor: textColor,
                    subtextColor: subtextColor, borderColor: borderColor),
                ]),
                const SizedBox(height: 16),

                // ── Categoría: Usuarios ────────────────────
                _categoryHeader('👤 Usuarios y Seguridad', subtextColor),
                _settingsCard(surface, borderColor, [
                  _buildBoolTile(icon: Icons.person_add_outlined, iconColor: Colors.orange,
                    title: 'Nuevos registros', subtitle: 'Se pueden crear nuevas cuentas',
                    settingKey: 'newRegistrationsEnabled', surface: surface, textColor: textColor,
                    subtextColor: subtextColor, borderColor: borderColor),
                  _buildBoolTile(icon: Icons.construction_rounded, iconColor: Colors.red,
                    title: 'Modo mantenimiento', subtitle: 'Muestra aviso a todos los usuarios',
                    settingKey: 'maintenanceMode', surface: surface, textColor: textColor,
                    subtextColor: subtextColor, borderColor: borderColor),
                ]),
                const SizedBox(height: 16),

                // ── Categoría: Pagos y Finanzas ────────────
                _categoryHeader('💰 Pagos y Finanzas', subtextColor),
                _settingsCard(surface, borderColor, [
                  _buildBoolTile(icon: Icons.payment_outlined, iconColor: Colors.green,
                    title: 'Pagos habilitados', subtitle: 'Los usuarios pueden realizar pagos',
                    settingKey: 'paymentsEnabled', surface: surface, textColor: textColor,
                    subtextColor: subtextColor, borderColor: borderColor),
                  _buildBoolTile(icon: Icons.account_balance_wallet_outlined, iconColor: Colors.cyan,
                    title: 'Retiros habilitados', subtitle: 'Cuidadores pueden solicitar retiros',
                    settingKey: 'retirosEnabled', surface: surface, textColor: textColor,
                    subtextColor: subtextColor, borderColor: borderColor),
                  _buildBoolTile(icon: Icons.gavel_rounded, iconColor: Colors.purple,
                    title: 'Disputas habilitadas', subtitle: 'Clientes pueden abrir disputas',
                    settingKey: 'disputasEnabled', surface: surface, textColor: textColor,
                    subtextColor: subtextColor, borderColor: borderColor),
                  _buildNumericTile(icon: Icons.percent_rounded, iconColor: Colors.green,
                    title: 'Comisión GARDEN', subtitle: 'Porcentaje aplicado a cada reserva',
                    settingKey: 'platformCommissionPct', unit: '%', surface: surface,
                    textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
                  _buildNumericTile(icon: Icons.arrow_downward_rounded, iconColor: Colors.cyan,
                    title: 'Retiro mínimo', subtitle: 'Monto mínimo para solicitar retiro',
                    settingKey: 'montoMinimoRetiro', unit: 'Bs', surface: surface,
                    textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
                  _buildNumericTile(icon: Icons.qr_code_2_rounded, iconColor: Colors.indigo,
                    title: 'Validez QR (horas)', subtitle: 'Horas de vigencia del QR de pago',
                    settingKey: 'qrValidityHours', unit: 'h', surface: surface,
                    textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
                  _buildNumericTile(icon: Icons.timer_outlined, iconColor: Colors.teal,
                    title: 'Ventana QR (minutos)', subtitle: 'Minutos para iniciar pago con QR',
                    settingKey: 'qrValidityMinutes', unit: 'min', surface: surface,
                    textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
                  _buildNumericTile(icon: Icons.auto_mode_rounded, iconColor: Colors.amber,
                    title: 'Auto-liberación (horas)', subtitle: 'Horas para liberar pago sin reseña',
                    settingKey: 'autoReleasePaymentHoras', unit: 'h', surface: surface,
                    textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
                ]),
                const SizedBox(height: 16),

                // ── Categoría: Política HOSPEDAJE ──────────
                _categoryHeader('🏠 Política Cancelación — Hospedaje', subtextColor),
                _settingsCard(surface, borderColor, [
                  _buildNumericTile(icon: Icons.monetization_on_outlined, iconColor: Colors.orange,
                    title: 'Tarifa admin (Bs)', subtitle: 'Fee fijo que retiene GARDEN al cancelar',
                    settingKey: 'hospedajeRefundAdminFeeBS', unit: 'Bs', surface: surface,
                    textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
                  _buildNumericTile(icon: Icons.check_circle_outline_rounded, iconColor: Colors.green,
                    title: 'Reembolso 100% (horas)', subtitle: 'Horas antes del servicio → 100% devuelto',
                    settingKey: 'hospedajeRefund100Horas', unit: 'h', surface: surface,
                    textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
                  _buildNumericTile(icon: Icons.timelapse_rounded, iconColor: Colors.amber,
                    title: 'Reembolso 50% (horas)', subtitle: 'Horas antes del servicio → 50% devuelto',
                    settingKey: 'hospedajeRefund50Horas', unit: 'h', surface: surface,
                    textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
                ]),
                const SizedBox(height: 16),

                // ── Categoría: Política PASEO ──────────────
                _categoryHeader('🦮 Política Cancelación — Paseo', subtextColor),
                _settingsCard(surface, borderColor, [
                  _buildNumericTile(icon: Icons.check_circle_outline_rounded, iconColor: Colors.green,
                    title: 'Reembolso 100% (horas)', subtitle: 'Horas antes del paseo → 100% devuelto',
                    settingKey: 'paseoRefund100Horas', unit: 'h', surface: surface,
                    textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
                  _buildNumericTile(icon: Icons.timelapse_rounded, iconColor: Colors.amber,
                    title: 'Reembolso 50% (horas)', subtitle: 'Horas antes del paseo → 50% devuelto',
                    settingKey: 'paseoRefund50Horas', unit: 'h', surface: surface,
                    textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
                ]),
              ]),

            const SizedBox(height: 28),

            // ── EMERGENCY BUTTONS ──────────────────────────
            _sectionTitle('Acciones de Emergencia', textColor),
            const SizedBox(height: 4),
            Text(
                'Estas acciones afectan a TODOS los usuarios activos de inmediato.',
                style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _emergencyBtn('⏸ Pausar pagos', Colors.orange,
                  () => _emergencyAction('pause_payments')),
              _emergencyBtn('🔧 Modo mantenimiento', Colors.red.shade700,
                  () => _emergencyAction('maintenance')),
              _emergencyBtn('🛒 Pausar marketplace', Colors.purple,
                  () => _emergencyAction('disable_marketplace')),
              _emergencyBtn('🔒 Bloquear registros', Colors.deepOrange,
                  () => _emergencyAction('disable_registrations')),
            ]),

            const SizedBox(height: 28),

            // ── AGENT STATS ────────────────────────────────
            _sectionTitle('Estadísticas de Agentes IA', textColor),
            const SizedBox(height: 12),
            _buildAgentStats(surface, textColor, subtextColor, borderColor),

            const SizedBox(height: 28),

            // ── AGENT MONITOR ──────────────────────────────
            Row(children: [
              Expanded(
                  child: _sectionTitle('Monitor de Agentes', textColor)),
              GestureDetector(
                onTap: _toggleLiveMode,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _liveMode
                        ? Colors.red.withOpacity(0.15)
                        : GardenColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _liveMode
                            ? Colors.red
                            : GardenColors.primary),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_liveMode)
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, __) => Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.red
                                .withOpacity(_pulseAnim.value),
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    else
                      const Icon(Icons.play_circle_outline,
                          size: 12, color: GardenColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      _liveMode ? 'EN VIVO' : 'Ver en vivo',
                      style: TextStyle(
                          color: _liveMode
                              ? Colors.red
                              : GardenColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: subtextColor,
                onPressed: () => Future.wait([_loadLogs(), _loadStats()]),
                tooltip: 'Recargar',
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ]),
            const SizedBox(height: 8),

            // Filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  'ALL', 'PRECIO', 'CALIFICACION', 'DISPUTA', 'CUSTOM'
                ].map((type) {
                  final sel = _selectedAgentType == type;
                  final count = type == 'ALL'
                      ? (_agentStats['total'] as int? ?? 0)
                      : ((_agentStats['byType'] as Map?)?[type] as int? ?? 0);
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedAgentType = type);
                      _loadLogs();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: sel
                            ? GardenColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: sel
                                ? GardenColors.primary
                                : borderColor),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          type == 'ALL' ? 'Todos' : type,
                          style: TextStyle(
                              color: sel ? Colors.white : subtextColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                        if (!_loadingStats && count > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: sel
                                  ? Colors.white.withOpacity(0.3)
                                  : GardenColors.primary
                                      .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('$count',
                                style: TextStyle(
                                    color: sel
                                        ? Colors.white
                                        : GardenColors.primary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),

            if (_newLogsArrived)
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green
                        .withOpacity(_pulseAnim.value * 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fiber_new_rounded,
                          color: Colors.green, size: 16),
                      SizedBox(width: 6),
                      Text('Nuevos eventos detectados',
                          style: TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),

            Container(
              height: 360,
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: _loadingLogs
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: GardenColors.primary))
                  : _agentLogs.isEmpty
                      ? Center(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                            const Icon(Icons.smart_toy_outlined,
                                size: 40,
                                color: Color(0xFF484F58)),
                            const SizedBox(height: 8),
                            Text('Sin actividad registrada',
                                style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13)),
                          ]))
                      : ListView.builder(
                          controller: _logsScrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _agentLogs.length,
                          itemBuilder: (_, i) =>
                              _buildLogEntry(_agentLogs[i]),
                        ),
            ),

            const SizedBox(height: 20),

            // ── AGENT INSTRUCTIONS ─────────────────────────
            _sectionTitle('Registrar instrucción manual', textColor),
            const SizedBox(height: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    color: Colors.blue, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Las instrucciones se registran en el log de agentes. '
                    'La ejecución automática se activa cuando los agentes procesan el evento.',
                    style:
                        TextStyle(color: Colors.blue.shade300, fontSize: 11),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _instructionController,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText:
                        'Ej: Revisar cuidadores con baja calificación en zona NORTE',
                    hintStyle:
                        TextStyle(color: subtextColor, fontSize: 13),
                    filled: true,
                    fillColor: surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: GardenColors.primary, width: 2)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _sendInstruction(),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: GardenColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size(52, 52),
                  padding: EdgeInsets.zero,
                  elevation: 0,
                ),
                onPressed: _sendInstruction,
                child: const Icon(Icons.send_rounded, size: 20),
              ),
            ]),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Widgets helpers
  // ─────────────────────────────────────────────

  Widget _sectionTitle(String title, Color textColor) => Text(title,
      style: TextStyle(
          color: textColor, fontSize: 16, fontWeight: FontWeight.w800));

  Widget _buildAgentStats(Color surface, Color textColor, Color subtextColor,
      Color borderColor) {
    if (_loadingStats) {
      return const SizedBox(
          height: 80,
          child: Center(
              child: CircularProgressIndicator(color: GardenColors.primary)));
    }
    final total = _agentStats['total'] as int? ?? 0;
    final last24h = _agentStats['last24h'] as int? ?? 0;
    final byStatus =
        (_agentStats['byStatus'] as Map?)?.cast<String, dynamic>() ?? {};
    final errors = byStatus['ERROR'] as int? ?? 0;
    final pending = byStatus['PENDING'] as int? ?? 0;
    final success = byStatus['SUCCESS'] as int? ?? 0;

    return Row(children: [
      Expanded(child: _statCard('Total', '$total', Icons.analytics_outlined, Colors.blue, surface, textColor, subtextColor)),
      const SizedBox(width: 8),
      Expanded(child: _statCard('Últimas 24h', '$last24h', Icons.access_time_rounded, Colors.green, surface, textColor, subtextColor)),
      const SizedBox(width: 8),
      Expanded(child: _statCard('Errores', '$errors', Icons.error_outline_rounded, errors > 0 ? Colors.red : Colors.grey, surface, textColor, subtextColor)),
      const SizedBox(width: 8),
      Expanded(child: _statCard('Éxitos', '$success', Icons.check_circle_outline_rounded, Colors.teal, surface, textColor, subtextColor)),
    ]);
  }

  Widget _statCard(String label, String value, IconData icon, Color color,
      Color surface, Color textColor, Color subtextColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
        Text(label,
            style: TextStyle(color: subtextColor, fontSize: 10),
            textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _categoryHeader(String title, Color subtextColor) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title,
        style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
  );

  Widget _settingsCard(Color surface, Color borderColor, List<Widget> tiles) {
    final divider = Divider(height: 1, color: borderColor);
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: tiles.expand((w) => [w, divider]).toList()..removeLast(),
      ),
    );
  }

  Widget _buildBoolTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String settingKey,
    bool enabled = true,
    required Color surface,
    required Color textColor,
    required Color subtextColor,
    required Color borderColor,
  }) {
    // Si la API devolvió el valor → úsalo; si no → usa el default correcto
    final value = _settings.containsKey(settingKey)
        ? _settings[settingKey] == true
        : (_boolDefaults[settingKey] ?? false);
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled ? iconColor.withOpacity(0.12) : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: enabled ? iconColor : Colors.grey.shade500, size: 18),
      ),
      title: Text(title,
          style: TextStyle(
              color: enabled ? textColor : subtextColor,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
      subtitle: Row(children: [
        Expanded(child: Text(subtitle, style: TextStyle(color: subtextColor, fontSize: 11))),
        if (!enabled) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('No disponible',
                style: TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
      trailing: _savingSetting
          ? const SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.primary))
          : Switch(
              value: value,
              onChanged: enabled ? (v) => _updateSetting(settingKey, v) : null,
              activeColor: GardenColors.primary,
            ),
    );
  }

  Widget _buildNumericTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String settingKey,
    required String unit,
    required Color surface,
    required Color textColor,
    required Color subtextColor,
    required Color borderColor,
  }) {
    final raw = _settings[settingKey];
    final value = raw != null
        ? (raw is num ? raw : num.tryParse(raw.toString()) ?? _numericDefaults[settingKey] ?? 0)
        : (_numericDefaults[settingKey] ?? 0);

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title,
          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: subtextColor, fontSize: 11)),
      trailing: GestureDetector(
        onTap: () => _showNumericDialog(settingKey, title, value, unit, textColor, subtextColor, surface, borderColor),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: iconColor.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$value',
                style: TextStyle(color: iconColor, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(width: 3),
            Text(unit, style: TextStyle(color: iconColor.withOpacity(0.7), fontSize: 11)),
            const SizedBox(width: 4),
            Icon(Icons.edit_rounded, color: iconColor.withOpacity(0.6), size: 13),
          ]),
        ),
      ),
    );
  }

  Future<void> _showNumericDialog(
    String settingKey,
    String title,
    num currentValue,
    String unit,
    Color textColor,
    Color subtextColor,
    Color surface,
    Color borderColor,
  ) async {
    final ctrl = TextEditingController(text: currentValue.toString());
    final result = await showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Valor actual: $currentValue $unit',
              style: TextStyle(color: subtextColor, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              suffixText: unit,
              suffixStyle: TextStyle(color: subtextColor),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: GardenColors.primary, width: 2)),
              filled: true,
              fillColor: GardenColors.primary.withOpacity(0.05),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: TextStyle(color: subtextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: GardenColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final parsed = num.tryParse(ctrl.text.trim());
              if (parsed != null && parsed >= 0) Navigator.pop(ctx, parsed);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null) await _updateSetting(settingKey, result);
  }

  Widget _emergencyBtn(
      String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.15),
        foregroundColor: color,
        elevation: 0,
        side: BorderSide(color: color.withOpacity(0.5)),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      onPressed: onPressed,
      child: Text(label,
          style:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildLogEntry(Map<String, dynamic> log) {
    final id = log['id'] as String? ?? '';
    final status = log['status'] as String? ?? 'SUCCESS';
    final agentType = log['agentType'] as String? ?? '?';
    final action = log['action'] as String? ?? '';
    final createdAt = log['createdAt'] as String? ?? '';
    final durationMs = log['durationMs'] as int?;
    final input = log['input'];
    final output = log['output'];
    final isExpanded = _expandedLogId == id;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'ERROR':
        statusColor = Colors.red;
        statusIcon = Icons.error_outline;
        break;
      case 'PENDING':
        statusColor = Colors.orange;
        statusIcon = Icons.pending_outlined;
        break;
      default:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
    }

    Color agentColor;
    switch (agentType) {
      case 'PRECIO':
        agentColor = Colors.blue;
        break;
      case 'CALIFICACION':
        agentColor = Colors.purple;
        break;
      case 'DISPUTA':
        agentColor = Colors.orange;
        break;
      case 'CUSTOM':
        agentColor = Colors.teal;
        break;
      default:
        agentColor = Colors.grey;
    }

    String timeStr = '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      timeStr =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {}

    return GestureDetector(
      onTap: () => setState(
          () => _expandedLogId = isExpanded ? null : id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isExpanded
              ? statusColor.withOpacity(0.1)
              : statusColor.withOpacity(0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border(
              left: BorderSide(color: statusColor, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(statusIcon, color: statusColor, size: 13),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: agentColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(agentType,
                    style: TextStyle(
                        color: agentColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(action,
                    style: const TextStyle(
                        color: Color(0xFFE6EDF3), fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ),
              if (durationMs != null) ...[
                const SizedBox(width: 4),
                Text('${durationMs}ms',
                    style: const TextStyle(
                        color: Color(0xFF484F58), fontSize: 10)),
              ],
              const SizedBox(width: 4),
              Text(timeStr,
                  style: const TextStyle(
                      color: Color(0xFF484F58), fontSize: 10)),
              const SizedBox(width: 4),
              Icon(
                isExpanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: const Color(0xFF484F58),
                size: 14,
              ),
            ]),
            if (isExpanded && (input != null || output != null)) ...[
              const SizedBox(height: 8),
              if (input != null) ...[
                const Text('INPUT',
                    style: TextStyle(
                        color: Color(0xFF6E7681),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    const JsonEncoder.withIndent('  ').convert(input),
                    style: const TextStyle(
                        color: Color(0xFF79C0FF),
                        fontSize: 10,
                        fontFamily: 'monospace'),
                  ),
                ),
              ],
              if (output != null) ...[
                const SizedBox(height: 6),
                const Text('OUTPUT',
                    style: TextStyle(
                        color: Color(0xFF6E7681),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    const JsonEncoder.withIndent('  ').convert(output),
                    style: const TextStyle(
                        color: Color(0xFF7EE787),
                        fontSize: 10,
                        fontFamily: 'monospace'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';

class SlotConflictScreen extends StatefulWidget {
  final String bookingId;
  final String serviceType;
  final String caregiverId;

  const SlotConflictScreen({
    super.key,
    required this.bookingId,
    required this.serviceType,
    required this.caregiverId,
  });

  @override
  State<SlotConflictScreen> createState() => _SlotConflictScreenState();
}

class _SlotConflictScreenState extends State<SlotConflictScreen> {
  String get _baseUrl =>
      const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  // Paseo
  DateTime? _selectedDate;
  String? _selectedTimeSlot;

  // Hospedaje / Guardería
  DateTime? _startDate;
  DateTime? _endDate;

  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isPaseo => widget.serviceType == 'PASEO';

  bool get _canConfirm {
    if (_isPaseo) return _selectedDate != null && _selectedTimeSlot != null;
    return _startDate != null && _endDate != null;
  }

  Future<void> _pickDate({bool isStart = true}) async {
    final now = DateTime.now();
    final firstDate = now;
    final lastDate = now.add(const Duration(days: 30));
    final initial = (_isPaseo
            ? _selectedDate
            : isStart
                ? _startDate
                : _endDate) ??
        now.add(const Duration(days: 1));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(firstDate) ? firstDate : initial,
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('es'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: GardenColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (_isPaseo) {
        _selectedDate = picked;
      } else if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
      _errorMessage = null;
    });
  }

  Future<void> _confirm() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final token = AuthState.token;
      final Map<String, dynamic> body = {};

      if (_isPaseo) {
        body['newWalkDate'] = _selectedDate!.toIso8601String().substring(0, 10);
        body['newTimeSlot'] = _selectedTimeSlot;
      } else {
        body['newStartDate'] = _startDate!.toIso8601String().substring(0, 10);
        body['newEndDate'] = _endDate!.toIso8601String().substring(0, 10);
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/resolve-slot-conflict'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (!mounted) return;

      if (data['success'] == true) {
        context.go('/my-bookings');
      } else {
        final msg = data['error']?['message'] ?? data['message'] ?? 'Hora no disponible. Elige otra.';
        setState(() => _errorMessage = msg);
      }
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Error de conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) => Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: surface,
          elevation: 0,
          title: Text(
            'Elige una nueva hora',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 18),
          ),
          automaticallyImplyLeading: false,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Alerta ────────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: GardenColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: GardenColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: GardenColors.error, size: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tu hora fue reservada',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Alguien más confirmó su reserva para el mismo horario. Tu pago está retenido de forma segura. Elige una nueva hora y continuamos sin costo adicional.',
                            style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              if (_isPaseo) ...[
                _sectionLabel('Nueva fecha', textColor),
                const SizedBox(height: 10),
                _dateTile(
                  label: _selectedDate == null
                      ? 'Seleccionar fecha'
                      : _formatDate(_selectedDate!),
                  icon: Icons.calendar_today_rounded,
                  onTap: () => _pickDate(),
                  textColor: textColor,
                  subtextColor: subtextColor,
                  surface: surface,
                ),
                const SizedBox(height: 24),
                _sectionLabel('Bloque horario', textColor),
                const SizedBox(height: 10),
                Row(
                  children: ['MANANA', 'TARDE', 'NOCHE'].map((slot) {
                    final labels = {'MANANA': 'Mañana', 'TARDE': 'Tarde', 'NOCHE': 'Noche'};
                    final icons = {
                      'MANANA': Icons.wb_sunny_outlined,
                      'TARDE': Icons.wb_twilight_rounded,
                      'NOCHE': Icons.nights_stay_outlined,
                    };
                    final isSelected = _selectedTimeSlot == slot;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GardenPressable(
                          pressedScale: 0.95,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedTimeSlot = slot;
                              _errorMessage = null;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? GardenColors.primary.withValues(alpha: 0.12)
                                  : surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? GardenColors.primary
                                    : (isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  icons[slot]!,
                                  color: isSelected ? GardenColors.primary : subtextColor,
                                  size: 22,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  labels[slot]!,
                                  style: TextStyle(
                                    color: isSelected ? GardenColors.primary : subtextColor,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ] else ...[
                _sectionLabel('Nueva fecha de inicio', textColor),
                const SizedBox(height: 10),
                _dateTile(
                  label: _startDate == null
                      ? 'Seleccionar fecha de inicio'
                      : _formatDate(_startDate!),
                  icon: Icons.calendar_today_rounded,
                  onTap: () => _pickDate(isStart: true),
                  textColor: textColor,
                  subtextColor: subtextColor,
                  surface: surface,
                ),
                const SizedBox(height: 20),
                _sectionLabel('Nueva fecha de fin', textColor),
                const SizedBox(height: 10),
                _dateTile(
                  label: _endDate == null
                      ? 'Seleccionar fecha de fin'
                      : _formatDate(_endDate!),
                  icon: Icons.event_rounded,
                  onTap: _startDate == null ? null : () => _pickDate(isStart: false),
                  textColor: textColor,
                  subtextColor: subtextColor,
                  surface: surface,
                  disabled: _startDate == null,
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: GardenColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: GardenColors.error, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: GardenColors.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 36),

              GardenButton(
                label: _isSubmitting ? 'Confirmando...' : 'Confirmar nueva hora',
                icon: Icons.check_circle_outline_rounded,
                onPressed: (_canConfirm && !_isSubmitting)
                    ? () {
                        HapticFeedback.mediumImpact();
                        _confirm();
                      }
                    : null,
                loading: _isSubmitting,
              ),

              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Tu pago está seguro y se aplicará a la nueva reserva.',
                  style: TextStyle(color: subtextColor, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, Color textColor) => Text(
        label,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15),
      );

  Widget _dateTile({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    required Color textColor,
    required Color subtextColor,
    required Color surface,
    bool disabled = false,
  }) {
    final isDark = themeNotifier.isDark;
    return GardenPressable(
      pressedScale: 0.97,
      onTap: disabled ? null : () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: disabled ? subtextColor.withValues(alpha: 0.4) : GardenColors.primary, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: disabled ? subtextColor.withValues(alpha: 0.4) : textColor,
                fontSize: 15,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                color: disabled ? subtextColor.withValues(alpha: 0.3) : subtextColor, size: 20),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
    ];
    return '${d.day} de ${months[d.month - 1]} de ${d.year}';
  }
}

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_empty_state.dart';
import '../../widgets/notification_bell.dart';
import '../../main.dart';
import '../chat/chat_screen.dart';
import '../service/service_execution_screen.dart';
import '../../widgets/pet_profile_sheet.dart';
import '../../widgets/price_suggestion_banner.dart';


class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({super.key});

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen> {
  // Estado base
  Map<String, dynamic>? _availability;
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;
  bool _setupPending = false; // true = show resume-registration screen
  bool _conversionInProgress = false; // true = CLIENT→CAREGIVER in progress
  bool _isAbandoningConversion = false;
  String _caregiverToken = '';
  Map<String, dynamic>? _caregiver;
  Map<String, dynamic>? _dashboardStats;
  Map<String, dynamic>? _nextBookingWithin24h;
  String _userName = 'Cuidador';


  int _selectedTab = 0; // 0: Inicio, 1: Disponibilidad, 2: Reservas
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  // Calendario e interactividad
  DateTime _calendarMonth = DateTime.now();
  DateTime? _selectedDay;
  Map<String, String> _dayStatus = {}; // 'available', 'blocked', 'partial', 'booked'
  

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _caregiverToken = prefs.getString('access_token') ?? '';
    if (_caregiverToken.isEmpty) {
      if (mounted) context.go('/login');
      return;
    }
    _conversionInProgress = prefs.getBool('client_conversion_in_progress') ?? false;
    // Cargar nombre desde prefs si existe
    final storedName = prefs.getString('user_name') ?? '';
    if (storedName.isNotEmpty) setState(() => _userName = storedName);

    try {
      await Future.wait([
        _loadCaregiverProfile(),
        _loadAvailability(),
        _loadBookings(),
        _loadDashboardStats(),
      ]);

      // Siempre verificar el estado real del backend
      if (_caregiver != null) {
        final status = (_caregiver!['status'] as String? ?? '').toUpperCase();
        if (status != 'APPROVED') {
          if (mounted) setState(() => _setupPending = true);
        }
      }

      _computeDayStatuses();
      _computeNextBookingWithin24h();
    } catch (e) {
      // silencioso
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _computeNextBookingWithin24h() {
    final now = DateTime.now();
    Map<String, dynamic>? nearest;
    Duration? nearestDiff;
    for (final b in _bookings) {
      if (b['status'] != 'CONFIRMED') continue;
      final dateStr = b['walkDate'] as String? ?? b['startDate'] as String?;
      if (dateStr == null) continue;
      final timeStr = b['startTime'] as String?;
      try {
        final parts = dateStr.split('-');
        final timeParts = timeStr?.split(':');
        final hour = timeParts != null && timeParts.isNotEmpty ? int.tryParse(timeParts.first) ?? 9 : 9;
        final minute = timeParts != null && timeParts.length > 1 ? int.tryParse(timeParts.last) ?? 0 : 0;
        final serviceTime = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]), hour, minute);
        final diff = serviceTime.difference(now);
        if (diff.isNegative || diff.inHours >= 24) continue;
        final nd = nearestDiff;
        if (nd == null || diff < nd) {
          nearest = b;
          nearestDiff = diff;
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _nextBookingWithin24h = nearest);
  }

  Future<void> _loadDashboardStats() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/caregiver/dashboard-stats'),
        headers: {'Authorization': 'Bearer $_caregiverToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _dashboardStats = data['data']);
      }
    } catch (e) {
      debugPrint('Dashboard error: $e');
    }
  }

  void _computeDayStatuses() {
    final statuses = <String, String>{};
    final now = DateTime.now();
    
    // Leer flags de días habilitados del schedule predeterminado
    final defaultSchedule = (_availability?['defaultSchedule'] as Map?) ?? {};
    final weekdaysEnabled = defaultSchedule['weekdays'] as bool? ?? true;
    final weekendsEnabled = defaultSchedule['weekends'] as bool? ?? true;
    final holidaysEnabled = defaultSchedule['holidays'] as bool? ?? true;

    // Feriados nacionales de Bolivia 2025-2026 (ISO)
    const bolivianHolidays = {
      '2025-01-01','2025-01-22','2025-02-24','2025-02-25','2025-04-18','2025-04-19',
      '2025-05-01','2025-06-19','2025-06-21','2025-08-06','2025-10-12','2025-11-02',
      '2025-12-25','2026-01-01','2026-01-22','2026-02-16','2026-02-17','2026-04-03',
      '2026-04-04','2026-05-01','2026-06-11','2026-06-21','2026-08-06','2026-10-12',
      '2026-11-02','2026-12-25',
    };

    // Generar los próximos 90 días
    for (int i = 0; i < 90; i++) {
      final date = now.add(Duration(days: i));
      final dateStr = date.toIso8601String().split('T')[0];

      // Verificar si tiene reserva confirmada
      final hasBooking = _bookings.any((b) =>
        (b['startDate'] == dateStr || b['walkDate'] == dateStr) &&
        (b['status'] == 'CONFIRMED' || b['status'] == 'IN_PROGRESS' || b['status'] == 'PENDING_PAYMENT')
      );

      if (hasBooking) {
        statuses[dateStr] = 'booked';
        continue;
      }

      // Verificar overrides explícitos (el API los devuelve en 'dates')
      final serverOverrides = (_availability?['overrides'] ?? _availability?['dates']) as Map?;
      if (serverOverrides != null && serverOverrides.containsKey(dateStr)) {
        final override = serverOverrides[dateStr];
        if (override is Map && override['isAvailable'] == false) {
          statuses[dateStr] = 'blocked';
          continue;
        }
      }

      // Verificar si el tipo de día está desactivado en el schedule predeterminado
      final weekday = date.weekday; // 1=lunes … 7=domingo
      final isWeekend = weekday == 6 || weekday == 7;
      final isHoliday = bolivianHolidays.contains(dateStr);

      if (isHoliday && !holidaysEnabled) {
        statuses[dateStr] = 'blocked';
        continue;
      }
      if (isWeekend && !weekendsEnabled) {
        statuses[dateStr] = 'blocked';
        continue;
      }
      if (!isWeekend && !isHoliday && !weekdaysEnabled) {
        statuses[dateStr] = 'blocked';
        continue;
      }

      statuses[dateStr] = 'available';
    }
    
    setState(() => _dayStatus = statuses);
  }

  Future<void> _loadAvailability() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/caregiver/availability'),
      headers: {'Authorization': 'Bearer $_caregiverToken'},
    );
    final data = jsonDecode(response.body);
    if (data['success'] == true) {
      setState(() => _availability = data['data']);
    }
  }

  Future<void> _loadCaregiverProfile() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $_caregiverToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _caregiver = data['data'];
          // Actualizar nombre desde el perfil del cuidador
          final user = data['data']?['user'];
          if (user != null) {
            _userName = '${user['firstName'] ?? ''}'.trim();
            if (_userName.isEmpty) _userName = 'Cuidador';
          }
        });
      }
    } catch (e) {
      // silencioso
    }
  }

  Future<void> _loadBookings() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/caregiver/bookings'),
      headers: {'Authorization': 'Bearer $_caregiverToken'},
    );
    final data = jsonDecode(response.body);
    if (data['success'] == true) {
      setState(() => _bookings = (data['data'] as List).cast<Map<String, dynamic>>());
      _computeDayStatuses();
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) context.go('/login');
  }

  Future<void> _toggleTimeBlock(String blockName, bool enabled) async {
    try {
      final rawCurrent = _availability?['defaultSchedule']?['paseoTimeBlocks'];
      final currentBlocks = rawCurrent is Map ? Map<String, dynamic>.from(rawCurrent) : <String, dynamic>{};
      final updatedBlocks = Map<String, dynamic>.from(currentBlocks);
      final existing = updatedBlocks[blockName];
      final existingMap = existing is Map ? Map<String, dynamic>.from(existing) : <String, dynamic>{};
      updatedBlocks[blockName] = {
        'start': blockName == 'morning' ? '08:00' : blockName == 'afternoon' ? '13:00' : '19:00',
        'end':   blockName == 'morning' ? '11:00' : blockName == 'afternoon' ? '17:00' : '22:00',
        ...existingMap,
        'enabled': enabled,
      };

      final response = await http.patch(
        Uri.parse('$_baseUrl/caregiver/availability'),
        headers: {
          'Authorization': 'Bearer $_caregiverToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'defaultSchedule': {
            'paseoTimeBlocks': updatedBlocks,
          },
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadAvailability();
        _computeDayStatuses();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Horario ${enabled ? 'activado' : 'desactivado'}'),
            backgroundColor: enabled ? Colors.green : Colors.orange,
          ),
        );
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _toggleDayBlock(String dateStr, bool block) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/caregiver/availability'),
        headers: {
          'Authorization': 'Bearer $_caregiverToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'overrides': {
            dateStr: {'isAvailable': !block, 'reason': block ? 'No disponible' : ''},
          },
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadAvailability();
        _computeDayStatuses();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(block ? 'Día bloqueado' : 'Día desbloqueado'),
            backgroundColor: block ? Colors.red : Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _toggleDayBlockImmediate(String dateStr, String blockKey, bool enabled) async {
    debugPrint('TOGGLE DAY BLOCK: date=$dateStr block=$blockKey enabled=$enabled');
    try {
      // Para no sobreescribir los otros bloques del mismo día en el servidor, 
      // debemos obtener el estado actual de los 3 bloques y enviar el conjunto completo.
      
      final rawGlobal = _availability?['defaultSchedule']?['paseoTimeBlocks'];
      final globalBlocks = rawGlobal is Map ? Map<String, dynamic>.from(rawGlobal) : <String, dynamic>{};
      
      // Obtener overrides actuales del servidor para este día
      final serverOverrides = (_availability?['overrides'] ?? _availability?['dates']) as Map?;
      final savedDayTimeBlocks = serverOverrides?[dateStr]?['timeBlocks'] as Map?;
      final savedSlots = (savedDayTimeBlocks?['slots'] as Map?) ?? savedDayTimeBlocks ?? {};

      Map<String, dynamic> buildBlock(String key) {
        final g = globalBlocks[key] is Map ? Map<String, dynamic>.from(globalBlocks[key]) : {
          'enabled': true, 
          'start': key == 'morning' ? '08:00' : key == 'afternoon' ? '13:00' : '19:00',
          'end': key == 'morning' ? '11:00' : key == 'afternoon' ? '17:00' : '22:00'
        };
        
        final s = savedSlots[key] is Map ? Map<String, dynamic>.from(savedSlots[key]) : null;
        
        // Si este es el bloque que estamos cambiando, usar el nuevo valor
        if (key == blockKey) {
          return {
            'enabled': enabled,
            'start': s?['start'] ?? g['start'],
            'end': s?['end'] ?? g['end'],
          };
        }
        
        // Si no, mantener el valor guardado o el global
        return {
          'enabled': s?['enabled'] ?? g['enabled'],
          'start': s?['start'] ?? g['start'],
          'end': s?['end'] ?? g['end'],
        };
      }

      final body = {
        'overrides': {
          dateStr: {
            'isAvailable': true,
            'timeBlocks': {
              'morning': buildBlock('morning'),
              'afternoon': buildBlock('afternoon'),
              'night': buildBlock('night'),
            }
          }
        }
      };

      final response = await http.patch(
        Uri.parse('$_baseUrl/caregiver/availability'),
        headers: {
          'Authorization': 'Bearer $_caregiverToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      
      final data = jsonDecode(response.body);
      debugPrint('TOGGLE RESPONSE: ${response.statusCode} ${response.body}');
      
      if (data['success'] == true) {
        await _loadAvailability();
        _computeDayStatuses();
        // Forzar reconstrucción del panel cerrando y reabriendo el día seleccionado
        final currentDay = _selectedDay;
        setState(() => _selectedDay = null);
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          setState(() => _selectedDay = currentDay);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${blockKey == 'morning' ? 'Mañana' : blockKey == 'afternoon' ? 'Tarde' : 'Noche'} ${enabled ? 'activado' : 'desactivado'} para este día'),
            backgroundColor: enabled ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _respondBooking(String bookingId, String action) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/$bookingId/$action'),
        headers: {
          'Authorization': 'Bearer $_caregiverToken',
          'Content-Type': 'application/json',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadBookings();
        _computeDayStatuses();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action == 'accept' ? 'Reserva aceptada' : 'Reserva rechazada'),
            backgroundColor: action == 'accept' ? Colors.green : Colors.red.shade700,
          ),
        );
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _requestCancellation(String bookingId, String reason) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/$bookingId/cancellation-request'),
        headers: {
          'Authorization': 'Bearer $_caregiverToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'reason': reason}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadBookings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Solicitud enviada. El admin revisará tu cancelación.'),
              backgroundColor: GardenColors.warning,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al solicitar cancelación');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Widget _buildDashboardTab() {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final stats = _dashboardStats;
    final allTime = stats?['allTime'] as Map<String, dynamic>?;
    final nextBooking = stats?['nextBooking'] as Map<String, dynamic>?;
    final completeness = (stats?['profileCompleteness'] as num? ?? 0).toInt();
    final acceptanceRate = (stats?['acceptanceRate'] as num? ?? 100).toInt();
    final pendingCount = (stats?['pendingBookings'] as int? ?? 0);

    final nb = _nextBookingWithin24h;
    return Column(
      children: [
        // ── BANNER RECORDATORIO 24H (sticky) ─────────────────
        if (nb != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: GardenColors.warning.withValues(alpha: 0.12),
              borderRadius: GardenRadius.lg_,
              border: Border.all(color: GardenColors.warning.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Text('⏰', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Servicio próximo',
                        style: TextStyle(color: GardenColors.warning, fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(
                        '${nb['petName'] ?? '—'} · hoy a las ${nb['startTime'] ?? nb['walkDate'] ?? ''}',
                        style: TextStyle(color: subtextColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                GardenButton(
                  label: 'Ver',
                  height: 34,
                  width: 60,
                  onPressed: () => setState(() => _selectedTab = 2),
                ),
              ],
            ),
          ),

        // ── CONTENIDO SCROLLABLE ─────────────────────────────
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([_loadDashboardStats(), _loadBookings()]);
              _computeNextBookingWithin24h();
            },
            color: GardenColors.primary,
            child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── 1. CARD DE BIENVENIDA ──────────────────────────
            _buildWelcomeCard(
              isDark: isDark,
              surface: surface,
              textColor: textColor,
              subtextColor: subtextColor,
              borderColor: borderColor,
              rating: (allTime?['rating'] as num? ?? 0).toDouble(),
              reviewCount: allTime?['reviewCount'] as int? ?? 0,
              pendingCount: pendingCount,
            ),
            const SizedBox(height: 16),

            // ── SUGERENCIAS DE PRECIO IA ───────────────────
            PriceSuggestionBanner(
              token: _caregiverToken,
              baseUrl: _baseUrl,
              onPriceUpdated: _loadCaregiverProfile,
            ),
            const SizedBox(height: 8),

            // ── 2. SOLICITUDES PENDIENTES (máxima prioridad) ──
            ..._buildPendingRequestsSection(
              surface: surface,
              textColor: textColor,
              subtextColor: subtextColor,
              borderColor: borderColor,
            ),

            // ── 3. RESERVA EN CURSO ────────────────────────────
            if (_bookings.any((b) => b['status'] == 'IN_PROGRESS')) ...[
              _buildActiveBookingCard(
                _bookings.firstWhere((b) => b['status'] == 'IN_PROGRESS'),
                surface, textColor, subtextColor, borderColor,
              ),
              const SizedBox(height: 16),
            ],

            // ── 4. RESERVAS CONFIRMADAS ────────────────────────
            ..._buildConfirmedBookingsSection(
              surface: surface,
              textColor: textColor,
              subtextColor: subtextColor,
              borderColor: borderColor,
            ),

            // ── 5. PRÓXIMA RESERVA ─────────────────────────────
            Text('Próxima reserva',
              style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            _buildNextBookingCard(
              nextBooking: nextBooking,
              surface: surface,
              surfaceEl: surfaceEl,
              textColor: textColor,
              subtextColor: subtextColor,
              borderColor: borderColor,
            ),
            const SizedBox(height: 16),

            // ── 5. BARRA DE COMPLETITUD DEL PERFIL ────────────
            if (completeness < 100 && _caregiver?['status'] != 'APPROVED') ...[
              _buildCompletenessBar(
                completeness: completeness,
                textColor: textColor,
                subtextColor: subtextColor,
                surface: surface,
                borderColor: borderColor,
              ),
              const SizedBox(height: 16),
            ],

            // ── 6. MÉTRICAS TOTALES ────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _totalStatChip(
                    '${allTime?['bookings'] ?? 0} servicios totales',
                    Icons.check_circle_outline_rounded,
                    GardenColors.success,
                    surface, borderColor, subtextColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _totalStatChip(
                    '$acceptanceRate% aceptación',
                    Icons.thumb_up_outlined,
                    GardenColors.secondary,
                    surface, borderColor, subtextColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── 7. PREVIEW RESERVAS RECIENTES ─────────────────
            if (_bookings.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Reservas recientes',
                    style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                  GestureDetector(
                    onTap: () => setState(() => _selectedTab = 2),
                    child: const Text('Ver todas',
                      style: TextStyle(color: GardenColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ..._bookings.take(3).map((b) =>
                _buildBookingPreviewCard(b, surface, textColor, subtextColor, borderColor)),
            ],
          ],
        ),
      ),
          ),  // RefreshIndicator
        ),    // Expanded
      ],
    );
  }

  // ── CARD DE BIENVENIDA ──────────────────────────────────────────────────
  Widget _buildWelcomeCard({
    required bool isDark,
    required Color surface,
    required Color textColor,
    required Color subtextColor,
    required Color borderColor,
    required double rating,
    required int reviewCount,
    required int pendingCount,
  }) {
    final status = _caregiver?['status'] as String? ?? 'APPROVED';
    final photoUrl = _caregiver?['profilePhoto'] as String?;
    final initial = _userName.isNotEmpty ? _userName[0].toUpperCase() : 'C';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E2433), Color(0xFF2D3250)],
        ),
        borderRadius: GardenRadius.xl_,
        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: GardenColors.primary.withValues(alpha: 0.5), width: 2),
            ),
            child: ClipOval(
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? Image.network(fixImageUrl(photoUrl), fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _avatarPlaceholder(initial))
                  : _avatarPlaceholder(initial),
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                Text(
                  _userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Badge estado
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: GardenColors.success.withValues(alpha: 0.15),
                        borderRadius: GardenRadius.full_,
                        border: Border.all(color: GardenColors.success.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: const BoxDecoration(
                              color: GardenColors.success, shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            status == 'APPROVED' ? 'Activo' : status,
                            style: const TextStyle(
                              color: GardenColors.success, fontSize: 10, fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (rating > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: GardenColors.star.withValues(alpha: 0.15),
                          borderRadius: GardenRadius.full_,
                          border: Border.all(color: GardenColors.star.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: GardenColors.star, size: 11),
                            const SizedBox(width: 4),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: GardenColors.star, fontSize: 10, fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Badge pendientes
          if (pendingCount > 0)
            GestureDetector(
              onTap: () => setState(() => _selectedTab = 2),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: GardenColors.warning.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: GardenColors.warning.withValues(alpha: 0.4)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.notifications_outlined, color: GardenColors.warning, size: 20),
                    Positioned(
                      top: 6, right: 6,
                      child: Container(
                        width: 12, height: 12,
                        decoration: const BoxDecoration(
                          color: GardenColors.warning, shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$pendingCount',
                            style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── SOLICITUDES PENDIENTES DE APROBACIÓN ──────────────────────────────────
  List<Widget> _buildPendingRequestsSection({
    required Color surface,
    required Color textColor,
    required Color subtextColor,
    required Color borderColor,
  }) {
    final pending = _bookings
        .where((b) => b['status'] == 'WAITING_CAREGIVER_APPROVAL')
        .toList();
    if (pending.isEmpty) return [];

    return [
      Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: GardenColors.error,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${pending.length} NUEVA${pending.length > 1 ? 'S' : ''}',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          Text('Solicitudes de reserva',
            style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
      const SizedBox(height: 10),
      ...pending.map((b) => _buildPendingRequestCard(
        booking: b,
        surface: surface,
        textColor: textColor,
        subtextColor: subtextColor,
        borderColor: borderColor,
      )),
      const SizedBox(height: 16),
    ];
  }

  Widget _buildPendingRequestCard({
    required Map<String, dynamic> booking,
    required Color surface,
    required Color textColor,
    required Color subtextColor,
    required Color borderColor,
  }) {
    final petName     = booking['petName']     as String? ?? '—';
    final serviceType = booking['serviceType'] as String? ?? '';
    final clientName  = booking['clientName']  as String?
        ?? '${booking['client']?['firstName'] ?? ''} ${booking['client']?['lastName'] ?? ''}'.trim();
    final dateStr     = booking['walkDate']    as String? ?? booking['startDate'] as String?;
    final startTime   = booking['startTime']   as String?;
    final net = _caregiverNetAmount(booking);
    final isPaseo     = serviceType == 'PASEO';
    final bookingId   = booking['id'] as String? ?? '';

    String dateLabel = '';
    if (dateStr != null) {
      try {
        final d = DateTime.parse(dateStr);
        final now = DateTime.now();
        final diff = d.difference(DateTime(now.year, now.month, now.day)).inDays;
        if (diff == 0) {
          dateLabel = 'Hoy';
        } else if (diff == 1) {
          dateLabel = 'Mañana';
        } else {
          dateLabel = '${d.day}/${d.month}';
        }
      } catch (_) { dateLabel = dateStr; }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GardenColors.error.withValues(alpha: 0.45), width: 1.5),
        boxShadow: [BoxShadow(color: GardenColors.error.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // Header pulsante
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: GardenColors.error.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_rounded, color: GardenColors.error, size: 16),
                const SizedBox(width: 6),
                const Text('Esperando tu respuesta',
                  style: TextStyle(color: GardenColors.error, fontSize: 12, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(isPaseo ? '🦮' : '🏠', style: const TextStyle(fontSize: 20)),
              ],
            ),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(petName, style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(clientName.isNotEmpty ? clientName : 'Cliente',
                            style: TextStyle(color: subtextColor, fontSize: 12)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Bs $net',
                          style: const TextStyle(color: GardenColors.success, fontSize: 20, fontWeight: FontWeight.w800)),
                        Text('tu ganancia', style: TextStyle(color: subtextColor, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    _infoChip(isPaseo ? 'Paseo' : 'Hospedaje', Icons.pets_rounded, subtextColor, borderColor),
                    if (dateLabel.isNotEmpty)
                      _infoChip(dateLabel, Icons.calendar_today_rounded, subtextColor, borderColor),
                    if (startTime != null)
                      _infoChip(startTime, Icons.access_time_rounded, subtextColor, borderColor),
                  ],
                ),
              ],
            ),
          ),
          // Botones
          Builder(builder: (_) {
            final hasMG = booking['meetAndGreet'] != null;
            if (hasMG) {
              return Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: GardenColors.success),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '🤝 Meet & Greet incluido — coordina antes de aceptar',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: GardenColors.success, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: const Text('Abrir chat'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            bookingId: bookingId,
                            otherPersonName: clientName,
                            token: _caregiverToken,
                            role: 'CAREGIVER',
                            bookingStatus: 'WAITING_CAREGIVER_APPROVAL',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: GardenButton(
                      label: 'Aceptar',
                      icon: Icons.check_rounded,
                      height: 46,
                      color: GardenColors.success,
                      onPressed: () => _respondBooking(bookingId, 'accept'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GardenButton(
                      label: 'Rechazar',
                      icon: Icons.close_rounded,
                      height: 46,
                      color: GardenColors.error,
                      outline: true,
                      onPressed: () => _respondBooking(bookingId, 'reject'),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── RESERVAS CONFIRMADAS ───────────────────────────────────────────────────
  List<Widget> _buildConfirmedBookingsSection({
    required Color surface,
    required Color textColor,
    required Color subtextColor,
    required Color borderColor,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endOfTomorrow = today.add(const Duration(days: 2));

    final confirmed = _bookings.where((b) {
      if (b['status'] != 'CONFIRMED') return false;
      final dateStr = b['walkDate'] as String? ?? b['startDate'] as String?;
      if (dateStr == null) return false;
      try {
        final d = DateTime.parse(dateStr);
        final serviceDay = DateTime(d.year, d.month, d.day);
        return !serviceDay.isBefore(today) && serviceDay.isBefore(endOfTomorrow);
      } catch (_) {
        return false;
      }
    }).toList();
    if (confirmed.isEmpty) return [];

    return [
      Text('Reservas confirmadas',
        style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      ...confirmed.map((b) => _buildConfirmedBookingCard(
        booking: b,
        surface: surface,
        textColor: textColor,
        subtextColor: subtextColor,
        borderColor: borderColor,
      )),
      const SizedBox(height: 16),
    ];
  }

  Widget _buildConfirmedBookingCard({
    required Map<String, dynamic> booking,
    required Color surface,
    required Color textColor,
    required Color subtextColor,
    required Color borderColor,
  }) {
    final petName     = booking['petName']     as String? ?? '—';
    final serviceType = booking['serviceType'] as String? ?? '';
    final clientName  = (booking['clientName'] as String?
        ?? '${booking['client']?['firstName'] ?? ''} ${booking['client']?['lastName'] ?? ''}'.trim())
        .trim();
    final dateStr     = booking['walkDate'] as String? ?? booking['startDate'] as String?;
    final startTime   = booking['startTime'] as String?;
    final bookingId   = booking['id'] as String? ?? '';
    final isPaseo     = serviceType == 'PASEO';
    final net         = _caregiverNetAmount(booking);

    String dateLabel = '';
    if (dateStr != null) {
      try {
        final d = DateTime.parse(dateStr);
        final now = DateTime.now();
        final diff = d.difference(DateTime(now.year, now.month, now.day)).inDays;
        if (diff == 0) {
          dateLabel = 'Hoy';
        } else if (diff == 1) {
          dateLabel = 'Mañana';
        } else {
          dateLabel = '${d.day}/${d.month}';
        }
      } catch (_) {
        dateLabel = dateStr;
      }
    }

    void openService() => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceExecutionScreen(bookingId: bookingId, role: 'CAREGIVER'),
      ),
    );

    void openChat() => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          bookingId: bookingId,
          otherPersonName: clientName.isNotEmpty ? clientName : 'Cliente',
          token: _caregiverToken,
          role: 'CAREGIVER',
          bookingStatus: booking['status'] as String?,
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [BoxShadow(color: GardenColors.primary.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: GardenColors.primary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: GardenColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('CONFIRMADA',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ),
                const Spacer(),
                Text(isPaseo ? '🦮' : '🏠', style: const TextStyle(fontSize: 20)),
              ],
            ),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(petName,
                            style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(clientName.isNotEmpty ? clientName : 'Cliente',
                            style: TextStyle(color: subtextColor, fontSize: 12)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Bs $net',
                          style: const TextStyle(color: GardenColors.success, fontSize: 20, fontWeight: FontWeight.w800)),
                        Text('tu ganancia', style: TextStyle(color: subtextColor, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    _infoChip(isPaseo ? 'Paseo' : 'Hospedaje', Icons.pets_rounded, subtextColor, borderColor),
                    if (dateLabel.isNotEmpty)
                      _infoChip(dateLabel, Icons.calendar_today_rounded, subtextColor, borderColor),
                    if (startTime != null)
                      _infoChip(startTime, Icons.access_time_rounded, subtextColor, borderColor),
                  ],
                ),
              ],
            ),
          ),
          // Botones
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: GardenButton(
                    label: 'Gestionar servicio',
                    icon: Icons.pets_outlined,
                    height: 46,
                    color: GardenColors.primary,
                    onPressed: openService,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 46,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: openChat,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: BorderSide(color: GardenColors.primary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Icon(Icons.chat_bubble_outline_rounded, color: GardenColors.primary, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, IconData icon, Color subtextColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: subtextColor),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: subtextColor, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder(String initial) {
    return Container(
      color: GardenColors.primary.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(color: GardenColors.primary, fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ── RESERVA EN CURSO ────────────────────────────────────────────────────
  Widget _buildActiveBookingCard(
    Map<String, dynamic> booking,
    Color surface,
    Color textColor,
    Color subtextColor,
    Color borderColor,
  ) {
    final petName    = booking['petName']    as String? ?? '—';
    final serviceType = booking['serviceType'] as String? ?? '';
    final dateStr    = booking['walkDate']   as String? ?? booking['startDate'] as String?;
    final startTime  = booking['startTime']  as String?;
    final bookingId  = booking['id']         as String? ?? '';
    final isPaseo    = serviceType == 'PASEO';

    void openService() => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceExecutionScreen(bookingId: bookingId, role: 'CAREGIVER'),
      ),
    );

    return GestureDetector(
      onTap: openService,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              GardenColors.primary.withValues(alpha: 0.18),
              GardenColors.primary.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: GardenRadius.xl_,
          border: Border.all(color: GardenColors.primary.withValues(alpha: 0.45), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: GardenColors.primary,
                    borderRadius: GardenRadius.full_,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radio_button_checked, color: Colors.white, size: 10),
                      SizedBox(width: 5),
                      Text('EN CURSO', style: TextStyle(
                        color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w800, letterSpacing: 0.5,
                      )),
                    ],
                  ),
                ),
                const Spacer(),
                Text(isPaseo ? '🦮' : '🏠', style: const TextStyle(fontSize: 26)),
              ],
            ),
            const SizedBox(height: 14),
            Text(petName,
              style: TextStyle(color: textColor, fontSize: 22,
                fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const SizedBox(height: 4),
            Text(
              '${isPaseo ? 'Paseo' : 'Hospedaje'}'
              '${dateStr != null ? ' · ${_formatNextDate(dateStr)}' : ''}'
              '${startTime != null ? ' · $startTime' : ''}',
              style: TextStyle(color: subtextColor, fontSize: 13),
            ),
            const SizedBox(height: 16),
            GardenButton(
              label: '🔴  Ver servicio en curso',
              height: 44,
              color: GardenColors.primary,
              onPressed: openService,
            ),
          ],
        ),
      ),
    );
  }

  // ── PRÓXIMA RESERVA ─────────────────────────────────────────────────────
  Widget _buildNextBookingCard({
    required Map<String, dynamic>? nextBooking,
    required Color surface,
    required Color surfaceEl,
    required Color textColor,
    required Color subtextColor,
    required Color borderColor,
  }) {
    if (nextBooking == null) {
      return const GardenEmptyState(
        type: GardenEmptyType.bookings,
        title: 'Sin reservas próximas',
        subtitle: 'Cuando tengas servicios confirmados aparecerán aquí.',
        compact: true,
      );
    }

    final dateStr = nextBooking['date'] as String?;
    final petName = nextBooking['petName'] as String? ?? '—';
    final serviceType = nextBooking['serviceType'] as String? ?? '';
    final startTime = nextBooking['startTime'] as String?;
    final countdown = _getCountdown(dateStr, startTime);
    final isUrgent = countdown != null;

    return GestureDetector(
      onTap: () {
        final bookingId = nextBooking['id'] as String?;
        if (bookingId == null) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ServiceExecutionScreen(
              bookingId: bookingId,
              role: 'CAREGIVER',
              token: _caregiverToken,
            ),
          ),
        );
      },
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUrgent
            ? GardenColors.warning.withValues(alpha: 0.06)
            : surface,
        borderRadius: GardenRadius.lg_,
        border: Border.all(
          color: isUrgent
              ? GardenColors.warning.withValues(alpha: 0.4)
              : borderColor,
          width: isUrgent ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Ícono servicio
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: isUrgent
                  ? GardenColors.warning.withValues(alpha: 0.12)
                  : GardenColors.secondary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                serviceType == 'PASEO' ? '🦮' : '🏠',
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  petName,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${serviceType == 'PASEO' ? 'Paseo' : 'Hospedaje'} · ${_formatNextDate(dateStr)}${startTime != null ? ' · $startTime' : ''}',
                  style: TextStyle(color: subtextColor, fontSize: 12),
                ),
              ],
            ),
          ),
          // Countdown o flecha
          if (countdown != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: GardenColors.warning,
                borderRadius: GardenRadius.md_,
              ),
              child: Text(
                countdown,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            Icon(Icons.chevron_right, color: subtextColor),
        ],
      ),
    ),
    );
  }

  String? _getCountdown(String? dateStr, String? timeStr) {
    if (dateStr == null) return null;
    try {
      final parts = dateStr.split('-');
      final timeParts = timeStr?.split(':');
      final hour = timeParts != null && timeParts.isNotEmpty ? int.tryParse(timeParts.first) ?? 9 : 9;
      final minute = timeParts != null && timeParts.length > 1 ? int.tryParse(timeParts.last) ?? 0 : 0;
      final serviceTime = DateTime(
        int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]), hour, minute,
      );
      final diff = serviceTime.difference(DateTime.now());
      if (diff.isNegative || diff.inHours >= 24) return null;
      if (diff.inHours < 1) return 'En ${diff.inMinutes}min';
      return 'En ${diff.inHours}h ${diff.inMinutes % 60}min';
    } catch (_) {
      return null;
    }
  }

  String _formatNextDate(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      final dt = DateTime.parse(dateStr);
      const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      final now = DateTime.now();
      if (dt.day == now.day && dt.month == now.month) return 'Hoy';
      if (dt.day == now.day + 1 && dt.month == now.month) return 'Mañana';
      return '${dt.day} ${months[dt.month - 1]}';
    } catch (_) {
      return dateStr;
    }
  }


  // ── BARRA DE COMPLETITUD ────────────────────────────────────────────────
  Widget _buildCompletenessBar({
    required int completeness,
    required Color textColor,
    required Color subtextColor,
    required Color surface,
    required Color borderColor,
  }) {
    final color = completeness < 50
        ? GardenColors.error
        : completeness < 80
            ? GardenColors.warning
            : GardenColors.success;

    return GestureDetector(
      onTap: () => context.push('/caregiver/profile-data'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: GardenRadius.lg_,
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Completitud del perfil',
                  style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  '$completeness%',
                  style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: GardenRadius.full_,
              child: LinearProgressIndicator(
                value: completeness / 100,
                backgroundColor: borderColor,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Completa tu perfil para recibir más reservas →',
              style: TextStyle(color: subtextColor, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ── STAT CHIP TOTAL ─────────────────────────────────────────────────────
  Widget _totalStatChip(
    String label,
    IconData icon,
    Color color,
    Color surface,
    Color borderColor,
    Color subtextColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: GardenRadius.md_,
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días,';
    if (hour < 18) return 'Buenas tardes,';
    return 'Buenas noches,';
  }

  Widget _buildBookingPreviewCard(Map<String, dynamic> booking, Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final status = booking['status'] as String? ?? '';
    final bookingId = booking['id'] as String? ?? '';
    final canOpen = status == 'CONFIRMED' || status == 'IN_PROGRESS';
    return GestureDetector(
      onTap: canOpen && bookingId.isNotEmpty
          ? () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceExecutionScreen(bookingId: bookingId, role: 'CAREGIVER'),
              ),
            )
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            bookingStatusBadge(status),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(booking['petName'] as String? ?? 'Mascota', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(booking['serviceType'] as String? ?? '', style: TextStyle(color: subtextColor, fontSize: 12)),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Bs ${_caregiverNet(booking)}', style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700, fontSize: 15)),
                if (canOpen) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: GardenColors.primary, size: 18),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _caregiverNet(Map<String, dynamic> booking) => _caregiverNetAmount(booking);

  Widget _buildAvailability() {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    int availableCount = 0, blockedCount = 0, bookedCount = 0;
    for (int i = 1; i <= daysInMonth; i++) {
      final ds = '${now.year}-${now.month.toString().padLeft(2,'0')}-${i.toString().padLeft(2,'0')}';
      final s = _dayStatus[ds] ?? 'available';
      if (s == 'blocked') blockedCount++;
      else if (s == 'booked') bookedCount++;
      else availableCount++;
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadAvailability();
        _computeDayStatuses();
      },
      color: GardenColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── TÍTULO ─────────────────────────────────────────
            Text('Disponibilidad',
              style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text('Gestiona cuándo estás disponible para servicios',
              style: TextStyle(color: subtextColor, fontSize: 13)),
            const SizedBox(height: 16),

            // ── RESUMEN DEL MES ─────────────────────────────────
            Row(children: [
              _availStatChip('$availableCount disponibles', GardenColors.success),
              const SizedBox(width: 8),
              _availStatChip('$blockedCount bloqueados', GardenColors.error),
              const SizedBox(width: 8),
              _availStatChip('$bookedCount reservados', GardenColors.primary),
            ]),
            const SizedBox(height: 24),

            // ── DÍAS DISPONIBLES ────────────────────────────────
            Text('Días disponibles',
              style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Activa los días en que puedes recibir servicios',
              style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(height: 12),
            _buildDayTypeToggles(textColor, subtextColor, borderColor, surface),
            const SizedBox(height: 24),

            // ── HORARIOS HABITUALES ─────────────────────────────
            Text('Horarios habituales',
              style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Toca para activar/desactivar · Toca "Editar hora" para cambiar rango',
              style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(height: 12),
            _buildScheduleBlockCards(textColor, subtextColor, borderColor, surface),
            const SizedBox(height: 28),

            // ── CALENDARIO ─────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_monthName(_calendarMonth),
                  style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                Row(children: [
                  _calNavBtn(Icons.chevron_left, () => setState(() =>
                    _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1))),
                  const SizedBox(width: 6),
                  _calNavBtn(Icons.chevron_right, () => setState(() =>
                    _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1))),
                ]),
              ],
            ),
            const SizedBox(height: 10),

            // Leyenda
            Row(children: [
              _legendDot(GardenColors.success, 'Disponible'),
              const SizedBox(width: 12),
              _legendDot(GardenColors.error, 'Bloqueado'),
              const SizedBox(width: 12),
              _legendDot(GardenColors.primary, 'Reservado'),
            ]),
            const SizedBox(height: 10),

            // Días semana
            Row(
              children: ['Lu','Ma','Mi','Ju','Vi','Sa','Do'].map((d) =>
                Expanded(child: Center(
                  child: Text(d, style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ))
              ).toList(),
            ),
            const SizedBox(height: 6),

            _buildCalendarGrid(),
            const SizedBox(height: 12),
            Center(
              child: Text('Toca un día para ver detalles o bloquearlo',
                style: TextStyle(color: subtextColor, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayTypeToggles(Color textColor, Color subtextColor, Color borderColor, Color surface) {
    final defaultSchedule = (_availability?['defaultSchedule'] as Map?) ?? {};
    final weekdays = defaultSchedule['weekdays'] as bool? ?? true;
    final weekends = defaultSchedule['weekends'] as bool? ?? true;
    final holidays = defaultSchedule['holidays'] as bool? ?? true;

    final items = [
      {'key': 'weekdays',  'label': 'Lun – Vie', 'icon': Icons.work_outline_rounded,    'value': weekdays},
      {'key': 'weekends',  'label': 'Sáb – Dom', 'icon': Icons.weekend_outlined,         'value': weekends},
      {'key': 'holidays',  'label': 'Feriados',  'icon': Icons.celebration_outlined,     'value': holidays},
    ];

    return Row(
      children: items.asMap().entries.map((entry) {
        final i = entry.key;
        final item = entry.value;
        final isEnabled = item['value'] as bool;

        return Expanded(
          child: GestureDetector(
            onTap: () => _toggleDayType(item['key'] as String, !isEnabled),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
              decoration: BoxDecoration(
                color: isEnabled
                  ? GardenColors.success.withValues(alpha: 0.1)
                  : surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isEnabled
                    ? GardenColors.success.withValues(alpha: 0.55)
                    : borderColor,
                  width: isEnabled ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(item['icon'] as IconData,
                    color: isEnabled ? GardenColors.success : subtextColor, size: 22),
                  const SizedBox(height: 8),
                  Text(item['label'] as String,
                    style: TextStyle(
                      color: isEnabled ? textColor : subtextColor,
                      fontSize: 12, fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  _miniToggle(isEnabled, GardenColors.success),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _toggleDayType(String key, bool enabled) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/caregiver/availability'),
        headers: {
          'Authorization': 'Bearer $_caregiverToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'defaultSchedule': {key: enabled},
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadAvailability();
        _computeDayStatuses();
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Widget _availStatChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _calNavBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: GardenColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: GardenColors.primary, size: 20),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: kTextSecondary, fontSize: 11)),
      ],
    );
  }

  Widget _buildScheduleBlockCards(Color textColor, Color subtextColor, Color borderColor, Color surface) {
    final rawBlocks = () {
      final raw = _availability?['defaultSchedule']?['paseoTimeBlocks'];
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    }();

    final blockDefs = [
      {'key': 'morning',   'label': 'Mañana', 'icon': Icons.wb_sunny_rounded,   'color': const Color(0xFFFFB347), 'ds': '08:00', 'de': '11:00'},
      {'key': 'afternoon', 'label': 'Tarde',  'icon': Icons.wb_cloudy_rounded,  'color': const Color(0xFF5BB8FF), 'ds': '13:00', 'de': '17:00'},
      {'key': 'night',     'label': 'Noche',  'icon': Icons.nights_stay_rounded,'color': const Color(0xFF9B8AFB), 'ds': '19:00', 'de': '22:00'},
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blockDefs.asMap().entries.map((entry) {
        final i = entry.key;
        final b = entry.value;
        final key = b['key'] as String;
        final rawBlock = rawBlocks[key];
        final block = rawBlock is Map
          ? Map<String, dynamic>.from(rawBlock)
          : {'enabled': true, 'start': b['ds'], 'end': b['de']};
        final isEnabled = block['enabled'] == true;
        final color = b['color'] as Color;
        final icon = b['icon'] as IconData;

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
            child: GestureDetector(
              onTap: () => _toggleTimeBlock(key, !isEnabled),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isEnabled ? color.withValues(alpha: 0.1) : surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isEnabled ? color.withValues(alpha: 0.55) : borderColor,
                    width: isEnabled ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(icon, color: isEnabled ? color : subtextColor, size: 20),
                        _miniToggle(isEnabled, color),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(b['label'] as String,
                      style: TextStyle(
                        color: isEnabled ? textColor : subtextColor,
                        fontWeight: FontWeight.w700, fontSize: 13,
                      )),
                    const SizedBox(height: 3),
                    Text('${block['start']} - ${block['end']}',
                      style: TextStyle(
                        color: isEnabled ? color : subtextColor,
                        fontSize: 11, fontWeight: FontWeight.w500,
                      )),
                    if (isEnabled) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => _showEditBlockSheet(key, block),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.access_time, size: 10, color: color),
                            const SizedBox(width: 4),
                            Text('Editar hora', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _miniToggle(bool isEnabled, Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 30, height: 17,
      decoration: BoxDecoration(
        color: isEnabled ? color : kTextSecondary.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 220),
        alignment: isEnabled ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.all(2),
          width: 13, height: 13,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
      ),
    );
  }

  Future<void> _showEditBlockSheet(String blockKey, Map<String, dynamic> block) async {
    String start = block['start'] as String? ?? '08:00';
    String end = block['end'] as String? ?? '11:00';
    final label = blockKey == 'morning' ? 'Mañana' : blockKey == 'afternoon' ? 'Tarde' : 'Noche';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => GlassBox(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Horario de $label',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Ajusta el rango horario para este bloque',
                style: TextStyle(color: kTextSecondary, fontSize: 13)),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Inicio', style: TextStyle(color: kTextSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () async {
                      final parts = start.split(':');
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
                        builder: (c, child) => Theme(
                          data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: kPrimaryColor)),
                          child: child!,
                        ),
                      );
                      if (picked != null) setSheetState(() => start = '${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: kBackgroundColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kPrimaryColor.withOpacity(0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.access_time, color: kPrimaryColor, size: 16),
                        const SizedBox(width: 8),
                        Text(start, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      ]),
                    ),
                  ),
                ])),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Fin', style: TextStyle(color: kTextSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () async {
                      final parts = end.split(':');
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
                        builder: (c, child) => Theme(
                          data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: kPrimaryColor)),
                          child: child!,
                        ),
                      );
                      if (picked != null) setSheetState(() => end = '${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: kBackgroundColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kPrimaryColor.withOpacity(0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.access_time, color: kPrimaryColor, size: 16),
                        const SizedBox(width: 8),
                        Text(end, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      ]),
                    ),
                  ),
                ])),
              ]),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _saveBlockTime(blockKey, start, end);
                  },
                  child: const Text('Guardar horario', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveBlockTime(String blockKey, String start, String end) async {
    try {
      final raw = _availability?['defaultSchedule']?['paseoTimeBlocks'];
      final currentBlocks = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final updatedBlocks = Map<String, dynamic>.from(currentBlocks);
      final existing = updatedBlocks[blockKey] is Map ? Map<String, dynamic>.from(updatedBlocks[blockKey]) : {'enabled': true};
      updatedBlocks[blockKey] = {...existing, 'start': start, 'end': end};

      final response = await http.patch(
        Uri.parse('$_baseUrl/caregiver/availability'),
        headers: {'Authorization': 'Bearer $_caregiverToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'defaultSchedule': {'paseoTimeBlocks': updatedBlocks}}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadAvailability();
        _computeDayStatuses();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Horario actualizado'), backgroundColor: Colors.green),
        );
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
      );
    }
  }

  String _monthName(DateTime date) {
    const months = ['Enero','Febrero','Marzo','Abril','Mayo','Junio',
      'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
    return '${months[date.month - 1]} ${date.year}';
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final startWeekday = firstDay.weekday; 
    final paddingDays = startWeekday - 1;
    
    final cells = <Widget>[];
    for (int i = 0; i < paddingDays; i++) {
      cells.add(const SizedBox());
    }
    
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_calendarMonth.year, _calendarMonth.month, day);
      final dateStr = date.toIso8601String().split('T')[0];
      final status = _dayStatus[dateStr] ?? 'available';

      final isPast = date.isBefore(DateTime.now().subtract(const Duration(days: 0)));
      
      Color bgColor;
      switch (status) {
        case 'blocked': bgColor = Colors.red.shade700; break;
        case 'booked': bgColor = kPrimaryColor; break;
        case 'partial': bgColor = Colors.orange; break;
        default: bgColor = Colors.green.shade700;
      }
      
      if (isPast) bgColor = kSurfaceColor;
      
      final isToday = date.year == DateTime.now().year &&
        date.month == DateTime.now().month &&
        date.day == DateTime.now().day;

      cells.add(
        GestureDetector(
          onTap: isPast ? null : () {
            setState(() => _selectedDay = date);
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => _buildDayPanel(date),
            );
          },
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: bgColor.withOpacity(isPast ? 0.3 : 0.8),
              borderRadius: BorderRadius.circular(8),
              border: isToday
                ? Border.all(color: Colors.white, width: 2)
                : null,
            ),
            child: Center(
              child: Text(
                '$day',
                style: TextStyle(
                  color: isPast ? kTextSecondary : Colors.white,
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      );
    }
    
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.1,
      children: cells,
    );
  }

  Widget _buildDayPanel(DateTime date) {
    final dateStr = date.toIso8601String().split('T')[0];
    final status = _dayStatus[dateStr] ?? 'available';
    final isBooked = status == 'booked';
    
    return GlassBox(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${date.day}/${date.month}/${date.year}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              if (isBooked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: kPrimaryColor, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Reservado', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (!isBooked) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Bloquear día completo', style: TextStyle(color: Colors.white)),
                Switch(
                  value: status == 'blocked',
                  activeColor: Colors.red,
                  onChanged: (val) => _toggleDayBlock(dateStr, val),
                ),
              ],
            ),
            if (status != 'blocked') ...[
              const Divider(color: Colors.white12),
              const Text('Horarios disponibles este día:',
                style: TextStyle(color: kTextSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              _buildDayTimeBlocks(dateStr),
            ],
          ] else
            const Text(
              'Este día tiene reservas activas. ¡Mantente atento!',
              style: TextStyle(color: kTextSecondary, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildDayTimeBlocks(String dateStr) {
    final raw = _availability?['defaultSchedule']?['paseoTimeBlocks'];
    final rawGlobal = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    final rawDateEntry = (_availability?['dates'] as Map?)?[dateStr];
    final rawTimeBlocks = rawDateEntry is Map ? rawDateEntry['timeBlocks'] : null;
    final rawSlots = rawTimeBlocks is Map ? rawTimeBlocks['slots'] : null;
    final dayOverride = rawSlots is Map ? Map<String, dynamic>.from(rawSlots) : <String, dynamic>{};

    return Column(
      children: ['morning', 'afternoon', 'night'].map((blockKey) {
        final rawGlobalBlock = rawGlobal[blockKey];
        final globalBlock = rawGlobalBlock is Map
          ? Map<String, dynamic>.from(rawGlobalBlock)
          : {
              'enabled': true,
              'start': blockKey == 'morning' ? '08:00' : blockKey == 'afternoon' ? '13:00' : '19:00',
              'end':   blockKey == 'morning' ? '11:00' : blockKey == 'afternoon' ? '17:00' : '22:00',
            };

        final label = blockKey == 'morning' ? 'Mañana' : blockKey == 'afternoon' ? 'Tarde' : 'Noche';
        final rawDayBlock = dayOverride[blockKey];
        final dayBlockOverride = rawDayBlock is Map ? Map<String, dynamic>.from(rawDayBlock) : null;
        final isEnabled = dayBlockOverride != null
          ? dayBlockOverride['enabled'] == true
          : globalBlock['enabled'] == true;
        final isCustomized = dayOverride.containsKey(blockKey);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: kBackgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: isCustomized ? Border.all(color: kAccentColor.withValues(alpha: 0.5)) : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      if (isCustomized) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: kAccentColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Personalizado', style: TextStyle(color: kAccentColor, fontSize: 10)),
                        ),
                      ],
                    ]),
                    Text('${globalBlock['start']} - ${globalBlock['end']}',
                      style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Switch(
                value: isEnabled,
                activeColor: kPrimaryColor,
                onChanged: (val) => _toggleDayBlockImmediate(dateStr, blockKey, val),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFullBookingCard(Map<String, dynamic> booking) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return _ExpandableBookingCard(
      booking: booking,
      surface: surface,
      textColor: textColor,
      subtextColor: subtextColor,
      borderColor: borderColor,
      isDark: isDark,
      onRespond: _respondBooking,
      onRequestCancellation: _requestCancellation,
      token: _caregiverToken,
    );
  }

  Widget _buildBookings() {
    if (_bookings.isEmpty) {
      return const GardenEmptyState(
        type: GardenEmptyType.bookings,
        title: 'Sin reservas por ahora',
        subtitle: 'Cuando los dueños reserven tus servicios, tus reservas aparecerán aquí.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: _bookings.length,
      itemBuilder: (context, index) {
        return _buildFullBookingCard(_bookings[index]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        return Scaffold(
          backgroundColor: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
          appBar: AppBar(
            backgroundColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                GestureDetector(
                  onTap: () => context.go('/caregiver/home'),
                  child: const Text('GARDEN', style: TextStyle(color: GardenColors.primary, fontSize: 20, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: GardenColors.primary.withOpacity(0.3)),
                  ),
                  child: const Text('Cuidador', style: TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            actions: [
              NotificationBell(
                token: _caregiverToken,
                baseUrl: _baseUrl,
              ),
              IconButton(
                icon: Icon(Icons.logout_outlined,
                  color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
                onPressed: _logout,
              ),
            ],
          ),
          body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
            : _setupPending
              ? _buildResumeRegistrationScreen(isDark)
              : [
                _buildDashboardTab(),
                _buildAvailability(),
                _buildBookings(),
              ][_selectedTab],
          bottomNavigationBar: _setupPending ? null : LiquidGlassNavBar(
            selectedIndex: _selectedTab,
            onTap: (i) {
              if (i == 3) {
                context.push('/profile');
              } else {
                setState(() => _selectedTab = i);
              }
            },
            items: const [
              GardenNavItem(Icons.home_outlined,            Icons.home_rounded,            'Inicio'),
              GardenNavItem(Icons.calendar_month_outlined,  Icons.calendar_month_rounded,  'Disponibilidad'),
              GardenNavItem(Icons.list_alt_outlined,        Icons.list_alt_rounded,        'Reservas'),
              GardenNavItem(Icons.person_outline_rounded,   Icons.person_rounded,          'Mi Perfil'),
            ],
          ),
        );
      },
    );
  }

  void _confirmAbandonConversion() {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;

    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('¿Abandonar registro?',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(
          'Se eliminará tu perfil de cuidador en proceso y volverás a tu cuenta de dueño de mascota. Esta acción no se puede deshacer.',
          style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: TextStyle(color: subtextColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abandonar', style: TextStyle(color: GardenColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) _abandonConversion();
    });
  }

  Future<void> _abandonConversion() async {
    if (_isAbandoningConversion) return;
    setState(() => _isAbandoningConversion = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/abandon-caregiver-profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        final result = data['data'] as Map<String, dynamic>;
        await prefs.setString('access_token', result['accessToken'] as String);
        await prefs.setString('refresh_token', result['refreshToken'] as String);
        await prefs.setString('user_role', 'CLIENT');
        await prefs.remove('active_role');
        await prefs.remove('client_conversion_in_progress');
        if (!mounted) return;
        context.go('/service-selector');
      } else {
        final msg = (data['error'] as Map<String, dynamic>?)?['message']
            ?? 'No se pudo abandonar el registro. Intenta de nuevo.';
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: GardenColors.error),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error de conexión. Verifica tu internet.'),
          backgroundColor: GardenColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isAbandoningConversion = false);
    }
  }

  Widget _buildResumeRegistrationScreen(bool isDark) {
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Container(
      color: bg,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [GardenColors.primary, Color(0xFF1B5E20)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: GardenColors.primary.withOpacity(0.35),
                        blurRadius: 28,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.assignment_late_outlined, color: Colors.white, size: 48),
                ),
                const SizedBox(height: 28),
                Text(
                  'Completa tu registro',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tu perfil aún no está completo. Termina los pasos pendientes para que tu perfil sea visible en el marketplace.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: subtextColor,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GardenColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('caregiver_setup_complete', false);
                      if (context.mounted) {
                        if (_conversionInProgress) {
                          context.go('/caregiver/onboarding', extra: {'clientConversionMode': true});
                        } else {
                          context.go('/caregiver/onboarding', extra: {'resumeMode': true});
                        }
                      }
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_forward_rounded, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Continuar registro',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _isAbandoningConversion
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton(
                        onPressed: _confirmAbandonConversion,
                        child: Text(
                          'Abandonar registro',
                          style: TextStyle(
                            color: GardenColors.error,
                            fontSize: 14,
                            decoration: TextDecoration.underline,
                            decorationColor: GardenColors.error,
                          ),
                        ),
                      ),
                TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('access_token');
                    await prefs.remove('user_name');
                    if (mounted) context.go('/login');
                  },
                  child: Text(
                    'Cerrar sesión',
                    style: TextStyle(color: subtextColor, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandableBookingCard extends StatefulWidget {
  final Map<String, dynamic> booking;
  final Color surface, textColor, subtextColor, borderColor;
  final bool isDark;
  final Function(String, String) onRespond;
  final Function(String, String) onRequestCancellation;
  final String token;

  const _ExpandableBookingCard({
    required this.booking,
    required this.surface,
    required this.textColor,
    required this.subtextColor,
    required this.borderColor,
    required this.isDark,
    required this.onRespond,
    required this.onRequestCancellation,
    required this.token,
  });

  @override
  State<_ExpandableBookingCard> createState() => _ExpandableBookingCardState();
}

class _ExpandableBookingCardState extends State<_ExpandableBookingCard> {
  bool _expanded = false;

  Future<void> _showCancellationDialog(String bookingId) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => GardenGlassDialog(
        title: const Text('Solicitar cancelación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta solicitud será revisada por el administrador. La cancelación no es inmediata.',
              style: TextStyle(fontSize: 13, color: GardenColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Escribe el motivo de cancelación...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error),
            onPressed: () {
              if (reasonController.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onRequestCancellation(bookingId, reasonController.text.trim());
    }
    reasonController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final status = booking['status'] as String? ?? '';

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: widget.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _expanded ? GardenColors.primary.withOpacity(0.4) : widget.borderColor,
            width: _expanded ? 1.5 : 1,
          ),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(widget.isDark ? 0.2 : 0.05),
            blurRadius: _expanded ? 12 : 6,
            offset: const Offset(0, 2),
          )],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── HEADER siempre visible ──
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: GardenColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      booking['serviceType'] == 'PASEO' ? Icons.directions_walk_outlined : Icons.home_outlined,
                      color: GardenColors.primary, size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking['serviceType'] == 'PASEO' ? 'Paseo' : 'Hospedaje',
                          style: TextStyle(color: widget.textColor, fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${booking['petName'] ?? '—'} · ${booking['walkDate'] ?? booking['startDate'] ?? '—'}',
                          style: TextStyle(color: widget.subtextColor, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      bookingStatusBadge(status),
                      const SizedBox(height: 4),
                      Text(
                        'Bs ${_caregiverNetAmount(booking)}',
                        style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: widget.subtextColor, size: 20,
                  ),
                ],
              ),
            ),

            // ── CONTENIDO EXPANDIDO ──
            if (_expanded) ...[
              Divider(height: 1, color: widget.borderColor),

              // Datos de la mascota
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    Text('Mascota', style: TextStyle(color: widget.subtextColor, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                    const Spacer(),
                    // Botón "Ver perfil" solo para reservas activas/pendientes
                    if (['WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS'].contains(status) &&
                        booking['petId'] != null)
                      GestureDetector(
                        onTap: () => showPetProfileSheet(
                          context: context,
                          bookingId: booking['id'] as String,
                          token: widget.token,
                          petName: booking['petName'] as String? ?? 'Mascota',
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Ver perfil completo', style: TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 3),
                            const Icon(Icons.arrow_forward_ios_rounded, color: GardenColors.primary, size: 10),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: ['WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS'].contains(status) && booking['petId'] != null
                    ? () => showPetProfileSheet(
                        context: context,
                        bookingId: booking['id'] as String,
                        token: widget.token,
                        petName: booking['petName'] as String? ?? 'Mascota',
                      )
                    : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: GardenColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.pets, color: GardenColors.primary, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(booking['petName'] as String? ?? '—',
                              style: TextStyle(
                                color: ['WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS'].contains(status) && booking['petId'] != null
                                    ? GardenColors.primary
                                    : widget.textColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                decoration: ['WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS'].contains(status) && booking['petId'] != null
                                    ? TextDecoration.underline
                                    : TextDecoration.none,
                              )),
                            Text(
                              [
                                if (booking['petBreed'] != null) booking['petBreed'] as String,
                                if (booking['petAge'] != null) '${booking['petAge']} años',
                              ].join(' · '),
                              style: TextStyle(color: widget.subtextColor, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (booking['specialNeeds'] != null && (booking['specialNeeds'] as String).isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: GardenColors.warning.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('⚠️ Especial', style: TextStyle(color: GardenColors.warning, fontSize: 11)),
                        ),
                    ],
                  ),
                ),
              ),

              if (booking['specialNeeds'] != null && (booking['specialNeeds'] as String).isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: GardenColors.warning.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: GardenColors.warning.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: GardenColors.warning),
                        const SizedBox(width: 8),
                        Expanded(child: Text(booking['specialNeeds'] as String,
                          style: TextStyle(color: widget.subtextColor, fontSize: 12))),
                      ],
                    ),
                  ),
                ),
              ],

              Divider(height: 1, color: widget.borderColor),

              // Datos del dueño
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Text('Dueño', style: TextStyle(color: widget.subtextColor, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    GardenAvatar(
                      imageUrl: booking['clientPhoto'],
                      size: 40,
                      initials: (booking['clientName'] as String? ?? 'D')[0],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(booking['clientName'] as String? ?? 'Cliente',
                            style: TextStyle(color: widget.textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                          if (booking['clientPhone'] != null)
                            Row(children: [
                              Icon(Icons.phone_outlined, size: 12, color: widget.subtextColor),
                              const SizedBox(width: 4),
                              Text(booking['clientPhone'] as String,
                                style: TextStyle(color: widget.subtextColor, fontSize: 12)),
                            ]),
                          if (booking['clientEmail'] != null)
                            Row(children: [
                              Icon(Icons.email_outlined, size: 12, color: widget.subtextColor),
                              const SizedBox(width: 4),
                              Expanded(child: Text(booking['clientEmail'] as String,
                                style: TextStyle(color: widget.subtextColor, fontSize: 12),
                                overflow: TextOverflow.ellipsis)),
                            ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Acciones si aplica
              if (status == 'WAITING_CAREGIVER_APPROVAL') ...[
                Divider(height: 1, color: widget.borderColor),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: GardenButton(
                          label: 'Aceptar',
                          icon: Icons.check_rounded,
                          height: 42,
                          color: GardenColors.success,
                          onPressed: () => widget.onRespond(booking['id'] as String, 'accept'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GardenButton(
                          label: 'Rechazar',
                          icon: Icons.close_rounded,
                          height: 42,
                          color: GardenColors.error,
                          outline: true,
                          onPressed: () => widget.onRespond(booking['id'] as String, 'reject'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (status == 'CONFIRMED' || status == 'IN_PROGRESS')
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: GardenButton(
                    label: status == 'CONFIRMED' ? 'Gestionar servicio' : '🔴 Servicio en curso',
                    icon: status == 'CONFIRMED' ? Icons.pets_outlined : Icons.play_circle_outline,
                    height: 42,
                    color: status == 'IN_PROGRESS' ? GardenColors.success : GardenColors.primary,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServiceExecutionScreen(
                          bookingId: booking['id'] as String,
                          role: 'CAREGIVER',
                        ),
                      ),
                    ),
                  ),
                ),

              if (status == 'CONFIRMED')
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: GardenButton(
                    label: 'Solicitar cancelación',
                    icon: Icons.cancel_outlined,
                    height: 40,
                    color: GardenColors.error,
                    outline: true,
                    onPressed: () => _showCancellationDialog(booking['id'] as String),
                  ),
                ),

              // Verificar si hay disputa pendiente para el cuidador
              if (status == 'COMPLETED' && booking['hasDisputePending'] == true)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: GardenButton(
                    label: '⚠️ Responder disputa',
                    height: 42,
                    color: GardenColors.warning,
                    onPressed: () => context.push(
                      '/dispute/${booking['id']}',
                      extra: {
                        'role': 'CAREGIVER',
                        'clientReasons': (booking['disputeReasons'] as List?)?.cast<String>(),
                      },
                    ),
                  ),
                ),

              if (status == 'CONFIRMED' || status == 'IN_PROGRESS' || status == 'WAITING_CAREGIVER_APPROVAL')
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: GardenButton(
                    label: 'Abrir chat',
                    icon: Icons.chat_outlined,
                    outline: true,
                    height: 40,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          bookingId: booking['id'] as String,
                          otherPersonName: booking['clientName'] as String? ?? 'Cliente',
                          token: widget.token,
                          role: 'CAREGIVER',
                          bookingStatus: booking['status'] as String?,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}


String _caregiverNetAmount(Map<String, dynamic> booking) {
  final total = double.tryParse(booking['totalAmount']?.toString() ?? '0') ?? 0;
  final commission = double.tryParse(booking['commissionAmount']?.toString() ?? '0') ?? 0;
  final net = total - commission;
  return net > 0 ? net.toStringAsFixed(0) : (total > 0 ? total.toStringAsFixed(0) : '—');
}

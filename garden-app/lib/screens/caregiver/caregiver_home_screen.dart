import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../main.dart';
import '../chat/chat_screen.dart';

class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({Key? key}) : super(key: key);

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen> {
  // Estado base
  Map<String, dynamic>? _availability;
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;
  String _caregiverToken = '';
  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  Timer? _notifTimer;
  Map<String, dynamic>? _caregiver;

  static const String _devToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJmNmRmZmYzMS1lYTFhLTQ4MzktYmZkOC1kMWY4OTgwNDQxMjAiLCJyb2xlIjoiQ0FSRUdJVkVSIiwiaWQiOiJmNmRmZmYzMS1lYTFhLTQ4MzktYmZkOC1kMWY4OTgwNDQxMjAiLCJpYXQiOjE3NzM2ODU4NjQsImV4cCI6MTc3NjI3Nzg2NH0.I9cvXI16qEgG55S6FTHeieDLqPjhCQewLKvN0xXgddw';

  int _selectedTab = 0; // 0: Inicio, 1: Disponibilidad, 2: Reservas
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  // Calendario e interactividad
  DateTime _calendarMonth = DateTime.now();
  DateTime? _selectedDay;
  Map<String, String> _dayStatus = {}; // 'available', 'blocked', 'partial', 'booked'
  
  // Modo edición
  bool _editMode = false;
  Map<String, dynamic> _pendingChanges = {}; // cambios sin guardar
  Map<String, dynamic> _editableSchedule = {}; // copia editable del schedule

  @override
  void initState() {
    super.initState();
    _initData();
    _notifTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadNotifications());
  }

  @override
  void dispose() {
    _notifTimer?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _caregiverToken = prefs.getString('access_token') ?? '';
    if (_caregiverToken.isEmpty) {
      _caregiverToken = _devToken;
    }

    try {
      await Future.wait([
        _loadCaregiverProfile(),
        _loadAvailability(),
        _loadBookings(),
        _loadNotifications(),
      ]);
      _computeDayStatuses();
    } catch (e) {
      // silencioso
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _enterEditMode() {
    final raw = _availability?['defaultSchedule']?['paseoTimeBlocks'];
    final currentBlocks = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    
    Map<String, dynamic> safeBlock(String key, String defaultStart, String defaultEnd) {
      final b = currentBlocks[key];
      if (b is Map) return Map<String, dynamic>.from(b);
      return {'enabled': true, 'start': defaultStart, 'end': defaultEnd};
    }
    
    _editableSchedule = {
      'morning': safeBlock('morning', '08:00', '11:00'),
      'afternoon': safeBlock('afternoon', '13:00', '17:00'),
      'night': safeBlock('night', '19:00', '22:00'),
    };
    _pendingChanges = {};
    setState(() => _editMode = true);
  }

  Future<void> _saveChanges() async {
    // Mostrar resumen antes de guardar
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSaveConfirmSheet(),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final body = <String, dynamic>{};
      
      // Incluir cambios de schedule si los hay
      if (_editableSchedule.isNotEmpty) {
        body['defaultSchedule'] = {
          'paseoTimeBlocks': _editableSchedule,
          'hospedajeDefault': true,
        };
      }
      
      // Incluir overrides de días bloqueados si los hay
      if (_pendingChanges.isNotEmpty) {
        body['overrides'] = _pendingChanges;
      }
      
      if (body.isEmpty) {
        setState(() => _editMode = false);
        return;
      }
      
      final response = await http.patch(
        Uri.parse('$_baseUrl/caregiver/availability'),
        headers: {
          'Authorization': 'Bearer $_caregiverToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadAvailability();
        _computeDayStatuses();
        setState(() {
          _editMode = false;
          _pendingChanges = {};
          _editableSchedule = {};
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cambios guardados'), backgroundColor: Colors.green),
        );
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al guardar');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSaveConfirmSheet() {
    final blockedDays = _pendingChanges.keys.toList();
    final changedBlocks = _editableSchedule.entries.where((e) {
      final rawCurrent = (_availability?['defaultSchedule']?['paseoTimeBlocks'] as Map?)?[e.key];
      final current = rawCurrent is Map ? Map<String, dynamic>.from(rawCurrent) : null;
      return current == null || 
        current['enabled'] != e.value['enabled'] ||
        current['start'] != e.value['start'] ||
        current['end'] != e.value['end'];
    }).toList();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Resumen de cambios',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          if (changedBlocks.isEmpty && blockedDays.isEmpty)
            const Text('No hay cambios pendientes', style: TextStyle(color: kTextSecondary))
          else ...[
            if (changedBlocks.isNotEmpty) ...[
              const Text('Horarios modificados:', style: TextStyle(color: kTextSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              ...changedBlocks.map((e) {
                final label = e.key == 'morning' ? 'Mañana' : e.key == 'afternoon' ? 'Tarde' : 'Noche';
                final enabled = e.value['enabled'] == true ? 'Activado' : 'Desactivado';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 14, color: kPrimaryColor),
                      const SizedBox(width: 8),
                      Text('$label: ${e.value['start']} - ${e.value['end']} ($enabled)',
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],
            if (blockedDays.isNotEmpty) ...[
              const Text('Días bloqueados:', style: TextStyle(color: kTextSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              ...blockedDays.map((day) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.block, size: 14, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(day, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              )),
            ],
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _computeDayStatuses() {
    final statuses = <String, String>{};
    final now = DateTime.now();
    
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
      
      // Verificar overrides (el API puede devolverlos en 'overrides' o 'dates')
      final serverOverrides = (_availability?['overrides'] ?? _availability?['dates']) as Map?;
      if (serverOverrides != null && serverOverrides.containsKey(dateStr)) {
        final override = serverOverrides[dateStr];
        if (override is Map && override['isAvailable'] == false) {
          statuses[dateStr] = 'blocked';
          continue;
        }
      }
      
      // Por defecto: disponible
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
        setState(() => _caregiver = data['data']);
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
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) context.go('/login');
  }

  Future<void> _toggleTimeBlock(String blockName, bool enabled) async {
    try {
      final currentBlocks = _availability!['defaultSchedule']['paseoTimeBlocks'];
      final updatedBlocks = Map<String, dynamic>.from(currentBlocks);
      updatedBlocks[blockName] = {
        ...Map<String, dynamic>.from(updatedBlocks[blockName]),
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

  Future<void> _loadNotifications() async {
    if (_caregiverToken.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/caregiver/notifications'),
        headers: {'Authorization': 'Bearer $_caregiverToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final notifs = (data['data'] as List).cast<Map<String, dynamic>>();
        if (mounted) {
          setState(() {
            _notifications = notifs;
            _unreadCount = notifs.where((n) => n['read'] == false).length;
          });
        }
      }
    } catch (_) {}
  }

  void _showNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final isDark = themeNotifier.isDark;
          final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
          final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
          final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
          final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Notificaciones',
                        style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                      if (_unreadCount > 0)
                        TextButton(
                          onPressed: () async {
                            // Marcar todas como leídas
                            for (final n in _notifications.where((n) => n['read'] == false)) {
                              await http.patch(
                                Uri.parse('$_baseUrl/caregiver/notifications/${n['id']}/read'),
                                headers: {'Authorization': 'Bearer $_caregiverToken'},
                              );
                            }
                            await _loadNotifications();
                            setSheetState(() {});
                          },
                          child: const Text('Marcar todas leídas',
                            style: TextStyle(color: GardenColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: borderColor),
                // Lista de notificaciones
                Expanded(
                  child: _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_none_outlined, size: 56, color: subtextColor),
                            const SizedBox(height: 12),
                            Text('Sin notificaciones', style: TextStyle(color: subtextColor, fontSize: 16)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final notif = _notifications[index];
                          final isUnread = notif['read'] == false;
                          return GestureDetector(
                            onTap: () async {
                              if (isUnread) {
                                await http.patch(
                                  Uri.parse('$_baseUrl/caregiver/notifications/${notif['id']}/read'),
                                  headers: {'Authorization': 'Bearer $_caregiverToken'},
                                );
                                await _loadNotifications();
                                setSheetState(() {});
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isUnread 
                                  ? GardenColors.primary.withOpacity(0.06)
                                  : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isUnread ? GardenColors.primary.withOpacity(0.2) : borderColor,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Ícono según tipo
                                  Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: _notifColor(notif['type'] as String? ?? '').withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      _notifIcon(notif['type'] as String? ?? ''),
                                      color: _notifColor(notif['type'] as String? ?? ''),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(notif['title'] as String? ?? '',
                                                style: TextStyle(
                                                  color: textColor,
                                                  fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            if (isUnread)
                                              Container(
                                                width: 8, height: 8,
                                                decoration: const BoxDecoration(
                                                  color: GardenColors.primary,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(notif['message'] as String? ?? '',
                                          style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatNotifDate(notif['createdAt'] as String? ?? ''),
                                          style: TextStyle(color: subtextColor.withOpacity(0.7), fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _notifIcon(String type) {
    switch (type) {
      case 'NEW_BOOKING': return Icons.calendar_today_outlined;
      case 'BOOKING_CANCELLED': return Icons.cancel_outlined;
      case 'PAYMENT_RECEIVED': return Icons.payments_outlined;
      case 'REVIEW_RECEIVED': return Icons.star_outline_rounded;
      case 'SYSTEM': return Icons.info_outline;
      case 'PROFILE_APPROVED': return Icons.verified_outlined;
      default: return Icons.notifications_outlined;
    }
  }

  Color _notifColor(String type) {
    switch (type) {
      case 'NEW_BOOKING': return GardenColors.primary;
      case 'BOOKING_CANCELLED': return GardenColors.error;
      case 'PAYMENT_RECEIVED': return GardenColors.success;
      case 'REVIEW_RECEIVED': return GardenColors.star;
      case 'SYSTEM': return GardenColors.secondary;
      case 'PROFILE_APPROVED': return GardenColors.success;
      default: return GardenColors.secondary;
    }
  }

  String _formatNotifDate(String isoDate) {
    if (isoDate.isEmpty) return '';
    try {
      final date = DateTime.parse(isoDate).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
      if (diff.inDays < 7) return 'Hace ${diff.inDays}d';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildHome() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final pendingCount = _bookings.where((b) => b['status'] == 'WAITING_CAREGIVER_APPROVAL').length;
    final confirmedCount = _bookings.where((b) => b['status'] == 'CONFIRMED' || b['status'] == 'IN_PROGRESS').length;
    final completedCount = _bookings.where((b) => b['status'] == 'COMPLETED').length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Saludo
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Buenos días 👋', style: TextStyle(color: subtextColor, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('Panel de ', style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 22, fontWeight: FontWeight.w400)),
                      Text('cuidador', style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    ],
                  ),
                ],
              ),
              // Foto de perfil removida por solicitud del usuario
            ],
          ),
          if (_caregiver != null && _caregiver!['user'] != null) ...[
            const SizedBox(height: 8),
            Text('${_caregiver!['user']['firstName']} ${_caregiver!['user']['lastName']}', 
              style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 24),

          // Alerta de reservas pendientes
          if (pendingCount > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: GardenColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: GardenColors.warning.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, color: GardenColors.warning, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$pendingCount reserva${pendingCount > 1 ? 's' : ''} pendiente${pendingCount > 1 ? 's' : ''}',
                          style: const TextStyle(color: GardenColors.warning, fontWeight: FontWeight.w700, fontSize: 15)),
                        Text('Acepta o rechaza antes de que expiren',
                          style: TextStyle(color: GardenColors.warning.withOpacity(0.8), fontSize: 13)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _selectedTab = 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: GardenColors.warning,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Ver', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),

          // Métricas en grid 2x2
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _metricCard('Pendientes', pendingCount.toString(), Icons.hourglass_top_outlined, GardenColors.warning, surface, textColor, subtextColor, borderColor),
              _metricCard('Confirmadas', confirmedCount.toString(), Icons.check_circle_outline, GardenColors.success, surface, textColor, subtextColor, borderColor),
              _metricCard('Completadas', completedCount.toString(), Icons.done_all_outlined, GardenColors.secondary, surface, textColor, subtextColor, borderColor),
              _metricCard('Total', _bookings.length.toString(), Icons.calendar_month_outlined, GardenColors.primary, surface, textColor, subtextColor, borderColor),
            ],
          ),
          const SizedBox(height: 24),

          // Acciones rápidas
          Text('Acciones rápidas', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GardenButton(
                  label: 'Disponibilidad',
                  icon: Icons.calendar_month_outlined,
                  outline: true,
                  onPressed: () => setState(() => _selectedTab = 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GardenButton(
                  label: 'Verificación IA',
                  icon: Icons.verified_user_outlined,
                  onPressed: () => context.push('/caregiver/verification'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Últimas reservas (preview de 3)
          if (_bookings.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Reservas recientes', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                GestureDetector(
                  onTap: () => setState(() => _selectedTab = 2),
                  child: Text('Ver todas', style: TextStyle(color: GardenColors.primary, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._bookings.take(3).map((b) => _buildBookingPreviewCard(b, surface, textColor, subtextColor, borderColor)),
          ],
        ],
      ),
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color, Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(color: subtextColor, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBookingPreviewCard(Map<String, dynamic> booking, Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final status = booking['status'] as String? ?? '';
    return Container(
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
          Text('Bs ${booking['totalAmount'] ?? '—'}', style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildAvailability() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con botón Editar / Guardar / Cancelar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Disponibilidad',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              if (!_editMode)
                ElevatedButton.icon(
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Editar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  onPressed: _enterEditMode,
                )
              else
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _editMode = false;
                        _pendingChanges = {};
                        _editableSchedule = {};
                      }),
                      child: const Text('Cancelar', style: TextStyle(color: kTextSecondary)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save, size: 16),
                      label: const Text('Guardar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                      ),
                      onPressed: _saveChanges,
                    ),
                  ],
                ),
            ],
          ),
          
          // Banner de modo edición
          if (_editMode) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: kPrimaryColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Modo edición activo. Realiza todos los cambios y presiona Guardar.',
                      style: TextStyle(color: kPrimaryColor, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          const SizedBox(height: 20),
          
          // Sección horarios por defecto
          const Text('Horarios por defecto',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const Text('Aplican a todos los días salvo excepciones',
            style: TextStyle(color: kTextSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          _buildEditableScheduleBlocks(),
          
          const SizedBox(height: 24),
          
          // Leyenda
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _legendItem(Colors.green.shade700, 'Disponible'),
                const SizedBox(width: 12),
                _legendItem(Colors.red.shade700, 'Bloqueado'),
                const SizedBox(width: 12),
                _legendItem(Colors.orange, 'Parcial'),
                const SizedBox(width: 12),
                _legendItem(kPrimaryColor, 'Reservado'),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Navegación de mes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: () => setState(() =>
                  _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1)),
              ),
              Text(_monthName(_calendarMonth),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: () => setState(() =>
                  _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1)),
              ),
            ],
          ),
          
          // Días de la semana
          Row(
            children: ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sa', 'Do'].map((d) =>
              Expanded(
                child: Center(
                  child: Text(d, style: const TextStyle(color: kTextSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              )
            ).toList(),
          ),
          const SizedBox(height: 8),
          
          _buildCalendarGrid(),
          const SizedBox(height: 24),
          
          if (_selectedDay != null) _buildDayPanel(_selectedDay!),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color.withOpacity(0.8), borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 11)),
      ],
    );
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
      final isSelected = _selectedDay?.toIso8601String().split('T')[0] == dateStr;
      final isPast = date.isBefore(DateTime.now().subtract(const Duration(days: 0)));
      
      Color bgColor;
      switch (status) {
        case 'blocked': bgColor = Colors.red.shade700; break;
        case 'booked': bgColor = kPrimaryColor; break;
        case 'partial': bgColor = Colors.orange; break;
        default: bgColor = Colors.green.shade700;
      }
      
      if (isPast) bgColor = kSurfaceColor;
      
      cells.add(
        GestureDetector(
          onTap: isPast ? null : () => setState(() => _selectedDay = date),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: bgColor.withOpacity(isPast ? 0.3 : 0.8),
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
            ),
            child: Center(
              child: Text(
                '$day',
                style: TextStyle(
                  color: isPast ? kTextSecondary : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
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
                  value: status == 'blocked' || (_pendingChanges[dateStr]?['isAvailable'] == false),
                  activeColor: Colors.red,
                  onChanged: (val) {
                    if (_editMode) {
                      setState(() {
                        if (val) {
                          _pendingChanges[dateStr] = {'isAvailable': false, 'reason': 'No disponible'};
                          _dayStatus[dateStr] = 'blocked';
                        } else {
                          _pendingChanges.remove(dateStr);
                          _dayStatus[dateStr] = 'available';
                        }
                      });
                    } else {
                      // Sin modo edición: guardar inmediatamente
                      _toggleDayBlock(dateStr, val);
                    }
                  },
                ),
              ],
            ),
            if (status != 'blocked') ...[
              const Divider(color: Colors.white12),
              const Text('Horarios disponibles este día:', 
                style: TextStyle(color: kTextSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              _buildDayTimeBlocks(dateStr),
              if (_editMode && _pendingChanges.containsKey(dateStr) && 
                  _pendingChanges[dateStr]['timeBlocks'] != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.restore, size: 14, color: kTextSecondary),
                  label: const Text('Restablecer horarios a predeterminado',
                    style: TextStyle(color: kTextSecondary, fontSize: 12)),
                  onPressed: () {
                    setState(() {
                      if (_pendingChanges[dateStr] != null) {
                        (_pendingChanges[dateStr] as Map).remove('timeBlocks');
                        if ((_pendingChanges[dateStr] as Map).isEmpty) {
                          _pendingChanges.remove(dateStr);
                        }
                      }
                    });
                  },
                ),
              ],
            ],
          ] else
            const Text(
              'Este día tiene reservas activas. Mantente atento!',
              style: TextStyle(color: kTextSecondary, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildDayTimeBlocks(String dateStr) {
    debugPrint('DAY PANEL dates data: ${(_availability?['dates'] as Map?)?[dateStr]}');
    
    final rawGlobal = _editMode 
      ? _editableSchedule 
      : (() {
          final raw = _availability?['defaultSchedule']?['paseoTimeBlocks'];
          return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        })();

    // El backend devuelve overrides en dates[dateStr].timeBlocks.slots
    final rawDateEntry = (_availability?['dates'] as Map?)?[dateStr];
    final rawTimeBlocks = rawDateEntry is Map ? rawDateEntry['timeBlocks'] : null;
    final rawSlots = rawTimeBlocks is Map ? rawTimeBlocks['slots'] : null;
    final dayOverride = rawSlots is Map 
      ? Map<String, dynamic>.from(rawSlots) 
      : <String, dynamic>{};

    // También verificar _pendingChanges para cambios no guardados en modo edición
    final rawPending = _pendingChanges[dateStr]?['timeBlocks'];
    final pendingOverride = rawPending is Map 
      ? Map<String, dynamic>.from(rawPending) 
      : <String, dynamic>{};
    
    // Combinar: pending tiene prioridad sobre lo guardado en backend
    final effectiveOverride = {...dayOverride, ...pendingOverride};

    return Column(
      children: ['morning', 'afternoon', 'night'].map((blockKey) {
        final rawGlobalBlock = rawGlobal[blockKey];
        final globalBlock = rawGlobalBlock is Map
          ? Map<String, dynamic>.from(rawGlobalBlock)
          : {'enabled': true, 'start': blockKey == 'morning' ? '08:00' : blockKey == 'afternoon' ? '13:00' : '19:00',
             'end': blockKey == 'morning' ? '11:00' : blockKey == 'afternoon' ? '17:00' : '22:00'};

        final label = blockKey == 'morning' ? 'Mañana' : blockKey == 'afternoon' ? 'Tarde' : 'Noche';

        // El estado del bloque para este día específico:
        // Priorizar effectiveOverride (servidor + local)
        final rawDayBlock = effectiveOverride[blockKey];
        final dayBlockOverride = rawDayBlock is Map 
          ? Map<String, dynamic>.from(rawDayBlock) 
          : null;
        
        final isEnabled = dayBlockOverride != null 
          ? dayBlockOverride['enabled'] == true
          : globalBlock['enabled'] == true;
        
        final timeRange = '${globalBlock['start']} - ${globalBlock['end']}';
        final isCustomized = effectiveOverride.containsKey(blockKey);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: kBackgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: isCustomized 
              ? Border.all(color: kAccentColor.withOpacity(0.5)) 
              : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        if (isCustomized) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: kAccentColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Personalizado',
                              style: TextStyle(color: kAccentColor, fontSize: 10)),
                          ),
                        ],
                      ],
                    ),
                    Text(timeRange, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Switch(
                value: isEnabled,
                activeColor: kPrimaryColor,
                onChanged: (val) {
                  if (_editMode) {
                    // Modo edición: acumular en _pendingChanges
                    setState(() {
                      if (!_pendingChanges.containsKey(dateStr)) {
                        _pendingChanges[dateStr] = {'isAvailable': true, 'timeBlocks': {}};
                      }
                      final timeBlocks = _pendingChanges[dateStr]['timeBlocks'];
                      final blocksMap = timeBlocks is Map 
                        ? Map<String, dynamic>.from(timeBlocks) 
                        : <String, dynamic>{};
                      blocksMap[blockKey] = {
                        'enabled': val,
                        'start': globalBlock['start'],
                        'end': globalBlock['end'],
                      };
                      _pendingChanges[dateStr]['timeBlocks'] = blocksMap;
                    });
                  } else {
                    // Sin modo edición: guardar inmediatamente
                    _toggleDayBlockImmediate(dateStr, blockKey, val);
                  }
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEditableScheduleBlocks() {
    final rawBlocks = _editMode ? _editableSchedule : (() {
      final raw = _availability?['defaultSchedule']?['paseoTimeBlocks'];
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    })();
    
    return Column(
      children: ['morning', 'afternoon', 'night'].map((key) {
        final rawBlock = rawBlocks[key];
        final block = rawBlock is Map 
          ? Map<String, dynamic>.from(rawBlock)
          : {'enabled': true, 
             'start': key == 'morning' ? '08:00' : key == 'afternoon' ? '13:00' : '19:00',
             'end': key == 'morning' ? '11:00' : key == 'afternoon' ? '17:00' : '22:00'};
        final label = key == 'morning' ? 'Mañana' : key == 'afternoon' ? 'Tarde' : 'Noche';
        final isEnabled = block['enabled'] == true;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: _editMode ? Border.all(color: kPrimaryColor.withOpacity(0.3)) : null,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        if (_editMode && isEnabled)
                          // Editores de hora en modo edición
                          Row(
                            children: [
                              _timeEditor('Inicio', block['start'] as String, (newTime) {
                                setState(() {
                                  (_editableSchedule[key] as Map<String, dynamic>)['start'] = newTime;
                                });
                              }),
                              const Text(' - ', style: TextStyle(color: kTextSecondary)),
                              _timeEditor('Fin', block['end'] as String, (newTime) {
                                setState(() {
                                  (_editableSchedule[key] as Map<String, dynamic>)['end'] = newTime;
                                });
                              }),
                            ],
                          )
                        else
                          Text('${block['start']} - ${block['end']}',
                            style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  Switch(
                    value: isEnabled,
                    activeColor: kPrimaryColor,
                    onChanged: _editMode ? (val) {
                      setState(() {
                        (_editableSchedule[key] as Map<String, dynamic>)['enabled'] = val;
                      });
                    } : null,
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _timeEditor(String label, String currentTime, Function(String) onChanged) {
    return GestureDetector(
      onTap: () async {
        final parts = currentTime.split(':');
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
          builder: (context, child) {
            return Theme(
              data: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(primary: kPrimaryColor),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          final formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          onChanged(formatted);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: kPrimaryColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: kPrimaryColor.withOpacity(0.5)),
        ),
        child: Text(currentTime,
          style: const TextStyle(color: kPrimaryColor, fontSize: 13, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildFullBookingCard(Map<String, dynamic> booking) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final status = booking['status'] as String? ?? '';

    return _ExpandableBookingCard(
      booking: booking,
      surface: surface,
      textColor: textColor,
      subtextColor: subtextColor,
      borderColor: borderColor,
      isDark: isDark,
      onRespond: _respondBooking,
    );
  }

  Widget _buildBookings() {
    if (_bookings.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, color: GardenColors.darkTextSecondary, size: 64),
            SizedBox(height: 16),
            Text('No tienes reservas aún', style: TextStyle(color: GardenColors.darkTextSecondary)),
          ],
        ),
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

  Widget _buildStatusBadge(String status) {
    Color color = kTextSecondary;
    String label = status;
    switch (status) {
      case 'WAITING_CAREGIVER_APPROVAL': color = Colors.orange; label = 'Por Aceptar'; break;
      case 'CONFIRMED': color = Colors.green; label = 'Confirmada'; break;
      case 'PENDING_PAYMENT': color = kPrimaryColor; label = 'Pendiente Pago'; break;
      case 'CANCELLED': color = Colors.red; label = 'Cancelada'; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withOpacity(0.3))),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEarnings() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    // Calcular estadísticas desde _bookings
    final completedBookings = _bookings.where((b) => b['status'] == 'COMPLETED').toList();
    final confirmedBookings = _bookings.where((b) => b['status'] == 'CONFIRMED' || b['status'] == 'IN_PROGRESS').toList();

    double totalEarned = 0;
    double totalCommission = 0;
    double pendingEarnings = 0;

    for (final b in completedBookings) {
      final amount = double.tryParse(b['totalAmount']?.toString() ?? '0') ?? 0;
      final commission = double.tryParse(b['commissionAmount']?.toString() ?? '0') ?? 0;
      totalEarned += amount - commission;
      totalCommission += commission;
    }

    for (final b in confirmedBookings) {
      final amount = double.tryParse(b['totalAmount']?.toString() ?? '0') ?? 0;
      final commission = double.tryParse(b['commissionAmount']?.toString() ?? '0') ?? 0;
      pendingEarnings += amount - commission;
    }

    // Agrupar por mes
    final Map<String, double> byMonth = {};
    for (final b in completedBookings) {
      final date = b['walkDate'] ?? b['startDate'] ?? b['createdAt'];
      if (date == null) continue;
      final month = date.toString().substring(0, 7); // YYYY-MM
      final amount = double.tryParse(b['totalAmount']?.toString() ?? '0') ?? 0;
      final commission = double.tryParse(b['commissionAmount']?.toString() ?? '0') ?? 0;
      byMonth[month] = (byMonth[month] ?? 0) + (amount - commission);
    }

    // Agrupar por tipo de servicio
    double walkEarnings = 0;
    double hospedajeEarnings = 0;
    for (final b in completedBookings) {
      final amount = double.tryParse(b['totalAmount']?.toString() ?? '0') ?? 0;
      final commission = double.tryParse(b['commissionAmount']?.toString() ?? '0') ?? 0;
      final net = amount - commission;
      if (b['serviceType'] == 'PASEO') walkEarnings += net;
      else hospedajeEarnings += net;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mis ganancias', style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text('Ingresos netos después de comisión GARDEN', style: TextStyle(color: subtextColor, fontSize: 13)),
          const SizedBox(height: 24),

          // Tarjeta principal de ganancias totales
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF6B35), Color(0xFFE55A25)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: GardenColors.primary.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 6))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total ganado', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text('Bs ${totalEarned.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _earningsChip('${completedBookings.length} completadas', Icons.check_circle_outline),
                    const SizedBox(width: 10),
                    _earningsChip('Bs ${totalCommission.toStringAsFixed(0)} comisión', Icons.info_outline),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Ganancias pendientes
          if (pendingEarnings > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: GardenColors.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: GardenColors.success.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: GardenColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.hourglass_top_outlined, color: GardenColors.success, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Por cobrar', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                        Text('De reservas confirmadas en curso', style: TextStyle(color: subtextColor, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text('Bs ${pendingEarnings.toStringAsFixed(2)}',
                    style: const TextStyle(color: GardenColors.success, fontWeight: FontWeight.w800, fontSize: 18)),
                ],
              ),
            ),

          // Desglose por servicio
          Text('Por servicio', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _serviceEarningsCard('🦮 Paseo', walkEarnings, completedBookings.where((b) => b['serviceType'] == 'PASEO').length, surface, textColor, subtextColor, borderColor)),
              const SizedBox(width: 12),
              Expanded(child: _serviceEarningsCard('🏠 Hospedaje', hospedajeEarnings, completedBookings.where((b) => b['serviceType'] == 'HOSPEDAJE').length, surface, textColor, subtextColor, borderColor)),
            ],
          ),
          const SizedBox(height: 24),

          // Historial por mes
          if (byMonth.isNotEmpty) ...[
            Text('Historial mensual', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...byMonth.entries.toList().reversed.map((entry) {
              final monthStr = _formatMonth(entry.key);
              final amount = entry.value;
              final maxAmount = byMonth.values.reduce((a, b) => a > b ? a : b);
              final percentage = maxAmount > 0 ? amount / maxAmount : 0.0;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 70,
                      child: Text(monthStr, style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percentage,
                          backgroundColor: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                          valueColor: const AlwaysStoppedAnimation<Color>(GardenColors.primary),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('Bs ${amount.toStringAsFixed(0)}',
                      style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
              );
            }),
          ],

          // Si no hay ganancias
          if (completedBookings.isEmpty)
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: GardenColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined, size: 36, color: GardenColors.primary),
                  ),
                  const SizedBox(height: 16),
                  Text('Sin ganancias aún', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('Completa tus primeras reservas para ver tus estadísticas',
                    style: TextStyle(color: subtextColor, fontSize: 14), textAlign: TextAlign.center),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _earningsChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _serviceEarningsCard(String title, double amount, int count, Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Bs ${amount.toStringAsFixed(0)}',
            style: const TextStyle(color: GardenColors.primary, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('$count servicios', style: TextStyle(color: subtextColor, fontSize: 12)),
        ],
      ),
    );
  }

  String _formatMonth(String yearMonth) {
    final parts = yearMonth.split('-');
    if (parts.length < 2) return yearMonth;
    const months = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    final month = int.tryParse(parts[1]) ?? 0;
    return '${months[month]} ${parts[0]}';
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
                Text('GARDEN', style: TextStyle(color: GardenColors.primary, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: GardenColors.primary.withOpacity(0.3)),
                  ),
                  child: Text('Cuidador', style: TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.account_circle_outlined,
                  color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
                onPressed: () => context.push('/profile'),
                tooltip: 'Mi perfil',
              ),
              Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications_outlined, 
                      color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
                    onPressed: () => _showNotificationsSheet(),
                  ),
                  if (_unreadCount > 0)
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        width: 16, height: 16,
                        decoration: const BoxDecoration(
                          color: GardenColors.error,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            _unreadCount > 9 ? '9+' : '$_unreadCount',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: Icon(themeNotifier.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
                onPressed: () => themeNotifier.toggle(),
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
            : [
                _buildHome(),
                _buildAvailability(),
                _buildBookings(),
                _buildEarnings(),
              ][_selectedTab],
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedTab,
            onTap: (i) => setState(() => _selectedTab = i),
            backgroundColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            selectedItemColor: GardenColors.primary,
            unselectedItemColor: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home_rounded),
                label: 'Inicio',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.calendar_month_outlined),
                activeIcon: Icon(Icons.calendar_month_rounded),
                label: 'Disponibilidad',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.list_alt_outlined),
                activeIcon: Icon(Icons.list_alt_rounded),
                label: 'Reservas',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_outlined),
                activeIcon: Icon(Icons.account_balance_wallet_rounded),
                label: 'Ganancias',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExpandableBookingCard extends StatefulWidget {
  final Map<String, dynamic> booking;
  final Color surface, textColor, subtextColor, borderColor;
  final bool isDark;
  final Function(String, String) onRespond;

  const _ExpandableBookingCard({
    required this.booking,
    required this.surface,
    required this.textColor,
    required this.subtextColor,
    required this.borderColor,
    required this.isDark,
    required this.onRespond,
  });

  @override
  State<_ExpandableBookingCard> createState() => _ExpandableBookingCardState();
}

class _ExpandableBookingCardState extends State<_ExpandableBookingCard> {
  bool _expanded = false;

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
                        'Bs ${booking['totalAmount'] ?? '—'}',
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
                child: Text('Mascota', style: TextStyle(color: widget.subtextColor, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
              ),
              Padding(
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(booking['petName'] as String? ?? '—',
                          style: TextStyle(color: widget.textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(
                          [
                            if (booking['petBreed'] != null) booking['petBreed'] as String,
                            if (booking['petAge'] != null) '${booking['petAge']} años',
                          ].join(' · '),
                          style: TextStyle(color: widget.subtextColor, fontSize: 12),
                        ),
                      ],
                    ),
                    if (booking['specialNeeds'] != null && (booking['specialNeeds'] as String).isNotEmpty)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: GardenColors.warning.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('⚠️ Especial', style: TextStyle(color: GardenColors.warning, fontSize: 11)),
                          ),
                        ),
                      ),
                  ],
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
                        Icon(Icons.info_outline, size: 14, color: GardenColors.warning),
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

              if (status == 'CONFIRMED' || status == 'IN_PROGRESS' || status == 'WAITING_CAREGIVER_APPROVAL' || status == 'COMPLETED')
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

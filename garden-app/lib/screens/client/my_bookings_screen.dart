import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../design/garden_bookings.dart';
import '../../design/garden_icons.dart';
import '../../design/garden_payment.dart';
import '../../design/garden_wallet.dart';
import '../../design/garden_pet_avatar.dart';
import '../../design/garden_service.dart';
import '../../design/garden_status_pill.dart';
import '../../narrative/booking_story.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/booking_history_detail.dart';
import '../../widgets/garden_empty_state.dart';
import '../../widgets/notification_bell.dart';
import '../service/meet_and_greet_screen.dart';
import '../chat/chat_screen.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../design/garden_depth.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;
  String _clientToken = '';
  String _selectedFilter = 'todas'; // 'todas', 'activas', 'completadas', 'canceladas'
  // IDs donde ya se mostró la decisión M&G (se persiste en SharedPreferences)
  final Set<String> _shownMGDecisionIds = {};
  SharedPreferences? _prefs;
  // Bookings con una cancelación en curso — evita doble-tap / doble submit
  // (dos taps rápidos, o un reintento antes de que llegue la respuesta)
  // disparando dos POST /cancel para la misma reserva.
  final Set<String> _cancellingIds = {};

  String? _highlightBookingId;
  Timer? _highlightClearTimer;
  Timer? _refreshTimer;
  Map<String, int> _unreadCounts = {};

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _initData();
    _loadAutoReleaseHoras();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    String token = AuthState.token;
    debugPrint('MY_BOOKINGS: Loaded access_token: ${token.length > 20 ? token.substring(0, 20) : token}...');
    if (token.isEmpty) {
      token = const String.fromEnvironment('TEST_JWT', defaultValue: '');
      debugPrint('MY_BOOKINGS: Using TEST_JWT: ${token.length > 20 ? token.substring(0, 20) : token}...');
    }
    // Cargar IDs donde ya se mostró la decisión M&G (persiste entre sesiones)
    final saved = prefs.getStringList('mg_decision_shown_ids') ?? [];
    _shownMGDecisionIds.addAll(saved);
    debugPrint('MY_BOOKINGS: mg_decision_shown_ids cargados: $saved');

    // Highlight booking recién creado (viene de payment_screen)
    final highlightId = prefs.getString('highlight_booking_id');
    if (highlightId != null && highlightId.isNotEmpty) {
      await prefs.remove('highlight_booking_id');
      setState(() {
        _highlightBookingId = highlightId;
        _selectedFilter = 'activas';
      });
    }

    setState(() => _clientToken = token);
    await _loadBookings();
    await _loadUnreadCounts();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        _loadBookings(silent: true);
        _loadUnreadCounts();
      }
    });
  }

  Future<void> _loadUnreadCounts() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/chat/unread-counts'),
        headers: {'Authorization': 'Bearer $_clientToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && mounted) {
        final counts = Map<String, dynamic>.from(data['data']['counts'] ?? {});
        setState(() => _unreadCounts = counts.map((k, v) => MapEntry(k, v as int)));
      }
    } catch (_) {
      // No bloquear la lista de reservas si esto falla — es solo un badge informativo
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _highlightClearTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBookings({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      debugPrint('MY_BOOKINGS: Fetching /bookings/my with token: ${_clientToken.length > 20 ? _clientToken.substring(0, 20) : _clientToken}...');
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/my'),
        headers: {'Authorization': 'Bearer $_clientToken'},
      );
      debugPrint('MY_BOOKINGS: Response ${response.statusCode}: ${response.body}');
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final loaded = (data['data'] as List).cast<Map<String, dynamic>>();
        if (mounted) setState(() => _bookings = loaded);
        _checkMGDecisionNeeded();
        // Schedule highlight clear after 5 seconds on first load
        if (_highlightBookingId != null) {
          _highlightClearTimer?.cancel();
          _highlightClearTimer = Timer(const Duration(seconds: 5), () {
            if (mounted) setState(() => _highlightBookingId = null);
          });
        }
      }
    } catch (e) {
      debugPrint('MY_BOOKINGS ERROR: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkMGDecisionNeeded() async {
    final now = DateTime.now();
    for (final booking in _bookings) {
      final status = booking['status'] as String?;
      final mg = booking['meetAndGreet'] as Map<String, dynamic>?;
      final mgStatus = mg?['status'] as String?;
      final confirmedDateStr = mg?['confirmedDate'] as String?;
      final bookingId = booking['id'] as String?;
      if (bookingId == null) continue;
      if (status == 'CONFIRMED' && mgStatus == 'ACCEPTED' && confirmedDateStr != null && !_shownMGDecisionIds.contains(bookingId)) {
        try {
          final confirmedDate = DateTime.parse(confirmedDateStr).toLocal();
          if (now.isAfter(confirmedDate)) {
            _shownMGDecisionIds.add(bookingId);
            // Persistir en SharedPreferences para no volver a preguntar nunca más
            await _prefs?.setStringList('mg_decision_shown_ids', _shownMGDecisionIds.toList());
            debugPrint('MY_BOOKINGS: mg_decision persisted for bookingId=$bookingId');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showMGDecisionSheet(bookingId);
            });
            break; // show one at a time
          }
        } catch (_) {}
      }
    }
  }

  void _showMGDecisionSheet(String bookingId) {
    final isDark = themeNotifier.isDark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) {
        final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const GardenIcon(GIcon.meetGreet, size: GIconSize.xl, state: GIconState.active),
              const SizedBox(height: 12),
              Text('¿Cómo fue el Meet & Greet?', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'El Meet & Greet ya pasó. ¿Deseas continuar con la reserva o cancelarla sin costo?',
                style: TextStyle(color: subtextColor, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GardenColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Continuar con la reserva', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GardenColors.error,
                    side: const BorderSide(color: GardenColors.error),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _cancelBookingPostMG(bookingId);
                  },
                  child: const Text('Cancelar sin costo', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cancelBookingPostMG(String bookingId) async {
    if (_cancellingIds.contains(bookingId)) return; // ya hay una cancelación en curso
    setState(() => _cancellingIds.add(bookingId));
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/$bookingId/cancel'),
        headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'reason': 'Cancelado por dueño tras Meet & Greet', 'source': 'CLIENT_REQUEST'}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadBookings();
        if (mounted) {
          GardenSnackBar.warning(context, 'Reserva cancelada sin costo');
        }
      } else {
        if (mounted) {
          GardenSnackBar.error(context, data['error']?['message'] ?? 'Error al cancelar');
        }
      }
    } catch (e) {
      if (mounted) {
        GardenSnackBar.error(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _cancellingIds.remove(bookingId));
    }
  }

  /// Returns true if the booking has an active (not yet expired) QR.
  bool _hasActiveQr(Map<String, dynamic> b) {
    if (b['status'] != 'PENDING_PAYMENT') return false;
    final qrId = b['qrId'];
    final qrExpiresAtStr = b['qrExpiresAt'];
    if (qrId == null || qrExpiresAtStr == null) return false;
    final expiry = DateTime.tryParse(qrExpiresAtStr.toString());
    return expiry != null && expiry.isAfter(DateTime.now());
  }

  /// A PENDING_PAYMENT booking is only visible to the client while the QR is active.
  /// Once expired the booking is hidden here but kept alive in the backend so
  /// admin can still approve the manual bank transfer.
  bool _shouldShowBooking(Map<String, dynamic> b) {
    if (b['status'] != 'PENDING_PAYMENT') return true;
    return _hasActiveQr(b);
  }

  List<Map<String, dynamic>> get _filteredBookings => _bookingsFor(_selectedFilter);

  List<Map<String, dynamic>> _bookingsFor(String filter) {
    // Only show PENDING_PAYMENT bookings that have an active QR;
    // hide those without QR or with an expired one.
    final visible = _bookings.where(_shouldShowBooking).toList();
    if (filter == 'todas') return visible;
    if (filter == 'activas') {
      return visible.where((b) => [
        'PENDING_MG', 'PENDING_PAYMENT', 'PAYMENT_PENDING_APPROVAL',
        'WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS'
      ].contains(b['status'])).toList();
    }
    if (filter == 'completadas') {
      return visible.where((b) => b['status'] == 'COMPLETED').toList();
    }
    if (filter == 'canceladas') {
      return visible.where((b) => ['CANCELLED', 'REJECTED_BY_CAREGIVER'].contains(b['status'])).toList();
    }
    return visible;
  }

  Future<void> _proceedToPayment(String bookingId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/$bookingId/proceed-to-payment'),
        headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        if (mounted) {
          await context.push('/payment/$bookingId');
          // Refresca siempre al volver (se canceló, se pagó, o no cambió
          // nada) — más simple y seguro que confiar en el timer de 30s.
          if (mounted) _loadBookings();
        }
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al continuar con el pago');
      }
    } catch (e) {
      if (mounted) GardenSnackBar.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  static const Map<String, String> _cancellationReasonLabels = {
    'CLIMA': 'Mal clima',
    'EMERGENCIA_PERSONAL': 'Emergencia personal',
    'CAMBIO_DE_PLANES': 'Cambio de planes',
    'PROBLEMA_CON_MASCOTA_O_CUIDADOR': 'Problema con la mascota o el cuidador',
    'OTRO': 'Otro',
  };

  Future<void> _cancelBooking(String bookingId, {String? serviceType}) async {
    if (_cancellingIds.contains(bookingId)) return; // ya hay una cancelación en curso
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _buildCancelSheet(ctx, serviceType: serviceType),
    );
    if (result == null) return;
    if (_cancellingIds.contains(bookingId)) return; // re-chequeo tras cerrar el sheet
    setState(() => _cancellingIds.add(bookingId));
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/$bookingId/cancel'),
        headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'reasonCode': result['reasonCode'],
          if (result['reasonDetail'] != null && result['reasonDetail']!.isNotEmpty)
            'reason': result['reasonDetail'],
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadBookings();
        if (mounted) GardenSnackBar.warning(context, 'Reserva cancelada');
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      if (mounted) {
        GardenSnackBar.error(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _cancellingIds.remove(bookingId));
    }
  }

  Widget _buildCancelSheet(BuildContext ctx, {String? serviceType}) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    String? selectedReasonCode;
    final detailController = TextEditingController();
    // "Mal clima" solo garantiza reembolso 100% en Paseo (el backend ya lo
    // restringe así) — se oculta para Hospedaje/Guardería para no confundir
    // con una opción que ahí ya no da el reembolso garantizado.
    final visibleReasons = serviceType == 'PASEO'
        ? _cancellationReasonLabels
        : (Map<String, String>.from(_cancellationReasonLabels)..remove('CLIMA'));

    return StatefulBuilder(
      builder: (ctx, setSheetState) => Container(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 40,
        ),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: GardenColors.textHint, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 28),
            GardenClay(size: 72, tint: GardenColors.error.withValues(alpha: 0.1), interactive: false, child: const GardenIcon(GIcon.cancelado, size: GIconSize.xl, color: GardenColors.error)),
            const SizedBox(height: 20),
            Text(
              'Cancelar reserva',
              style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              '¿Cuál es el motivo? Esta acción no se puede deshacer.',
              style: TextStyle(color: subtextColor, fontSize: 15, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: visibleReasons.entries.map((entry) {
                final isSelected = selectedReasonCode == entry.key;
                return ChoiceChip(
                  label: Text(entry.value),
                  selected: isSelected,
                  selectedColor: GardenColors.primary,
                  backgroundColor: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
                  labelStyle: TextStyle(color: isSelected ? Colors.white : textColor, fontSize: 13),
                  onSelected: (_) => setSheetState(() => selectedReasonCode = entry.key),
                );
              }).toList(),
            ),
            if (selectedReasonCode == 'OTRO') ...[
              const SizedBox(height: 16),
              TextField(
                controller: detailController,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Cuéntanos brevemente qué pasó',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (_) => setSheetState(() {}),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: GardenColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: (selectedReasonCode == null ||
                        (selectedReasonCode == 'OTRO' && detailController.text.trim().isEmpty))
                    ? null
                    : () => Navigator.pop(ctx, {
                          'reasonCode': selectedReasonCode!,
                          'reasonDetail': detailController.text.trim(),
                        }),
                child: const Text('Sí, cancelar reserva', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'No, mantener reserva',
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Una sola forma de calificar: la encuesta del resumen del servicio
  /// (service_execution_screen.dart), que ya maneja la disputa si es < 3 y la
  /// propina si es ≥ 3. Al volver se recarga la lista.
  Future<void> _showRatingDialog(String bookingId) async {
    await context.push('/service/$bookingId', extra: {'role': 'CLIENT', 'token': _clientToken});
    if (mounted) _loadBookings();
  }

  /// Calificación < 3 → el pago queda retenido y el dueño cuenta qué pasó.
  Future<void> _openQualityClaim(String bookingId) async {
    await context.push('/dispute/$bookingId', extra: {'role': 'CLIENT'});
    if (mounted) _loadBookings();
  }

  /// Horas para calificar o reclamar tras el servicio (setting público
  /// autoReleasePaymentHoras). Pasado el plazo, el pago se libera solo.
  int _autoReleaseHoras = 24;

  /// Horas que tiene el cuidador para aceptar; si no responde, el backend
  /// cancela y devuelve todo a la billetera (caregiver-accept-expiry.job.ts).
  int _acceptWindowHoras = 3;

  Future<void> _loadAutoReleaseHoras() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/settings'));
      final d = (jsonDecode(res.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>?;
      final h = (d?['autoReleasePaymentHoras'] as num?)?.toInt();
      final w = (d?['caregiverAcceptWindowHoras'] as num?)?.toInt();
      if (!mounted) return;
      setState(() {
        if (h != null && h > 0) _autoReleaseHoras = h;
        if (w != null && w > 0) _acceptWindowHoras = w;
      });
    } catch (_) {
      // Sin red: se queda el default del backend (24 h).
    }
  }

  /// Hasta cuándo puede calificar/reclamar, o null si no aplica.
  DateTime? _rateDeadline(Map<String, dynamic> b) {
    final ended = DateTime.tryParse(b['serviceEndedAt'] as String? ?? '');
    return ended?.add(Duration(hours: _autoReleaseHoras)).toLocal();
  }

  static String _deadlineLabel(DateTime d) {
    final now = DateTime.now();
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = d.year == tomorrow.year && d.month == tomorrow.month && d.day == tomorrow.day;
    final day = sameDay ? 'hoy' : isTomorrow ? 'mañana' : 'el ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return '$day a las $hh:$mm';
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _buildBookingCard(Map<String, dynamic> booking, bool isDark) {
    final status = booking['status'] as String;
    final serviceType = booking['serviceType'] as String? ?? '';
    final isPaseo = serviceType == 'PASEO';
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final isHighlighted = booking['id'] == _highlightBookingId;

    // Texto, color e icono del estado salen de BookingStory: la misma reserva
    // se cuenta igual acá, en el inicio, en el chat y en las notificaciones.
    final storyCtx = BookingStoryContext.fromBooking(booking);
    final story = BookingStory.of(status, storyCtx);
    final svc = storyCtx.service;
    final statusColor = StoryColors.of(story.tone, isDark: isDark, service: svc).ink;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.xl),
        border: Border.all(
          color: isHighlighted ? GardenColors.success : borderColor,
          width: isHighlighted ? 2 : 1,
        ),
        boxShadow: isHighlighted
            ? [BoxShadow(color: GardenColors.success.withValues(alpha: 0.3), blurRadius: 16, spreadRadius: 1)]
            : GardenShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GardenRadius.xl),
        child: Column(
          children: [
            // Status strip
            Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [statusColor, statusColor.withValues(alpha: 0.5)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GardenPetAvatar(
                    name: storyCtx.pet,
                    size: 48,
                    tone: story.tone,
                    service: svc,
                    caregiverImageUrl: booking['caregiverPhoto'] as String?,
                    caregiverName: booking['caregiverName'] as String?,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GardenStatusPill(story, service: svc, dense: true),
                        const SizedBox(height: 4),
                        Text(
                          story.ownerHeadline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GardenText.bodyMedium.copyWith(
                              color: textColor, fontWeight: FontWeight.w700, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  if (status == 'SLOT_CONFLICT')
                    GardenButton(
                      label: 'Elegir nueva hora',
                      height: 36,
                      color: GardenColors.error,
                      onPressed: () async {
                        await context.push(
                          '/slot-conflict/${booking['id']}',
                          extra: {
                            'serviceType': booking['serviceType'] ?? 'PASEO',
                            'caregiverId': booking['caregiverId'] ?? '',
                          },
                        );
                        if (mounted) _loadBookings();
                      },
                    ),
                  if (status == 'PENDING_PAYMENT')
                    GardenButton(
                      label: _hasActiveQr(booking) ? 'Ver QR' : 'Pagar',
                      height: 36,
                      width: _hasActiveQr(booking) ? 90 : 80,
                      onPressed: () async {
                        await context.push('/payment/${booking['id']}');
                        if (mounted) _loadBookings();
                      },
                    ),
                  if (status == 'CANCELLED' && booking['cancellationSource'] == 'NO_SHOW')
                    Builder(builder: (context) {
                      final disputeStatus = booking['disputeStatus'] as String?;

                      // El cuidador ya reportó este no-show primero y está
                      // esperando la versión del cliente — mostrar el flujo
                      // de "Responder", no el de "Reclamar" desde cero.
                      // Outline, no relleno — misma familia visual que
                      // "Solicitar cancelación" en el lado del cuidador:
                      // acción seria pero sin gritar.
                      if (disputeStatus == 'PENDING_CLIENT') {
                        return GardenButton(
                          label: 'Responder',
                          height: 36,
                          color: GardenColors.error,
                          outline: true,
                          onPressed: () async {
                            await context.push(
                              '/dispute/${booking['id']}',
                              extra: {'role': 'CLIENT', 'isNoShowDispute': true},
                            );
                            if (mounted) _loadBookings();
                          },
                        );
                      }

                      // Estados informativos: solo texto pequeño de bajo
                      // contraste, sin fondo de color ni banner — el cliente
                      // ya reportó y está esperando al cuidador (sin esto, el
                      // botón "Reclamar" seguiría apareciendo indefinidamente
                      // en cada apertura de la app).
                      if (disputeStatus == 'PENDING_CAREGIVER') {
                        return Text('Esperando respuesta del cuidador',
                            style: TextStyle(color: subtextColor, fontSize: 11.5, fontWeight: FontWeight.w500));
                      }

                      if (disputeStatus == 'PENDING_AI') {
                        return Text('Evaluando tu reclamo...',
                            style: TextStyle(color: subtextColor, fontSize: 11.5, fontWeight: FontWeight.w500));
                      }

                      if (disputeStatus == 'RESOLVED') {
                        return GardenButton(
                          label: 'Reclamo resuelto',
                          height: 36,
                          outline: true,
                          onPressed: () async {
                            await context.push(
                              '/dispute/${booking['id']}',
                              extra: {'role': 'CLIENT', 'isNoShowDispute': true},
                            );
                            if (mounted) _loadBookings();
                          },
                        );
                      }

                      // Sin disputa todavía — flujo original: "Reclamar",
                      // con el mismo límite de 24h que valida el backend
                      // (mostrar el botón solo mientras el reclamo todavía
                      // puede enviarse, en vez de dejar que el cliente lo
                      // intente y recién ahí se entere de que el plazo cerró).
                      final cancelledAtRaw = booking['cancelledAt'] as String?;
                      final cancelledAt = cancelledAtRaw != null ? DateTime.tryParse(cancelledAtRaw) : null;
                      final hoursSince = cancelledAt != null
                          ? DateTime.now().toUtc().difference(cancelledAt.toUtc()).inMinutes / 60.0
                          : double.infinity;
                      if (hoursSince > 24) {
                        return Text('Plazo de reclamo cerrado',
                            style: TextStyle(color: subtextColor, fontSize: 11.5, fontWeight: FontWeight.w500));
                      }
                      return GardenButton(
                        label: 'Reclamar',
                        height: 36,
                        color: GardenColors.error,
                        outline: true,
                        onPressed: () async {
                          await context.push(
                            '/dispute/${booking['id']}',
                            extra: {'role': 'CLIENT', 'isNoShowDispute': true},
                          );
                          if (mounted) _loadBookings();
                        },
                      );
                    }),
                ],
              ),
            ),
            Divider(height: 1, color: borderColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  // Qué, cuándo y cuánto en una sola fila. Antes: el nombre de
                  // la mascota repetido (ya está en el titular), la fecha en
                  // otra columna y el total en una caja aparte.
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: (svc ?? GardenService.paseo).soft(isDark),
                          borderRadius: BorderRadius.circular(GardenRadius.md),
                        ),
                        child: GardenIcon(GIcon.forService(svc ?? GardenService.paseo),
                            size: GIconSize.md, state: GIconState.active),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(bookingServiceLine(booking),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13.5)),
                            Text(
                              _capitalize(paymentWhenLabel({...booking, 'duration': null}) ?? '—'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: subtextColor, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GardenAmount(
                        double.tryParse(booking['totalAmount']?.toString() ?? ''),
                        size: 19,
                        color: textColor,
                        animate: false,
                      ),
                    ],
                  ),
                Builder(builder: (_) {
                  final exts = (booking['serviceEvents'] as List<dynamic>? ?? [])
                      .where((e) => e['type'] == 'EXTENSION_CONFIRMED')
                      .toList();
                  if (exts.isEmpty) return const SizedBox();
                  final String summaryText;
                  final GIcon summaryIcon;
                  final String sectionLabel;
                  if (isPaseo) {
                    final totalMins = exts.fold<int>(0,
                        (s, e) => s + ((e['additionalMinutes'] as num?)?.toInt() ?? 0));
                    summaryText = '+$totalMins min · ${exts.length} ${exts.length == 1 ? "extensión" : "extensiones"}';
                    summaryIcon = GIcon.alarma;
                    sectionLabel = 'Tiempo ampliado';
                  } else {
                    final totalDays = exts.fold<int>(0,
                        (s, e) => s + ((e['additionalDays'] as num?)?.toInt() ?? 0));
                    summaryText = '+$totalDays noche${totalDays == 1 ? '' : 's'} · ${exts.length} ${exts.length == 1 ? "extensión" : "extensiones"}';
                    summaryIcon = GIcon.modoOscuro;
                    sectionLabel = 'Noches añadidas';
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: GardenColors.primary.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(GardenRadius.md),
                        border: Border.all(
                            color: GardenColors.primary.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        children: [
                          GardenIcon(summaryIcon, size: GIconSize.xs, color: subtextColor),
                          const SizedBox(width: 7),
                          Text(sectionLabel,
                              style: TextStyle(
                                  color: subtextColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                          const Spacer(),
                          Text(
                            summaryText,
                            style: TextStyle(
                                color: textColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (status == 'PENDING_MG') ...[
                  const SizedBox(height: 12),
                  Builder(builder: (_) {
                    final mg = booking['meetAndGreet'] as Map<String, dynamic>?;
                    final proposedDateStr = mg?['proposedDate'] as String?;
                    DateTime? proposedDate;
                    String dateLabel = 'Fecha pendiente';
                    String meetingPoint = mg?['meetingPoint'] as String? ?? '';
                    if (proposedDateStr != null) {
                      try {
                        proposedDate = DateTime.parse(proposedDateStr).toLocal();
                        const months = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
                        const days = ['lun','mar','mié','jue','vie','sáb','dom'];
                        final h = proposedDate.hour.toString().padLeft(2,'0');
                        final m = proposedDate.minute.toString().padLeft(2,'0');
                        dateLabel = '${days[proposedDate.weekday-1]} ${proposedDate.day} ${months[proposedDate.month-1]} · $h:$m';
                      } catch (_) {}
                    }
                    final mgPassed = proposedDate != null && DateTime.now().isAfter(proposedDate);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: StoryColors.of(StoryTone.info, isDark: isDark).ink.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: StoryColors.of(StoryTone.info, isDark: isDark).ink.withValues(alpha: 0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                GardenIcon(GIcon.meetGreet, size: GIconSize.sm, state: GIconState.active,
                                    color: StoryColors.of(StoryTone.info, isDark: isDark).ink),
                                const SizedBox(width: 8),
                                Text('Meet & Greet programado',
                                    style: TextStyle(color: StoryColors.of(StoryTone.info, isDark: isDark).ink,
                                        fontSize: 13, fontWeight: FontWeight.w700)),
                              ]),
                              const SizedBox(height: 6),
                              Row(children: [
                                GardenIcon(GIcon.reloj, size: GIconSize.xs, color: subtextColor),
                                const SizedBox(width: 5),
                                Text(dateLabel, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
                              ]),
                              if (meetingPoint.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(children: [
                                  GardenIcon(GIcon.ubicacion, size: GIconSize.xs, color: subtextColor),
                                  const SizedBox(width: 5),
                                  Expanded(child: Text(meetingPoint, style: TextStyle(color: subtextColor, fontSize: 11), overflow: TextOverflow.ellipsis)),
                                ]),
                              ],
                              if (!mgPassed) ...[
                                const SizedBox(height: 6),
                                Text('El botón para continuar con el pago se activará después de la fecha del M&G.',
                                    style: TextStyle(color: subtextColor, fontSize: 10)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        GardenButton(
                          label: mgPassed ? 'Continuar con el pago' : 'Esperando fecha M&G',
                          gIcon: mgPassed ? GIcon.avanzar : GIcon.seguridad,
                          color: mgPassed ? GardenColors.primary : subtextColor,
                          onPressed: mgPassed ? () => _proceedToPayment(booking['id'] as String) : null),
                        if (mgPassed) ...[
                          const SizedBox(height: 8),
                          Builder(builder: (_) {
                            final isCancelling = _cancellingIds.contains(booking['id'] as String);
                            return OutlinedButton(
                              onPressed: isCancelling ? null : () => _showMGDecisionSheet(booking['id'] as String),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: GardenColors.error),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                minimumSize: const Size(double.infinity, 40),
                              ),
                              child: isCancelling
                                  ? const SizedBox(
                                      height: 16, width: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.error),
                                    )
                                  : const Text('Cancelar — M&G no salió bien', style: TextStyle(color: GardenColors.error, fontWeight: FontWeight.bold, fontSize: 12)),
                            );
                          }),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              bookingId: booking['id'] as String,
                              otherPersonName: booking['caregiverName'] as String? ?? 'Cuidador',
                              otherPersonPhoto: booking['caregiverPhoto'] as String?,
                              token: _clientToken,
                              role: 'CLIENT',
                              bookingStatus: status,
                            ),
                          )),
                          icon: const GardenIcon(GIcon.chat, size: GIconSize.sm, inheritColor: true),
                          label: const Text('Coordinar M&G por chat', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GardenColors.primary,
                            side: const BorderSide(color: GardenColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            minimumSize: const Size(double.infinity, 40),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
                if (status == 'WAITING_CAREGIVER_APPROVAL' || status == 'CONFIRMED' || status == 'COMPLETED' || status == 'IN_PROGRESS') ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (status == 'CONFIRMED' || status == 'IN_PROGRESS')
                        Expanded(
                          child: GardenButton(
                            label: status == 'CONFIRMED' ? 'Ver reserva' : 'En curso',
                            gIcon: status == 'CONFIRMED' ? GIcon.ver : GIcon.iniciar,
                            height: 40,
                            color: status == 'IN_PROGRESS' ? GardenColors.success : GardenColors.primary,
                            onPressed: () => context.push(
                              '/service/${booking['id']}',
                              extra: {'role': 'CLIENT', 'token': _clientToken},
                            )),
                        ),
                      // Cancel is allowed before service starts — not once IN_PROGRESS
                      if (status == 'WAITING_CAREGIVER_APPROVAL' || status == 'CONFIRMED')
                        const SizedBox(width: 8),
                      if (status == 'WAITING_CAREGIVER_APPROVAL' || status == 'CONFIRMED')
                        Expanded(
                          child: Builder(builder: (_) {
                            final isCancelling = _cancellingIds.contains(booking['id'] as String);
                            return OutlinedButton(
                              onPressed: isCancelling ? null : () => _cancelBooking(booking['id'], serviceType: booking['serviceType'] as String?),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: GardenColors.error),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 0),
                                minimumSize: const Size(0, 40),
                              ),
                              child: isCancelling
                                  ? const SizedBox(
                                      height: 16, width: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.error),
                                    )
                                  : const Text('Cancelar', style: TextStyle(color: GardenColors.error, fontWeight: FontWeight.bold, fontSize: 12)),
                            );
                          }),
                        ),
                      // ownerRated también queda en true cuando el pago se
                      // libera solo (sin nota): ahí ya no se puede calificar.
                      if (status == 'COMPLETED' && booking['ownerRated'] != true && booking['ownerRating'] == null)
                        Expanded(
                          child: GardenButton(
                            label: 'Calificar experiencia',
                            onPressed: () => _showRatingDialog(booking['id']),
                          ),
                        ),
                      // Calificó < 3 pero no llegó a contar qué pasó: el pago
                      // sigue retenido — dejarle retomar el reclamo.
                      if (status == 'COMPLETED' &&
                          booking['payoutStatus'] == 'ON_HOLD' &&
                          booking['disputeStatus'] == null)
                        Expanded(
                          child: GardenButton(
                            label: 'Contar qué pasó',
                            color: GardenColors.error,
                            outline: true,
                            onPressed: () => _openQualityClaim(booking['id'] as String),
                          ),
                        ),
                    ],
                  ),
                  if (status == 'WAITING_CAREGIVER_APPROVAL')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Si ${storyCtx.caregiver} no responde en $_acceptWindowHoras h, cancelamos la reserva '
                        'y te devolvemos todo a tu billetera.',
                        style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
                      ),
                    ),
                  if (status == 'COMPLETED' &&
                      booking['ownerRated'] != true &&
                      booking['ownerRating'] == null &&
                      _rateDeadline(booking) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Tienes hasta ${_deadlineLabel(_rateDeadline(booking)!)} para calificar o reportar un '
                        'problema. Después, el pago se libera al cuidador.',
                        style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
                      ),
                    ),
                  // Report card del servicio — ya existe la vista completa
                  // (fotos, distancia recorrida, resumen) en
                  // service_execution_screen.dart, solo faltaba el link
                  // para llegar a ella una vez COMPLETED.
                  // "Reservar de nuevo" — precarga el mismo cuidador,
                  // servicio Y mascota (la misma que se usó en esta reserva,
                  // no la primera del cliente por defecto) — fecha/hora se
                  // eligen frescas, eso sí, booking_screen.dart las auto-carga
                  // con caregiverId+serviceType+petId.
                  // Resumen y "Reservar de nuevo" lado a lado (antes apilados).
                  if (status == 'COMPLETED') ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(
                            '/service/${booking['id']}',
                            extra: {'role': 'CLIENT', 'token': _clientToken},
                          ),
                          icon: const GardenIcon(GIcon.recibo, size: GIconSize.sm, inheritColor: true),
                          label: const Text('Ver resumen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GardenColors.primary,
                            side: const BorderSide(color: GardenColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            minimumSize: const Size(0, 40),
                          ),
                        ),
                      ),
                      if (booking['caregiverId'] != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => context.push(
                              '/booking/${booking['caregiverId']}',
                              extra: {
                                'serviceType': booking['serviceType'],
                                if (booking['petId'] != null) 'petId': booking['petId'],
                              },
                            ),
                            icon: const GardenIcon(GIcon.repetir, size: GIconSize.sm, inheritColor: true),
                            label: const Text('Reservar de nuevo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: GardenColors.primary,
                              side: const BorderSide(color: GardenColors.primary),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              minimumSize: const Size(0, 40),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ],
                  // Chat y "Ampliar tiempo" lado a lado: antes eran dos botones a
                  // todo el ancho apilados y la tarjeta en curso quedaba altísima.
                  if (status == 'WAITING_CAREGIVER_APPROVAL' || status == 'CONFIRMED' || status == 'IN_PROGRESS') ...[
                    const SizedBox(height: 8),
                    Row(children: [
                    Expanded(child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                bookingId: booking['id'] as String,
                                otherPersonName: booking['caregiverName'] as String? ?? 'Cuidador',
                                otherPersonPhoto: booking['caregiverPhoto'] as String?,
                                token: _clientToken,
                                role: 'CLIENT',
                                bookingStatus: status,
                              ),
                            ));
                            if (mounted) _loadUnreadCounts();
                          },
                          icon: const GardenIcon(GIcon.chat, size: GIconSize.sm, inheritColor: true),
                          label: const Text('Abrir chat', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GardenColors.primary,
                            side: const BorderSide(color: GardenColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            minimumSize: const Size(double.infinity, 40),
                          ),
                        ),
                        if ((_unreadCounts[booking['id']] ?? 0) > 0)
                          Positioned(
                            top: -6,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              constraints: const BoxConstraints(minWidth: 18),
                              decoration: BoxDecoration(
                                color: GardenColors.error,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: Text(
                                '${_unreadCounts[booking['id']]}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                      ],
                    )),
                    // Ampliar tiempo — solo PASEO IN_PROGRESS; navega a la pantalla
                    // del servicio, que cobra la extensión con QR antes de aplicarla.
                    if (status == 'IN_PROGRESS' && isPaseo) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(
                            '/service/${booking['id']}',
                            extra: {'role': 'CLIENT', 'token': _clientToken},
                          ),
                          icon: const GardenIcon(GIcon.alarma, size: GIconSize.sm, inheritColor: true),
                          label: const Text('Más tiempo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GardenColors.primary,
                            side: const BorderSide(color: GardenColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            minimumSize: const Size(0, 40),
                          ),
                        ),
                      ),
                    ],
                    ]),
                  ],
                  // ── BOTÓN REPORTAR ──────────────────────────────────────────
                  // Visible cuando la reserva está CONFIRMED y ya pasó el tiempo de gracia
                  // (paseo: +10 min, otros: +30 min después de la hora programada).
                  if (status == 'CONFIRMED' && _canReport(booking)) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _showReportDialog(booking),
                      icon: const GardenIcon(GIcon.reportar, size: GIconSize.sm, color: GardenColors.error),
                      label: const Text(
                        'Reportar incumplimiento',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: GardenColors.error,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GardenColors.error,
                        side: const BorderSide(color: GardenColors.error),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        minimumSize: const Size(double.infinity, 42),
                      ),
                    ),
                  ],
                  // Meet & Greet para HOSPEDAJE (no aplica a GUARDERIA ni PASEO).
                  // Solo se puede solicitar ANTES de que el cuidador acepte la
                  // reserva (WAITING_CAREGIVER_APPROVAL). Si ya fue aceptado
                  // (mgStatus == ACCEPTED), se sigue mostrando la info aunque
                  // el booking ya haya pasado a CONFIRMED/IN_PROGRESS/etc.
                  if (serviceType == 'HOSPEDAJE' &&
                      (status == 'WAITING_CAREGIVER_APPROVAL' ||
                       (booking['meetAndGreet'] as Map<String, dynamic>?)?['status'] == 'ACCEPTED')) ...[
                    Builder(builder: (_) {
                      final mg = booking['meetAndGreet'] as Map<String, dynamic>?;
                      final mgStatus = mg?['status'] as String?;

                      // ACCEPTED: mostrar solo la info de fecha (sin botón extra)
                      if (mgStatus == 'ACCEPTED') {
                        final confirmedDate = mg?['confirmedDate'] as String?;
                        String dateLabel = 'Meet & Greet confirmado';
                        if (confirmedDate != null) {
                          try {
                            final d = DateTime.parse(confirmedDate).toLocal();
                            const months = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
                            const days = ['lun','mar','mié','jue','vie','sáb','dom'];
                            final h = d.hour.toString().padLeft(2,'0');
                            final m = d.minute.toString().padLeft(2,'0');
                            dateLabel = '${days[d.weekday-1]} ${d.day} ${months[d.month-1]} · $h:$m';
                          } catch (_) {}
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: GardenColors.success.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: GardenColors.success.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const GardenIcon(GIcon.meetGreet, size: GIconSize.sm, state: GIconState.active),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Meet & Greet confirmado',
                                          style: TextStyle(color: GardenColors.success, fontSize: 12, fontWeight: FontWeight.w700)),
                                      Text(dateLabel,
                                          style: TextStyle(color: subtextColor, fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      // No aceptado → botón para coordinar
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => MeetAndGreetScreen(
                              bookingId: booking['id'] as String,
                              role: 'CLIENT',
                            ),
                          )),
                          icon: const GardenIcon(GIcon.meetGreet, size: GIconSize.xs, state: GIconState.active),
                          label: Text(
                            mgStatus == 'PROPOSED' ? 'Meet & Greet · Propuesta pendiente'
                              : mgStatus == 'COMPLETED' ? 'Meet & Greet finalizado'
                              : 'Coordinar Meet & Greet',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GardenColors.primary,
                            side: const BorderSide(color: GardenColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            minimumSize: const Size(double.infinity, 42),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ],
            ),
          ),
          if (BookingHistoryDetail.appliesTo(status))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: BookingHistoryDetail(bookingId: booking['id'] as String, token: _clientToken, isDark: isDark),
            ),
        ],
      ),
    ),
  );
  }

  Widget _buildEmptyState(bool isDark) {
    switch (_selectedFilter) {
      case 'completadas':
        return const GardenEmptyState(
          type: GardenEmptyType.bookings,
          title: 'Sin reservas completadas',
          subtitle: 'Los servicios que hayas finalizado aparecerán aquí.',
        );
      case 'canceladas':
        return const GardenEmptyState(
          type: GardenEmptyType.bookings,
          title: 'Sin reservas canceladas',
          subtitle: 'Aquí verás las reservas que hayas cancelado.',
        );
      case 'activas':
        return GardenEmptyState(
          type: GardenEmptyType.bookings,
          title: 'No tienes reservas activas',
          subtitle: '¿Buscas al cuidador perfecto para tu mascota?',
          ctaLabel: 'Buscar cuidadores',
          onCta: () => context.go('/marketplace'),
        );
      default:
        return GardenEmptyState(
          type: GardenEmptyType.bookings,
          title: 'Sin reservas aún',
          subtitle: '¡Encuentra al cuidador perfecto para tu mascota!',
          ctaLabel: 'Buscar cuidadores',
          onCta: () => context.go('/marketplace'),
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
        final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: surface,
            elevation: 0,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(GardenRadius.sm),
                  ),
                  child: const GardenIcon(GIcon.lista, size: GIconSize.sm, color: GardenColors.primary),
                ),
                const SizedBox(width: 10),
                Text('Mis reservas', style: GardenText.h4.copyWith(color: textColor)),
              ],
            ),
            centerTitle: true,
            actions: [
              NotificationBell(token: _clientToken, baseUrl: _baseUrl),
              IconButton(
                tooltip: 'Paseos recurrentes',
                icon: GardenIcon(GIcon.repetir, size: GIconSize.md, color: subtextColor),
                onPressed: () => context.push('/recurring-bookings'),
              ),
            ],
          ),
          body: LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            return Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isWide ? 860 : double.infinity),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(isWide ? 40 : 16, 12, isWide ? 40 : 16, 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: GardenFilterPills<String>(
                          options: [
                            for (final (v, label) in const [
                              ('todas', 'Todas'),
                              ('activas', 'Ahora'),
                              ('completadas', 'Recuerdos'),
                              ('canceladas', 'Canceladas'),
                            ])
                              (v, _isLoading || v == 'todas' ? label : '$label ${_bookingsFor(v).length}'),
                          ],
                          selected: _selectedFilter,
                          onSelect: (v) {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedFilter = v);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
                      : _filteredBookings.isEmpty
                          ? _buildEmptyState(isDark)
                          : Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: isWide ? 860 : double.infinity),
                                // En curso → Próximas (la más cercana primero) → pasadas
                                // por mes. Antes todo iba mezclado por fecha de creación.
                                child: RefreshIndicator(
                                  color: GardenColors.primary,
                                  onRefresh: _loadBookings,
                                  child: ListView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.fromLTRB(isWide ? 40 : 16, 8, isWide ? 40 : 16, 24),
                                    children: [
                                      for (final g in groupBookings(_filteredBookings)) ...[
                                        GardenListHeader(g.title,
                                            count: g.bookings.length > 1 ? g.bookings.length : null,
                                            emphasis: g.emphasis),
                                        for (final b in g.bookings) _buildBookingCard(b, isDark),
                                        const SizedBox(height: 6),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                ),
              ],
            );
          }),
        );
      },
    );
  }

  // ─── HELPERS: Report ──────────────────────────────────────────────────────

  /// Returns true when the "Reportar" button should be visible for this booking.
  /// Grace period: 10 min for PASEO, 30 min for others.
  bool _canReport(Map<String, dynamic> booking) {
    if (booking.containsKey('serviceReport') && booking['serviceReport'] != null) {
      return false; // already reported
    }
    final serviceType = booking['serviceType'] as String? ?? '';
    final isPaseo = serviceType == 'PASEO';
    final graceMins = isPaseo ? 10 : 30;

    final dateStr = ((booking['walkDate'] ?? booking['startDate']) as String? ?? '').split('T').first;
    if (dateStr.isEmpty) return false;
    try {
      final parts = dateStr.split('-');
      // HOSPEDAJE no almacena startTime — el inicio por defecto es mediodía
      final defaultTime = serviceType == 'HOSPEDAJE' ? '12:00' : '08:00';
      final timeStr = (booking['startTime'] as String? ?? defaultTime);
      final timeParts = timeStr.split(':');
      final defaultHour = serviceType == 'HOSPEDAJE' ? 12 : 8;
      final scheduled = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
        int.tryParse(timeParts[0]) ?? defaultHour,
        int.tryParse(timeParts.length > 1 ? timeParts[1] : '0') ?? 0,
      );
      final reportAvailable = scheduled.add(Duration(minutes: graceMins));
      return DateTime.now().isAfter(reportAvailable);
    } catch (_) {
      return false;
    }
  }

  List<String> _getReportReasons(String serviceType) {
    if (serviceType == 'HOSPEDAJE') {
      return [
        'El cuidador nunca recibió a mi mascota',
        'El cuidador no se comunicó durante el hospedaje',
        'El cuidador no envió actualizaciones ni fotos',
        'El cuidador me cobró un monto extra no acordado',
        'El cuidador canceló el hospedaje sin aviso previo',
        'Mi mascota regresó lastimada o enferma',
        'El cuidador no trató bien a mi mascota',
        'Las condiciones del alojamiento no eran las prometidas',
        'El cuidador entregó la mascota en mal estado',
        'Otro motivo',
      ];
    }
    // PASEO y GUARDERIA comparten los mismos motivos
    return [
      'El cuidador nunca llegó',
      'El cuidador no se comunicó',
      'El cuidador llegó tarde sin avisar',
      'El cuidador me cobró un monto extra',
      'El cuidador canceló sin aviso previo',
      'Me sentí inseguro/a con el servicio',
      'El cuidador no trató bien a mi mascota',
      'El cuidador no cumplió lo acordado',
      'Otro motivo',
    ];
  }

  Future<void> _showReportDialog(Map<String, dynamic> booking) async {
    final isDark = themeNotifier.isDark;
    final serviceType = booking['serviceType'] as String? ?? '';
    final reportReasons = _getReportReasons(serviceType);
    final selectedReasons = <String>{};
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          decoration: BoxDecoration(
            color: isDark ? GardenColors.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: GardenColors.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const GardenIcon(GIcon.reportar, size: GIconSize.md, color: GardenColors.error),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Reportar incumplimiento',
                        style: TextStyle(
                          color: isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Selecciona todos los motivos que apliquen. Se procesará un reembolso a tu billetera Garden automáticamente.',
                  style: TextStyle(
                    color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                ...reportReasons.map((reason) {
                  final selected = selectedReasons.contains(reason);
                  return GestureDetector(
                    onTap: () => setSheetState(() {
                      if (selected) {
                        selectedReasons.remove(reason);
                      } else {
                        selectedReasons.add(reason);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? GardenColors.error.withValues(alpha: 0.08)
                            : (isDark ? GardenColors.darkBackground : GardenColors.lightBackground),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? GardenColors.error : (isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          GardenIcon(selected ? GIcon.casillaMarcada : GIcon.casilla, size: GIconSize.md, state: selected ? GIconState.active : GIconState.idle, color: selected ? GardenColors.error : (isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              reason,
                              style: TextStyle(
                                color: isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary,
                                fontSize: 14,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: GardenColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const GardenIcon(GIcon.info, size: GIconSize.sm, color: GardenColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Primera infracción: advertencia al cuidador. '
                          'Siguientes: multa automática del 20% de la reserva.',
                          style: TextStyle(
                            color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedReasons.isEmpty || isSubmitting
                        ? null
                        : () async {
                            setSheetState(() => isSubmitting = true);
                            try {
                              final response = await http.post(
                                Uri.parse('$_baseUrl/bookings/${booking['id']}/report'),
                                headers: {
                                  'Content-Type': 'application/json',
                                  'Authorization': 'Bearer $_clientToken',
                                },
                                body: jsonEncode({'reasons': selectedReasons.toList()}),
                              );
                              final data = jsonDecode(response.body);
                              if (!mounted) return;
                              Navigator.pop(ctx);
                              if (data['success'] == true) {
                                final refund = (data['data']['refundAmount'] as num?)?.toDouble() ?? 0;
                                final infrType = data['data']['infractionType'] as String? ?? 'WARNING';
                                _showSuccess(
                                  'Reporte enviado',
                                  'Tu reembolso de Bs ${refund.round()} fue procesado a tu billetera. '
                                  '${infrType == 'WARNING' ? 'El cuidador recibió una advertencia.' : 'Se aplicó una multa al cuidador.'}',
                                );
                                await _loadBookings();
                              } else {
                                GardenSnackBar.error(context, data['error']?['message'] ?? 'Error al enviar el reporte');
                              }
                            } catch (e) {
                              Navigator.pop(ctx);
                              GardenSnackBar.error(context, 'Error de conexión. Intenta de nuevo.');
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GardenColors.error,
                      disabledBackgroundColor: GardenColors.error.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: isSubmitting
                        ? const GardenLoadingIndicator(size: 20, color: Colors.white)
                        : const Text('Enviar reporte y solicitar reembolso',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSuccess(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          const GardenIcon(GIcon.confirmado, size: GIconSize.lg, state: GIconState.active, color: GardenColors.success),
          const SizedBox(width: 8),
          Text(title),
        ]),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}

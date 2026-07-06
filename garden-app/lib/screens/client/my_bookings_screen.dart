import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_empty_state.dart';
import '../../widgets/notification_bell.dart';
import '../service/meet_and_greet_screen.dart';
import '../chat/chat_screen.dart';
import '../../services/auth_state.dart';

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

  String? _highlightBookingId;
  Timer? _highlightClearTimer;
  Timer? _refreshTimer;
  Map<String, int> _unreadCounts = {};

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _initData();
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
              const Text('🤝', style: TextStyle(fontSize: 40)),
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

  List<Map<String, dynamic>> get _filteredBookings {
    // Only show PENDING_PAYMENT bookings that have an active QR;
    // hide those without QR or with an expired one.
    final visible = _bookings.where(_shouldShowBooking).toList();
    if (_selectedFilter == 'todas') return visible;
    if (_selectedFilter == 'activas') {
      return visible.where((b) => [
        'PENDING_MG', 'PENDING_PAYMENT', 'PAYMENT_PENDING_APPROVAL',
        'WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS'
      ].contains(b['status'])).toList();
    }
    if (_selectedFilter == 'completadas') {
      return visible.where((b) => b['status'] == 'COMPLETED').toList();
    }
    if (_selectedFilter == 'canceladas') {
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
        if (mounted) context.push('/payment/$bookingId');
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al continuar con el pago');
      }
    } catch (e) {
      if (mounted) GardenSnackBar.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _cancelBooking(String bookingId) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _buildCancelSheet(ctx),
    );
    if (confirmed != true) return;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/$bookingId/cancel'),
        headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
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
    }
  }

  Widget _buildCancelSheet(BuildContext ctx) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Container(
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
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: GardenColors.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: GardenColors.error.withValues(alpha: 0.3), width: 2),
            ),
            child: const Icon(Icons.cancel_outlined, color: GardenColors.error, size: 40),
          ),
          const SizedBox(height: 20),
          Text(
            'Cancelar reserva',
            style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            '¿Estás seguro de que quieres cancelar esta reserva? Esta acción no se puede deshacer.',
            style: TextStyle(color: subtextColor, fontSize: 15, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
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
              onPressed: () => Navigator.pop(ctx, true),
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
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'No, mantener reserva',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _extendPaseo(String bookingId, int additionalMinutes, double pricePerWalk60) async {
    final ratePerMin = pricePerWalk60 / 60;
    final extraAmount = (ratePerMin * additionalMinutes).ceil();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => GardenGlassDialog(
        title: const Text('Confirmar extensión'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ampliar $additionalMinutes minutos adicionales al paseo en curso.'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Costo adicional', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('Bs $extraAmount', style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w900, fontSize: 16)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar pago', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/$bookingId/extend-paseo'),
        headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'additionalMinutes': additionalMinutes}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadBookings();
        if (mounted) GardenSnackBar.success(context, 'Paseo ampliado $additionalMinutes min · Cuidador notificado');
      } else {
        throw Exception(data['error']?['message'] ?? data['message'] ?? 'Error al ampliar');
      }
    } catch (e) {
      if (mounted) GardenSnackBar.error(context, e.toString());
    }
  }

  void _showExtendPaseoSheet(String bookingId, double pricePerWalk60) {
    int selectedMinutes = 15;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = themeNotifier.isDark;
          final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
          final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
          final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

          Widget durationChip(int minutes) {
            final isSelected = selectedMinutes == minutes;
            final cost = ((pricePerWalk60 / 60) * minutes).ceil();
            return Expanded(
              child: GestureDetector(
                onTap: () => setSheetState(() => selectedMinutes = minutes),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected ? GardenColors.primary : (isDark ? GardenColors.darkBackground : GardenColors.lightBackground),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? GardenColors.primary : (isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '+$minutes min',
                        style: TextStyle(
                          color: isSelected ? Colors.white : textColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Bs $cost',
                        style: TextStyle(
                          color: isSelected ? Colors.white70 : subtextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Container(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Ampliar tiempo del paseo', style: GardenText.h4.copyWith(color: textColor)),
                const SizedBox(height: 4),
                Text(
                  'Selecciona cuántos minutos adicionales necesitas.',
                  style: GardenText.metadata.copyWith(color: subtextColor),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [15, 30, 60].map(durationChip).toList(),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Costo adicional', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                      Text(
                        'Bs ${((pricePerWalk60 / 60) * selectedMinutes).ceil()}',
                        style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: GardenButton(
                    label: 'Confirmar y pagar',
                    onPressed: () {
                      Navigator.pop(ctx);
                      _extendPaseo(bookingId, selectedMinutes, pricePerWalk60);
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

  void _showRatingDialog(String bookingId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _RatingSheet(
        bookingId: bookingId,
        onSubmitted: () {
          _loadBookings();
          Navigator.pop(context);
        },
        baseUrl: _baseUrl,
        token: _clientToken,
      ),
    );
  }

  Widget _filterPill(String label, String value, bool isDark) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? GardenColors.primary
              : (isDark
                  ? GardenColors.primary.withValues(alpha: 0.10)
                  : GardenColors.lime.withValues(alpha: 0.70)),
          borderRadius: BorderRadius.circular(GardenRadius.full),
          boxShadow: isSelected
              ? [BoxShadow(color: GardenColors.primary.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 3))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : GardenColors.primary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking, bool isDark) {
    final status = booking['status'] as String;
    final serviceType = booking['serviceType'] as String? ?? '';
    final isPaseo = serviceType == 'PASEO';
    final isGuarderia = serviceType == 'GUARDERIA';
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final isHighlighted = booking['id'] == _highlightBookingId;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'PENDING_MG':
        statusColor = const Color(0xFF6C63FF);
        statusText = 'Meet & Greet pendiente';
        statusIcon = Icons.handshake_outlined;
        break;
      case 'SLOT_CONFLICT':
        statusColor = GardenColors.error;
        statusText = '¡Elige nueva hora!';
        statusIcon = Icons.warning_amber_rounded;
        break;
      case 'PENDING_PAYMENT':
        statusColor = GardenColors.warning;
        statusText = 'Pendiente de pago';
        statusIcon = Icons.payment_rounded;
        break;
      case 'PAYMENT_PENDING_APPROVAL':
        statusColor = GardenColors.warning;
        statusText = 'Pago en revisión';
        statusIcon = Icons.schedule_rounded;
        break;
      case 'WAITING_CAREGIVER_APPROVAL':
        statusColor = GardenColors.primary;
        statusText = 'Esperando cuidador';
        statusIcon = Icons.hourglass_top_rounded;
        break;
      case 'CONFIRMED':
        statusColor = GardenColors.success;
        statusText = 'Confirmada';
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      case 'IN_PROGRESS':
        statusColor = GardenColors.accent;
        statusText = 'En curso';
        statusIcon = Icons.play_circle_fill_rounded;
        break;
      case 'COMPLETED':
        statusColor = GardenColors.primary;
        statusText = 'Completada';
        statusIcon = Icons.done_all_rounded;
        break;
      case 'CANCELLED':
      case 'REJECTED_BY_CAREGIVER':
        statusColor = GardenColors.error;
        statusText = status == 'CANCELLED' ? 'Cancelada' : 'Rechazada';
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = subtextColor;
        statusText = status;
        statusIcon = Icons.info_outline_rounded;
    }

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
                  GardenAvatar(
                    imageUrl: booking['caregiverPhoto'],
                    size: 52,
                    initials: (booking['caregiverName'] as String?)?.isNotEmpty == true
                        ? (booking['caregiverName'] as String)[0]
                        : 'C',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking['caregiverName'] ?? 'Cuidador',
                          style: GardenText.h4.copyWith(color: textColor, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(GardenRadius.full),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, color: statusColor, size: 10),
                              const SizedBox(width: 4),
                              Text(
                                statusText,
                                style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (status == 'SLOT_CONFLICT')
                    GardenButton(
                      label: 'Elegir nueva hora',
                      height: 36,
                      color: GardenColors.error,
                      onPressed: () => context.push(
                        '/slot-conflict/${booking['id']}',
                        extra: {
                          'serviceType': booking['serviceType'] ?? 'PASEO',
                          'caregiverId': booking['caregiverId'] ?? '',
                        },
                      ),
                    ),
                  if (status == 'PENDING_PAYMENT')
                    GardenButton(
                      label: _hasActiveQr(booking) ? 'Ver QR' : 'Pagar',
                      height: 36,
                      width: _hasActiveQr(booking) ? 90 : 80,
                      onPressed: () => context.push('/payment/${booking['id']}'),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: borderColor),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: GardenColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(GardenRadius.md),
                        ),
                        child: Icon(
                          isPaseo ? Icons.directions_walk_rounded
                              : isGuarderia ? Icons.cottage_outlined
                              : Icons.home_rounded,
                          color: GardenColors.primary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(booking['petName'] ?? 'Mascota',
                                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                            Text(
                              isPaseo
                                  ? 'Paseo de ${booking['duration']} min'
                                  : isGuarderia
                                      ? 'Guardería ${(booking['duration'] as num? ?? 0) ~/ 60}h'
                                      : 'Hospedaje',
                              style: TextStyle(color: subtextColor, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      // Flexible evita overflow cuando la fecha/texto es largo
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              (isPaseo || isGuarderia)
                                  ? (booking['walkDate'] ?? '').toString().split('T')[0]
                                  : (booking['startDate'] ?? '').toString().split('T')[0],
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              (isPaseo || isGuarderia)
                                  ? (() {
                                      final st = (booking['startTime'] ?? '').toString().trim();
                                      if (st.isNotEmpty) return st;
                                      // fallback: translate slot name
                                      switch ((booking['timeSlot'] ?? '').toString()) {
                                        case 'MANANA': return 'Mañana';
                                        case 'TARDE':  return 'Tarde';
                                        case 'NOCHE':  return 'Noche';
                                        default:       return (booking['timeSlot'] ?? '').toString();
                                      }
                                    })()
                                  : '${booking['totalDays'] ?? 0} noches',
                              style: TextStyle(color: subtextColor, fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: GardenColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(GardenRadius.md),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w500)),
                        Text('Bs ${booking['totalAmount']}',
                            style: GardenText.price.copyWith(fontSize: 17)),
                      ],
                    ),
                  ),
                Builder(builder: (_) {
                  final exts = (booking['serviceEvents'] as List<dynamic>? ?? [])
                      .where((e) => e['type'] == 'EXTENSION_CONFIRMED')
                      .toList();
                  if (exts.isEmpty) return const SizedBox();
                  final String summaryText;
                  final IconData summaryIcon;
                  final String sectionLabel;
                  if (isPaseo) {
                    final totalMins = exts.fold<int>(0,
                        (s, e) => s + ((e['additionalMinutes'] as num?)?.toInt() ?? 0));
                    summaryText = '+$totalMins min · ${exts.length} ${exts.length == 1 ? "extensión" : "extensiones"}';
                    summaryIcon = Icons.add_alarm_rounded;
                    sectionLabel = 'Tiempo ampliado';
                  } else {
                    final totalDays = exts.fold<int>(0,
                        (s, e) => s + ((e['additionalDays'] as num?)?.toInt() ?? 0));
                    summaryText = '+$totalDays noche${totalDays == 1 ? '' : 's'} · ${exts.length} ${exts.length == 1 ? "extensión" : "extensiones"}';
                    summaryIcon = Icons.nightlight_round;
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
                          Icon(summaryIcon, size: 13, color: subtextColor),
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
                            color: const Color(0xFF6C63FF).withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Text('🤝', style: TextStyle(fontSize: 15)),
                                const SizedBox(width: 8),
                                Text('Meet & Greet programado',
                                    style: TextStyle(color: const Color(0xFF6C63FF), fontSize: 13, fontWeight: FontWeight.w700)),
                              ]),
                              const SizedBox(height: 6),
                              Row(children: [
                                Icon(Icons.access_time_rounded, size: 13, color: subtextColor),
                                const SizedBox(width: 5),
                                Text(dateLabel, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
                              ]),
                              if (meetingPoint.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(children: [
                                  Icon(Icons.location_on_outlined, size: 13, color: subtextColor),
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
                          icon: mgPassed ? Icons.arrow_forward_rounded : Icons.lock_clock_outlined,
                          color: mgPassed ? GardenColors.primary : subtextColor,
                          onPressed: mgPassed ? () => _proceedToPayment(booking['id'] as String) : null,
                        ),
                        if (mgPassed) ...[
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => _showMGDecisionSheet(booking['id'] as String),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: GardenColors.error),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              minimumSize: const Size(double.infinity, 40),
                            ),
                            child: const Text('Cancelar — M&G no salió bien', style: TextStyle(color: GardenColors.error, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              bookingId: booking['id'] as String,
                              otherPersonName: booking['caregiverName'] as String? ?? 'Cuidador',
                              token: _clientToken,
                              role: 'CLIENT',
                              bookingStatus: status,
                            ),
                          )),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
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
                            label: status == 'CONFIRMED' ? 'Ver reserva' : '🔴 En curso',
                            icon: status == 'CONFIRMED' ? Icons.visibility_outlined : Icons.play_circle_outline,
                            height: 40,
                            color: status == 'IN_PROGRESS' ? GardenColors.success : GardenColors.primary,
                            onPressed: () => context.push(
                              '/service/${booking['id']}',
                              extra: {'role': 'CLIENT', 'token': _clientToken},
                            ),
                          ),
                        ),
                      // Cancel is allowed before service starts — not once IN_PROGRESS
                      if (status == 'WAITING_CAREGIVER_APPROVAL' || status == 'CONFIRMED')
                        const SizedBox(width: 8),
                      if (status == 'WAITING_CAREGIVER_APPROVAL' || status == 'CONFIRMED')
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _cancelBooking(booking['id']),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: GardenColors.error),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 0),
                              minimumSize: const Size(0, 40),
                            ),
                            child: const Text('Cancelar', style: TextStyle(color: GardenColors.error, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ),
                      if (status == 'COMPLETED' && booking['ownerRating'] == null)
                        Expanded(
                          child: GardenButton(
                            label: 'Calificar experiencia',
                            onPressed: () => _showRatingDialog(booking['id']),
                          ),
                        ),
                    ],
                  ),
                  // Chat button — visible for all active statuses
                  if (status == 'WAITING_CAREGIVER_APPROVAL' || status == 'CONFIRMED' || status == 'IN_PROGRESS') ...[
                    const SizedBox(height: 8),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                bookingId: booking['id'] as String,
                                otherPersonName: booking['caregiverName'] as String? ?? 'Cuidador',
                                token: _clientToken,
                                role: 'CLIENT',
                                bookingStatus: status,
                              ),
                            ));
                            if (mounted) _loadUnreadCounts();
                          },
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
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
                    ),
                  ],
                  // Ampliar tiempo — solo PASEO IN_PROGRESS
                  if (status == 'IN_PROGRESS' && isPaseo) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        final price60 = double.tryParse(booking['pricePerUnit']?.toString() ?? '') ?? 0.0;
                        _showExtendPaseoSheet(booking['id'] as String, price60);
                      },
                      icon: const Icon(Icons.add_alarm_rounded, size: 16),
                      label: const Text('Ampliar tiempo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GardenColors.primary,
                        side: const BorderSide(color: GardenColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        minimumSize: const Size(double.infinity, 42),
                      ),
                    ),
                  ],
                  // ── BOTÓN REPORTAR ──────────────────────────────────────────
                  // Visible cuando la reserva está CONFIRMED y ya pasó el tiempo de gracia
                  // (paseo: +10 min, otros: +30 min después de la hora programada).
                  if (status == 'CONFIRMED' && _canReport(booking)) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _showReportDialog(booking),
                      icon: const Icon(Icons.flag_outlined, size: 16, color: GardenColors.error),
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
                  // Meet & Greet para HOSPEDAJE CONFIRMED (no aplica a GUARDERIA ni PASEO)
                  if (status == 'CONFIRMED' && serviceType == 'HOSPEDAJE') ...[
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
                                const Text('🤝', style: TextStyle(fontSize: 16)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Meet & Greet confirmado',
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
                          icon: const Text('🤝', style: TextStyle(fontSize: 14)),
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
        ],
      ),
    ),
  );
  }

  Widget _buildEmptyState(bool isDark) {
    switch (_selectedFilter) {
      case 'completadas':
        return GardenEmptyState(
          type: GardenEmptyType.bookings,
          title: 'Sin reservas completadas',
          subtitle: 'Los servicios que hayas finalizado aparecerán aquí.',
        );
      case 'canceladas':
        return GardenEmptyState(
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
                  child: const Icon(Icons.list_alt_rounded, color: GardenColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Text('Mis reservas', style: GardenText.h4.copyWith(color: textColor)),
              ],
            ),
            centerTitle: true,
            actions: [
              NotificationBell(token: _clientToken, baseUrl: _baseUrl),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: subtextColor, size: 20),
                onPressed: _loadBookings,
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
                        child: Row(
                          children: [
                            _filterPill('Todas', 'todas', isDark),
                            _filterPill('Activas', 'activas', isDark),
                            _filterPill('Completadas', 'completadas', isDark),
                            _filterPill('Canceladas', 'canceladas', isDark),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
                      : _filteredBookings.isEmpty
                          ? _buildEmptyState(isDark)
                          : Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: isWide ? 860 : double.infinity),
                                child: ListView.builder(
                                  padding: EdgeInsets.fromLTRB(isWide ? 40 : 16, 16, isWide ? 40 : 16, 16),
                                  itemCount: _filteredBookings.length,
                                  itemBuilder: (context, index) => _buildBookingCard(_filteredBookings[index], isDark),
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
                      child: const Icon(Icons.flag_outlined, color: GardenColors.error, size: 20),
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
                          Icon(
                            selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                            color: selected ? GardenColors.error : (isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
                            size: 20,
                          ),
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
                      const Icon(Icons.info_outline_rounded, color: GardenColors.warning, size: 16),
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
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
          const Icon(Icons.check_circle_rounded, color: GardenColors.success),
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

class _RatingSheet extends StatefulWidget {
  final String bookingId;
  final VoidCallback onSubmitted;
  final String baseUrl;
  final String token;

  const _RatingSheet({
    required this.bookingId,
    required this.onSubmitted,
    required this.baseUrl,
    required this.token,
  });

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  int _rating = 0;
  bool _isSubmitting = false;
  final TextEditingController _commentController = TextEditingController();

  Future<void> _submitRating() async {
    if (_rating == 0) return;
    setState(() => _isSubmitting = true);
    try {
      final response = await http.post(
        Uri.parse('${widget.baseUrl}/bookings/${widget.bookingId}/confirm-receipt'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'rating': _rating,
          if (_commentController.text.trim().isNotEmpty) 'comment': _commentController.text.trim(),
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        if (!mounted) return;
        widget.onSubmitted(); // Esto cierra el ModalBottom y recarga _loadBookings() en la pantalla principal
        
        if (_rating < 3) {
          context.push(
            '/dispute/${widget.bookingId}',
            extra: {'role': 'CLIENT'},
          );
        } else {
          GardenSnackBar.success(context, '¡Gracias por tu calificación!');
        }
      }
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GlassBox(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: subtextColor.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text(
                'Califica tu experiencia',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textColor),
              ),
              const SizedBox(height: 12),
              Text(
                'Tu opinión ayuda a otros dueños de mascotas a encontrar a los mejores cuidadores.',
                textAlign: TextAlign.center,
                style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starIndex = index + 1;
                  return GestureDetector(
                    onTap: () => setState(() => _rating = starIndex),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        starIndex <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: starIndex <= _rating ? GardenColors.star : subtextColor.withValues(alpha: 0.2),
                        size: 48,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _commentController,
                maxLines: 3,
                style: TextStyle(color: textColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Escribe una reseña (Opcional)',
                  hintStyle: TextStyle(color: subtextColor),
                  filled: true,
                  fillColor: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              GardenButton(
                label: 'Enviar calificación',
                loading: _isSubmitting,
                onPressed: _rating > 0 ? _submitRating : null,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

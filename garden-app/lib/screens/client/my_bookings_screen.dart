import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/notification_bell.dart';
import '../service/meet_and_greet_screen.dart';
import '../chat/chat_screen.dart';

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

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    String token = prefs.getString('access_token') ?? '';
    debugPrint('MY_BOOKINGS: Loaded access_token: ${token.length > 20 ? token.substring(0, 20) : token}...');
    if (token.isEmpty) {
      token = const String.fromEnvironment('TEST_JWT', defaultValue: '');
      debugPrint('MY_BOOKINGS: Using TEST_JWT: ${token.length > 20 ? token.substring(0, 20) : token}...');
    }
    setState(() => _clientToken = token);
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('MY_BOOKINGS: Fetching /bookings/my with token: ${_clientToken.length > 20 ? _clientToken.substring(0, 20) : _clientToken}...');
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/my'),
        headers: {'Authorization': 'Bearer $_clientToken'},
      );
      debugPrint('MY_BOOKINGS: Response ${response.statusCode}: ${response.body}');
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _bookings = (data['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('MY_BOOKINGS ERROR: $e');
      // silencioso
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredBookings {
    if (_selectedFilter == 'todas') return _bookings;
    if (_selectedFilter == 'activas') {
      return _bookings.where((b) => [
        'PENDING_PAYMENT', 'PAYMENT_PENDING_APPROVAL',
        'WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS'
      ].contains(b['status'])).toList();
    }
    if (_selectedFilter == 'completadas') {
      return _bookings.where((b) => b['status'] == 'COMPLETED').toList();
    }
    if (_selectedFilter == 'canceladas') {
      return _bookings.where((b) => ['CANCELLED', 'REJECTED_BY_CAREGIVER'].contains(b['status'])).toList();
    }
    return _bookings;
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reserva cancelada'), backgroundColor: Colors.orange),
          );
        }
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
            decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 28),
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.red.withOpacity(0.3), width: 2),
            ),
            child: const Icon(Icons.cancel_outlined, color: Colors.red, size: 40),
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
                backgroundColor: Colors.red,
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
                color: GardenColors.primary.withOpacity(0.1),
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Paseo ampliado $additionalMinutes min · Cuidador notificado'),
              backgroundColor: GardenColors.success,
            ),
          );
        }
      } else {
        throw Exception(data['error']?['message'] ?? data['message'] ?? 'Error al ampliar');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
        );
      }
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
                    color: GardenColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GardenColors.primary.withOpacity(0.2)),
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
    final isPaseo = booking['serviceType'] == 'PASEO';
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
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

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.xl),
        border: Border.all(color: borderColor),
        boxShadow: GardenShadows.card,
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
                    initials: (booking['caregiverName'] as String? ?? 'C')[0],
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
                  if (status == 'PENDING_PAYMENT')
                    GardenButton(
                      label: 'Pagar',
                      height: 36,
                      width: 80,
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
                        child: Icon(isPaseo ? Icons.directions_walk_rounded : Icons.home_rounded,
                            color: GardenColors.primary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(booking['petName'] ?? 'Mascota',
                                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                            Text(isPaseo ? 'Paseo de ${booking['duration']} min' : 'Hospedaje',
                                style: TextStyle(color: subtextColor, fontSize: 12)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            isPaseo ? booking['walkDate'] ?? '' : '${booking['startDate']}',
                            style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          Text(
                            isPaseo ? (booking['timeSlot'] ?? '') : '${booking['totalDays']} noches',
                            style: TextStyle(color: subtextColor, fontSize: 11),
                          ),
                        ],
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
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 0),
                              minimumSize: const Size(0, 40),
                            ),
                            child: const Text('Cancelar', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
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
                  // Meet & Greet para HOSPEDAJE CONFIRMED
                  if (status == 'CONFIRMED' && !isPaseo) ...[
                    const SizedBox(height: 10),
                    Builder(builder: (_) {
                      final mg = booking['meetAndGreet'] as Map<String, dynamic>?;
                      final mgStatus = mg?['status'] as String?;
                      final isAccepted = mgStatus == 'ACCEPTED';

                      if (isAccepted) {
                        // M&G confirmado → ir directo al chat con banner de fecha
                        final confirmedDate = mg?['confirmedDate'] as String?;
                        String note = 'Meet & Greet confirmado';
                        if (confirmedDate != null) {
                          try {
                            final d = DateTime.parse(confirmedDate).toLocal();
                            const months = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
                            const days = ['lun','mar','mié','jue','vie','sáb','dom'];
                            final h = d.hour.toString().padLeft(2,'0');
                            final m = d.minute.toString().padLeft(2,'0');
                            note = 'Meet & Greet · ${days[d.weekday-1]} ${d.day} ${months[d.month-1]} · $h:$m';
                          } catch (_) {}
                        }
                        return OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              bookingId: booking['id'] as String,
                              otherPersonName: 'Cuidador',
                              token: _clientToken,
                              meetAndGreetNote: note,
                            ),
                          )),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                          label: const Text('Chat · Meet & Greet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GardenColors.success,
                            side: const BorderSide(color: GardenColors.success),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            minimumSize: const Size(double.infinity, 42),
                          ),
                        );
                      }

                      // M&G no aceptado aún → ir a pantalla Meet & Greet
                      return OutlinedButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => MeetAndGreetScreen(
                            bookingId: booking['id'] as String,
                            role: 'CLIENT',
                          ),
                        )),
                        icon: const Text('🤝', style: TextStyle(fontSize: 14)),
                        label: Text(
                          mgStatus == 'PROPOSED' ? '🤝 Meet & Greet · Propuesta pendiente'
                            : mgStatus == 'COMPLETED' ? '🤝 Meet & Greet finalizado'
                            : '🤝 Coordinar Meet & Greet',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: GardenColors.primary,
                          side: const BorderSide(color: GardenColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          minimumSize: const Size(double.infinity, 42),
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
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [GardenColors.lime, GardenColors.lime.withValues(alpha: 0.4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.calendar_today_outlined, size: 44, color: GardenColors.primary),
            ),
            const SizedBox(height: 24),
            Text('Sin reservas aún', style: GardenText.h4.copyWith(color: textColor)),
            const SizedBox(height: 8),
            Text(
              '¡Encuentra al cuidador perfecto para tu mascota!',
              style: GardenText.bodyMedium.copyWith(color: subtextColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 220,
              child: GardenButton(
                label: 'Buscar cuidadores',
                icon: Icons.search_rounded,
                onPressed: () => context.go('/marketplace'),
              ),
            ),
          ],
        ),
      ),
    );
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
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
                    : _filteredBookings.isEmpty
                        ? _buildEmptyState(isDark)
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredBookings.length,
                            itemBuilder: (context, index) => _buildBookingCard(_filteredBookings[index], isDark),
                          ),
              ),
            ],
          ),
        );
      },
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('¡Gracias por tu calificación!'), backgroundColor: GardenColors.success),
          );
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
              Container(width: 40, height: 4, decoration: BoxDecoration(color: subtextColor.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
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
                        color: starIndex <= _rating ? GardenColors.star : subtextColor.withOpacity(0.2),
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

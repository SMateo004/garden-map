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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => GardenGlassDialog(
        title: const Text('Cancelar reserva'),
        content: const Text('¿Estás seguro? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reserva cancelada'), backgroundColor: Colors.orange),
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
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? GardenColors.primary : (isDark ? GardenColors.darkSurface : GardenColors.lightSurface),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? GardenColors.primary : (isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
          ),
          boxShadow: isSelected ? [BoxShadow(color: GardenColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : subtextColor,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
    IconData? statusIcon;

    switch (status) {
      case 'PENDING_PAYMENT':
        statusColor = Colors.orange;
        statusText = 'Pendiente de pago';
        break;
      case 'PAYMENT_PENDING_APPROVAL':
        statusColor = Colors.orange;
        statusText = 'Pago en revisión';
        break;
      case 'WAITING_CAREGIVER_APPROVAL':
        statusColor = GardenColors.primary;
        statusText = 'Esperando cuidador';
        break;
      case 'CONFIRMED':
        statusColor = Colors.green;
        statusText = 'Confirmada';
        break;
      case 'IN_PROGRESS':
        statusColor = GardenColors.primary;
        statusText = 'En curso';
        statusIcon = Icons.play_arrow_rounded;
        break;
      case 'COMPLETED':
        statusColor = Colors.grey;
        statusText = 'Completada';
        break;
      case 'CANCELLED':
      case 'REJECTED_BY_CAREGIVER':
        statusColor = Colors.red;
        statusText = status == 'CANCELLED' ? 'Cancelada' : 'Rechazada';
        break;
      default:
        statusColor = subtextColor;
        statusText = status;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GardenAvatar(
                  imageUrl: booking['caregiverPhoto'],
                  size: 48,
                  initials: (booking['caregiverName'] as String? ?? 'C')[0],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking['caregiverName'] ?? 'Cuidador',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textColor),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(statusIcon ?? Icons.circle, color: statusColor, size: 8),
                          const SizedBox(width: 6),
                          Text(
                            statusText,
                            style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: GardenColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                          child: Icon(isPaseo ? Icons.pets : Icons.home_rounded, color: GardenColors.primary, size: 16),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(booking['petName'] ?? 'Mascota', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
                            Text(isPaseo ? 'Paseo de ${booking['duration']} min' : 'Hospedaje', style: TextStyle(color: subtextColor, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isPaseo ? booking['walkDate'] ?? '' : '${booking['startDate']} - ${booking['endDate']}',
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
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total pagado', style: TextStyle(color: subtextColor, fontSize: 12)),
                    Text('Bs ${booking['totalAmount']}', style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w900, fontSize: 18)),
                  ],
                ),
                if (status == 'CONFIRMED' || status == 'COMPLETED' || status == 'IN_PROGRESS') ...[
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
                      if (status == 'CONFIRMED' || status == 'IN_PROGRESS')
                        const SizedBox(width: 12),
                      if (status == 'CONFIRMED' || status == 'IN_PROGRESS')
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
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: GardenColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.calendar_today_outlined, size: 48, color: GardenColors.primary),
          ),
          const SizedBox(height: 24),
          Text(
            'Todavía no tienes reservas',
            style: TextStyle(color: isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '¡Tus mascotas te agradecerán un descanso!',
            style: TextStyle(color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary, fontSize: 14),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 200,
            child: GardenButton(
              label: 'Buscar cuidadores',
              onPressed: () => context.go('/marketplace'),
            ),
          ),
        ],
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

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: surface,
            elevation: 0,
            title: Text('Mis reservas', style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 18)),
            centerTitle: true,
            actions: [
              NotificationBell(
                token: _clientToken,
                baseUrl: _baseUrl,
              ),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: textColor),
                onPressed: _loadBookings,
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                color: surface,
                padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16, top: 4),
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
                        color: starIndex <= _rating ? const Color(0xFFFFB800) : subtextColor.withOpacity(0.2),
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

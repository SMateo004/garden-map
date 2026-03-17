import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({Key? key}) : super(key: key);

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;
  String _clientToken = '';
  String _selectedFilter = 'todas'; // 'todas', 'activas', 'completadas', 'canceladas'

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    String token = prefs.getString('access_token') ?? '';
    if (token.isEmpty) {
      token = const String.fromEnvironment('TEST_JWT', defaultValue: '');
    }
    setState(() => _clientToken = token);
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/my'),
        headers: {'Authorization': 'Bearer $_clientToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _bookings = (data['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
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
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceColor,
        title: const Text('Cancelar reserva', style: TextStyle(color: Colors.white)),
        content: const Text('¿Estás seguro? Esta acción no se puede deshacer.',
          style: TextStyle(color: kTextSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(color: kTextSecondary))),
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

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = value),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryColor : kBackgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? kPrimaryColor : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : kTextSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final status = booking['status'] as String;
    final isPaseo = booking['serviceType'] == 'PASEO';
    
    Color statusColor;
    String statusText;
    IconData? statusIcon;

    switch (status) {
      case 'PENDING_PAYMENT':
        statusColor = kTextSecondary;
        statusText = 'Pendiente de pago';
        break;
      case 'PAYMENT_PENDING_APPROVAL':
        statusColor = Colors.orange;
        statusText = 'Pago en revisión';
        break;
      case 'WAITING_CAREGIVER_APPROVAL':
        statusColor = kPrimaryColor;
        statusText = 'Esperando al cuidador';
        break;
      case 'CONFIRMED':
        statusColor = Colors.green;
        statusText = 'Confirmada';
        break;
      case 'IN_PROGRESS':
        statusColor = Colors.greenAccent;
        statusText = 'En curso';
        statusIcon = Icons.play_arrow;
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
        statusColor = kTextSecondary;
        statusText = status;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: kBackgroundColor,
                backgroundImage: booking['caregiverPhoto'] != null ? NetworkImage(booking['caregiverPhoto']) : null,
                child: booking['caregiverPhoto'] == null ? const Icon(Icons.person, color: kTextSecondary) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  booking['caregiverName'] ?? 'Cuidador',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (statusIcon != null) ...[
                      Icon(statusIcon, color: statusColor, size: 12),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Mascota y servicio
          Row(
            children: [
              const Icon(Icons.pets, size: 14, color: kTextSecondary),
              const SizedBox(width: 4),
              Text(
                booking['petName'] ?? 'Mascota',
                style: const TextStyle(color: kTextSecondary, fontSize: 13),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isPaseo ? kPrimaryColor.withOpacity(0.15) : Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isPaseo ? 'PASEO' : 'HOSPEDAJE',
                  style: TextStyle(
                    color: isPaseo ? kPrimaryColor : Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Fecha y hora
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 14, color: kTextSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isPaseo 
                    ? '${booking['walkDate']} • ${booking['timeSlot'] == 'MANANA' ? 'Mañana' : booking['timeSlot'] == 'TARDE' ? 'Tarde' : 'Noche'} (${booking['duration']} min)'
                    : '${booking['startDate']} al ${booking['endDate']} • ${booking['totalDays']} noches',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Footer: Precio y Acciones
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Bs ${booking['totalAmount']}',
                style: const TextStyle(color: kPrimaryColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  if (status == 'PENDING_PAYMENT')
                    OutlinedButton(
                      onPressed: () => context.push('/payment/${booking['id']}'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kPrimaryColor),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('Pagar ahora', style: TextStyle(color: kPrimaryColor, fontSize: 12)),
                    ),
                  if (status == 'CONFIRMED' || status == 'IN_PROGRESS')
                    OutlinedButton(
                      onPressed: () => _cancelBooking(booking['id']),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('Cancelar', style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  if (status == 'COMPLETED' && booking['rating'] == null)
                    OutlinedButton(
                      onPressed: () => _showRatingDialog(booking['id']),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kPrimaryColor),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('Calificar', style: TextStyle(color: kPrimaryColor, fontSize: 12)),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('Mis reservas'),
        backgroundColor: kSurfaceColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBookings,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtros
          Container(
            color: kSurfaceColor,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('Todas', 'todas'),
                  _buildFilterChip('Activas', 'activas'),
                  _buildFilterChip('Completadas', 'completadas'),
                  _buildFilterChip('Canceladas', 'canceladas'),
                ],
              ),
            ),
          ),
          // Lista
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: kPrimaryColor))
                : _filteredBookings.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_today, size: 64, color: kTextSecondary.withOpacity(0.5)),
                            const SizedBox(height: 16),
                            Text(
                              'No tienes reservas en esta categoría',
                              style: TextStyle(color: kTextSecondary.withOpacity(0.8)),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredBookings.length,
                        itemBuilder: (context, index) => _buildBookingCard(_filteredBookings[index]),
                      ),
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
        body: jsonEncode({'rating': _rating}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        widget.onSubmitted();
      }
    } catch (e) {
      // ignore
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Califica tu experiencia',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          const Text(
            'Tu opinión ayuda a otros dueños de mascotas a encontrar a los mejores cuidadores.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kTextSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starIndex = index + 1;
              return GestureDetector(
                onTap: () => setState(() => _rating = starIndex),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.star,
                    color: starIndex <= _rating ? const Color(0xFFFFD700) : kTextSecondary.withOpacity(0.3),
                    size: 44,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _rating > 0 && !_isSubmitting ? _submitRating : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Enviar calificación', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

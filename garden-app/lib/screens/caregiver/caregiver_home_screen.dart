import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';

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

  static const String _devToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJmNmRmZmYzMS1lYTFhLTQ4MzktYmZkOC1kMWY4OTgwNDQxMjAiLCJyb2xlIjoiQ0FSRUdJVkVSIiwiaWQiOiJmNmRmZmYzMS1lYTFhLTQ4MzktYmZkOC1kMWY4OTgwNDQxMjAiLCJpYXQiOjE3NzM2ODU4NjQsImV4cCI6MTc3NjI3Nzg2NH0.I9cvXI16qEgG55S6FTHeieDLqPjhCQewLKvN0xXgddw';

  int _selectedTab = 0; // 0: Inicio, 1: Disponibilidad, 2: Reservas
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  // Calendario e interactividad
  DateTime _calendarMonth = DateTime.now();
  DateTime? _selectedDay;
  Map<String, String> _dayStatus = {}; // 'available', 'blocked', 'partial', 'booked'

  @override
  void initState() {
    super.initState();
    _initData();
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
        _loadAvailability(),
        _loadBookings(),
      ]);
      _computeDayStatuses();
    } catch (e) {
      // silencioso
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
      
      // Verificar overrides
      final overrides = _availability?['dates'] as Map<String, dynamic>? ?? {};
      if (overrides.containsKey(dateStr)) {
        final override = overrides[dateStr];
        if (override['isAvailable'] == false) {
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

  Widget _buildHome() {
    final pendingCount = _bookings.where((b) => b['status'] == 'WAITING_CAREGIVER_APPROVAL').length;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.7)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '¡Bienvenido, Sai Mateo!',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Tu perfil está activo y recibiendo reservas',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.pets, color: Colors.white, size: 40),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildMetricCard('Total Reservas', _bookings.length.toString()),
              const SizedBox(width: 16),
              _buildMetricCard('Pendientes', pendingCount.toString()),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: kSurfaceColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.calendar_month, color: kPrimaryColor),
            label: const Text('Gestionar disponibilidad'),
            onPressed: () => setState(() => _selectedTab = 1),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurfaceColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kPrimaryColor)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: kTextSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailability() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Horarios por defecto', 
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          _buildDefaultScheduleBlocks(),
          const SizedBox(height: 24),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _legendItem(Colors.green.shade700, 'Disponible'),
                const SizedBox(width: 16),
                _legendItem(Colors.red.shade700, 'Bloqueado'),
                const SizedBox(width: 16),
                _legendItem(Colors.orange, 'Parcial'),
                const SizedBox(width: 16),
                _legendItem(kPrimaryColor, 'Reservado'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: () => setState(() => 
                  _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1)),
              ),
              Text(
                _monthName(_calendarMonth),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: () => setState(() => 
                  _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1)),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
              'Este día tiene reservas activas. Mantente atento!',
              style: TextStyle(color: kTextSecondary, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildDayTimeBlocks(String dateStr) {
    final defaultBlocks = _availability?['defaultSchedule']?['paseoTimeBlocks'] as Map<String, dynamic>? ?? {};
    return Column(
      children: ['morning', 'afternoon', 'night'].map((blockKey) {
        final defaultBlock = defaultBlocks[blockKey] as Map<String, dynamic>?;
        if (defaultBlock == null) return const SizedBox();
        final label = blockKey == 'morning' ? 'Mañana' : blockKey == 'afternoon' ? 'Tarde' : 'Noche';
        final timeRange = '${defaultBlock['start']} - ${defaultBlock['end']}';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: kBackgroundColor, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(timeRange, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Switch(
                value: defaultBlock['enabled'] == true,
                activeColor: kPrimaryColor,
                onChanged: (val) => _toggleTimeBlock(blockKey, val),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDefaultScheduleBlocks() {
    final blocks = _availability?['defaultSchedule']?['paseoTimeBlocks'] as Map<String, dynamic>? ?? {};
    return Column(
      children: ['morning', 'afternoon', 'night'].map((key) {
        final block = blocks[key] as Map<String, dynamic>?;
        if (block == null) return const SizedBox();
        final label = key == 'morning' ? 'Mañana' : key == 'afternoon' ? 'Tarde' : 'Noche';
        final timeRange = '${block['start']} - ${block['end']}';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kSurfaceColor, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(timeRange, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Switch(
                value: block['enabled'] == true,
                activeColor: kPrimaryColor,
                onChanged: (val) => _toggleTimeBlock(key, val),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBookings() {
    if (_bookings.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, color: kTextSecondary, size: 64),
            SizedBox(height: 16),
            Text('No tienes reservas aún', style: TextStyle(color: kTextSecondary)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bookings.length,
      itemBuilder: (context, index) {
        final b = _bookings[index];
        final id = b['id'] as String;
        final status = b['status'] as String;
        final isPending = status == 'WAITING_CAREGIVER_APPROVAL';
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isPending ? kPrimaryColor : Colors.transparent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatusBadge(status),
                  Text('Bs ${b['totalAmount']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimaryColor)),
                ],
              ),
              const SizedBox(height: 12),
              Text('${b['serviceType']} - ${b['petName'] ?? 'Mascota'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 4),
              Text('Fecha: ${b['walkDate'] ?? b['startDate']}', style: const TextStyle(color: kTextSecondary, fontSize: 14)),
              if (isPending) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green), onPressed: () => _respondBooking(id, 'accept'), child: const Text('Aceptar'))),
                    const SizedBox(width: 8),
                    Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700), onPressed: () => _respondBooking(id, 'reject'), child: const Text('Rechazar'))),
                  ],
                ),
              ],
            ],
          ),
        );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('Mi Panel'),
        backgroundColor: kSurfaceColor,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: kPrimaryColor))
        : [
            _buildHome(),
            _buildAvailability(),
            _buildBookings(),
          ][_selectedTab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        onTap: (idx) => setState(() => _selectedTab = idx),
        backgroundColor: kSurfaceColor,
        selectedItemColor: kPrimaryColor,
        unselectedItemColor: kTextSecondary,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Inicio'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Disponibilidad'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Reservas'),
        ],
      ),
    );
  }
}

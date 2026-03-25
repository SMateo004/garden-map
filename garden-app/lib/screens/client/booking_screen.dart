import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class BookingScreen extends StatefulWidget {
  final String caregiverId;
  const BookingScreen({super.key, required this.caregiverId});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  Map<String, dynamic>? _caregiver;
  List<Map<String, dynamic>> _pets = [];
  bool _isLoading = true;
  String _clientToken = '';
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  // Selecciones del usuario
  String? _selectedPetId;
  String? _selectedService; // 'PASEO' o 'HOSPEDAJE'
  DateTime? _selectedDate; // para paseo: fecha del paseo; para hospedaje: fecha inicio
  DateTime? _endDate; // solo hospedaje
  String? _selectedTimeSlot; // 'MANANA', 'TARDE', 'NOCHE'
  final int _selectedDuration = 30; // solo paseo: 30 o 60 minutos
  bool _isSubmitting = false;

  List<Map<String, dynamic>> _availableSlots = [];
  bool _loadingSlots = false;
  String? _selectedStartTime; // hora específica dentro del slot, ej: "09:00"

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    _clientToken = prefs.getString('access_token') ?? '';
    // Fallback if empty for dev
    if (_clientToken.isEmpty) {
      _clientToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJiMWEyMWYzMS01MzRmLTQxMjktODdiNi02MWY1MDA4NDc0ZDIiLCJyb2xlIjoiQ0xJRU5UIiwiaWQiOiJiMWEyMWYzMS01MzRmLTQxMjktODdiNi02MWY1MDA4NDc0ZDIiLCJpYXQiOjE3NzM2NzM5MTgsImV4cCI6MTc3NjI2NTkxOH0.z3UlAvEptacachixvfUTMpgR19RZ536dm-44rLInGmM';
    }

    await Future.wait([_loadCaregiver(), _loadPets()]);
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCaregiver() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/caregivers/${widget.caregiverId}'),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        if (mounted) {
          setState(() {
             _caregiver = data['data'];
             final services = (_caregiver!['services'] as List?)?.cast<String>() ?? [];
             if (services.length == 1) {
               _selectedService = services.first;
             }
          });
        }
      }
    } catch (e) {
      // silencioso
    }
  }

  Future<void> _loadPets() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/client/pets'),
        headers: {'Authorization': 'Bearer $_clientToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        if (mounted) {
          setState(() => _pets = (data['data'] as List).cast<Map<String, dynamic>>());
          if (_pets.isNotEmpty) {
            _selectedPetId = _pets.first['id'];
          } else {
             WidgetsBinding.instance.addPostFrameCallback((_) {
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('Primero agrega una mascota en tu perfil')),
               );
             });
          }
        }
      }
    } catch (e) {
      // silencioso
    }
  }

  Future<void> _loadAvailableSlots(DateTime date) async {
    setState(() {
      _loadingSlots = true;
      _selectedTimeSlot = null;
      _selectedStartTime = null;
      _availableSlots = [];
    });
    try {
      final dateStr = date.toIso8601String().split('T')[0];
      
      final uri = Uri.parse(
        '$_baseUrl/caregivers/${widget.caregiverId}/availability'
      ).replace(queryParameters: {
        'date': dateStr,
        'service': 'PASEO',
      });
      
      final response = await http.get(uri);
      final body = jsonDecode(response.body);
      
      List<Map<String, dynamic>> slots = [];

      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is Map) {
          final paseos = data['paseos'];
          if (paseos is Map && paseos[dateStr] != null) {
            slots = (paseos[dateStr] as List).cast<Map<String, dynamic>>();
          }
          if (slots.isEmpty && data['availableSlots'] != null) {
            slots = (data['availableSlots'] as List).cast<Map<String, dynamic>>();
          }
        }
      } else if (body is List) {
        slots = body.cast<Map<String, dynamic>>();
      }

      final enabledSlots = slots.where((s) => s['enabled'] == true).toList();
      setState(() => _availableSlots = enabledSlots);
      
    } catch (e) {
      debugPrint('ERROR slots: $e');
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _createBooking() async {
    if (_selectedPetId == null) {
      _showError('Selecciona una mascota');
      return;
    }
    if (_selectedService == null) {
      _showError('Selecciona un tipo de servicio');
      return;
    }
    if (_selectedDate == null) {
      _showError('Selecciona una fecha');
      return;
    }
    if (_selectedService == 'PASEO' && _selectedTimeSlot == null) {
      _showError('Selecciona un horario');
      return;
    }
    if (_selectedService == 'PASEO' && _selectedStartTime == null) {
      _showError('Selecciona una hora de inicio');
      return;
    }
    if (_selectedService == 'HOSPEDAJE' && _endDate == null) {
      _showError('Selecciona la fecha de salida');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final Map<String, dynamic> body;
      if (_selectedService == 'PASEO') {
        body = {
          'serviceType': 'PASEO',
          'caregiverId': widget.caregiverId,
          'petId': _selectedPetId,
          'walkDate': _selectedDate!.toIso8601String().split('T')[0],
          'timeSlot': _selectedTimeSlot,
          'duration': _selectedDuration,
          if (_selectedStartTime != null) 'startTime': _selectedStartTime,
        };
      } else {
        final totalDays = _endDate!.difference(_selectedDate!).inDays;
        body = {
          'serviceType': 'HOSPEDAJE',
          'caregiverId': widget.caregiverId,
          'petId': _selectedPetId,
          'startDate': _selectedDate!.toIso8601String().split('T')[0],
          'endDate': _endDate!.toIso8601String().split('T')[0],
          'totalDays': totalDays > 0 ? totalDays : 1,
        };
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/bookings'),
        headers: {
          'Authorization': 'Bearer $_clientToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 && data['success'] == true) {
        final bookingId = data['data']['id'];
        if (!mounted) return;
        context.push('/payment/$bookingId');
      } else {
        if (data['errors'] != null) {
          final errors = (data['errors'] as List)
              .map((e) => e['message'] as String)
              .join(', ');
          throw Exception(errors);
        }
        throw Exception(data['error']?['message'] ?? data['message'] ?? 'Error al crear reserva');
      }
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: GardenColors.error),
    );
  }

  String formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  double? _calculatePrice() {
     if (_caregiver == null || _selectedService == null) return null;
     if (_selectedService == 'PASEO') {
         if (_selectedDuration == 30) {
             return (_caregiver!['pricePerWalk30'] as num?)?.toDouble();
         } else {
             return (_caregiver!['pricePerWalk60'] as num?)?.toDouble();
         }
     } else if (_selectedService == 'HOSPEDAJE') {
         if (_selectedDate != null && _endDate != null) {
             int days = _endDate!.difference(_selectedDate!).inDays;
             if (days <= 0) days = 1;
             final pricePerDay = (_caregiver!['pricePerDay'] as num?)?.toDouble() ?? 0.0;
             return pricePerDay * days;
         }
     }
     return null;
  }

  Widget _buildCaregiverHeader() {
    if (_caregiver == null) return const SizedBox();
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
      ),
      child: Row(
        children: [
          GardenAvatar(
            imageUrl: _caregiver!['profilePicture'] as String?,
            size: 56,
            initials: '${(_caregiver!['firstName'] as String? ?? 'C')[0]}${(_caregiver!['lastName'] as String? ?? '')[0]}',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_caregiver!['firstName']} ${_caregiver!['lastName']}',
                  style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                Row(children: [
                  const Icon(Icons.star_rounded, color: GardenColors.star, size: 14),
                  const SizedBox(width: 4),
                  Text((_caregiver!['rating'] as num? ?? 0).toStringAsFixed(1),
                    style: TextStyle(color: subtextColor, fontSize: 13)),
                ]),
              ],
            ),
          ),
          // Precio
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _caregiver!['pricePerWalk30'] != null
                  ? 'Bs ${_caregiver!['pricePerWalk30']}'
                  : _caregiver!['pricePerDay'] != null
                    ? 'Bs ${_caregiver!['pricePerDay']}'
                    : 'Consultar',
                style: const TextStyle(color: GardenColors.primary, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              Text(
                _caregiver!['pricePerWalk30'] != null ? 'por paseo' : 'por noche',
                style: TextStyle(color: subtextColor, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      final isDark = themeNotifier.isDark;
      final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
      final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
      final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
      final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
      final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;

      if (_isLoading) {
        return Scaffold(
          backgroundColor: bg,
          body: const Center(child: CircularProgressIndicator(color: GardenColors.primary)),
        );
      }

      if (_caregiver == null) {
        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(title: const Text('Reservar'), backgroundColor: surface),
          body: const Center(child: Text('No se pudo cargar la información del cuidador')),
        );
      }

    final services = (_caregiver!['services'] as List?)?.cast<String>() ?? [];
    double? calculatedPrice = _calculatePrice();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Reservar'),
        backgroundColor: surface,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info Cuidador
                _buildCaregiverHeader(),
                const SizedBox(height: 24),
                
                // Selección de Mascota
                Text('Tu mascota', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                if (_pets.isEmpty)
                  GardenButton(
                    label: 'Agregar mascota',
                    outline: true,
                    onPressed: () => context.push('/my-pets'),
                  )
                else
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pets.length,
                      itemBuilder: (context, index) {
                        final pet = _pets[index];
                        final isSelected = _selectedPetId == pet['id'];
                        return GestureDetector(
                          onTap: () => setState(() => _selectedPetId = pet['id']),
                          child: Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? GardenColors.primary.withOpacity(0.12) : surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? GardenColors.primary : borderColor,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                GardenAvatar(
                                  imageUrl: pet['photoUrl'],
                                  size: 40,
                                  initials: pet['name']?[0] ?? 'P',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  pet['name'] ?? '',
                                  style: TextStyle(
                                    color: isSelected ? GardenColors.primary : textColor,
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                
                const SizedBox(height: 24),
                Divider(color: borderColor),
                const SizedBox(height: 24),

                // Tipo de Servicio
                Text('Tipo de servicio', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (services.contains('PASEO'))
                      Expanded(
                        child: _ServiceCard(
                          title: 'Paseo',
                          emoji: '🦮',
                          price: 'Bs ${_caregiver!['pricePerWalk30'] ?? '—'}',
                          isSelected: _selectedService == 'PASEO',
                          onTap: () => setState(() {
                            _selectedService = 'PASEO';
                            _selectedDate = null;
                            _endDate = null;
                            _selectedTimeSlot = null;
                            _selectedStartTime = null;
                          }),
                        ),
                      ),
                    if (services.contains('PASEO') && services.contains('HOSPEDAJE')) const SizedBox(width: 12),
                    if (services.contains('HOSPEDAJE'))
                      Expanded(
                        child: _ServiceCard(
                          title: 'Hospedaje',
                          emoji: '🏠',
                          price: 'Bs ${_caregiver!['pricePerDay'] ?? '—'}',
                          isSelected: _selectedService == 'HOSPEDAJE',
                          onTap: () => setState(() {
                            _selectedService = 'HOSPEDAJE';
                            _selectedDate = null;
                            _endDate = null;
                            _selectedTimeSlot = null;
                            _selectedStartTime = null;
                          }),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 24),
                Divider(color: borderColor),
                const SizedBox(height: 24),

                // Selección de Fecha / Hora
                if (_selectedService == 'PASEO') ...[
                  Text('¿Cuándo?', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ListTile(
                    tileColor: surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: borderColor)),
                    leading: const Icon(Icons.calendar_today, color: GardenColors.primary),
                    title: Text(
                      _selectedDate == null ? 'Seleccionar fecha' : formatDate(_selectedDate!),
                      style: TextStyle(color: textColor),
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(hours: 2)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                      );
                      if (date != null) {
                        setState(() => _selectedDate = date);
                        await _loadAvailableSlots(date);
                      }
                    },
                  ),
                  if (_loadingSlots)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(color: GardenColors.primary)),
                    ),
                  if (_availableSlots.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Horario', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ..._availableSlots.map((slot) {
                      final slotName = slot['slot'] as String;
                      final label = slotName == 'MANANA' ? 'Mañana' : slotName == 'TARDE' ? 'Tarde' : 'Noche';
                      final range = '${slot['start']} - ${slot['end']}';
                      final isSelected = _selectedTimeSlot == slotName;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => setState(() {
                                _selectedTimeSlot = slotName;
                                _selectedStartTime = null;
                              }),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                    color: GardenColors.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Text(range, style: TextStyle(color: subtextColor, fontSize: 12)),
                                ],
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(height: 12),
                              _buildTimeChips(slot),
                            ],
                          ],
                        ),
                      );
                    }),
                    const Text(
                      '* 30 min de descanso incluidos después del servicio',
                      style: TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ] else if (_selectedService == 'HOSPEDAJE') ...[
                  Text('Fechas', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          tileColor: surface,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: borderColor)),
                          title: const Text('Llegada', style: TextStyle(fontSize: 12, color: GardenColors.primary)),
                          subtitle: Text(_selectedDate == null ? '---' : formatDate(_selectedDate!), style: TextStyle(color: textColor)),
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 90)),
                            );
                            if (date != null) {
                              setState(() {
                                _selectedDate = date;
                                if (_endDate != null && _endDate!.isBefore(_selectedDate!)) _endDate = null;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ListTile(
                          tileColor: surface,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: borderColor)),
                          title: const Text('Salida', style: TextStyle(fontSize: 12, color: GardenColors.primary)),
                          subtitle: Text(_endDate == null ? '---' : formatDate(_endDate!), style: TextStyle(color: textColor)),
                          onTap: () async {
                            if (_selectedDate == null) return _showError('Selecciona primero la llegada');
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate!.add(const Duration(days: 1)),
                              firstDate: _selectedDate!.add(const Duration(days: 1)),
                              lastDate: DateTime.now().add(const Duration(days: 90)),
                            );
                            if (date != null) setState(() => _endDate = date);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_selectedDate != null && _endDate != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '${_endDate!.difference(_selectedDate!).inDays} noches',
                      style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],

                const SizedBox(height: 32),
                
                // Resumen Final
                if (calculatedPrice != null && _selectedPetId != null)
                  _buildSummary(calculatedPrice),
              ],
            ),
          ),

          // Botón Sticky
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: bg,
                border: Border(top: BorderSide(color: borderColor)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -4))],
              ),
              child: GardenButton(
                label: _isSubmitting ? 'Creando reserva...' : 'Confirmar reserva',
                loading: _isSubmitting,
                onPressed: _createBooking,
              ),
            ),
          )
        ],
      ),
    );
    } catch (e, stack) {
      debugPrint('BUILD ERROR: $e');
      debugPrint('STACK TRACE: $stack');
      return Scaffold(
        backgroundColor: GardenColors.darkBackground,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              const Text('Error:', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              Text('$e', style: const TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(height: 16),
              const Text('Stack:', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              Text('$stack', style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildTimeChips(Map<String, dynamic> slot) {
    final startParts = (slot['start'] as String).split(':');
    final endParts = (slot['end'] as String).split(':');
    final startHour = int.parse(startParts[0]);
    final endHour = int.parse(endParts[0]);
    
    final timeSlots = <String>[];
    for (int h = startHour; h < endHour; h++) {
      for (int m = 0; m < 60; m += 30) {
        final totalMinutes = h * 60 + m + _selectedDuration + 30;
        if (totalMinutes <= endHour * 60) {
          timeSlots.add('${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
        }
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: timeSlots.map((time) {
        final isSelected = _selectedStartTime == time;
        return GestureDetector(
          onTap: () => setState(() => _selectedStartTime = time),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? GardenColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSelected ? GardenColors.primary : GardenColors.darkBorder),
            ),
            child: Text(
              time,
              style: TextStyle(
                color: isSelected ? Colors.white : themeNotifier.isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSummary(double price) {
    if (_selectedPetId == null || _selectedService == null || _selectedDate == null) {
      return const SizedBox();
    }
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final petName = _pets.firstWhere((p) => p['id'] == _selectedPetId)['name'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: GardenColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GardenColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resumen de reserva', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _summaryRow(Icons.pets, 'Mascota', petName),
          _summaryRow(Icons.settings, 'Servicio', _selectedService == 'PASEO' ? 'Paseo' : 'Hospedaje'),
          _summaryRow(Icons.calendar_today, 'Fecha', formatDate(_selectedDate!)),
          if (_selectedService == 'PASEO') _summaryRow(Icons.access_time, 'Hora', _selectedStartTime ?? ''),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
              Text('Bs $price', style: const TextStyle(color: GardenColors.primary, fontSize: 24, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: GardenColors.primary),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: GardenColors.darkTextSecondary, fontSize: 13)),
          Text(value, style: TextStyle(color: themeNotifier.isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final String title;
  final String emoji;
  final String price;
  final bool isSelected;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.title,
    required this.emoji,
    required this.price,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? GardenColors.primary.withOpacity(0.12) : surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? GardenColors.primary : borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(price, style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

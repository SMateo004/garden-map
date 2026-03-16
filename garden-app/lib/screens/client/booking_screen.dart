import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';

class BookingScreen extends StatefulWidget {
  final String caregiverId;
  const BookingScreen({Key? key, required this.caregiverId}) : super(key: key);

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
  int _selectedDuration = 30; // solo paseo: 30 o 60 minutos
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
      
      // Llamar con date Y service para obtener slots específicos
      final uri = Uri.parse(
        '$_baseUrl/caregivers/${widget.caregiverId}/availability'
      ).replace(queryParameters: {
        'date': dateStr,
        'service': 'PASEO',
      });
      
      debugPrint('SLOTS URL: $uri');
      
      final response = await http.get(uri);
      final body = jsonDecode(response.body);
      
      debugPrint('SLOTS body type: ${body.runtimeType}');
      debugPrint('SLOTS raw: ${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}');
      
      List<Map<String, dynamic>> slots = [];

      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is Map) {
          // El endpoint devuelve data.paseos como objeto {fecha: [slots]}
          final paseos = data['paseos'];
          if (paseos is Map && paseos[dateStr] != null) {
            slots = (paseos[dateStr] as List).cast<Map<String, dynamic>>();
          }
          
          // También verificar data.availableSlots como fallback
          if (slots.isEmpty && data['availableSlots'] != null) {
            slots = (data['availableSlots'] as List).cast<Map<String, dynamic>>();
          }
        }
      } else if (body is List) {
        slots = body.cast<Map<String, dynamic>>();
      }

      debugPrint('SLOTS de paseos[$dateStr]: $slots');
      final enabledSlots = slots.where((s) => s['enabled'] == true).toList();
      setState(() => _availableSlots = enabledSlots);
      
    } catch (e, stack) {
      debugPrint('ERROR slots: $e');
      debugPrint('STACK: $stack');
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _createBooking() async {
    // Validaciones
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
          'totalDays': totalDays > 0 ? totalDays : 1, // At least 1 day
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
        // Navegar a la pantalla de pago
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
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _caregiver == null) {
      return const Scaffold(
        backgroundColor: kBackgroundColor,
        body: Center(child: CircularProgressIndicator(color: kPrimaryColor)),
      );
    }

    final services = (_caregiver!['services'] as List?)?.cast<String>() ?? [];
    double? calculatedPrice = _calculatePrice();

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('Crear reserva'),
        backgroundColor: kSurfaceColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sección 1 — Seleccionar mascota
            const Text('¿Para quién es el servicio?', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
            const SizedBox(height: 12),
            if (_pets.isEmpty)
              Container(
                 decoration: BoxDecoration(
                   color: kSurfaceColor,
                   borderRadius: BorderRadius.circular(12),
                 ),
                 padding: const EdgeInsets.all(16),
                 child: Column(
                   children: [
                     const Text('No tienes mascotas registradas', style: TextStyle(color: kTextSecondary)),
                     const SizedBox(height: 8),
                     TextButton(
                       onPressed: () => context.push('/my-pets'),
                       child: const Text('Agregar mascota', style: TextStyle(color: kPrimaryColor)),
                     ),
                   ],
                 ),
              )
            else
              Column(
                children: _pets.map((pet) {
                  final isSelected = _selectedPetId == pet['id'];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedPetId = pet['id']),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected ? kPrimaryColor.withOpacity(0.2) : kSurfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSelected ? kPrimaryColor : Colors.transparent),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: pet['photoUrl'] != null && pet['photoUrl'].toString().isNotEmpty
                                ? Image.network(pet['photoUrl'], width: 40, height: 40, fit: BoxFit.cover)
                                : Container(width: 40, height: 40, color: kBackgroundColor, child: const Icon(Icons.pets, color: kTextSecondary, size: 20)),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(pet['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                              if (pet['breed'] != null) Text(pet['breed'], style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            
            const SizedBox(height: 24),

            // Sección 2 — Seleccionar servicio
            const Text('Tipo de servicio', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
            const SizedBox(height: 12),
            Row(
              children: [
                if (services.contains('PASEO')) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _selectedService = 'PASEO';
                        _selectedDate = null;
                        _endDate = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedService == 'PASEO' ? kPrimaryColor : kSurfaceColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Paseo 🦮',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedService == 'PASEO' ? Colors.white : kTextSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (services.contains('HOSPEDAJE')) const SizedBox(width: 12),
                ],
                if (services.contains('HOSPEDAJE')) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _selectedService = 'HOSPEDAJE';
                        _selectedDate = null;
                        _endDate = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedService == 'HOSPEDAJE' ? kPrimaryColor : kSurfaceColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Hospedaje 🏠',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedService == 'HOSPEDAJE' ? Colors.white : kTextSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 24),

            // Sección 3 — Fechas
            if (_selectedService != null) ...[
               if (_selectedService == 'PASEO') ...[
                  const Text('Fecha del paseo', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 12),
                  ListTile(
                    tileColor: kSurfaceColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.calendar_today, color: kTextSecondary),
                    title: Text(_selectedDate == null ? 'Seleccionar fecha' : formatDate(_selectedDate!), style: const TextStyle(color: Colors.white)),
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
                  const SizedBox(height: 16),
                  if (_loadingSlots)
                    const Center(child: CircularProgressIndicator(color: kPrimaryColor))
                  else if (_availableSlots.isEmpty && _selectedDate != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kSurfaceColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'No hay horarios disponibles para esta fecha',
                        style: TextStyle(color: kTextSecondary),
                      ),
                    )
                  else if (_availableSlots.isNotEmpty) ...[
                    const Text('Horario', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableSlots.map((slot) {
                        final slotName = slot['slot'] as String;
                        final start = slot['start'] as String;
                        final end = slot['end'] as String;
                        final label = slotName == 'MANANA' ? 'Mañana' : slotName == 'TARDE' ? 'Tarde' : 'Noche';
                        final isSelected = _selectedTimeSlot == slotName;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _selectedTimeSlot = slotName;
                            _selectedStartTime = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? kPrimaryColor : kSurfaceColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? kPrimaryColor : Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : kTextSecondary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '$start - $end',
                                  style: TextStyle(
                                    color: isSelected ? Colors.white.withOpacity(0.8) : kTextSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (_selectedTimeSlot != null) ...[
                      const SizedBox(height: 16),
                      const Text('Hora de inicio', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final slot = _availableSlots.firstWhere((s) => s['slot'] == _selectedTimeSlot);
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
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? kPrimaryColor : kSurfaceColor,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected ? kPrimaryColor : Colors.white.withOpacity(0.1),
                                    ),
                                  ),
                                  child: Text(
                                    time,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : kTextSecondary,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '* Incluye 30 min de descanso para el paseador después del servicio',
                        style: TextStyle(color: kTextSecondary.withOpacity(0.7), fontSize: 11),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  const Text('Duración', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                       ChoiceChip(
                         label: const Text('30 min'),
                         selected: _selectedDuration == 30,
                         onSelected: (val) => setState(() => _selectedDuration = 30),
                         selectedColor: kPrimaryColor,
                         backgroundColor: kSurfaceColor,
                         labelStyle: TextStyle(color: _selectedDuration == 30 ? Colors.white : kTextSecondary),
                       ),
                       const SizedBox(width: 8),
                       ChoiceChip(
                         label: const Text('60 min'),
                         selected: _selectedDuration == 60,
                         onSelected: (val) => setState(() => _selectedDuration = 60),
                         selectedColor: kPrimaryColor,
                         backgroundColor: kSurfaceColor,
                         labelStyle: TextStyle(color: _selectedDuration == 60 ? Colors.white : kTextSecondary),
                       ),
                    ],
                  ),
               ] else if (_selectedService == 'HOSPEDAJE') ...[
                  const Text('Fechas de hospedaje', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 12),
                  ListTile(
                    tileColor: kSurfaceColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.calendar_today, color: kTextSecondary),
                    title: Text(_selectedDate == null ? 'Fecha de entrada' : formatDate(_selectedDate!), style: const TextStyle(color: Colors.white)),
                    onTap: () async {
                      final date = await showDatePicker(
                         context: context, 
                         initialDate: DateTime.now().add(const Duration(hours: 2)),
                         firstDate: DateTime.now(), 
                         lastDate: DateTime.now().add(const Duration(days: 60)),
                      );
                      if (date != null) {
                        setState(() {
                         _selectedDate = date;
                         if (_endDate != null && _endDate!.isBefore(_selectedDate!)) {
                           _endDate = null;
                         }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    tileColor: kSurfaceColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.event_available, color: kTextSecondary),
                    title: Text(_endDate == null ? 'Fecha de salida' : formatDate(_endDate!), style: const TextStyle(color: Colors.white)),
                    onTap: () async {
                      if (_selectedDate == null) {
                         _showError('Selecciona primero la fecha de entrada');
                         return;
                      }
                      final date = await showDatePicker(
                         context: context, 
                         initialDate: _selectedDate!.add(const Duration(days: 1)),
                         firstDate: _selectedDate!.add(const Duration(days: 1)), 
                         lastDate: DateTime.now().add(const Duration(days: 90)),
                      );
                      if (date != null) setState(() => _endDate = date);
                    },
                  ),
                  if (_selectedDate != null && _endDate != null) ...[
                     const SizedBox(height: 8),
                     Text(
                       'Total: ${_endDate!.difference(_selectedDate!).inDays > 0 ? _endDate!.difference(_selectedDate!).inDays : 1} noches · Bs ${calculatedPrice ?? 0}',
                       style: const TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 16),
                     ),
                  ]
               ],

               const SizedBox(height: 32),

               // Sección 4 — Resumen y precio
               if ((_selectedService == 'PASEO' && _selectedDate != null && _selectedStartTime != null) || 
                   (_selectedService == 'HOSPEDAJE' && _selectedDate != null && _endDate != null)) 
                 if (_selectedPetId != null)
                   Container(
                     padding: const EdgeInsets.all(16),
                     decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
                     ),
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                          const Text('Resumen', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                          const SizedBox(height: 8),
                          Text('Cuidador: ${_caregiver!['firstName']} ${_caregiver!['lastName']}', style: const TextStyle(color: Colors.white)),
                          Text('Mascota: ${_pets.firstWhere((p) => p['id'] == _selectedPetId)['name']}', style: const TextStyle(color: Colors.white)),
                          Text('Servicio: $_selectedService', style: const TextStyle(color: Colors.white)),
                          if (calculatedPrice != null) ...[
                            const SizedBox(height: 8),
                            Text('Total: Bs $calculatedPrice', style: const TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
                          ]
                       ],
                     ),
                   ),

               const SizedBox(height: 24),

               // Sección 5 — Botón confirmar
               ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    backgroundColor: kPrimaryColor,
                  ),
                  onPressed: _isSubmitting ? null : _createBooking,
                  child: _isSubmitting 
                     ? const CircularProgressIndicator(color: Colors.white)
                     : const Text('Confirmar reserva', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
               ),
            ],
          ],
        ),
      ),
    );
  }
}

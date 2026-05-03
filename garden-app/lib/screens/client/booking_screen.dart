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
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  // Selecciones del usuario
  String? _selectedPetId;
  String? _selectedService; // 'PASEO' o 'HOSPEDAJE'
  DateTime? _selectedDate; // para paseo single: fecha del paseo; para hospedaje: fecha inicio
  DateTime? _endDate; // solo hospedaje
  String? _selectedTimeSlot; // 'MANANA', 'TARDE', 'NOCHE'
  int _selectedDuration = 60; // solo paseo: 60 minutos (walk30 deshabilitado)
  bool _isSubmitting = false;

  // Multi-day paseo
  bool _isMultiDay = false;
  final List<DateTime> _selectedDates = []; // fechas seleccionadas en modo multi-día
  String? _multiDayTimeSlot; // slot compartido para todos los días

  // Meet & Greet opcional
  bool _includeMG = false;
  DateTime? _mgDate;
  TimeOfDay? _mgTime;
  final _mgPlaceCtrl = TextEditingController();
  List<Map<String, dynamic>> _mgLocationSuggestions = [];
  double? _mgSelectedLat;
  double? _mgSelectedLng;

  List<Map<String, dynamic>> _availableSlots = [];
  List<Map<String, dynamic>> _bookedPaseos = []; // reservas activas del cuidador
  bool _loadingSlots = false;
  String? _selectedStartTime; // hora específica dentro del slot, ej: "09:00"

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _mgPlaceCtrl.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    _clientToken = prefs.getString('access_token') ?? '';
    if (_clientToken.isEmpty) {
      if (mounted) context.go('/login');
      return;
    }

    await Future.wait([_loadCaregiver(), _loadPets()]);

    if (mounted) setState(() => _isLoading = false);
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
             // Priorizar PASEO; si no ofrece paseo, elegir el primer servicio disponible
             if (services.contains('PASEO')) {
               _selectedService = 'PASEO';
             } else if (services.isNotEmpty) {
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
          final pets = (data['data'] as List).cast<Map<String, dynamic>>();
          for (final p in pets) {
            debugPrint('PET: ${p['name']} photoUrl=${p['photoUrl']}');
          }
          setState(() => _pets = pets);
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

      List<Map<String, dynamic>> booked = [];
      if (body is Map && body['success'] == true) {
        final d = body['data'];
        if (d is Map && d['bookedPaseos'] is List) {
          booked = (d['bookedPaseos'] as List).cast<Map<String, dynamic>>();
        }
      }

      setState(() {
        _availableSlots = enabledSlots;
        _bookedPaseos = booked;
      });
      
    } catch (e) {
      debugPrint('ERROR slots: $e');
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _searchMGLocations(String query) async {
    if (query.trim().length < 3) { setState(() => _mgLocationSuggestions = []); return; }
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search').replace(queryParameters: {
        'q': query,
        'format': 'json',
        'limit': '5',
        'countrycodes': 'bo',
        'accept-language': 'es',
      });
      final res = await http.get(uri, headers: {'User-Agent': 'GardenApp/1.0'});
      final list = jsonDecode(res.body) as List;
      if (mounted) setState(() => _mgLocationSuggestions = list.cast<Map<String, dynamic>>());
    } catch (_) {}
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
    if (_selectedService == 'PASEO') {
      if (_isMultiDay) {
        if (_selectedDates.isEmpty) {
          _showError('Selecciona al menos un día');
          return;
        }
        if (_multiDayTimeSlot == null) {
          _showError('Selecciona un horario para los paseos');
          return;
        }
      } else {
        if (_selectedTimeSlot == null) {
          _showError('Selecciona un horario');
          return;
        }
        if (_selectedStartTime == null) {
          _showError('Selecciona una hora de inicio');
          return;
        }
      }
    }
    if (_selectedService == 'HOSPEDAJE' && _endDate == null) {
      _showError('Selecciona la fecha de salida');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final Map<String, dynamic> body;
      if (_selectedService == 'PASEO') {
        if (_isMultiDay) {
          // Reserva multi-día
          body = {
            'serviceType': 'PASEO',
            'caregiverId': widget.caregiverId,
            'petId': _selectedPetId,
            'duration': _selectedDuration,
            'walkDays': _selectedDates.map((d) => {
              'date': d.toIso8601String().split('T')[0],
              'timeSlot': _multiDayTimeSlot,
            }).toList(),
          };
        } else {
          body = {
            'serviceType': 'PASEO',
            'caregiverId': widget.caregiverId,
            'petId': _selectedPetId,
            'walkDate': _selectedDate!.toIso8601String().split('T')[0],
            'timeSlot': _selectedTimeSlot,
            'duration': _selectedDuration,
            if (_selectedStartTime != null) 'startTime': _selectedStartTime,
          };
        }
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
        debugPrint('[MG] Booking created: $bookingId, includeMG=$_includeMG');
        // Construir mgData si el cliente quiere M&G
        Map<String, dynamic>? mgData;
        if (_includeMG && _mgDate != null && _mgPlaceCtrl.text.trim().isNotEmpty) {
          final timeStr = _mgTime != null
              ? '${_mgTime!.hour.toString().padLeft(2, '0')}:${_mgTime!.minute.toString().padLeft(2, '0')}'
              : '10:00';
          final dateStr = _mgDate!.toIso8601String().split('T')[0];
          mgData = {
            'modalidad': 'IN_PERSON',
            'proposedDate': '${dateStr}T$timeStr:00',
            'meetingPoint': _mgPlaceCtrl.text.trim(),
            if (_mgSelectedLat != null && _mgSelectedLng != null) ...{
              'meetingPointLat': _mgSelectedLat,
              'meetingPointLng': _mgSelectedLng,
            },
          };
          debugPrint('[MG] mgData built: $mgData');
        }
        context.push('/payment/$bookingId', extra: mgData != null ? {'mgData': mgData} : null);
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
      final price60 = (_caregiver!['pricePerWalk60'] as num?)?.toDouble();
      if (price60 == null) return null;
      final unitPrice = _selectedDuration == 30 ? (price60 / 2).roundToDouble() : price60;
      if (_isMultiDay) {
        final numDays = _selectedDates.length;
        return numDays > 0 ? unitPrice * numDays : null;
      }
      return unitPrice;
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

  /// Verifica si una fecha está en la lista multi-day
  bool _isDateSelected(DateTime date) {
    return _selectedDates.any(
      (d) => d.year == date.year && d.month == date.month && d.day == date.day,
    );
  }

  /// Toggle una fecha en la lista multi-day
  void _toggleDate(DateTime date) {
    setState(() {
      if (_isDateSelected(date)) {
        _selectedDates.removeWhere(
          (d) => d.year == date.year && d.month == date.month && d.day == date.day,
        );
      } else {
        _selectedDates.add(date);
        // ordenar por fecha
        _selectedDates.sort((a, b) => a.compareTo(b));
      }
    });
  }

  Widget _buildDurationChip({
    required int minutes,
    required String price,
    required Color textColor,
    required Color subtextColor,
    required Color borderColor,
    required Color surface,
  }) {
    final isSelected = _selectedDuration == minutes;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedDuration = minutes;
          _selectedTimeSlot = null;
          _selectedStartTime = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? GardenColors.primary : surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? GardenColors.primary : borderColor,
              width: isSelected ? 0 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined,
                      color: isSelected ? Colors.white : GardenColors.primary,
                      size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '$minutes min',
                    style: GardenText.body.copyWith(
                      color: isSelected ? Colors.white : textColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                price,
                style: GardenText.metadata.copyWith(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.9)
                      : GardenColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaregiverHeader() {
    if (_caregiver == null) return const SizedBox();
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? GardenColors.darkSurface : const Color(0xFFEEF3E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.25)),
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
                  style: GardenText.h4.copyWith(color: textColor)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.star_rounded, color: GardenColors.star, size: 14),
                  const SizedBox(width: 4),
                  Text((_caregiver!['rating'] as num? ?? 0).toStringAsFixed(1),
                    style: GardenText.metadata.copyWith(color: subtextColor)),
                ]),
              ],
            ),
          ),
          // Precio dinámico
          Builder(builder: (_) {
            String priceText;
            String priceUnit;
            if (_selectedService == 'PASEO') {
              final p = _caregiver!['pricePerWalk60'];
              priceText = p != null ? 'Bs $p' : '—';
              priceUnit = '1 hora';
            } else if (_selectedService == 'HOSPEDAJE') {
              priceText = _caregiver!['pricePerDay'] != null ? 'Bs ${_caregiver!['pricePerDay']}' : '—';
              priceUnit = 'por noche';
            } else {
              final p60 = _caregiver!['pricePerWalk60'];
              priceText = p60 != null ? 'Bs $p60/hora' : '—';
              priceUnit = 'paseo 1h';
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(priceText,
                    style: const TextStyle(color: GardenColors.primary, fontSize: 17, fontWeight: FontWeight.w800)),
                Text(priceUnit, style: TextStyle(color: subtextColor, fontSize: 11)),
              ],
            );
          }),
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
                Text('Tu mascota', style: GardenText.h4.copyWith(color: textColor)),
                const SizedBox(height: 16),
                if (_pets.isEmpty)
                  GardenButton(
                    label: 'Agregar mascota',
                    outline: true,
                    onPressed: () => context.push('/my-pets'),
                  )
                else
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pets.length,
                      itemBuilder: (context, index) {
                        final pet = _pets[index];
                        final isSelected = _selectedPetId == pet['id'];
                        return GestureDetector(
                          onTap: () => setState(() => _selectedPetId = pet['id']),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 180,
                            margin: const EdgeInsets.only(right: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: isSelected
                                ? BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        GardenColors.primary.withValues(alpha: 0.18),
                                        GardenColors.primary.withValues(alpha: 0.08),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: GardenColors.primary, width: 1.5),
                                  )
                                : BoxDecoration(
                                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.60),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: borderColor, width: 1.0),
                                  ),
                            child: Row(
                              children: [
                                // Foto de la mascota
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 48,
                                    height: 56,
                                    child: () {
                                      final rawUrl = pet['photoUrl'] as String? ?? '';
                                      final url = rawUrl.isNotEmpty ? fixImageUrl(rawUrl) : '';
                                      if (url.isEmpty) return _petPlaceholder(pet, isSelected, textColor);
                                      return Image.network(
                                        url,
                                        width: 48,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _petPlaceholder(pet, isSelected, textColor),
                                        loadingBuilder: (_, child, progress) {
                                          if (progress == null) return child;
                                          return _petPlaceholder(pet, isSelected, textColor);
                                        },
                                      );
                                    }(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Nombre y especie
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        pet['name'] ?? '',
                                        style: TextStyle(
                                          color: isSelected ? GardenColors.primary : textColor,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if ((pet['breed'] ?? '').toString().isNotEmpty)
                                        Text(
                                          pet['breed'] ?? '',
                                          style: TextStyle(
                                            color: isSelected
                                                ? GardenColors.primary.withValues(alpha: 0.7)
                                                : (isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
                                            fontSize: 11,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded, color: GardenColors.primary, size: 16),
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

                // Selección de Fecha / Hora
                if (_selectedService == 'PASEO') ...[
                  // ── Duración ──
                  Text('Duración', style: GardenText.h4.copyWith(color: textColor)),
                  const SizedBox(height: 12),
                  Builder(builder: (_) {
                    final price60 = (_caregiver!['pricePerWalk60'] as num?)?.toDouble();
                    final price30 = price60 != null ? (price60 / 2).round() : null;
                    final ratePerMin = price60 != null ? price60 / 60 : null;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildDurationChip(
                              minutes: 30,
                              price: price30 != null ? 'Bs $price30' : '—',
                              textColor: textColor,
                              subtextColor: subtextColor,
                              borderColor: borderColor,
                              surface: surface,
                            ),
                            const SizedBox(width: 12),
                            _buildDurationChip(
                              minutes: 60,
                              price: price60 != null ? 'Bs ${price60.round()}' : '—',
                              textColor: textColor,
                              subtextColor: subtextColor,
                              borderColor: borderColor,
                              surface: surface,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Nota extensiones de tiempo
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: GardenColors.primary.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: GardenColors.primary.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  color: GardenColors.primary, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Puedes pedir una extensión de 15, 30 o 60 min directamente desde la app una vez iniciado el paseo. El costo se prorratea desde la tarifa de 1 hora${ratePerMin != null ? ' (Bs ${ratePerMin.round()}/min)' : ''}. Sin extensión confirmada, se cobra automáticamente un extra.',
                                  style: GardenText.metadata.copyWith(
                                    color: GardenColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 24),
                  Divider(color: borderColor),
                  const SizedBox(height: 24),

                  // Toggle un día / varios días
                  Row(
                    children: [
                      Text('¿Cuándo?', style: GardenText.h4.copyWith(color: textColor)),
                      const Spacer(),
                      Container(
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildDayModeTab('1 día', !_isMultiDay, () {
                              setState(() {
                                _isMultiDay = false;
                                _selectedDates.clear();
                                _multiDayTimeSlot = null;
                              });
                            }),
                            _buildDayModeTab('Varios días', _isMultiDay, () {
                              setState(() {
                                _isMultiDay = true;
                                _selectedDate = null;
                                _selectedTimeSlot = null;
                                _selectedStartTime = null;
                                _availableSlots = [];
                              });
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (!_isMultiDay) ...[
                    // ── Modo un día: chips de fecha ──
                    SizedBox(
                      height: 72,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: 14,
                        itemBuilder: (_, i) {
                          final date = DateTime.now().add(Duration(days: i + 1));
                          final isSelected = _selectedDate != null &&
                              _selectedDate!.year == date.year &&
                              _selectedDate!.month == date.month &&
                              _selectedDate!.day == date.day;
                          const months = ['ENE','FEB','MAR','ABR','MAY','JUN',
                                          'JUL','AGO','SEP','OCT','NOV','DIC'];
                          final mon = months[date.month - 1];
                          return GestureDetector(
                            onTap: () async {
                              setState(() => _selectedDate = date);
                              await _loadAvailableSlots(date);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(right: 10),
                              width: 58,
                              decoration: BoxDecoration(
                                color: isSelected ? GardenColors.primary : surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: isSelected ? GardenColors.primary : borderColor),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(mon,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white.withValues(alpha: 0.8)
                                            : subtextColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      )),
                                  const SizedBox(height: 4),
                                  Text('${date.day}',
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : textColor,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      )),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (_loadingSlots)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator(color: GardenColors.primary)),
                      ),
                    if (_availableSlots.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('Horario', style: GardenText.h4.copyWith(color: textColor)),
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
                                _buildTimeChips(slot, _selectedDate!),
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
                  ] else ...[
                    // ── Modo varios días: cuadrícula de calendario ──
                    _buildMultiDayCalendar(textColor, subtextColor, borderColor, surface),
                    if (_selectedDates.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('Horario para todos los días',
                          style: GardenText.h4.copyWith(color: textColor)),
                      const SizedBox(height: 4),
                      Text('El mismo horario se aplicará a todos los días seleccionados.',
                          style: TextStyle(color: subtextColor, fontSize: 12)),
                      const SizedBox(height: 12),
                      _buildMultiDaySlotSelector(textColor, subtextColor),
                    ],
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

                const SizedBox(height: 24),
                Divider(color: borderColor),
                const SizedBox(height: 20),

                // ── Meet & Greet opcional ───────────────────────────────
                _buildMeetAndGreetSection(surface, textColor, subtextColor, borderColor),

                const SizedBox(height: 24),

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
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, -4))],
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

  bool _isTimeConflicting(String time, String dateStr) {
    if (_bookedPaseos.isEmpty) return false;
    final parts = time.split(':');
    final newStart = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    final newEnd = newStart + _selectedDuration + 30; // +30 min descanso
    for (final b in _bookedPaseos) {
      if (b['date'] != dateStr) continue;
      final sp = (b['startTime'] as String).split(':');
      final bStart = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final bEnd = bStart + (b['duration'] as int? ?? 30) + 30;
      if (newStart < bEnd && newEnd > bStart) return true;
    }
    return false;
  }

  /// Tab del toggle "1 día / Varios días"
  Widget _buildDayModeTab(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? GardenColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : (themeNotifier.isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  /// Calendario de cuadrícula para seleccionar múltiples días (próximos 30 días)
  Widget _buildMultiDayCalendar(Color textColor, Color subtextColor, Color borderColor, Color surface) {
    final today = DateTime.now();
    final firstDay = today.add(const Duration(days: 1));
    final lastDay = today.add(const Duration(days: 30));

    // Agrupar por semana para mostrar en cuadrícula
    final days = <DateTime>[];
    for (var d = firstDay; !d.isAfter(lastDay); d = d.add(const Duration(days: 1))) {
      days.add(d);
    }

    const dayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    // padding inicial: weekday 1=L..7=D
    final startPad = (firstDay.weekday - 1) % 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedDates.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _selectedDates.map((d) {
                const months = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
                return Chip(
                  label: Text('${d.day} ${months[d.month - 1]}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  backgroundColor: GardenColors.primary,
                  deleteIconColor: Colors.white.withValues(alpha: 0.8),
                  onDeleted: () => _toggleDate(d),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ),
        // Cabecera días de la semana
        Row(
          children: dayLabels.map((l) => Expanded(
            child: Center(
              child: Text(l,
                  style: TextStyle(
                    color: subtextColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          )).toList(),
        ),
        const SizedBox(height: 6),
        // Cuadrícula
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 4,
            childAspectRatio: 1,
          ),
          itemCount: startPad + days.length,
          itemBuilder: (_, i) {
            if (i < startPad) return const SizedBox();
            final date = days[i - startPad];
            final isSelected = _isDateSelected(date);
            return GestureDetector(
              onTap: () => _toggleDate(date),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isSelected ? GardenColors.primary : surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? GardenColors.primary : borderColor,
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      color: isSelected ? Colors.white : textColor,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Toca los días para seleccionar o quitar. Puedes elegir hasta 30 días.',
          style: TextStyle(color: subtextColor, fontSize: 11),
        ),
      ],
    );
  }

  /// Selector de horario compartido para modo multi-día
  Widget _buildMultiDaySlotSelector(Color textColor, Color subtextColor) {
    const slots = [
      {'key': 'MANANA', 'label': 'Mañana', 'icon': '🌤️'},
      {'key': 'TARDE',  'label': 'Tarde',  'icon': '🌇'},
      {'key': 'NOCHE',  'label': 'Noche',  'icon': '🌙'},
    ];
    return Row(
      children: slots.map((s) {
        final isSelected = _multiDayTimeSlot == s['key'];
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _multiDayTimeSlot = s['key']),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isSelected ? GardenColors.primary : (themeNotifier.isDark ? GardenColors.darkSurface : GardenColors.lightSurface),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? GardenColors.primary : (themeNotifier.isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                ),
              ),
              child: Column(
                children: [
                  Text(s['icon']!, style: const TextStyle(fontSize: 20)),
                  const SizedBox(height: 4),
                  Text(
                    s['label']!,
                    style: TextStyle(
                      color: isSelected ? Colors.white : textColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTimeChips(Map<String, dynamic> slot, DateTime date) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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

    // Ocultar horarios que ya están reservados (incluye buffer de descanso)
    final available = timeSlots.where((t) => !_isTimeConflicting(t, dateStr)).toList();

    if (available.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text('No hay horarios disponibles en este bloque',
            style: TextStyle(color: themeNotifier.isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary, fontSize: 12)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: available.map((time) {
        final isSelected = _selectedStartTime == time;
        return GestureDetector(
          onTap: () => setState(() => _selectedStartTime = time),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? GardenColors.primary
                  : themeNotifier.isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : GardenColors.lightSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? GardenColors.primary : (themeNotifier.isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                width: isSelected ? 0 : 1,
              ),
            ),
            child: Text(
              time,
              style: GardenText.metadata.copyWith(
                color: isSelected
                    ? Colors.white
                    : themeNotifier.isDark
                        ? GardenColors.darkTextPrimary
                        : GardenColors.lightTextPrimary,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _petPlaceholder(Map<String, dynamic> pet, bool isSelected, Color textColor) {
    return Container(
      width: 48,
      height: 56,
      decoration: BoxDecoration(
        color: GardenColors.primary.withValues(alpha: isSelected ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          (pet['name'] as String? ?? 'P')[0].toUpperCase(),
          style: TextStyle(
            color: GardenColors.primary,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildMeetAndGreetSection(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🐾', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Meet & Greet', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('Conoce al cuidador antes del servicio', style: TextStyle(color: subtextColor, fontSize: 12)),
                  ],
                ),
              ),
              Switch(
                value: _includeMG,
                onChanged: (v) => setState(() => _includeMG = v),
                activeColor: GardenColors.primary,
              ),
            ],
          ),
          if (_includeMG) ...[
            const SizedBox(height: 16),
            // Date picker
            GestureDetector(
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _mgDate ?? now.add(const Duration(days: 1)),
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 60)),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.dark(primary: GardenColors.primary),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) setState(() => _mgDate = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: GardenColors.primary),
                    const SizedBox(width: 10),
                    Text(
                      _mgDate != null
                          ? '${_mgDate!.day}/${_mgDate!.month}/${_mgDate!.year}'
                          : 'Seleccionar fecha',
                      style: TextStyle(color: _mgDate != null ? textColor : subtextColor, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Time picker
            GestureDetector(
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _mgTime ?? const TimeOfDay(hour: 10, minute: 0),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.dark(primary: GardenColors.primary),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) setState(() => _mgTime = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: GardenColors.primary),
                    const SizedBox(width: 10),
                    Text(
                      _mgTime != null
                          ? '${_mgTime!.hour.toString().padLeft(2, '0')}:${_mgTime!.minute.toString().padLeft(2, '0')}'
                          : 'Seleccionar hora',
                      style: TextStyle(color: _mgTime != null ? textColor : subtextColor, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Meeting point with autocomplete
            TextField(
              controller: _mgPlaceCtrl,
              style: TextStyle(color: textColor, fontSize: 14),
              onChanged: _searchMGLocations,
              decoration: InputDecoration(
                hintText: 'Punto de encuentro',
                hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                prefixIcon: Icon(Icons.location_on, color: GardenColors.primary, size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: GardenColors.primary),
                ),
              ),
            ),
            if (_mgLocationSuggestions.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(12),
                  color: surface,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _mgLocationSuggestions.length,
                  itemBuilder: (_, i) {
                    final s = _mgLocationSuggestions[i];
                    return ListTile(
                      dense: true,
                      title: Text(s['display_name'] ?? '', style: TextStyle(color: textColor, fontSize: 12)),
                      onTap: () {
                        setState(() {
                          _mgPlaceCtrl.text = s['display_name'] ?? '';
                          _mgSelectedLat = double.tryParse(s['lat']?.toString() ?? '');
                          _mgSelectedLng = double.tryParse(s['lon']?.toString() ?? '');
                          _mgLocationSuggestions = [];
                        });
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'El cuidador recibirá esta propuesta automáticamente tras confirmar el pago.',
              style: TextStyle(color: subtextColor, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary(double price) {
    if (_selectedPetId == null || _selectedService == null) return const SizedBox();
    // En modo multi-day, no es necesario _selectedDate
    if (!_isMultiDay && _selectedDate == null) return const SizedBox();
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final petName = _pets.firstWhere((p) => p['id'] == _selectedPetId)['name'];

    // Texto de fecha para el resumen
    String fechaText;
    if (_selectedService == 'PASEO' && _isMultiDay) {
      fechaText = '${_selectedDates.length} día${_selectedDates.length == 1 ? '' : 's'}';
    } else if (_selectedService == 'HOSPEDAJE' && _endDate != null && _selectedDate != null) {
      fechaText = '${formatDate(_selectedDate!)} → ${formatDate(_endDate!)}';
    } else if (_selectedDate != null) {
      fechaText = formatDate(_selectedDate!);
    } else {
      fechaText = '';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: GardenColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resumen de reserva', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _summaryRow(Icons.pets, 'Mascota', petName),
          _summaryRow(Icons.settings, 'Servicio', _selectedService == 'PASEO' ? 'Paseo' : 'Hospedaje'),
          if (_selectedService == 'PASEO')
            _summaryRow(Icons.timer_outlined, 'Duración', '$_selectedDuration min'),
          if (fechaText.isNotEmpty)
            _summaryRow(Icons.calendar_today, _isMultiDay ? 'Días' : 'Fecha', fechaText),
          if (_selectedService == 'PASEO' && _isMultiDay && _multiDayTimeSlot != null)
            _summaryRow(Icons.access_time, 'Horario',
                _multiDayTimeSlot == 'MANANA' ? 'Mañana' : _multiDayTimeSlot == 'TARDE' ? 'Tarde' : 'Noche'),
          if (_selectedService == 'PASEO' && !_isMultiDay && _selectedStartTime != null)
            _summaryRow(Icons.access_time, 'Hora', _selectedStartTime!),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
              Text('Bs ${price.round()}',
                  style: const TextStyle(color: GardenColors.primary, fontSize: 24, fontWeight: FontWeight.w900)),
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

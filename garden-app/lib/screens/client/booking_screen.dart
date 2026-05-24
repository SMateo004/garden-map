import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class BookingScreen extends StatefulWidget {
  final String caregiverId;
  final Map<String, dynamic>? preloadedCaregiver;
  final List<dynamic>? preloadedPets;
  final String? preloadedToken;
  final String? preloadedService; // 'PASEO' | 'HOSPEDAJE' — pre-selected from profile screen

  const BookingScreen({
    super.key,
    required this.caregiverId,
    this.preloadedCaregiver,
    this.preloadedPets,
    this.preloadedToken,
    this.preloadedService,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  Map<String, dynamic>? _caregiver;
  List<Map<String, dynamic>> _pets = [];
  bool _isLoading = true;
  String _clientToken = '';
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  // Selecciones del usuario
  String? _selectedPetId;
  String? _selectedService; // 'PASEO', 'HOSPEDAJE' o 'GUARDERIA'
  DateTime? _selectedDate; // para paseo single / guardería: fecha; para hospedaje: fecha inicio
  DateTime? _endDate; // solo hospedaje
  String? _selectedTimeSlot; // 'MANANA', 'TARDE', 'NOCHE'
  int _selectedDuration = 60; // solo paseo: 60 minutos (walk30 deshabilitado)
  int _guarderiaSelectedDuration = 180; // solo guardería: 180 min por defecto
  bool _isSubmitting = false;

  // Multi-day paseo
  bool _isMultiDay = false;
  final List<DateTime> _selectedDates = []; // fechas seleccionadas en modo multi-día
  String? _multiDayTimeSlot; // slot compartido para todos los días (MANANA/TARDE/NOCHE)
  bool _multiDaySameTime = true; // ¿misma hora para todos?
  String? _multiDaySharedTime; // hora única cuando _multiDaySameTime = true
  Map<String, String> _perDayTimes = {}; // dateStr -> hora cuando _multiDaySameTime = false
  // Datos reales del cuidador para el rango multi-día (1 sola llamada API)
  Map<String, List<Map<String, dynamic>>> _multiDaySlotsByDate = {}; // dateStr -> slots con start/end reales
  Set<String> _blockedDates = {}; // fechas explícitamente bloqueadas por el cuidador
  List<Map<String, dynamic>> _multiDayRangeBookings = []; // reservas activas en el rango
  bool _loadingMultiDayData = false;
  bool _multiDayDataLoaded = false; // true una vez que la llamada API terminó (éxito o error)

  // Meet & Greet opcional
  bool _includeMG = false;
  DateTime? _mgDate;
  TimeOfDay? _mgTime;
  final _mgPlaceCtrl = TextEditingController();
  List<Map<String, dynamic>> _mgLocationSuggestions = [];
  double? _mgSelectedLat;
  double? _mgSelectedLng;
  Timer? _mgSearchDebounce;
  bool _mgTimeExpanded = true;
  bool _mgVirtual = false; // false = Presencial, true = Virtual

  List<Map<String, dynamic>> _availableSlots = [];
  List<Map<String, dynamic>> _bookedPaseos = []; // reservas activas del cuidador
  bool _loadingSlots = false;
  String? _selectedStartTime; // hora específica dentro del slot, ej: "09:00"

  /// Start date of the booking (first selected date or single-day date)
  DateTime? get _bookingStartDate {
    if (_selectedService == 'PASEO' && _isMultiDay && _selectedDates.isNotEmpty) {
      return _selectedDates.reduce((a, b) => a.isBefore(b) ? a : b);
    }
    return _selectedDate;
  }

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _mgSearchDebounce?.cancel();
    _mgPlaceCtrl.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    // Use pre-loaded data if available — renders instantly
    if (widget.preloadedCaregiver != null && widget.preloadedPets != null && widget.preloadedToken != null) {
      _clientToken = widget.preloadedToken!;
      final services = (widget.preloadedCaregiver!['services'] as List?)?.cast<String>() ?? [];
      final pets = widget.preloadedPets!.cast<Map<String, dynamic>>();
      setState(() {
        _caregiver = widget.preloadedCaregiver!;
        _pets = pets;
        _isLoading = false;
        // Respect the service pre-selected from the profile screen, else auto-detect
        if (widget.preloadedService != null && services.contains(widget.preloadedService)) {
          _selectedService = widget.preloadedService;
        } else if (services.contains('PASEO')) {
          _selectedService = 'PASEO';
        } else if (services.contains('GUARDERIA')) {
          _selectedService = 'GUARDERIA';
        } else if (services.isNotEmpty) {
          _selectedService = services.first;
        }
        if (_pets.isNotEmpty) _selectedPetId = _pets.first['id'];
      });
      // Precargar disponibilidad real del cuidador (para filtrar días no disponibles)
      _loadMultiDayData();
      return;
    }

    // Fallback: fetch everything
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
             // Respect pre-selected service from profile screen; fallback to PASEO or first
             if (widget.preloadedService != null && services.contains(widget.preloadedService)) {
               _selectedService = widget.preloadedService;
             } else if (services.contains('PASEO')) {
               _selectedService = 'PASEO';
             } else if (services.contains('GUARDERIA')) {
               _selectedService = 'GUARDERIA';
             } else if (services.isNotEmpty) {
               _selectedService = services.first;
             }
          });
          // Precargar disponibilidad real del cuidador (para filtrar días no disponibles)
          _loadMultiDayData();
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

  void _searchMGLocations(String query) {
    _mgSearchDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _mgLocationSuggestions = []);
      return;
    }
    _mgSearchDebounce = Timer(const Duration(milliseconds: 450), () async {
      final q = query.trim();
      try {
        final uri = Uri.parse('$_baseUrl/places/autocomplete')
            .replace(queryParameters: {'input': q});
        final res = await http.get(uri);
        if (!mounted || _mgPlaceCtrl.text.trim() != q) return;
        final body = jsonDecode(res.body) as Map;
        final predictions = (body['predictions'] as List? ?? []).cast<Map<String, dynamic>>();
        setState(() => _mgLocationSuggestions = predictions);
      } catch (_) {}
    });
  }

  Future<void> _selectMGPlace(Map<String, dynamic> prediction) async {
    final placeId = prediction['place_id'] as String? ?? '';
    final description = prediction['description'] as String? ?? '';
    setState(() {
      _mgPlaceCtrl.text = description;
      _mgLocationSuggestions = [];
      _mgSelectedLat = null;
      _mgSelectedLng = null;
    });
    if (placeId.isEmpty) return;
    try {
      final uri = Uri.parse('$_baseUrl/places/details')
          .replace(queryParameters: {'place_id': placeId});
      final res = await http.get(uri);
      if (!mounted) return;
      final body = jsonDecode(res.body) as Map;
      if (body['status'] == 'OK') {
        final loc = body['result']?['geometry']?['location'];
        if (loc != null) {
          setState(() {
            _mgSelectedLat = (loc['lat'] as num).toDouble();
            _mgSelectedLng = (loc['lng'] as num).toDouble();
          });
        }
      }
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
    // Multi-day PASEO uses _selectedDates, not _selectedDate — skip the single-date check
    final isMultiDayPaseo = _selectedService == 'PASEO' && _isMultiDay;
    if (!isMultiDayPaseo && _selectedDate == null) {
      _showError('Selecciona una fecha');
      return;
    }
    if (_selectedService == 'GUARDERIA') {
      if (_selectedTimeSlot == null) {
        _showError('Selecciona un horario (Mañana o Tarde)');
        return;
      }
      if (_selectedStartTime == null) {
        _showError('Selecciona una hora de inicio');
        return;
      }
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
        if (_multiDaySameTime) {
          if (_multiDaySharedTime == null) {
            _showError('Selecciona una hora para los paseos');
            return;
          }
        } else {
          final missing = _selectedDates.any((d) {
            final ds = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
            return !_perDayTimes.containsKey(ds);
          });
          if (missing) {
            _showError('Selecciona la hora para cada día');
            return;
          }
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
      if (_selectedService == 'GUARDERIA') {
        body = {
          'serviceType': 'GUARDERIA',
          'caregiverId': widget.caregiverId,
          'petId': _selectedPetId,
          'walkDate': _selectedDate!.toIso8601String().split('T')[0],
          'timeSlot': _selectedTimeSlot,
          'duration': _guarderiaSelectedDuration,
          'startTime': _selectedStartTime!,
        };
      } else if (_selectedService == 'PASEO') {
        if (_isMultiDay) {
          // Reserva multi-día
          body = {
            'serviceType': 'PASEO',
            'caregiverId': widget.caregiverId,
            'petId': _selectedPetId,
            'duration': _selectedDuration,
            'walkDays': _selectedDates.map((d) {
              final ds = d.toIso8601String().split('T')[0];
              return {
                'date': ds,
                'timeSlot': _multiDayTimeSlot,
                'startTime': _multiDaySameTime ? _multiDaySharedTime : _perDayTimes[ds],
              };
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

      // If M&G enabled, include mgData in the booking body so backend creates PENDING_MG
      if (_includeMG && _mgDate != null) {
        final timeStr = _mgTime != null
            ? '${_mgTime!.hour.toString().padLeft(2, '0')}:${_mgTime!.minute.toString().padLeft(2, '0')}'
            : '10:00';
        final dateStr = _mgDate!.toIso8601String().split('T')[0];
        body['mgData'] = {
          'modalidad': _mgVirtual ? 'VIRTUAL' : 'IN_PERSON',
          'proposedDate': '${dateStr}T$timeStr:00',
          if (_mgPlaceCtrl.text.trim().isNotEmpty) 'meetingPoint': _mgPlaceCtrl.text.trim(),
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

        if (_includeMG && _mgDate != null) {
          // M&G flow: go to Mis Reservas with highlight — payment comes later
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('highlight_booking_id', bookingId);
          if (mounted) context.go('/my-bookings-tab');
        } else {
          context.push('/payment/$bookingId');
        }
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
    if (_selectedService == 'GUARDERIA') {
      if (_selectedDate == null || _selectedTimeSlot == null) return null;
      final pricePerGuarderia = (_caregiver!['pricePerGuarderia'] as num?)?.toDouble()
          ?? (_caregiver!['pricePerWalk60'] as num?)?.toDouble();
      if (pricePerGuarderia == null || pricePerGuarderia <= 0) return null;
      return pricePerGuarderia * (_guarderiaSelectedDuration / 60);
    } else if (_selectedService == 'PASEO') {
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
        final ds = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        _selectedDates.removeWhere(
          (d) => d.year == date.year && d.month == date.month && d.day == date.day,
        );
        _perDayTimes.remove(ds);
      } else {
        _selectedDates.add(date);
        _selectedDates.sort((a, b) => a.compareTo(b));
      }
      // Resetear hora compartida al cambiar la selección de días
      _multiDaySharedTime = null;
      // Clear M&G date if it's no longer before the earliest selected booking date
      if (_mgDate != null && _selectedDates.isNotEmpty) {
        final earliest = _selectedDates.reduce((a, b) => a.isBefore(b) ? a : b);
        if (!_mgDate!.isBefore(earliest)) _mgDate = null;
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
            } else if (_selectedService == 'GUARDERIA') {
              final pg = _caregiver!['pricePerGuarderia'] ?? _caregiver!['pricePerWalk60'];
              priceText = pg != null ? 'Bs $pg' : '—';
              priceUnit = 'por hora';
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
      body: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        return Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(isWide ? 0 : 20, isWide ? 32 : 20, isWide ? 0 : 20, 120),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isWide ? 860 : double.infinity),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 0),
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
                                    color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFFAF7F2).withValues(alpha: 0.90),
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
                                _selectedDate = null;      // force fresh date pick
                                _selectedDates.clear();
                                _multiDayTimeSlot = null;
                                _bookedPaseos = [];        // clear stale conflict data
                                _availableSlots = [];
                                _selectedTimeSlot = null;
                                _selectedStartTime = null;
                              });
                            }),
                            _buildDayModeTab('Varios días', _isMultiDay, () {
                              setState(() {
                                _isMultiDay = true;
                                _selectedDate = null;
                                _selectedTimeSlot = null;
                                _selectedStartTime = null;
                                _availableSlots = [];
                                _bookedPaseos = [];        // clear stale conflict data
                              });
                              // Datos ya cargados en init; recargar solo si falta
                              if (_multiDaySlotsByDate.isEmpty) _loadMultiDayData();
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (!_isMultiDay) ...[
                    // ── Modo un día: chips de fecha ──
                    if (_loadingMultiDayData)
                      const SizedBox(height: 72, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                    else SizedBox(
                      height: 72,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: 14,
                        // i=1: start from tomorrow (1-day advance booking requirement)
                        itemBuilder: (_, i) {
                          final date = DateTime.now().add(Duration(days: i + 1));
                          final ds = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                          final isSelected = _selectedDate != null &&
                              _selectedDate!.year == date.year &&
                              _selectedDate!.month == date.month &&
                              _selectedDate!.day == date.day;
                          const months = ['ENE','FEB','MAR','ABR','MAY','JUN',
                                          'JUL','AGO','SEP','OCT','NOV','DIC'];
                          final mon = months[date.month - 1];

                          // Verificar disponibilidad real del cuidador ese día
                          // Un día está bloqueado si:
                          //  1. Está en _blockedDates (cuidador lo desactivó explícitamente), O
                          //  2. Está en _multiDaySlotsByDate pero todos sus slots están disabled, O
                          //  3. Los datos ya cargaron (_multiDayDataLoaded) y el día NO aparece en
                          //     _multiDaySlotsByDate → el backend no lo registró como disponible
                          final bool isDayUnavailable = _blockedDates.contains(ds) ||
                              (_multiDaySlotsByDate.containsKey(ds) &&
                               _multiDaySlotsByDate[ds]!.every((s) => s['enabled'] != true)) ||
                              (_multiDayDataLoaded && !_multiDaySlotsByDate.containsKey(ds));

                          return GestureDetector(
                            onTap: isDayUnavailable ? null : () async {
                              setState(() {
                                _selectedDate = date;
                                // Clear M&G date if it's no longer before the booking date
                                if (_mgDate != null && !_mgDate!.isBefore(date)) {
                                  _mgDate = null;
                                }
                              });
                              await _loadAvailableSlots(date);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(right: 10),
                              width: 58,
                              decoration: BoxDecoration(
                                color: isDayUnavailable
                                    ? (themeNotifier.isDark
                                        ? Colors.white.withValues(alpha: 0.04)
                                        : Colors.grey.withValues(alpha: 0.08))
                                    : isSelected
                                        ? GardenColors.primary
                                        : surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDayUnavailable
                                      ? borderColor.withValues(alpha: 0.35)
                                      : isSelected
                                          ? GardenColors.primary
                                          : borderColor,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(mon,
                                      style: TextStyle(
                                        color: isDayUnavailable
                                            ? subtextColor.withValues(alpha: 0.4)
                                            : isSelected
                                                ? Colors.white.withValues(alpha: 0.8)
                                                : subtextColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      )),
                                  const SizedBox(height: 4),
                                  Text('${date.day}',
                                      style: TextStyle(
                                        color: isDayUnavailable
                                            ? subtextColor.withValues(alpha: 0.4)
                                            : isSelected
                                                ? Colors.white
                                                : textColor,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      )),
                                  if (isDayUnavailable)
                                    Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        color: GardenColors.error,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
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
                      Row(
                        children: [
                          Text('Horario', style: GardenText.h4.copyWith(color: textColor)),
                          if (_selectedStartTime != null) ...[
                            const Spacer(),
                            GestureDetector(
                              onTap: () => setState(() {
                                _selectedTimeSlot = null;
                                _selectedStartTime = null;
                              }),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_outlined, size: 16, color: GardenColors.primary),
                                  const SizedBox(width: 4),
                                  Text('Cambiar', style: TextStyle(color: GardenColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_selectedStartTime != null) ...[
                        // Compact summary once time is chosen
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: GardenColors.primary.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time_rounded, color: GardenColors.primary, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                '${_selectedTimeSlot == 'MANANA' ? 'Mañana' : _selectedTimeSlot == 'TARDE' ? 'Tarde' : 'Noche'} · $_selectedStartTime',
                                style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
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
                      ],
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
                      Text('El mismo bloque horario se aplicará a todos los días seleccionados.',
                          style: TextStyle(color: subtextColor, fontSize: 12)),
                      const SizedBox(height: 12),
                      _buildMultiDaySlotSelector(textColor, subtextColor),
                      if (_multiDayTimeSlot != null) ...[
                        const SizedBox(height: 24),
                        _buildMultiDayTimePicker(textColor, subtextColor, borderColor, surface),
                      ],
                    ],
                  ],
                ] else if (_selectedService == 'GUARDERIA') ...[
                  // ── Guardería: duración fija ──
                  Text('Duración', style: GardenText.h4.copyWith(color: textColor)),
                  const SizedBox(height: 12),
                  Builder(builder: (_) {
                    final pricePerGuarderia = (_caregiver!['pricePerGuarderia'] as num?)?.toDouble()
                        ?? (_caregiver!['pricePerWalk60'] as num?)?.toDouble() ?? 0.0;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [180, 240, 360, 480, 600].map((mins) {
                        final isSelected = _guarderiaSelectedDuration == mins;
                        final hours = mins ~/ 60;
                        final price = (pricePerGuarderia * (mins / 60)).round();
                        return GestureDetector(
                          onTap: () => setState(() {
                            _guarderiaSelectedDuration = mins;
                            _selectedDate = null;
                            _selectedTimeSlot = null;
                            _selectedStartTime = null;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                            decoration: BoxDecoration(
                              color: isSelected ? GardenColors.primary : surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isSelected ? GardenColors.primary : borderColor),
                            ),
                            child: Column(
                              children: [
                                Text('${hours}h', style: TextStyle(
                                  color: isSelected ? Colors.white : textColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                )),
                                Text(pricePerGuarderia > 0 ? 'Bs $price' : '—', style: TextStyle(
                                  color: isSelected ? Colors.white.withValues(alpha: 0.85) : subtextColor,
                                  fontSize: 12,
                                )),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  }),
                  const SizedBox(height: 24),
                  Divider(color: borderColor),
                  const SizedBox(height: 24),

                  // ── Guardería: fecha ──
                  Text('Fecha', style: GardenText.h4.copyWith(color: textColor)),
                  const SizedBox(height: 12),
                  if (_loadingMultiDayData)
                    const SizedBox(height: 72, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                  else SizedBox(
                    height: 72,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: 14,
                      itemBuilder: (_, i) {
                        final date = DateTime.now().add(Duration(days: i + 1));
                        final ds = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                        final isSelected = _selectedDate != null &&
                            _selectedDate!.year == date.year &&
                            _selectedDate!.month == date.month &&
                            _selectedDate!.day == date.day;
                        const months = ['ENE','FEB','MAR','ABR','MAY','JUN',
                                        'JUL','AGO','SEP','OCT','NOV','DIC'];
                        final mon = months[date.month - 1];
                        final bool isDayUnavailable = _blockedDates.contains(ds) ||
                            (_multiDaySlotsByDate.containsKey(ds) &&
                             _multiDaySlotsByDate[ds]!.every((s) => s['enabled'] != true)) ||
                            (_multiDayDataLoaded && !_multiDaySlotsByDate.containsKey(ds)) ||
                            _guarderiaHasNoTimeAvailable(ds);
                        return GestureDetector(
                          onTap: isDayUnavailable ? null : () async {
                            setState(() {
                              _selectedDate = date;
                              _selectedTimeSlot = null;
                              _selectedStartTime = null;
                            });
                            await _loadAvailableSlots(date);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(right: 10),
                            width: 58,
                            decoration: BoxDecoration(
                              color: isDayUnavailable
                                  ? (themeNotifier.isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.withValues(alpha: 0.08))
                                  : isSelected ? GardenColors.primary : surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDayUnavailable
                                    ? borderColor.withValues(alpha: 0.35)
                                    : isSelected ? GardenColors.primary : borderColor,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(mon, style: TextStyle(
                                  color: isDayUnavailable ? subtextColor.withValues(alpha: 0.4) : isSelected ? Colors.white.withValues(alpha: 0.8) : subtextColor,
                                  fontSize: 10, fontWeight: FontWeight.w700,
                                )),
                                const SizedBox(height: 4),
                                Text('${date.day}', style: TextStyle(
                                  color: isDayUnavailable ? subtextColor.withValues(alpha: 0.4) : isSelected ? Colors.white : textColor,
                                  fontSize: 22, fontWeight: FontWeight.w800,
                                )),
                                if (isDayUnavailable)
                                  Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    width: 4, height: 4,
                                    decoration: const BoxDecoration(color: GardenColors.error, shape: BoxShape.circle),
                                  ),
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
                  // ── Guardería: horario (solo MANANA y TARDE) ──
                  if (_selectedDate != null && _availableSlots.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text('Horario', style: GardenText.h4.copyWith(color: textColor)),
                        if (_selectedStartTime != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setState(() {
                              _selectedTimeSlot = null;
                              _selectedStartTime = null;
                            }),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_outlined, size: 16, color: GardenColors.primary),
                                const SizedBox(width: 4),
                                Text('Cambiar', style: TextStyle(color: GardenColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_selectedStartTime != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: GardenColors.primary.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time_rounded, color: GardenColors.primary, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              '${_selectedTimeSlot == 'MANANA' ? 'Mañana' : 'Tarde'} · $_selectedStartTime',
                              style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      ...(_availableSlots.where((slot) => slot['slot'] != 'NOCHE').map((slot) {
                        final slotName = slot['slot'] as String;
                        final label = slotName == 'MANANA' ? 'Mañana' : 'Tarde';
                        final range = '${slot['start']} - ${slot['end']}';
                        final isSelected = _selectedTimeSlot == slotName;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => setState(() {
                                _selectedTimeSlot = slotName;
                                _selectedStartTime = null;
                              }),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: isSelected ? GardenColors.primary.withValues(alpha: 0.08) : surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isSelected ? GardenColors.primary : borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                      color: GardenColors.primary, size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 8),
                                    Text(range, style: TextStyle(color: subtextColor, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                            if (isSelected) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('Hora de inicio',
                                    style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                              _buildTimeChips(slot, _selectedDate!, durationOverride: _guarderiaSelectedDuration),
                              const SizedBox(height: 12),
                            ],
                          ],
                        );
                      })).toList(),
                    ],
                  ],
                ] else if (_selectedService == 'HOSPEDAJE') ...[
                  Text('Fechas', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  // ── Selector de rango en un solo calendario ──
                  GestureDetector(
                    onTap: () async {
                      final tomorrow = DateTime.now().add(const Duration(days: 1));
                      final lastDate = DateTime.now().add(const Duration(days: 90));
                      // initialDate debe satisfacer selectableDayPredicate → primer día libre
                      DateTime firstAvailable = tomorrow;
                      while (firstAvailable.isBefore(lastDate) &&
                          _blockedDates.contains(firstAvailable.toIso8601String().split('T')[0])) {
                        firstAvailable = firstAvailable.add(const Duration(days: 1));
                      }
                      final range = await showDateRangePicker(
                        context: context,
                        initialDateRange: (_selectedDate != null && _endDate != null)
                            ? DateTimeRange(start: _selectedDate!, end: _endDate!)
                            : null,
                        firstDate: tomorrow,
                        lastDate: lastDate,
                        initialEntryMode: DatePickerEntryMode.calendarOnly,
                        selectableDayPredicate: (d, start, end) {
                          final ds = d.toIso8601String().split('T')[0];
                          return !_blockedDates.contains(ds);
                        },
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: Theme.of(context).colorScheme.copyWith(
                              primary: GardenColors.primary,
                              onPrimary: Colors.white,
                              surface: surface,
                              onSurface: textColor,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (range != null) {
                        setState(() {
                          _selectedDate = range.start;
                          _endDate = range.end;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: (_selectedDate != null && _endDate != null) ? GardenColors.primary : borderColor),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month_outlined, color: GardenColors.primary, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Llegada', style: TextStyle(fontSize: 11, color: GardenColors.primary, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 2),
                                          Text(
                                            _selectedDate == null ? '---' : formatDate(_selectedDate!),
                                            style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.arrow_forward, size: 16, color: subtextColor),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('Salida', style: TextStyle(fontSize: 11, color: GardenColors.primary, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 2),
                                          Text(
                                            _endDate == null ? '---' : formatDate(_endDate!),
                                            style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (_selectedDate != null && _endDate != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    '${_endDate!.difference(_selectedDate!).inDays} noches',
                                    style: const TextStyle(color: GardenColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: subtextColor, size: 20),
                        ],
                      ),
                    ),
                  ),
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
        ),
      ),
    ),

          // Botón Sticky
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                border: Border(top: BorderSide(color: borderColor)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, -4))],
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isWide ? 860 : double.infinity),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(isWide ? 40 : 20, 16, isWide ? 40 : 20, 32),
                    child: GardenButton(
                      label: _isSubmitting ? 'Procesando...' : 'Continuar al pago',
                      loading: _isSubmitting,
                      onPressed: _createBooking,
                    ),
                  ),
                ),
              ),
            ),
          )
        ],
      );
      }),
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

  bool _isTimeConflicting(String time, String dateStr, {int? durationOverride}) {
    if (_bookedPaseos.isEmpty) return false;
    final parts = time.split(':');
    final newStart = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    final dur = durationOverride ?? _selectedDuration;
    final newEnd = newStart + dur + 30; // +30 min buffer entre servicios
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
    final firstDay = today;
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
            final ds = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            final isSelected = _isDateSelected(date);

            // Deshabilitar si el cuidador no tiene slots habilitados ese día
            final bool isUnavailable = _blockedDates.contains(ds) ||
                (_multiDaySlotsByDate.containsKey(ds) &&
                 _multiDaySlotsByDate[ds]!.every((s) => s['enabled'] != true)) ||
                (_multiDayDataLoaded && !_multiDaySlotsByDate.containsKey(ds));

            return GestureDetector(
              onTap: isUnavailable ? null : () => _toggleDate(date),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isUnavailable
                      ? (themeNotifier.isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.withValues(alpha: 0.08))
                      : isSelected
                          ? GardenColors.primary
                          : surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isUnavailable
                        ? borderColor.withValues(alpha: 0.4)
                        : isSelected
                            ? GardenColors.primary
                            : borderColor,
                    width: 1,
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          color: isUnavailable
                              ? subtextColor.withValues(alpha: 0.4)
                              : isSelected
                                  ? Colors.white
                                  : textColor,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    // Marca de no disponible
                    if (isUnavailable)
                      Positioned(
                        bottom: 3,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: subtextColor.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        if (_loadingMultiDayData)
          const Center(child: Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.primary)),
          )),
        Text(
          'Toca los días para seleccionar o quitar. Días grises = no disponible.',
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
        final slotKey = s['key'] as String;
        final slotEnabled = _isSlotEnabledForAllDates(slotKey);
        return Expanded(
          child: GestureDetector(
            onTap: slotEnabled
                ? () => setState(() {
                      _multiDayTimeSlot = slotKey;
                      _multiDaySharedTime = null;
                      _perDayTimes = {};
                    })
                : null,
            child: Opacity(
              opacity: slotEnabled ? 1.0 : 0.35,
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
          ),
        );
      }).toList(),
    );
  }

  // ─── Multi-day availability helpers ─────────────────────────────────────

  /// Una sola llamada API: carga slots reales y reservas del cuidador para los próximos 30 días
  Future<void> _loadMultiDayData() async {
    setState(() => _loadingMultiDayData = true);
    try {
      final today = DateTime.now();
      final from  = today;
      final to    = today.add(const Duration(days: 30));
      final uri   = Uri.parse('$_baseUrl/caregivers/${widget.caregiverId}/availability')
          .replace(queryParameters: {
            'from': from.toIso8601String().split('T')[0],
            'to':   to.toIso8601String().split('T')[0],
          });
      final response = await http.get(uri);
      final body = jsonDecode(response.body);
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is Map) {
          final paseosRaw = data['paseos'] as Map? ?? {};
          final bookingsRaw = data['bookedPaseos'];
          final blockedRaw  = data['blockedDates'];
          setState(() {
            _multiDaySlotsByDate = paseosRaw.map(
              (k, v) => MapEntry(k as String, (v as List).cast<Map<String, dynamic>>()),
            );
            _blockedDates = blockedRaw is List
                ? Set<String>.from(blockedRaw.cast<String>())
                : {};
            _multiDayRangeBookings = bookingsRaw is List
                ? bookingsRaw.cast<Map<String, dynamic>>()
                : [];
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading multi-day data: $e');
    } finally {
      if (mounted) setState(() {
        _loadingMultiDayData = false;
        _multiDayDataLoaded = true;
      });
    }
  }

  /// Para GUARDERIA: ¿hay alguna hora de inicio válida en este día para la duración seleccionada?
  /// Devuelve true si el día debe deshabilitarse (sin tiempo suficiente).
  bool _guarderiaHasNoTimeAvailable(String dateStr) {
    if (!_multiDayDataLoaded) return false;
    final daySlots = _multiDaySlotsByDate[dateStr];
    if (daySlots == null || daySlots.isEmpty) return true;
    final usableSlots = daySlots.where((s) => s['enabled'] == true && s['slot'] != 'NOCHE').toList();
    if (usableSlots.isEmpty) return true;
    for (final slot in usableSlots) {
      final sp = (slot['start'] as String? ?? '08:00').split(':');
      final ep = (slot['end'] as String? ?? '11:00').split(':');
      final slotStartMin = int.parse(sp[0]) * 60 + (sp.length > 1 ? int.parse(sp[1]) : 0);
      final slotEndMin = int.parse(ep[0]) * 60 + (ep.length > 1 ? int.parse(ep[1]) : 0);
      if (slotStartMin + _guarderiaSelectedDuration > slotEndMin) continue;
      for (int t = slotStartMin; t + _guarderiaSelectedDuration <= slotEndMin; t += 30) {
        final h = t ~/ 60;
        final m = t % 60;
        final timeStr = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        bool conflicts = false;
        for (final b in _multiDayRangeBookings) {
          if (b['date'] != dateStr || b['startTime'] == null) continue;
          final bs = (b['startTime'] as String).split(':');
          final bStart = int.parse(bs[0]) * 60 + int.parse(bs[1]);
          final bEnd = bStart + (b['duration'] as int? ?? 30) + 30;
          final newEnd = t + _guarderiaSelectedDuration + 30;
          if (t < bEnd && newEnd > bStart) { conflicts = true; break; }
        }
        if (!conflicts) return false; // Hay al menos una hora válida
      }
    }
    return true; // Ninguna hora válida → deshabilitar día
  }

  /// ¿El cuidador atiende este slot (MANANA/TARDE/NOCHE) en TODAS las fechas seleccionadas?
  bool _isSlotEnabledForAllDates(String slotKey) {
    if (_selectedDates.isEmpty || _multiDaySlotsByDate.isEmpty) return true;
    for (final d in _selectedDates) {
      final ds = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final daySlots = _multiDaySlotsByDate[ds] ?? [];
      final found = daySlots.any(
        (s) => (s['slot'] ?? s['key']) == slotKey && s['enabled'] == true,
      );
      if (!found) return false;
    }
    return true;
  }

  /// Rango horario real del cuidador para un slot en una fecha concreta (con fallback)
  Map<String, dynamic> _slotRangeForDate(String slotKey, String dateStr) {
    final daySlots = _multiDaySlotsByDate[dateStr] ?? [];
    final slot = daySlots.firstWhere(
      (s) => (s['slot'] ?? s['key']) == slotKey,
      orElse: () => <String, dynamic>{},
    );
    if (slot.isNotEmpty && slot['start'] != null && slot['end'] != null) {
      return {'start': slot['start'], 'end': slot['end']};
    }
    // Fallback a valores típicos si no hay datos
    return switch (slotKey) {
      'MANANA' => {'start': '08:00', 'end': '11:00'},
      'TARDE'  => {'start': '13:00', 'end': '17:00'},
      _        => {'start': '19:00', 'end': '22:00'},
    };
  }

  /// Para "misma hora": intersección del rango real entre todas las fechas seleccionadas
  Map<String, dynamic> _computeSharedSlotRange() {
    if (_selectedDates.isEmpty || _multiDayTimeSlot == null) {
      return _slotRangeForDate(_multiDayTimeSlot ?? 'MANANA', '');
    }
    int maxStartMins = 0;
    int minEndMins   = 24 * 60;
    for (final d in _selectedDates) {
      final ds    = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final range = _slotRangeForDate(_multiDayTimeSlot!, ds);
      final sp    = (range['start'] as String).split(':');
      final ep    = (range['end']   as String).split(':');
      final s     = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final e     = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      if (s > maxStartMins) maxStartMins = s;
      if (e < minEndMins)   minEndMins   = e;
    }
    if (maxStartMins >= minEndMins) return {'start': '99:00', 'end': '99:00'}; // sin intersección
    return {
      'start': '${(maxStartMins ~/ 60).toString().padLeft(2, '0')}:${(maxStartMins % 60).toString().padLeft(2, '0')}',
      'end':   '${(minEndMins   ~/ 60).toString().padLeft(2, '0')}:${(minEndMins   % 60).toString().padLeft(2, '0')}',
    };
  }

  /// ¿Choca este horario con alguna reserva existente?
  /// dateStr=null → chequea en CUALQUIER fecha seleccionada (modo "misma hora")
  bool _isMultiDayTimeConflicting(String time, String? dateStr) {
    if (_multiDayRangeBookings.isEmpty) return false;
    final parts    = time.split(':');
    final newStart = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    final newEnd   = newStart + _selectedDuration + 30; // +30 min descanso
    for (final b in _multiDayRangeBookings) {
      final bDate = b['date'] as String? ?? b['walkDate'] as String? ?? '';
      // Si modo por día: solo chequear la fecha específica
      // Si modo misma hora: chequear en las fechas seleccionadas únicamente
      if (dateStr != null && bDate != dateStr) continue;
      if (dateStr == null) {
        // Verificar si esta reserva pertenece a una de las fechas seleccionadas
        final isRelevant = _selectedDates.any((d) {
          final ds = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          return ds == bDate;
        });
        if (!isRelevant) continue;
      }
      final rawTime = b['startTime'] as String?;
      if (rawTime == null || rawTime.isEmpty) continue;
      final sp    = rawTime.split(':');
      final bStart = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final bEnd   = bStart + (b['duration'] as int? ?? 60) + 30;
      if (newStart < bEnd && newEnd > bStart) return true;
    }
    return false;
  }

  /// Chips de hora para multi-día.
  /// dateStr=null → hora compartida para todos (usa intersección de rangos)
  /// dateStr≠null → hora individual para esa fecha (usa rango de esa fecha)
  Widget _buildMultiDayTimeChips(String? dateStr) {
    final range = dateStr == null
        ? _computeSharedSlotRange()
        : _slotRangeForDate(_multiDayTimeSlot!, dateStr);

    final startParts = (range['start'] as String).split(':');
    final endParts   = (range['end']   as String).split(':');
    final startHour  = int.parse(startParts[0]);
    final startMin   = int.parse(startParts[1]);
    final endHour    = int.parse(endParts[0]);

    // Sin intersección válida
    if (startHour >= endHour && startHour != 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Los días seleccionados tienen horarios incompatibles en este bloque.',
          style: TextStyle(
            color: themeNotifier.isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary,
            fontSize: 12,
          ),
        ),
      );
    }

    final timeSlots = <String>[];
    for (int h = startHour; h <= endHour; h++) {
      for (int m = 0; m < 60; m += 30) {
        if (h == startHour && m < startMin) continue;
        final totalEnd = h * 60 + m + _selectedDuration + 30;
        if (totalEnd <= endHour * 60) {
          timeSlots.add('${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
        }
      }
    }

    final available = timeSlots.where((t) => !_isMultiDayTimeConflicting(t, dateStr)).toList();

    if (available.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
          'No hay horarios disponibles en este bloque',
          style: TextStyle(
            color: themeNotifier.isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary,
            fontSize: 12,
          ),
        ),
      );
    }

    final selectedTime = dateStr == null ? _multiDaySharedTime : _perDayTimes[dateStr];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: available.map((time) {
        final isSelected = selectedTime == time;
        return GestureDetector(
          onTap: () => setState(() {
            if (dateStr == null) {
              _multiDaySharedTime = time;
            } else {
              _perDayTimes[dateStr] = time;
            }
          }),
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
                color: isSelected
                    ? GardenColors.primary
                    : (themeNotifier.isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
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

  /// Sección completa de selección de hora para modo multi-día
  Widget _buildMultiDayTimePicker(Color textColor, Color subtextColor, Color borderColor, Color surface) {
    if (_loadingMultiDayData) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.primary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Hora del paseo', style: GardenText.h4.copyWith(color: textColor)),
            const Spacer(),
            const Text(
              '* 30 min de descanso incluidos',
              style: TextStyle(color: GardenColors.primary, fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: themeNotifier.isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              _buildTimeToggleTab('Misma hora', _multiDaySameTime, () {
                setState(() {
                  _multiDaySameTime = true;
                  _perDayTimes = {};
                });
              }),
              _buildTimeToggleTab('Hora por día', !_multiDaySameTime, () {
                setState(() {
                  _multiDaySameTime = false;
                  _multiDaySharedTime = null;
                });
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_multiDaySameTime) ...[
          Text(
            'La misma hora se aplicará a todos los días seleccionados.',
            style: TextStyle(color: subtextColor, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _buildMultiDayTimeChips(null),
        ] else ...[
          Text(
            'Selecciona la hora para cada día por separado.',
            style: TextStyle(color: subtextColor, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ..._selectedDates.map((d) {
            const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
            final ds = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
            final picked = _perDayTimes[ds];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${d.day} ${months[d.month - 1]}',
                      style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    if (picked != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: GardenColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          picked,
                          style: const TextStyle(
                            color: GardenColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                _buildMultiDayTimeChips(ds),
                const SizedBox(height: 16),
              ],
            );
          }),
        ],
      ],
    );
  }

  /// Tab del toggle "Misma hora / Hora por día"
  Widget _buildTimeToggleTab(String label, bool isActive, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? GardenColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isActive
                    ? Colors.white
                    : (themeNotifier.isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeChips(Map<String, dynamic> slot, DateTime date, {int? durationOverride}) {
    final effectiveDuration = durationOverride ?? _selectedDuration;
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final startParts = (slot['start'] as String).split(':');
    final endParts = (slot['end'] as String).split(':');
    final startHour = int.parse(startParts[0]);
    final startMin = startParts.length > 1 ? int.parse(startParts[1]) : 0;
    final endHour = int.parse(endParts[0]);
    final endMin = endParts.length > 1 ? int.parse(endParts[1]) : 0;
    final slotEndMinutes = endHour * 60 + endMin;

    final timeSlots = <String>[];
    for (int h = startHour; h <= endHour; h++) {
      final mStart = (h == startHour) ? startMin : 0;
      for (int m = mStart; m < 60; m += 30) {
        final slotStart = h * 60 + m;
        if (slotStart >= slotEndMinutes) break;
        // El servicio completo debe caber dentro del bloque (sin buffer en el límite del bloque)
        if (slotStart + effectiveDuration <= slotEndMinutes) {
          timeSlots.add('${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
        }
      }
    }

    // Ocultar horarios que ya están reservados (incluye buffer de descanso entre servicios)
    final available = timeSlots.where((t) => !_isTimeConflicting(t, dateStr, durationOverride: effectiveDuration)).toList();

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
          style: const TextStyle(
            color: GardenColors.primary,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
    );
  }

  /// Returns true if the given hour:minute slot on the M&G date conflicts with a caregiver booking
  bool _isMGSlotConflicting(int hour, int minute) {
    if (_mgDate == null) return false;
    final mgDateStr =
        '${_mgDate!.year}-${_mgDate!.month.toString().padLeft(2, '0')}-${_mgDate!.day.toString().padLeft(2, '0')}';
    final slotMin = hour * 60 + minute;
    for (final b in _multiDayRangeBookings) {
      final bDate = (b['date'] ?? b['walkDate'] ?? '') as String;
      if (!bDate.startsWith(mgDateStr)) continue;
      final st = (b['startTime'] ?? '') as String;
      if (st.isEmpty) continue;
      final parts = st.split(':');
      if (parts.length < 2) continue;
      final startMin = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      final dur = (b['duration'] as num?)?.toInt() ?? 60;
      if (slotMin >= startMin - 30 && slotMin < startMin + dur) return true;
    }
    return false;
  }

  /// Friendly date label like "Lun, 26 may 2026"
  String _formatMGDate(DateTime d) {
    const weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _buildMeetAndGreetSection(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final isDark = themeNotifier.isDark;
    final bookingStart = _bookingStartDate;

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
          // ── Header row ─────────────────────────────────────────────────
          Row(
            children: [
              const Text('🐾', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Meet & Greet',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('Conoce al cuidador antes del servicio',
                        style: TextStyle(color: subtextColor, fontSize: 12)),
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
            const SizedBox(height: 14),

            // ── Modalidad: Presencial / Virtual ────────────────────────
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() { _mgVirtual = false; }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_mgVirtual ? GardenColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: !_mgVirtual ? GardenColors.primary : borderColor),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_on_outlined, size: 14, color: !_mgVirtual ? Colors.white : subtextColor),
                          const SizedBox(width: 5),
                          Text('Presencial', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: !_mgVirtual ? Colors.white : subtextColor)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() { _mgVirtual = true; }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _mgVirtual ? GardenColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _mgVirtual ? GardenColors.primary : borderColor),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.video_call_outlined, size: 14, color: _mgVirtual ? Colors.white : subtextColor),
                          const SizedBox(width: 5),
                          Text('Virtual', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _mgVirtual ? Colors.white : subtextColor)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── 1. Date picker ──────────────────────────────────────────
            GestureDetector(
              onTap: () async {
                final now = DateTime.now();
                // lastDate = day before booking start, or now+60 if no booking date yet
                final lastDate = bookingStart != null
                    ? bookingStart.subtract(const Duration(days: 1))
                    : now.add(const Duration(days: 60));
                // If lastDate is before today there's nothing to pick
                if (lastDate.isBefore(now)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('El M&G debe ser antes de la fecha de reserva. Selecciona primero la fecha del servicio.'),
                    ),
                  );
                  return;
                }
                final initialDate = (_mgDate != null && _mgDate!.isBefore(lastDate) && !_mgDate!.isBefore(now))
                    ? _mgDate!
                    : now.add(const Duration(days: 1)).isAfter(lastDate)
                        ? lastDate
                        : now.add(const Duration(days: 1));
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initialDate,
                  firstDate: now,
                  lastDate: lastDate,
                  builder: (ctx, child) {
                    return Theme(
                      data: (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
                        colorScheme: isDark
                            ? const ColorScheme.dark(
                                primary: GardenColors.primary,
                                onPrimary: Colors.white,
                              )
                            : const ColorScheme.light(
                                primary: GardenColors.primary,
                                onPrimary: Colors.white,
                                surface: Colors.white,
                                onSurface: Colors.black87,
                              ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (picked != null) setState(() => _mgDate = picked);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: borderColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: GardenColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _mgDate != null ? _formatMGDate(_mgDate!) : 'Seleccionar fecha',
                            style: TextStyle(
                              color: _mgDate != null ? textColor : subtextColor,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (_mgDate != null)
                          GestureDetector(
                            onTap: () => setState(() => _mgDate = null),
                            child: Icon(Icons.close, size: 16, color: subtextColor),
                          ),
                      ],
                    ),
                  ),
                  if (bookingStart != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        'Debe ser antes del ${_formatMGDate(bookingStart)}',
                        style: TextStyle(color: subtextColor, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            if (_mgDate != null) ...[
            const SizedBox(height: 10),

            // ── 2. Inline time chips (07:00–21:00, 30-min steps) ───────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: shows selected time + Cambiar button when collapsed
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 16, color: GardenColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      _mgTime != null
                          ? '${_mgTime!.hour.toString().padLeft(2, '0')}:${_mgTime!.minute.toString().padLeft(2, '0')}'
                          : 'Seleccionar hora',
                      style: TextStyle(
                        color: _mgTime != null ? textColor : subtextColor,
                        fontSize: 14,
                        fontWeight: _mgTime != null ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    if (_mgTime != null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _mgTimeExpanded = !_mgTimeExpanded),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: GardenColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            _mgTimeExpanded ? 'Cerrar' : 'Cambiar',
                            style: const TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_mgTimeExpanded) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int h = 7; h <= 21; h++)
                      for (int m = 0; m < 60; m += 30) ...[
                        if (h == 21 && m > 0) ...[],
                        if (!(h == 21 && m > 0))
                          Builder(builder: (_) {
                            final isConflicting = _isMGSlotConflicting(h, m);
                            final isSelected = _mgTime != null &&
                                _mgTime!.hour == h &&
                                _mgTime!.minute == m;
                            final label =
                                '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
                            return GestureDetector(
                              onTap: isConflicting
                                  ? null
                                  : () => setState(() {
                                      _mgTime = TimeOfDay(hour: h, minute: m);
                                      _mgTimeExpanded = false;
                                    }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isConflicting
                                      ? (isDark
                                          ? Colors.white.withValues(alpha: 0.04)
                                          : Colors.grey.withValues(alpha: 0.08))
                                      : isSelected
                                          ? GardenColors.primary
                                          : (isDark
                                              ? Colors.white.withValues(alpha: 0.06)
                                              : GardenColors.lightSurface),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isConflicting
                                        ? borderColor.withValues(alpha: 0.35)
                                        : isSelected
                                            ? GardenColors.primary
                                            : borderColor,
                                    width: isSelected ? 0 : 1,
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: isConflicting
                                        ? subtextColor.withValues(alpha: 0.4)
                                        : isSelected
                                            ? Colors.white
                                            : textColor,
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }),
                      ],
                  ],
                ),
                ], // end if (_mgTimeExpanded)
              ],
            ),
            ], // end if (_mgDate != null)

            if (_mgDate != null && _mgTime != null && !_mgVirtual) ...[
            const SizedBox(height: 10),

            // ── 3. Meeting point (only for in-person M&G) ───────────────
            TextField(
              controller: _mgPlaceCtrl,
              style: TextStyle(color: textColor, fontSize: 14),
              onChanged: _searchMGLocations,
              decoration: InputDecoration(
                hintText: 'Punto de encuentro',
                hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                prefixIcon: const Icon(Icons.location_on, color: GardenColors.primary, size: 18),
                suffixIcon: _mgPlaceCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, size: 16, color: subtextColor),
                        onPressed: () {
                          setState(() {
                            _mgPlaceCtrl.clear();
                            _mgLocationSuggestions = [];
                            _mgSelectedLat = null;
                            _mgSelectedLng = null;
                          });
                        },
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                constraints: const BoxConstraints(maxHeight: 200),
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
                    final fmt = s['structured_formatting'] as Map? ?? {};
                    final primaryName = (fmt['main_text'] ?? s['description'] ?? '') as String;
                    final secondaryAddr = (fmt['secondary_text'] ?? '') as String;
                    return InkWell(
                      onTap: () => _selectMGPlace(s),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.place,
                                size: 18, color: GardenColors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    primaryName,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (secondaryAddr.isNotEmpty)
                                    Text(
                                      secondaryAddr,
                                      style: TextStyle(
                                          color: subtextColor, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
            const SizedBox(height: 8),
            Text(
              'Coordina el punto de encuentro con el cuidador por chat.',
              style: TextStyle(color: subtextColor, fontSize: 11),
            ),
            ], // end if (_mgDate != null && _mgTime != null && !_mgVirtual)

            if (_mgDate != null && _mgTime != null && _mgVirtual) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.video_call_outlined, size: 15, color: GardenColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'El M&G será por videollamada. Coordina el enlace con el cuidador por chat.',
                    style: TextStyle(color: subtextColor, fontSize: 11),
                  )),
                ],
              ),
            ),
            ],
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

    final String serviceDisplayName = _selectedService == 'PASEO' ? 'Paseo'
        : _selectedService == 'GUARDERIA' ? 'Guardería'
        : 'Hospedaje';

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
          _summaryRow(Icons.settings, 'Servicio', serviceDisplayName),
          if (_selectedService == 'PASEO')
            _summaryRow(Icons.timer_outlined, 'Duración', '$_selectedDuration min'),
          if (_selectedService == 'GUARDERIA') ...[
            _summaryRow(Icons.timer_outlined, 'Duración', '${_guarderiaSelectedDuration ~/ 60}h'),
            if (_selectedTimeSlot != null)
              _summaryRow(Icons.access_time, 'Horario', _selectedTimeSlot == 'MANANA' ? 'Mañana' : 'Tarde'),
          ],
          if (fechaText.isNotEmpty)
            _summaryRow(Icons.calendar_today, _isMultiDay ? 'Días' : 'Fecha', fechaText),
          if (_selectedService == 'PASEO' && _isMultiDay && _multiDayTimeSlot != null)
            _summaryRow(Icons.access_time, 'Horario',
                _multiDayTimeSlot == 'MANANA' ? 'Mañana' : _multiDayTimeSlot == 'TARDE' ? 'Tarde' : 'Noche'),
          if (_selectedService == 'PASEO' && _isMultiDay && _multiDaySameTime && _multiDaySharedTime != null)
            _summaryRow(Icons.schedule, 'Hora', _multiDaySharedTime!),
          if (_selectedService == 'PASEO' && _isMultiDay && !_multiDaySameTime && _perDayTimes.isNotEmpty)
            _summaryRow(Icons.schedule, 'Horas',
                _selectedDates.map((d) {
                  final ds = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                  const m = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
                  final t = _perDayTimes[ds] ?? '--:--';
                  return '${d.day} ${m[d.month-1]}: $t';
                }).join(' · ')),
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

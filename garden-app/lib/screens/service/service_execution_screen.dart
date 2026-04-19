import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/garden_theme.dart';
import '../chat/chat_screen.dart';
import 'gps_tracking_screen.dart';
import 'meet_and_greet_screen.dart';

class ServiceExecutionScreen extends StatefulWidget {
  final String bookingId;
  final String role; // 'CAREGIVER' o 'CLIENT'
  final String? token; // Token opcional para evitar re-leer SharedPreferences
  const ServiceExecutionScreen({super.key, required this.bookingId, required this.role, this.token});

  @override
  State<ServiceExecutionScreen> createState() => _ServiceExecutionScreenState();
}

class _ServiceExecutionScreenState extends State<ServiceExecutionScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _booking;
  bool _isLoading = true;
  bool _isProcessing = false;
  String _token = '';
  late AnimationController _pulseController;
  Timer? _serviceTimer;
  Timer? _photoRefreshTimer;
  Duration _elapsed = Duration.zero;
  List<Map<String, dynamic>> _serviceEvents = [];

  // Survey state — must be class-level to survive parent rebuilds (e.g. themeNotifier)
  int _surveyRating = 0;
  final TextEditingController _surveyCommentController = TextEditingController();

  // Walk extension state
  int _allowedExtensionMinutes = 0;
  bool _loadingExtension = false;

  // Photo upload state
  bool _isSendingPhoto = false;

  // GPS monitoring (PASEO only)
  StreamSubscription<ServiceStatus>? _gpsStatusSub;
  bool _gpsDialogShown = false;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');
  bool get _alreadyRated => _booking?['ownerRating'] != null;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    // Rebuild when comment text changes so the submit button enables/disables correctly
    _surveyCommentController.addListener(() { if (mounted) setState(() {}); });
    _loadInitialData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _serviceTimer?.cancel();
    _photoRefreshTimer?.cancel();
    _surveyCommentController.dispose();
    _gpsStatusSub?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await _loadBooking();
  }

  Future<void> _loadBooking() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('access_token') ?? '';
      // Fallback: usar token pasado por navegación si SharedPreferences está vacío
      if (_token.isEmpty && widget.token != null && widget.token!.isNotEmpty) {
        _token = widget.token!;
      }
      
      debugPrint('SERVICE: Loading booking ${widget.bookingId} with token: ${_token.length > 20 ? _token.substring(0, 20) : _token}...');
      
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      
      debugPrint('SERVICE: Response ${response.statusCode}: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
      
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _booking = data['data'];
          _serviceEvents = (_booking?['serviceEvents'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((e) => e['photoUrl'] != null && e['photoUrl'].toString().isNotEmpty)
              .toList();
          _isLoading = false;
        });
        
        if (_booking?['status'] == 'IN_PROGRESS') {
          _startTimer();
          // Start GPS monitoring for caregiver on PASEO
          if (widget.role == 'CAREGIVER' && _booking?['serviceType'] == 'PASEO') {
            _startGpsMonitoring();
          }
          if (widget.role == 'CLIENT' && _photoRefreshTimer == null) {
            _photoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadBooking());
          }
          // Load extension availability for CLIENT on PASEO
          if (widget.role == 'CLIENT' && _booking?['serviceType'] == 'PASEO') {
            _loadExtensionAvailability();
          }
        } else {
          _serviceTimer?.cancel();
          _photoRefreshTimer?.cancel();
          _photoRefreshTimer = null;
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('SERVICE ERROR: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startGpsMonitoring() {
    _gpsStatusSub?.cancel();
    _gpsDialogShown = false;
    if (kIsWeb) return;
    _gpsStatusSub = Geolocator.getServiceStatusStream().listen((status) {
      if (status == ServiceStatus.disabled && mounted && !_gpsDialogShown) {
        _showGpsDisabledDialog();
      }
    });
  }

  void _showGpsDisabledDialog() {
    _gpsDialogShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        int _secondsLeft = 30;
        Timer? _countdown;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            _countdown ??= Timer.periodic(const Duration(seconds: 1), (t) {
              if (_secondsLeft <= 1) {
                t.cancel();
                Navigator.of(ctx, rootNavigator: true).pop();
                _cancelServiceGpsPenalty();
              } else {
                setLocal(() => _secondsLeft--);
              }
            });
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Text('⚠️', style: TextStyle(fontSize: 22)),
                  SizedBox(width: 8),
                  Expanded(child: Text('GPS desactivado', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Por seguridad, el GPS debe estar activo durante el paseo.\n\n'
                    'Activa el GPS de tu teléfono ahora. Si no lo haces en:',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      '$_secondsLeft s',
                      style: const TextStyle(
                        fontSize: 40, fontWeight: FontWeight.w900,
                        color: GardenColors.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: GardenColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '⚠️ El servicio se cancelará automáticamente y se aplicará un descuento por incumplimiento.',
                      style: TextStyle(fontSize: 12, color: GardenColors.error, height: 1.4),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    _countdown?.cancel();
                    Navigator.of(ctx, rootNavigator: true).pop();
                    // Verificar si el GPS ya está activo
                    await Future.delayed(const Duration(seconds: 2));
                    final enabled = await Geolocator.isLocationServiceEnabled();
                    if (!enabled && mounted) {
                      _gpsDialogShown = false;
                      _showGpsDisabledDialog();
                    } else {
                      if (mounted) _gpsDialogShown = false;
                    }
                  },
                  child: const Text('Ya lo activé', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _cancelServiceGpsPenalty() async {
    if (!mounted) return;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/cancel'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'reason': 'GPS desactivado durante el paseo — cancelación automática por seguridad'}),
      );
      final data = jsonDecode(response.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['success'] == true
                ? 'Servicio cancelado por desactivación de GPS.'
                : 'Error al cancelar. Contacta a soporte.'),
            backgroundColor: GardenColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
        if (data['success'] == true) {
          await _loadBooking();
        }
      }
    } catch (e) {
      debugPrint('Error cancelling by GPS: $e');
    }
  }

  void _startTimer() {
    _serviceTimer?.cancel();
    final startedAt = _booking?['serviceStartedAt'] as String?;
    if (startedAt != null) {
      final startTime = DateTime.tryParse(startedAt);
      if (startTime != null) {
        _elapsed = DateTime.now().difference(startTime);
      }
    }
    _serviceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;

        if (_isLoading) {
          return Scaffold(
            backgroundColor: bg,
            body: const Center(child: CircularProgressIndicator(color: GardenColors.primary)),
          );
        }

        final status = _booking?['status'] ?? '';

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.close_rounded, color: textColor),
              onPressed: () => context.pop(),
            ),
            title: Text(
              _getAppBarTitle(status),
              style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          body: _buildBody(status),
        );
      },
    );
  }

  String _getAppBarTitle(String status) {
    switch (status) {
      case 'CONFIRMED': return 'Preparación';
      case 'IN_PROGRESS': return 'Servicio Activo';
      case 'COMPLETED': return 'Servicio Finalizado';
      default: return 'Detalle de Servicio';
    }
  }

  Widget _buildBody(String status) {
    if (status == 'CONFIRMED' && widget.role == 'CAREGIVER') {
      return _buildReadyToStart();
    }
    if (status == 'IN_PROGRESS') {
      return _buildInProgressView();
    }
    if (status == 'COMPLETED') {
      if (widget.role == 'CLIENT' && !_alreadyRated) {
        return _buildSatisfactionSurvey();
      }
      return _buildCompletedView();
    }
    
    // Vista por defecto para otros estados
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('⌛', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text('Esperando actualización del estado...', 
              style: TextStyle(color: themeNotifier.isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
              textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // --- VISTA: READY TO START (CAREGIVER) ---
  Widget _buildReadyToStart() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Reserva confirmada', style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          // Banner superior de estado
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: GardenColors.success.withOpacity(0.08),
              border: Border(bottom: BorderSide(color: GardenColors.success.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                Container(
                  width: 12, height: 12,
                  decoration: const BoxDecoration(color: GardenColors.success, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                const Text('Lista para iniciar', style: TextStyle(color: GardenColors.success, fontWeight: FontWeight.w700, fontSize: 15)),
                const Spacer(),
                const GardenBadge(text: '⬡ Escrow listo', color: GardenColors.polygon, fontSize: 11),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Card principal de la mascota - estilo Airbnb
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor),
                      boxShadow: GardenShadows.card,
                    ),
                    child: Column(
                      children: [
                        // Header con foto del cuidador/mascota
                        Container(
                          height: 140,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [GardenColors.primary.withOpacity(0.8), GardenColors.primary],
                            ),
                          ),
                          child: Stack(
                            children: [
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _booking?['serviceType'] == 'PASEO' ? '🦮' : '🏠',
                                      style: const TextStyle(fontSize: 48),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _booking?['serviceType'] == 'PASEO' ? 'Paseo' : 'Hospedaje',
                                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                              // Hora programada
                              Positioned(
                                top: 12, right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _booking?['startTime'] ?? _booking?['timeSlot'] ?? '—',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Info de la mascota
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 48, height: 48,
                                    decoration: BoxDecoration(
                                      color: GardenColors.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.pets, color: GardenColors.primary, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_booking?['petName'] as String? ?? '—',
                                          style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                                        Text(
                                          '${_booking?['petBreed'] ?? ''} · ${_booking?['petAge'] != null ? '${_booking!['petAge']} años' : ''}',
                                          style: TextStyle(color: subtextColor, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    'Bs ${_booking?['totalAmount'] ?? '—'}',
                                    style: const TextStyle(color: GardenColors.primary, fontSize: 20, fontWeight: FontWeight.w900),
                                  ),
                                ],
                              ),
                              if (_booking?['specialNeeds'] != null && (_booking!['specialNeeds'] as String).isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: GardenColors.warning.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: GardenColors.warning.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.info_outline, size: 14, color: GardenColors.warning),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(_booking!['specialNeeds'] as String,
                                          style: TextStyle(color: subtextColor, fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Divider(height: 1, color: borderColor),
                        // Info del dueño
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              GardenAvatar(
                                imageUrl: null,
                                size: 44,
                                initials: (_booking?['clientName'] as String? ?? 'C')[0],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_booking?['clientName'] as String? ?? 'Cliente',
                                      style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 15)),
                                    Text('Dueño de ${_booking?['petName'] ?? 'la mascota'}',
                                      style: TextStyle(color: subtextColor, fontSize: 12)),
                                  ],
                                ),
                              ),
                              if (_booking?['clientPhone'] != null)
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: GardenColors.success.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: GardenColors.success.withOpacity(0.3)),
                                  ),
                                  child: const Icon(Icons.phone_outlined, color: GardenColors.success, size: 18),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Meet & Greet card (solo para HOSPEDAJE)
                  if (_booking?['serviceType'] == 'HOSPEDAJE') ...[
                    _buildMeetAndGreetCard(),
                    const SizedBox(height: 16),
                  ],

                  // Recomendación GPS (solo PASEO)
                  if (_booking?['serviceType'] == 'PASEO') ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: GardenColors.success.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: GardenColors.success.withOpacity(0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('📍', style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Mantén el GPS activado',
                                  style: TextStyle(color: GardenColors.success, fontWeight: FontWeight.w700, fontSize: 14)),
                                const SizedBox(height: 4),
                                Text(
                                  'Durante el paseo tu ubicación se comparte en tiempo real con el dueño. '
                                  'Si desactivas el GPS, el servicio se cancelará automáticamente por razones de seguridad.',
                                  style: TextStyle(color: subtextColor, fontSize: 12, height: 1.45),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Checklist pre-servicio
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Antes de iniciar', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 12),
                        _checkItem('Confirma la identidad del dueño', subtextColor),
                        _checkItem('Verifica el estado de la mascota', subtextColor),
                        _checkItem('Revisa las necesidades especiales', subtextColor),
                      ],
                    ),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      // Botón sticky
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: surface,
          border: Border(top: BorderSide(color: borderColor)),
          boxShadow: GardenShadows.elevated,
        ),
        child: GardenButton(
          label: _isProcessing ? 'Iniciando...' : '🐾 Iniciar servicio ahora',
          loading: _isProcessing,
          color: GardenColors.success,
          onPressed: _startService,
        ),
      ),
    );
  }

  Widget _checkItem(String text, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 16, color: GardenColors.success),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(color: subtextColor, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildMeetAndGreetCard() {
    final mg = _booking?['meetAndGreet'] as Map<String, dynamic>?;
    final status = mg?['status'] as String?;

    Color bgColor;
    Color borderColor;
    String emoji;
    String title;
    String subtitle;
    String btnLabel;

    if (status == null || status == 'PENDING_PROPOSAL') {
      bgColor = GardenColors.warning.withValues(alpha: 0.08);
      borderColor = GardenColors.warning.withValues(alpha: 0.35);
      emoji = '🤝';
      title = 'Meet & Greet recomendado';
      subtitle = 'Reúnete antes del hospedaje';
      btnLabel = 'Coordinar';
    } else if (status == 'PROPOSED') {
      bgColor = GardenColors.primary.withValues(alpha: 0.07);
      borderColor = GardenColors.primary.withValues(alpha: 0.3);
      emoji = '📅';
      title = 'Propuesta pendiente';
      subtitle = 'Hay una fecha propuesta';
      btnLabel = 'Ver';
    } else if (status == 'ACCEPTED') {
      bgColor = GardenColors.success.withValues(alpha: 0.08);
      borderColor = GardenColors.success.withValues(alpha: 0.3);
      emoji = '✅';
      title = 'Meet & Greet confirmado';
      subtitle = 'Reunión confirmada';
      btnLabel = 'Ver';
    } else if (status == 'COMPLETED' && mg?['approved'] == true) {
      bgColor = GardenColors.success.withValues(alpha: 0.08);
      borderColor = GardenColors.success.withValues(alpha: 0.3);
      emoji = '✅';
      title = 'Meet & Greet completado';
      subtitle = 'Compatibilidad confirmada';
      btnLabel = 'Ver';
    } else if (status == 'COMPLETED' && mg?['approved'] == false) {
      bgColor = GardenColors.error.withValues(alpha: 0.07);
      borderColor = GardenColors.error.withValues(alpha: 0.3);
      emoji = '❌';
      title = 'Reserva cancelada';
      subtitle = 'Incompatibilidad detectada';
      btnLabel = 'Ver';
    } else {
      bgColor = GardenColors.warning.withValues(alpha: 0.08);
      borderColor = GardenColors.warning.withValues(alpha: 0.35);
      emoji = '🤝';
      title = 'Meet & Greet';
      subtitle = status;
      btnLabel = 'Ver';
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MeetAndGreetScreen(
            bookingId: widget.bookingId,
            role: widget.role,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: GardenColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(btnLabel, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadExtensionAvailability() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/extension-availability'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          setState(() => _allowedExtensionMinutes = (data['data']['allowedMinutes'] as num?)?.toInt() ?? 0);
        }
      }
    } catch (_) {}
  }

  Future<void> _requestExtensionPayment(int minutes, String method) async {
    setState(() => _loadingExtension = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/request-extension-payment'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'additionalMinutes': minutes, 'method': method}),
      );

      // Guard: server may return HTML (503, 404, etc.) — parse safely
      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('Error del servidor (${response.statusCode}). Intenta de nuevo en un momento.');
      }

      if (data['success'] == true) {
        final payData = data['data'] as Map<String, dynamic>;
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _WalkExtensionPaymentScreen(
              bookingId: widget.bookingId,
              token: _token,
              baseUrl: _baseUrl,
              extensionId: payData['extensionId'] as String,
              additionalMinutes: minutes,
              extraAmount: (payData['extraAmount'] as num).toDouble(),
              qrImageUrl: payData['qrImageUrl'] as String?,
              qrExpiresAt: payData['qrExpiresAt'] as String?,
              method: method,
              onConfirmed: () async {
                await _loadBooking();
                await _loadExtensionAvailability();
              },
            ),
          ),
        );
      } else {
        throw Exception(data['error']?['message'] ?? data['message'] ?? 'Error al iniciar pago');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingExtension = false);
    }
  }

  void _showExtendTimeSheet() {
    final price60 = double.tryParse(_booking?['pricePerUnit']?.toString() ?? '') ?? 0.0;
    int selectedMinutes = _allowedExtensionMinutes >= 15 ? 15 : 0;
    String selectedMethod = 'qr'; // default: QR payment

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

          final available = [15, 30, 60].where((m) => m <= _allowedExtensionMinutes).toList();

          Widget minuteChip(int minutes) {
            final isSelected = selectedMinutes == minutes;
            final cost = ((price60 / 60) * minutes).ceil();
            return Expanded(
              child: GestureDetector(
                onTap: () => setSheetState(() => selectedMinutes = minutes),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected ? GardenColors.primary : (isDark ? GardenColors.darkBackground : GardenColors.lightBackground),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isSelected ? GardenColors.primary : (isDark ? GardenColors.darkBorder : GardenColors.lightBorder)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('+$minutes min', style: TextStyle(color: isSelected ? Colors.white : textColor, fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('Bs $cost', style: TextStyle(color: isSelected ? Colors.white70 : subtextColor, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            );
          }

          Widget methodChip(String method, String label, IconData icon) {
            final isSelected = selectedMethod == method;
            return Expanded(
              child: GestureDetector(
                onTap: () => setSheetState(() => selectedMethod = method),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? GardenColors.primary.withValues(alpha: 0.12) : (isDark ? GardenColors.darkBackground : GardenColors.lightBackground),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? GardenColors.primary : (isDark ? GardenColors.darkBorder : GardenColors.lightBorder), width: isSelected ? 1.5 : 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 16, color: isSelected ? GardenColors.primary : subtextColor),
                      const SizedBox(width: 6),
                      Text(label, style: TextStyle(color: isSelected ? GardenColors.primary : subtextColor, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            );
          }

          return Container(
            padding: EdgeInsets.only(left: 20, right: 20, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 28),
            decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Text('Ampliar tiempo del paseo', style: GardenText.h4.copyWith(color: textColor)),
                const SizedBox(height: 4),
                Text(
                  _allowedExtensionMinutes == 0
                      ? 'El cuidador no tiene disponibilidad en este momento.'
                      : 'Selecciona cuántos minutos adicionales necesitas.',
                  style: GardenText.metadata.copyWith(color: subtextColor),
                ),
                const SizedBox(height: 20),
                if (available.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
                    child: const Text('No hay tiempo disponible para ampliar (próximas reservas del cuidador o fin de bloque horario).', style: TextStyle(color: Colors.orange, fontSize: 13)),
                  )
                else ...[
                  Row(children: available.map(minuteChip).toList()),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: GardenColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Costo adicional', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                        Text('Bs ${((price60 / 60) * selectedMinutes).ceil()}', style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w900, fontSize: 18)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Método de pago', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(children: [
                    methodChip('qr', 'QR', Icons.qr_code_rounded),
                    methodChip('manual', 'Transferencia', Icons.account_balance_rounded),
                  ]),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: GardenButton(
                      label: 'Ir a pagar',
                      onPressed: selectedMinutes == 0 ? null : () {
                        Navigator.pop(ctx);
                        _requestExtensionPayment(selectedMinutes, selectedMethod);
                      },
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // --- VISTA: IN PROGRESS ---
  Widget _buildInProgressView() {
    return widget.role == 'CAREGIVER'
        ? _buildCaregiverInProgress()
        : _buildClientInProgress();
  }

  // ── CLIENTE: vista en servicio activo ────────────────────────────────────
  Widget _buildClientInProgress() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final isPaseo = _booking?['serviceType'] == 'PASEO';
    final timerStr = isPaseo
        ? '${_elapsed.inHours.toString().padLeft(2,'0')}:${(_elapsed.inMinutes%60).toString().padLeft(2,'0')}:${(_elapsed.inSeconds%60).toString().padLeft(2,'0')}'
        : '${_elapsed.inHours}h con tu cuidador';
    final incidents = (_booking?['serviceEvents'] as List<dynamic>? ?? [])
        .where((e) => e['type'] == 'INCIDENT').toList();
    final lastPhoto = _serviceEvents.isNotEmpty ? _serviceEvents.last : null;

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          // ── Hero ilustración del servicio ──────────────────────────────
          SliverToBoxAdapter(
            child: Stack(
              children: [
                Container(
                  height: 260,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isPaseo
                          ? [GardenColors.forest, const Color(0xFF1DB954)]
                          : [const Color(0xFFBF4B00), GardenColors.primary],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 8),
                        // Ilustración animada
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, _) {
                            return Transform.translate(
                              offset: Offset(0, _pulseController.value * -4),
                              child: isPaseo
                                  ? _WalkIllustration(petName: _booking?['petName'] ?? '')
                                  : _StayIllustration(petName: _booking?['petName'] ?? ''),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        // Live badge + timer
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _PulsingDot(),
                            const SizedBox(width: 6),
                            Text('EN VIVO  $timerStr',
                              style: const TextStyle(color: Colors.white, fontSize: 14,
                                  fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Botones de navegación (CLIENT: atrás→mis reservas, X→inicio)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8, left: 8,
                  child: GestureDetector(
                    onTap: () {
                      if (widget.role == 'CLIENT') {
                        context.go('/my-bookings-tab');
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    ),
                  ),
                ),
                if (widget.role == 'CLIENT')
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8, right: 8,
                    child: GestureDetector(
                      onTap: () => context.go('/marketplace'),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Alerta de incidente (si hay) ───────────────────────
                  if (incidents.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: GardenColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: GardenColors.warning.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: GardenColors.warning, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '⚠️ Tu cuidador reportó un incidente: "${incidents.last['description'] ?? ''}"',
                              style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Card mascota ────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: GardenColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(child: Text('🐾', style: TextStyle(fontSize: 22))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_booking?['petName'] as String? ?? '—',
                                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                              if ((_booking?['petBreed'] as String? ?? '').isNotEmpty)
                                Text(_booking!['petBreed'] as String,
                                  style: TextStyle(color: subtextColor, fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: GardenColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PulsingDot(size: 6, color: GardenColors.success),
                              const SizedBox(width: 5),
                              Text('Cuidado activo',
                                style: TextStyle(color: GardenColors.success, fontSize: 11, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Card cuidador (tappable → info completa) ────────────
                  GestureDetector(
                    onTap: _showServiceInfoSheet,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          GardenAvatar(
                            imageUrl: _booking?['caregiverPhoto'] as String?,
                            size: 44,
                            initials: (_booking?['caregiverName'] as String? ?? 'C')[0],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_booking?['caregiverName'] as String? ?? 'Cuidador',
                                  style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, color: GardenColors.star, size: 13),
                                    const SizedBox(width: 3),
                                    Text(
                                      _booking?['caregiverRating'] != null
                                          ? (_booking!['caregiverRating'] as num).toStringAsFixed(1)
                                          : 'Nuevo',
                                      style: TextStyle(color: subtextColor, fontSize: 12),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('· Tu cuidador',
                                      style: TextStyle(color: subtextColor, fontSize: 12)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: subtextColor),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── GPS: ver dónde está la mascota (solo PASEO) ──────────
                  if (_booking?['serviceType'] == 'PASEO') ...[
                    GardenButton(
                      label: '🗺️ Ver dónde está ${_booking?['petName'] ?? 'mi mascota'}',
                      color: GardenColors.success,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GpsTrackingScreen(
                            bookingId: widget.bookingId,
                            role: 'CLIENT',
                            petName: _booking?['petName'] ?? '',
                            token: _token,
                            petPhoto: _booking?['petPhoto'] as String?,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ── Ampliar tiempo ──────────────────────────────────────
                    OutlinedButton.icon(
                      onPressed: _loadingExtension ? null : _showExtendTimeSheet,
                      icon: _loadingExtension
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.primary))
                          : const Icon(Icons.add_alarm_rounded, size: 18),
                      label: Text(
                        _allowedExtensionMinutes == 0
                            ? 'Ampliar tiempo'
                            : 'Ampliar tiempo (hasta $_allowedExtensionMinutes min)',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GardenColors.primary,
                        side: const BorderSide(color: GardenColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size(double.infinity, 44),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Fotos del servicio (galería deslizable) ─────────────
                  if (_serviceEvents.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Fotos del servicio', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                        Text(
                          '${_serviceEvents.length} foto${_serviceEvents.length == 1 ? '' : 's'}',
                          style: TextStyle(color: subtextColor, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 200,
                      child: PageView.builder(
                        itemCount: _serviceEvents.length,
                        itemBuilder: (ctx, i) {
                          final photo = _serviceEvents[i];
                          return GestureDetector(
                            onTap: () => _showPhotoFullscreen(photo['photoUrl'] as String),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                children: [
                                  Image.network(
                                    fixImageUrl(photo['photoUrl'] as String),
                                    width: double.infinity,
                                    height: 200,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      height: 200,
                                      color: GardenColors.primary.withValues(alpha: 0.08),
                                      child: const Center(child: Icon(Icons.image_outlined, color: GardenColors.primary, size: 40)),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 10, right: 10,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.55),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_serviceEvents.length > 1) ...[
                                            Text('${i + 1}/${_serviceEvents.length}',
                                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                            const SizedBox(width: 6),
                                          ],
                                          const Icon(Icons.access_time, color: Colors.white, size: 11),
                                          const SizedBox(width: 4),
                                          Text(_formatEventTime(photo['timestamp'] as String? ?? ''),
                                            style: const TextStyle(color: Colors.white, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Cuando no hay fotos aún ─────────────────────────────
                  if (lastPhoto == null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      decoration: BoxDecoration(
                        color: GardenColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          const Text('📸', style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 12),
                          Expanded(child: Text('El cuidador te enviará fotos pronto',
                            style: TextStyle(color: subtextColor, fontSize: 13))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Botones sticky ──────────────────────────────────────────────────
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 14),
        decoration: BoxDecoration(
          color: surface,
          border: Border(top: BorderSide(color: borderColor)),
          boxShadow: GardenShadows.elevated,
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.info_outline_rounded, size: 18),
                label: const Text('Info'),
                onPressed: _showServiceInfoSheet,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: borderColor),
                  foregroundColor: textColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
                label: const Text('Foto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                onPressed: _requestPhotoFromCaregiver,
                style: ElevatedButton.styleFrom(
                  backgroundColor: GardenColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Colors.white),
                label: const Text('Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    bookingId: widget.bookingId,
                    otherPersonName: _booking?['caregiverName'] ?? 'Cuidador',
                    token: _token,
                  ),
                )),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GardenColors.secondary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── CUIDADOR: vista en servicio activo ───────────────────────────────────
  Widget _buildCaregiverInProgress() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final isHospedaje = _booking?['serviceType'] == 'HOSPEDAJE';
    final timerStr = isHospedaje
        ? '${_elapsed.inHours}h'
        : '${_elapsed.inHours.toString().padLeft(2,'0')}:${(_elapsed.inMinutes%60).toString().padLeft(2,'0')}:${(_elapsed.inSeconds%60).toString().padLeft(2,'0')}';
    final timerLabel = isHospedaje ? 'cuidando' : 'activo';

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header compacto con timer ────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isHospedaje
                      ? [const Color(0xFFBF4B00), GardenColors.primary]
                      : [GardenColors.forest, GardenColors.success],
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _PulsingDot(size: 7),
                            const SizedBox(width: 6),
                            Text(_booking?['petName'] as String? ?? 'Servicio activo',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                          ],
                        ),
                        Text('Dueño: ${_booking?['clientName'] ?? '—'}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                      ],
                    ),
                  ),
                  // Timer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(timerStr,
                          style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w900,
                            fontSize: isHospedaje ? 20 : 16, letterSpacing: 1)),
                        if (isHospedaje)
                          Text(timerLabel,
                            style: const TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Contenido scrollable ────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Acciones ─────────────────────────────────────────
                    Text('Acciones rápidas', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.35,
                      children: [
                        _ActionTile(
                          icon: Icons.camera_alt_rounded,
                          label: _isSendingPhoto ? 'Enviando...' : 'Enviar foto',
                          sublabel: 'Al dueño',
                          color: GardenColors.primary,
                          onTap: _isSendingPhoto ? () {} : _sendServicePhoto,
                          isDark: isDark,
                          loading: _isSendingPhoto,
                        ),
                        _ActionTile(
                          icon: Icons.chat_bubble_rounded,
                          label: 'Chat',
                          sublabel: 'Con el dueño',
                          color: GardenColors.secondary,
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              bookingId: widget.bookingId,
                              otherPersonName: _booking?['clientName'] ?? 'Dueño',
                              token: _token,
                            ),
                          )),
                          isDark: isDark,
                        ),
                        _ActionTile(
                          icon: Icons.warning_amber_rounded,
                          label: 'Reportar',
                          sublabel: 'Incidente',
                          color: GardenColors.warning,
                          onTap: _showReportDialog,
                          isDark: isDark,
                        ),
                        _ActionTile(
                          icon: Icons.check_circle_rounded,
                          label: 'Finalizar',
                          sublabel: 'Servicio',
                          color: GardenColors.success,
                          onTap: _showFinishConfirmation,
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    const SizedBox(height: 16),

                    // ── Fotos enviadas ────────────────────────────────────
                    Builder(builder: (_) {
                      final minPhotos = isHospedaje ? 4 : 2;
                      final photoCount = _serviceEvents.length;
                      final isPhotoMet = photoCount >= minPhotos;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isPhotoMet
                              ? GardenColors.success.withValues(alpha: 0.08)
                              : GardenColors.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isPhotoMet
                                ? GardenColors.success.withValues(alpha: 0.3)
                                : GardenColors.warning.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isPhotoMet ? Icons.check_circle_rounded : Icons.camera_alt_rounded,
                              color: isPhotoMet ? GardenColors.success : GardenColors.warning,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isPhotoMet
                                    ? 'Fotos enviadas: $photoCount/$minPhotos ✓'
                                    : 'Fotos enviadas: $photoCount/$minPhotos — faltan ${minPhotos - photoCount}',
                                style: TextStyle(
                                  color: isPhotoMet ? GardenColors.success : GardenColors.warning,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (_serviceEvents.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Fotos enviadas', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                          Text('${_serviceEvents.length}', style: TextStyle(color: subtextColor, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _serviceEvents.length,
                          itemBuilder: (_, i) {
                            final e = _serviceEvents[_serviceEvents.length - 1 - i];
                            final url = e['photoUrl']?.toString() ?? '';
                            if (url.isEmpty) return const SizedBox();
                            return GestureDetector(
                              onTap: () => _showPhotoFullscreen(url),
                              child: Container(
                                margin: const EdgeInsets.only(right: 10),
                                width: 120,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: GardenShadows.card,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.network(fixImageUrl(url), fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: GardenColors.primary.withValues(alpha: 0.1),
                                          child: const Icon(Icons.image_outlined, color: GardenColors.primary),
                                        )),
                                      Positioned(
                                        bottom: 5, left: 5,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.5),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Text(_formatEventTime(e['timestamp'] as String? ?? ''),
                                            style: const TextStyle(color: Colors.white, fontSize: 9)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ── Log de incidentes ─────────────────────────────────
                    Builder(builder: (_) {
                      final incidents = (_booking?['serviceEvents'] as List<dynamic>? ?? [])
                          .where((e) => e['type'] == 'INCIDENT').toList();
                      if (incidents.isEmpty) return const SizedBox();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Incidentes reportados',
                            style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 10),
                          ...incidents.map((inc) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: GardenColors.warning.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: GardenColors.warning, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(inc['description'] as String? ?? '—',
                                        style: TextStyle(color: textColor, fontSize: 13)),
                                      Text(_formatEventTime(inc['timestamp'] as String? ?? ''),
                                        style: TextStyle(color: subtextColor, fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )),
                          const SizedBox(height: 8),
                        ],
                      );
                    }),

                    // ── Badge blockchain compacto ─────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: GardenColors.polygon.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: GardenColors.polygon.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('⬡', style: TextStyle(color: GardenColors.polygon, fontSize: 13)),
                          const SizedBox(width: 6),
                          Text('Escrow activo · Pago protegido',
                            style: TextStyle(color: GardenColors.polygon, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Info del servicio (sheet para el cliente) ────────────────────────────
  void _showServiceInfoSheet() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: subtextColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Info del servicio',
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),

              // Cuidador
              _InfoSection(
                title: 'Tu cuidador',
                borderColor: borderColor,
                child: Row(
                  children: [
                    GardenAvatar(
                      imageUrl: _booking?['caregiverPhoto'] as String?,
                      size: 52,
                      initials: (_booking?['caregiverName'] as String? ?? 'C')[0],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_booking?['caregiverName'] as String? ?? '—',
                            style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 16)),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, color: GardenColors.star, size: 14),
                              const SizedBox(width: 3),
                              Text(
                                _booking?['caregiverRating'] != null
                                    ? '${(_booking!['caregiverRating'] as num).toStringAsFixed(1)} · Cuidador certificado'
                                    : 'Nuevo cuidador',
                                style: TextStyle(color: subtextColor, fontSize: 13),
                              ),
                            ],
                          ),
                          if (_booking?['caregiverPhone'] != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.phone_outlined, size: 13, color: subtextColor),
                                const SizedBox(width: 4),
                                Text(_booking!['caregiverPhone'] as String,
                                  style: TextStyle(color: subtextColor, fontSize: 12)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Mascota
              _InfoSection(
                title: 'Mascota',
                borderColor: borderColor,
                child: Column(
                  children: [
                    _InfoRow('Nombre', _booking?['petName'] as String? ?? '—', textColor, subtextColor),
                    if ((_booking?['petBreed'] as String? ?? '').isNotEmpty)
                      _InfoRow('Raza', _booking!['petBreed'] as String, textColor, subtextColor),
                    if (_booking?['petAge'] != null)
                      _InfoRow('Edad', '${_booking!['petAge']} años', textColor, subtextColor),
                    if ((_booking?['specialNeeds'] as String? ?? '').isNotEmpty)
                      _InfoRow('Necesidades', _booking!['specialNeeds'] as String, textColor, subtextColor),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Servicio
              _InfoSection(
                title: 'Reserva',
                borderColor: borderColor,
                child: Column(
                  children: [
                    _InfoRow('Tipo', _booking?['serviceType'] == 'PASEO' ? '🦮 Paseo' : '🏠 Hospedaje', textColor, subtextColor),
                    _InfoRow('Fecha', _booking?['walkDate'] ?? _booking?['startDate'] ?? '—', textColor, subtextColor),
                    if (_booking?['startTime'] != null)
                      _InfoRow('Hora', _booking!['startTime'] as String, textColor, subtextColor),
                    _InfoRow('Total', 'Bs ${_booking?['totalAmount'] ?? '—'}', textColor, subtextColor),
                    _InfoRow('Escrow', '⬡ Activo en Polygon', textColor, subtextColor),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers de UI ────────────────────────────────────────────────────────
  Widget _InfoRow(String label, String value, Color textColor, Color subtextColor) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: subtextColor, fontSize: 13)),
        Text(value, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    ),
  );

  void _showPhotoFullscreen(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(child: Image.network(fixImageUrl(url), fit: BoxFit.contain)),
            Positioned(
              top: 40, right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: 36, height: 36,
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatEventTime(String isoDate) {
    if (isoDate.isEmpty) return '';
    try {
      final date = DateTime.parse(isoDate).toLocal();
      return '${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}';
    } catch (_) { return ''; }
  }

  // --- VISTA: COMPLETED ---
  Widget _buildCompletedView() {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: GardenColors.success.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(child: Text('🏆', style: TextStyle(fontSize: 50))),
              ),
              const SizedBox(height: 32),
              Text('Servicio Completado',
                  style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Text('El servicio ha finalizado con éxito. Gracias por confiar en GARDEN para el cuidado de tu mascota.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subtextColor, fontSize: 15, height: 1.5)),
              const SizedBox(height: 48),
              GardenButton(
                label: widget.role == 'CAREGIVER' ? 'Volver al panel' : 'Volver a Mis Reservas',
                onPressed: () => context.go(
                  widget.role == 'CAREGIVER' ? '/caregiver/home' : '/marketplace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- LOGICA DE ACCIONES ---
  Future<void> _startService() async {
    // Para paseos en móvil, verificar permiso de ubicación antes de iniciar
    if (!kIsWeb && _booking?['serviceType'] == 'PASEO') {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Necesitas permitir el acceso a la ubicación para iniciar un paseo'),
              backgroundColor: GardenColors.error,
              action: SnackBarAction(
                label: 'Configuración',
                textColor: Colors.white,
                onPressed: Geolocator.openAppSettings,
              ),
            ),
          );
        }
        return;
      }
    }
    setState(() => _isProcessing = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/start'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadBooking();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Servicio iniciado! El escrow blockchain está activo.'), backgroundColor: GardenColors.success),
        );
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _sendServicePhoto() async {
    if (_isSendingPhoto) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: const Text('Cámara', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Galería'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    if (!mounted) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    if (!mounted) return;

    setState(() => _isSendingPhoto = true);

    try {
      final bytes = await picked.readAsBytes();
      final fileName = picked.name.isEmpty ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name;

      final uri = Uri.parse('$_baseUrl/bookings/${widget.bookingId}/event');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_token';
      request.fields['type'] = 'PHOTO';
      request.fields['description'] = 'Foto del servicio';
      request.files.add(http.MultipartFile.fromBytes(
        'photo', bytes,
        filename: fileName,
        contentType: MediaType('image', 'jpeg'),
      ));
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadBooking();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('📸 Foto enviada al dueño'), backgroundColor: GardenColors.success),
          );
        }
      } else {
        if (mounted) {
          final msg = data['error']?['message'] as String? ?? 'Error al enviar la foto';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: GardenColors.error),
          );
        }
      }
    } catch (e) {
      debugPrint('Error sending photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo enviar la foto. Intenta de nuevo.'),
            backgroundColor: GardenColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingPhoto = false);
    }
  }

  Future<void> _requestPhotoFromCaregiver() async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/${widget.bookingId}/messages'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'message': '📸 ¿Puedes enviarme una foto de mi mascota?'}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Solicitud enviada al cuidador'),
            backgroundColor: GardenColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error requesting photo: $e');
    }
  }

  void _showFinishConfirmation() {
    final isHospedaje = _booking?['serviceType'] == 'HOSPEDAJE';
    final minPhotos = isHospedaje ? 4 : 2;
    if (_serviceEvents.length < minPhotos) {
      final remaining = minPhotos - _serviceEvents.length;
      final isDark = themeNotifier.isDark;
      final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
      final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
      final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
      showModalBottomSheet(
        context: context,
        backgroundColor: bg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).padding.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: subtextColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: GardenColors.warning.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt_rounded, color: GardenColors.warning, size: 36),
              ),
              const SizedBox(height: 16),
              Text('Faltan fotos', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(
                'Debes enviar al menos $minPhotos fotos para finalizar este servicio.\nTe faltan $remaining foto${remaining > 1 ? 's' : ''} más.',
                textAlign: TextAlign.center,
                style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 28),
              GardenButton(
                label: '📸 Enviar foto ahora',
                color: GardenColors.primary,
                onPressed: () {
                  Navigator.pop(ctx);
                  _sendServicePhoto();
                },
              ),
            ],
          ),
        ),
      );
      return;
    }

    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).padding.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: subtextColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: GardenColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: GardenColors.success, size: 36),
            ),
            const SizedBox(height: 16),
            Text('¿Finalizar servicio?',
              style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              'El dueño recibirá una encuesta de satisfacción.\nEl smart contract liberará el pago según la calificación.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: subtextColor.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Cancelar', style: TextStyle(color: subtextColor)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GardenColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _concludeService();
                    },
                    child: const Text('Sí, finalizar',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _concludeService() async {
    setState(() => _isProcessing = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/conclude'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'rating': 5}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadBooking();
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showReportDialog() {
    final reportController = TextEditingController();
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final fieldBg = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: subtextColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Título
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: GardenColors.warning.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: GardenColors.warning, size: 22),
                ),
                const SizedBox(width: 12),
                Text('Reportar incidente',
                  style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            Text('El dueño será notificado inmediatamente',
              style: TextStyle(color: subtextColor, fontSize: 13)),
            const SizedBox(height: 20),

            // Campo de descripción
            Text('¿Qué ocurrió?', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: reportController,
              maxLines: 4,
              autofocus: true,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                hintText: 'Describe el incidente con el mayor detalle posible...',
                hintStyle: TextStyle(color: subtextColor),
                filled: true,
                fillColor: fieldBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 20),

            // Botones
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: subtextColor.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Cancelar', style: TextStyle(color: subtextColor)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GardenColors.warning,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final desc = reportController.text.trim();
                      if (desc.isEmpty) return;
                      Navigator.pop(ctx);
                      try {
                        final res = await http.post(
                          Uri.parse('$_baseUrl/bookings/${widget.bookingId}/event'),
                          headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
                          body: jsonEncode({'type': 'INCIDENT', 'description': desc}),
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(res.statusCode == 200
                                ? '⚠️ Incidente reportado. El dueño fue notificado.'
                                : 'Error al enviar el reporte. Intenta de nuevo.'),
                            backgroundColor: res.statusCode == 200 ? GardenColors.warning : GardenColors.error,
                            duration: const Duration(seconds: 4),
                          ));
                        }
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Sin conexión. Verifica tu internet.'),
                            backgroundColor: GardenColors.error,
                          ));
                        }
                      }
                    },
                    child: const Text('Enviar reporte', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSatisfactionSurvey() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final canSubmit = _surveyRating > 0 && _surveyCommentController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text('🐾', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 24),
            Text('¿Qué tal estuvo el servicio?',
                style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.w900),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Tu calificación es clave para que el Smart Contract libere el pago al cuidador.',
                style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 48),

            // Selector de estrellas gigante con feedback visual
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final ratingValue = index + 1;
                final isSelected = ratingValue <= _surveyRating;
                return GestureDetector(
                  onTap: () => setState(() => _surveyRating = ratingValue),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1.0, end: isSelected ? 1.2 : 1.0),
                    duration: const Duration(milliseconds: 200),
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: isSelected ? GardenColors.star : subtextColor.withOpacity(0.3),
                            size: 52,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
            ),

            if (_surveyRating > 0) ...[
              const SizedBox(height: 16),
              Text(
                ['', 'Terrible', 'Malo', 'Normal', 'Bueno', '¡Excelente!'][_surveyRating],
                style: const TextStyle(color: GardenColors.star, fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ],

            const SizedBox(height: 48),

            // Caja de comentarios Premium
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
                boxShadow: GardenShadows.card,
              ),
              child: TextField(
                controller: _surveyCommentController,
                maxLines: 4,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: 'Cuéntanos un poco más... (requerido)',
                  hintStyle: TextStyle(color: subtextColor.withOpacity(0.5)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(20),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Feedback visual del Smart Contract
            if (_surveyRating > 0)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (_surveyRating >= 3 ? GardenColors.success : GardenColors.error).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (_surveyRating >= 3 ? GardenColors.success : GardenColors.error).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _surveyRating >= 3 ? Icons.lock_open_rounded : Icons.lock_clock_rounded,
                      color: _surveyRating >= 3 ? GardenColors.success : GardenColors.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _surveyRating >= 3
                            ? 'El smart contract liberará el pago automáticamente.'
                            : 'El pago se retendrá para revisión manual por seguridad.',
                        style: TextStyle(
                          color: _surveyRating >= 3 ? GardenColors.success : GardenColors.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 40),
            GardenButton(
              label: _isProcessing ? 'Procesando en Blockchain...' : 'Confirmar calificación',
              loading: _isProcessing,
              onPressed: canSubmit ? () => _submitRating(_surveyRating, _surveyCommentController.text) : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitRating(int rating, String comment) async {
    debugPrint('SERVICE: _submitRating starting for ${widget.bookingId} with rating $rating. Comment: $comment');
    setState(() => _isProcessing = true);
    try {
      debugPrint('SERVICE: Sending confirmation to ${widget.bookingId} with rating $rating...');
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/confirm-receipt'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'rating': rating, 'comment': comment}),
      );
      debugPrint('SERVICE: Confirmation response ${response.statusCode}: ${response.body}');
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadBooking();
        if (!mounted) return;

        if (rating < 3) {
          debugPrint('SERVICE: Rating $rating < 3. Opening dispute flow for ${widget.bookingId}');
          // Abrir disputa
          context.push(
            '/dispute/${widget.bookingId}',
            extra: {'role': 'CLIENT'},
          );
          return;
        }

        _showSmartContractDialog(rating);
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSmartContractDialog(int rating) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: GlassBox(
          borderRadius: BorderRadius.circular(24),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: (rating >= 3 ? GardenColors.success : GardenColors.warning).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(rating >= 3 ? '✅' : '⏳', style: const TextStyle(fontSize: 40)),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                rating >= 3 ? '¡Pago Liberado!' : 'Pago en Revisión',
                textAlign: TextAlign.center,
                style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Text(
                rating >= 3
                    ? 'El Smart Contract en Polygon Amoy ha liberado los fondos al cuidador exitosamente.'
                    : 'Debido a la calificación, un administrador revisará el caso antes de liberar los fondos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 32),
              const GardenBadge(text: '⬡ Polygon Amoy Network', color: GardenColors.polygon),
              const SizedBox(height: 32),
              GardenButton(
                label: 'Finalizar',
                onPressed: () {
                  Navigator.pop(context);
                  context.go(
                    widget.role == 'CAREGIVER' ? '/caregiver/home' : '/marketplace',
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// --- HELPERS LOCALES PARA EL DISEÑO ---

class _PulsingDot extends StatefulWidget {
  final double size;
  final Color color;
  const _PulsingDot({this.size = 8, this.color = Colors.white});
  @override
  _PulsingDotState createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: widget.size, height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class _WalkIllustration extends StatelessWidget {
  final String petName;
  const _WalkIllustration({required this.petName});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🦮', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 4),
        Text(petName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
      ],
    );
  }
}

class _StayIllustration extends StatelessWidget {
  final String petName;
  const _StayIllustration({required this.petName});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🏠', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 4),
        Text(petName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;
  final bool isDark;
  final bool loading;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
    required this.isDark,
    this.loading = false,
  });
  @override
  Widget build(BuildContext context) {
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Opacity(
        opacity: loading ? 0.7 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
            boxShadow: GardenShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2, color: color),
                      )
                    : Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(label,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
              Text(sublabel,
                style: TextStyle(color: subtextColor, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final Widget child;
  final Color borderColor;
  const _InfoSection({required this.title, required this.child, required this.borderColor});
  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
            style: TextStyle(
              color: subtextColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            )),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PANTALLA DE PAGO DE EXTENSIÓN DE PASEO
// Flujo igual al de pago de reserva:
//   QR → muestra imagen → "Ya realicé el pago" → pantalla espera
//   Manual → directo a pantalla espera
//   Pantalla espera → polling /bookings/:id hasta EXTENSION_CONFIRMED → éxito
// ─────────────────────────────────────────────────────────────────────────────

class _WalkExtensionPaymentScreen extends StatefulWidget {
  final String bookingId;
  final String token;
  final String baseUrl;
  final String extensionId; // ID único de esta extensión — el polling lo valida
  final int additionalMinutes;
  final double extraAmount;
  final String? qrImageUrl;
  final String? qrExpiresAt;
  final String method; // 'qr' | 'manual'
  final Future<void> Function() onConfirmed;

  const _WalkExtensionPaymentScreen({
    required this.bookingId,
    required this.token,
    required this.baseUrl,
    required this.extensionId,
    required this.additionalMinutes,
    required this.extraAmount,
    required this.method,
    required this.onConfirmed,
    this.qrImageUrl,
    this.qrExpiresAt,
  });

  @override
  State<_WalkExtensionPaymentScreen> createState() => _WalkExtensionPaymentScreenState();
}

class _WalkExtensionPaymentScreenState extends State<_WalkExtensionPaymentScreen> {
  // false = mostrando QR/instrucciones | true = esperando confirmación
  bool _waitingConfirmation = false;
  bool _confirmed = false;
  Timer? _countdownTimer;
  Timer? _pollTimer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Iniciar countdown del QR
    if (widget.method == 'qr' && widget.qrExpiresAt != null) {
      final expiresAt = DateTime.tryParse(widget.qrExpiresAt!);
      if (expiresAt != null) {
        _remaining = expiresAt.difference(DateTime.now());
        if (_remaining.isNegative) _remaining = Duration.zero;
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() {
            _remaining = _remaining.inSeconds > 0 ? _remaining - const Duration(seconds: 1) : Duration.zero;
          });
        });
      }
    }
    // Manual: ir directo a espera
    if (widget.method == 'manual') {
      _waitingConfirmation = true;
      _startPolling();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// El usuario ya escaneó el QR — pasar a pantalla de espera y comenzar polling
  void _onPaymentDone() {
    setState(() => _waitingConfirmation = true);
    _startPolling();
  }

  /// Consulta el booking cada 10s; cuando serviceEvents tiene EXTENSION_CONFIRMED → éxito
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || _confirmed) return;
      try {
        final response = await http.get(
          Uri.parse('${widget.baseUrl}/bookings/${widget.bookingId}'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (response.statusCode != 200) return;
        final data = jsonDecode(response.body);
        if (data['success'] != true) return;
        final events = (data['data']?['serviceEvents'] as List? ?? []);
        final isConfirmed = events.any((e) =>
            e is Map &&
            e['type'] == 'EXTENSION_CONFIRMED' &&
            e['extensionId'] == widget.extensionId);
        if (isConfirmed && mounted) {
          _pollTimer?.cancel();
          setState(() => _confirmed = true);
          await widget.onConfirmed();
          if (mounted) {
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) Navigator.pop(context);
          }
        }
      } catch (_) {}
    });
  }

  String _formatCountdown(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;

    return Scaffold(
      backgroundColor: bg,
      appBar: _confirmed || _waitingConfirmation ? null : AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Pagar extensión', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: themeNotifier,
          builder: (context, _) {
            if (_confirmed) return _buildSuccessView();
            if (_waitingConfirmation) return _buildWaitingView();
            return _buildQrView();
          },
        ),
      ),
    );
  }

  // ── Vista QR ─────────────────────────────────────────────────────────────
  Widget _buildQrView() {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Resumen
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Tiempo adicional', style: TextStyle(color: subtextColor, fontSize: 14)),
                  Text('+${widget.additionalMinutes} min', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                ]),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Total a pagar', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 16)),
                  Text('Bs ${widget.extraAmount.toStringAsFixed(0)}', style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w900, fontSize: 22)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Countdown badge
          if (_remaining.inSeconds > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _remaining.inSeconds < 60 ? GardenColors.error.withValues(alpha: 0.12) : GardenColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'QR válido por: ${_formatCountdown(_remaining)}',
                style: TextStyle(color: _remaining.inSeconds < 60 ? GardenColors.error : GardenColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: GardenColors.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: const Text('QR expirado', style: TextStyle(color: GardenColors.error, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          const SizedBox(height: 24),

          // QR image
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: widget.qrImageUrl != null && widget.qrImageUrl!.isNotEmpty
                ? Image.network(widget.qrImageUrl!, width: 230, height: 230, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 230, height: 230,
                        child: Center(child: Icon(Icons.qr_code_rounded, size: 90, color: GardenColors.primary))))
                : const SizedBox(width: 230, height: 230,
                    child: Center(child: Icon(Icons.qr_code_rounded, size: 90, color: GardenColors.primary))),
          ),
          const SizedBox(height: 20),
          Text(
            'Escanea este código con tu app bancaria\no Tigo Money para pagar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: GardenButton(
              label: 'Ya realicé el pago',
              onPressed: _remaining.inSeconds == 0 ? null : _onPaymentDone,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: TextStyle(color: subtextColor)),
          ),
        ],
      ),
    );
  }

  // ── Vista de espera (polling) ─────────────────────────────────────────────
  Widget _buildWaitingView() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Container(
      color: bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 96, height: 96,
                decoration: BoxDecoration(
                  color: GardenColors.warning.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: GardenColors.warning.withValues(alpha: 0.4), width: 3),
                ),
                child: const Icon(Icons.access_time_rounded, color: GardenColors.warning, size: 48),
              ),
            ),
            const SizedBox(height: 28),
            Text('Pago en revisión', style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 24)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: GardenColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3)),
              ),
              child: const Text('Verificando pago...', style: TextStyle(color: GardenColors.warning, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const SizedBox(height: 20),
            Text(
              widget.method == 'qr'
                  ? 'Tu pago QR está siendo verificado. Los minutos adicionales se agregarán automáticamente cuando se confirme.'
                  : 'Tu solicitud de transferencia fue enviada al administrador. Los minutos se agregarán cuando sea aprobada.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtextColor, fontSize: 15, height: 1.6),
            ),
            const SizedBox(height: 32),

            // Resumen
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: borderColor)),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Tiempo adicional', style: TextStyle(color: subtextColor, fontSize: 14)),
                    Text('+${widget.additionalMinutes} min', style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Monto pagado', style: TextStyle(color: subtextColor, fontSize: 14)),
                    Text('Bs ${widget.extraAmount.toStringAsFixed(0)}', style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w900, fontSize: 18)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Pasos
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¿Qué sigue?', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 16),
                  _waitStep('1', widget.method == 'qr' ? 'GARDEN verifica tu pago QR' : 'El admin aprueba tu transferencia', GardenColors.warning, textColor),
                  const SizedBox(height: 12),
                  _waitStep('2', 'Los minutos se agregan al paseo', GardenColors.primary, textColor),
                  const SizedBox(height: 12),
                  _waitStep('3', 'Tu cuidador recibe la notificación', Colors.green, textColor),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: GardenColors.primary),
            ),
            const SizedBox(height: 8),
            Text('Verificando automáticamente...', style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Volver al servicio', style: TextStyle(color: subtextColor, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _waitStep(String num, String text, Color color, Color textColor) {
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Center(child: Text(num, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 14))),
      ],
    );
  }

  // ── Vista de éxito ────────────────────────────────────────────────────────
  Widget _buildSuccessView() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;

    return Container(
      color: bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 96, height: 96,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.green.withValues(alpha: 0.4), width: 3),
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.green, size: 52),
                ),
              ),
              const SizedBox(height: 28),
              Text('¡Extensión confirmada!', style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 24)),
              const SizedBox(height: 12),
              Text(
                '+${widget.additionalMinutes} minutos agregados al paseo.\nTu cuidador ha sido notificado.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600, fontSize: 16, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

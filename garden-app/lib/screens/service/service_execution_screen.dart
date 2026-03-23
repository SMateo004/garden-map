import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';
import 'dart:html' as html;
import '../../theme/garden_theme.dart';
import '../chat/chat_screen.dart';

class ServiceExecutionScreen extends StatefulWidget {
  final String bookingId;
  final String role; // 'CAREGIVER' o 'CLIENT'
  const ServiceExecutionScreen({Key? key, required this.bookingId, required this.role}) : super(key: key);

  @override
  State<ServiceExecutionScreen> createState() => _ServiceExecutionScreenState();
}

class _ServiceExecutionScreenState extends State<ServiceExecutionScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _booking;
  bool _isLoading = true;
  bool _isProcessing = false;
  String _token = '';
  String _userId = '';
  late AnimationController _pulseController;
  Timer? _serviceTimer;
  Timer? _photoRefreshTimer;
  Duration _elapsed = Duration.zero;
  List<Map<String, dynamic>> _serviceEvents = [];

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');
  bool get _alreadyRated => _booking?['ownerRating'] != null;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _loadInitialData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _serviceTimer?.cancel();
    _photoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await _loadBooking();
  }

  Future<void> _loadBooking() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('access_token') ?? '';
      _userId = prefs.getString('user_id') ?? '';
      
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
          if (widget.role == 'CLIENT' && _photoRefreshTimer == null) {
            _photoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadBooking());
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

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
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
                Text('Lista para iniciar', style: TextStyle(color: GardenColors.success, fontWeight: FontWeight.w700, fontSize: 15)),
                const Spacer(),
                GardenBadge(text: '⬡ Escrow listo', color: GardenColors.polygon, fontSize: 11),
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

  // --- VISTA: IN PROGRESS ---
  Widget _buildInProgressView() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final timerStr = '${_elapsed.inHours.toString().padLeft(2,'0')}:${(_elapsed.inMinutes%60).toString().padLeft(2,'0')}:${(_elapsed.inSeconds%60).toString().padLeft(2,'0')}';

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          // SliverAppBar con header animado
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: GardenColors.success,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A9954), GardenColors.success],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      // Indicador pulsante
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _PulsingDot(),
                          const SizedBox(width: 8),
                          const Text('EN CURSO', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Timer grande
                      Text(timerStr,
                        style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      const SizedBox(height: 8),
                      // Badge blockchain
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('⬡ Escrow activo en Polygon',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info compacta de la reserva
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        const Text('🐾', style: TextStyle(fontSize: 28)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_booking?['petName'] as String? ?? '—',
                                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 16)),
                              Text(_booking?['clientName'] as String? ?? '—',
                                style: TextStyle(color: subtextColor, fontSize: 13)),
                            ],
                          ),
                        ),
                        Text('Bs ${_booking?['totalAmount'] ?? '—'}',
                          style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w800, fontSize: 16)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Acciones del CUIDADOR
                  if (widget.role == 'CAREGIVER') ...[
                    Text('Acciones', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.4,
                      children: [
                        GestureDetector(
                          onTap: _sendServicePhoto,
                          child: _actionButton('Enviar foto', 'Al dueño', Icons.camera_alt_outlined, GardenColors.primary),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChatScreen(bookingId: widget.bookingId, otherPersonName: _booking?['clientName'] ?? 'Dueño'),
                          )),
                          child: _actionButton('Chat', 'Con el dueño', Icons.chat_outlined, GardenColors.secondary),
                        ),
                        GestureDetector(
                          onTap: _showReportDialog,
                          child: _actionButton('Reportar', 'Incidente', Icons.warning_amber_outlined, GardenColors.warning),
                        ),
                        GestureDetector(
                          onTap: _showFinishConfirmation,
                          child: _actionButton('Finalizar', 'Terminar', Icons.check_circle_outline, GardenColors.success),
                        ),
                      ],
                    ),
                  ],

                  // Vista del CLIENTE
                  if (widget.role == 'CLIENT') ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: GardenColors.success.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: GardenColors.success.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.pets, color: GardenColors.success, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Tu mascota está siendo cuidada 🐾',
                                  style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                                Text('El cuidador te enviará fotos durante el servicio',
                                  style: TextStyle(color: subtextColor, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GardenButton(
                      label: 'Chat con el cuidador',
                      icon: Icons.chat_outlined,
                      outline: true,
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ChatScreen(bookingId: widget.bookingId, otherPersonName: _booking?['caregiverName'] ?? 'Cuidador'),
                      )),
                    ),
                  ],

                  // Fotos enviadas
                  if (_serviceEvents.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Fotos del servicio', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                        Text('${_serviceEvents.length} foto${_serviceEvents.length > 1 ? 's' : ''}',
                          style: TextStyle(color: subtextColor, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 140,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _serviceEvents.length,
                        itemBuilder: (context, index) {
                          final event = _serviceEvents[_serviceEvents.length - 1 - index]; // más reciente primero
                          final photoUrl = event['photoUrl']?.toString() ?? '';
                          if (photoUrl.isEmpty) return const SizedBox();
                          return GestureDetector(
                            onTap: () => _showPhotoFullscreen(photoUrl),
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 140,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: GardenShadows.card,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(photoUrl, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: GardenColors.primary.withOpacity(0.1),
                                        child: const Icon(Icons.image_outlined, color: GardenColors.primary),
                                      )),
                                    // Timestamp
                                    Positioned(
                                      bottom: 6, left: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          _formatEventTime(event['timestamp'] as String? ?? ''),
                                          style: const TextStyle(color: Colors.white, fontSize: 10),
                                        ),
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
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPhotoFullscreen(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(child: Image.network(url, fit: BoxFit.contain)),
            Positioned(
              top: 40, right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
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

  Widget _buildTimeline() {
    final events = _booking?['serviceEvents'] as List<dynamic>? ?? [];
    if (events.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Resumen de actividad', style: TextStyle(color: themeNotifier.isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: events.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (ctx, i) {
              final e = events[i];
              if (e['type'] == 'PHOTO') {
                final url = e['photoUrl']?.toString() ?? '';
                if (url.isEmpty) return const SizedBox();
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    url,
                    width: 100, height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                );
              }
              return Container(width: 100, decoration: BoxDecoration(color: GardenColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(e['type'] == 'START' ? Icons.play_arrow_rounded : Icons.info_outline));
            },
          ),
        ),
      ],
    );
  }

  // --- VISTA: COMPLETED ---
  Widget _buildCompletedView() {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
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
                label: 'Volver a Mis Reservas',
                onPressed: () => context.go('/marketplace'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- LOGICA DE ACCIONES ---
  Future<void> _startService() async {
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
    final input = html.FileUploadInputElement();
    input.accept = 'image/*';
    input.setAttribute('capture', 'environment');
    input.click();
    await input.onChange.first;
    final file = input.files?.first;
    if (file == null) return;

    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    final bytes = Uint8List.fromList(reader.result as List<int>);

    try {
      final uri = Uri.parse('$_baseUrl/bookings/${widget.bookingId}/event');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_token';
      request.fields['type'] = 'PHOTO';
      request.fields['description'] = 'Foto del servicio';
      request.files.add(http.MultipartFile.fromBytes(
        'photo', bytes,
        filename: 'service-${DateTime.now().millisecondsSinceEpoch}.jpg',
        contentType: MediaType.parse('image/jpeg'),
      ));
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadBooking();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📸 Foto enviada al dueño'), backgroundColor: GardenColors.success),
        );
      }
    } catch (e) {
      debugPrint('Error sending photo: $e');
    }
  }

  void _showFinishConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: themeNotifier.isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
        title: const Text('¿Finalizar servicio?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          'Al finalizar, el dueño recibirá una encuesta de satisfacción. El smart contract liberará el pago según la calificación.',
          style: TextStyle(color: themeNotifier.isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.success),
            onPressed: () {
              Navigator.pop(ctx);
              _concludeService();
            },
            child: const Text('Sí, finalizar', style: TextStyle(color: Colors.white)),
          ),
        ],
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: themeNotifier.isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
        title: const Text('Reportar incidente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Describe el incidente o problema:', style: TextStyle(color: themeNotifier.isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: reportController,
              maxLines: 4,
              style: TextStyle(color: themeNotifier.isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary),
              decoration: InputDecoration(
                hintText: 'Describe qué ocurrió...',
                hintStyle: TextStyle(color: themeNotifier.isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
                filled: true,
                fillColor: themeNotifier.isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.warning),
            onPressed: () async {
              Navigator.pop(ctx);
              await http.post(
                Uri.parse('$_baseUrl/bookings/${widget.bookingId}/event'),
                headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
                body: jsonEncode({'type': 'INCIDENT', 'description': reportController.text.trim()}),
              );
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reporte enviado al equipo GARDEN'), backgroundColor: GardenColors.warning));
            },
            child: const Text('Enviar reporte', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildSatisfactionSurvey() {
    int selectedRating = 0;
    final commentController = TextEditingController();

    return StatefulBuilder(
      builder: (context, setSurvey) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

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
                    final isSelected = ratingValue <= selectedRating;
                    return GestureDetector(
                      onTap: () => setSurvey(() => selectedRating = ratingValue),
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

                if (selectedRating > 0) ...[
                  const SizedBox(height: 16),
                  Text(
                    ['', 'Terrible', 'Malo', 'Normal', 'Bueno', '¡Excelente!'][selectedRating],
                    style: TextStyle(color: GardenColors.star, fontWeight: FontWeight.w800, fontSize: 18),
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
                    controller: commentController,
                    maxLines: 4,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Cuéntanos un poco más...',
                      hintStyle: TextStyle(color: subtextColor.withOpacity(0.5)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(20),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Feedback visual del Smart Contract
                if (selectedRating > 0)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: (selectedRating >= 3 ? GardenColors.success : GardenColors.error).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (selectedRating >= 3 ? GardenColors.success : GardenColors.error).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedRating >= 3 ? Icons.lock_open_rounded : Icons.lock_clock_rounded,
                          color: selectedRating >= 3 ? GardenColors.success : GardenColors.error,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            selectedRating >= 3
                                ? 'El smart contract liberará el pago automáticamente.'
                                : 'El pago se retendrá para revisión manual por seguridad.',
                            style: TextStyle(
                              color: selectedRating >= 3 ? GardenColors.success : GardenColors.error,
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
                  onPressed: selectedRating == 0 ? null : () => _submitRating(selectedRating, commentController.text),
                ),
              ],
            ),
          ),
        );
      },
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
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
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
              GardenBadge(text: '⬡ Polygon Amoy Network', color: GardenColors.polygon),
              const SizedBox(height: 32),
              GardenButton(
                label: 'Finalizar',
                onPressed: () {
                  Navigator.pop(ctx);
                  context.go('/marketplace');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton(String title, String subtitle, IconData icon, Color color) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
          Text(subtitle, style: TextStyle(color: subtextColor, fontSize: 11)),
        ],
      ),
    );
  }
}

// --- HELPERS LOCALES PARA EL DISEÑO ---

class _PulsingDot extends StatefulWidget {
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
      child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
    );
  }
}

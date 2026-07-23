import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/slide_to_confirm_button.dart';
import '../chat/chat_screen.dart';
import 'gps_tracking_screen.dart';
import 'meet_and_greet_screen.dart';
import '../../services/gps_tracking_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_state.dart';
import '../../services/garden_live_activity.dart';
import '../../widgets/garden_loading_indicator.dart';

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
  Timer? _caregiverRefreshTimer;
  Duration _elapsed = Duration.zero;
  List<Map<String, dynamic>> _serviceEvents = [];

  // Confirmación del cuidador cuando el dueño marca "servicio terminado"
  // (clientMarkedEndAt) — el diálogo bloqueante solo debe mostrarse una vez
  // por cada marcado del dueño, no en loop cada vez que se refresca el booking.
  final Set<String> _respondedEndMarks = {};
  bool _endConfirmDialogShowing = false;
  bool _isRespondingToEndConfirm = false;

  // Survey state — must be class-level to survive parent rebuilds (e.g. themeNotifier)
  int _surveyRating = 0;
  final TextEditingController _surveyCommentController = TextEditingController();
  // Cualidades del cuidador que el dueño puede marcar al calificar — selección
  // múltiple, ninguna obligatoria. Se envían junto con rating/comment.
  final List<String> _surveySkillTags = [];
  static const List<String> _caregiverSkillOptions = [
    'Amable', 'Puntual', 'Responsable', 'Respetuoso', 'Buena comunicación',
  ];
  // Mensajes de validación mostrados cuando el usuario intenta enviar sin
  // completar los campos obligatorios (antes fallaba en silencio con el botón
  // simplemente deshabilitado, sin explicar por qué).
  bool _surveyShowValidationError = false;
  bool _caregiverSurveyShowValidationError = false;

  // Caregiver rates owner — post-service
  int _caregiverSurveyRating = 0;
  final TextEditingController _caregiverCommentController = TextEditingController();
  bool _isSubmittingCaregiverRating = false;

  // Extension state (PASEO + HOSPEDAJE)
  int _allowedExtensionMinutes = 0;
  int _allowedExtensionDays = 0;
  double _hospedajePricePerDay = 0;
  bool _loadingExtension = false;
  bool _markingEnd = false;

  // Photo/video upload state
  bool _isSendingPhoto = false;
  bool _isSendingVideo = false;

  // Photo reminder timers (caregiver side) — persisted to SharedPreferences so
  // app restarts don't re-trigger banners already shown in the same service session.
  bool _reminder1Shown = false;
  bool _reminder2Shown = false;
  bool _reminder3Shown = false;
  bool _remindersLoaded = false;

  // Emergency state (client side)
  String? _caregiverPhone; // populated from booking response

  // GPS monitoring (PASEO only)
  StreamSubscription<ServiceStatus>? _gpsStatusSub;
  bool _gpsDialogShown = false;

  // GPS live info — client side (PASEO, IN_PROGRESS)
  // Nota: solo indicamos si hay señal GPS reciente y cuándo fue la última
  // actualización — no se expone la cantidad de puntos ni la distancia
  // recorrida en esta pantalla (eso queda en la pantalla de mapa dedicada).
  bool _gpsHasSignal = false;
  DateTime? _gpsLastPoint;
  Timer? _gpsInfoTimer;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  bool get _alreadyRated => _booking?['ownerRating'] != null;

  // Setting admin `cardPaymentEnabled` para el chip "Tarjeta" en los sheets
  // de ampliación de tiempo/hospedaje — fail-closed (false) si el fetch
  // falla, igual que en payment_screen.dart.
  bool _cardPaymentEnabled = false;

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
    _loadCardPaymentSetting();
  }

  Future<void> _loadCardPaymentSetting() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/settings'));
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() => _cardPaymentEnabled = data['data']?['cardPaymentEnabled'] == true);
      }
    } catch (_) {
      // Fallo de red → se queda en false (fail-closed).
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _serviceTimer?.cancel();
    _photoRefreshTimer?.cancel();
    _caregiverRefreshTimer?.cancel();
    _surveyCommentController.dispose();
    _caregiverCommentController.dispose();
    _gpsStatusSub?.cancel();
    _gpsInfoTimer?.cancel();
    GardenLiveActivity.instance.endActivity();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await _loadReminderFlags();
    await _loadBooking();
  }

  Future<void> _loadReminderFlags() async {
    if (widget.role != 'CAREGIVER') return;
    final prefs = await SharedPreferences.getInstance();
    final id = widget.bookingId;
    _reminder1Shown = prefs.getBool('photo_reminder1_$id') ?? false;
    _reminder2Shown = prefs.getBool('photo_reminder2_$id') ?? false;
    _reminder3Shown = prefs.getBool('photo_reminder3_$id') ?? false;
    _remindersLoaded = true;
  }

  Future<void> _persistReminderFlag(int number) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('photo_reminder${number}_${widget.bookingId}', true);
  }

  Future<void> _loadBooking() async {
    try {
      _token = AuthState.token;
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
      // Este refresco corre cada 10s vía Timer.periodic mientras el servicio
      // está activo (ver más abajo) — si el usuario sale de la pantalla justo
      // cuando esta respuesta llega, el widget ya está disposed y setState()
      // crashearía. dispose() cancela el timer pero no un request en vuelo.
      if (!mounted) return;
      if (data['success'] == true) {
        setState(() {
          _booking = data['data'];
          _caregiverPhone = data['data']?['caregiverPhone'] as String?;
          _serviceEvents = (_booking?['serviceEvents'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((e) =>
                  (e['photoUrl'] != null && e['photoUrl'].toString().isNotEmpty) ||
                  (e['videoUrl'] != null && e['videoUrl'].toString().isNotEmpty))
              .toList();
          _isLoading = false;
        });
        
        if (_booking?['status'] == 'IN_PROGRESS') {
          if (_serviceTimer == null || !_serviceTimer!.isActive) {
            // First time — start the ticker and calibrate from server timestamp.
            _startTimer();
          } else {
            // Timer already running — only recalibrate elapsed from server to prevent drift
            // (respetando pausa por emergencia, ver _computeElapsedNow).
            setState(() => _elapsed = _computeElapsedNow());
          }
          // Start GPS monitoring for caregiver on PASEO
          if (widget.role == 'CAREGIVER' && _booking?['serviceType'] == 'PASEO') {
            _startGpsMonitoring();
          }
          if (widget.role == 'CLIENT' && _photoRefreshTimer == null) {
            _photoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadBooking());
          }
          // Refresco periódico para el cuidador — antes esta pantalla solo
          // cargaba el booking una vez para el cuidador y nunca más, así que
          // si el dueño marcaba "servicio terminado" (clientMarkedEndAt) o se
          // resolvía una emergencia desde el panel de admin, el cuidador no se
          // enteraba hasta salir y volver a entrar a la pantalla.
          if (widget.role == 'CAREGIVER' && _caregiverRefreshTimer == null) {
            _caregiverRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadBooking());
          }
          if (widget.role == 'CAREGIVER') {
            _maybeShowEndConfirmDialog();
          }
          // GPS live info polling — cliente+PASEO, cada 15s
          if (widget.role == 'CLIENT' && _booking?['serviceType'] == 'PASEO' && _gpsInfoTimer == null) {
            _loadGpsInfo();
            _gpsInfoTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadGpsInfo());
          }
          if (widget.role == 'CLIENT' && _booking?['serviceType'] == 'PASEO') {
            _loadExtensionAvailability();
          }
          if (widget.role == 'CLIENT' && _booking?['serviceType'] == 'HOSPEDAJE') {
            _loadHospedajeExtensionAvailability();
          }
        } else {
          _serviceTimer?.cancel();
          _photoRefreshTimer?.cancel();
          _photoRefreshTimer = null;
          _caregiverRefreshTimer?.cancel();
          _caregiverRefreshTimer = null;
          _gpsInfoTimer?.cancel();
          _gpsInfoTimer = null;
          GardenLiveActivity.instance.endActivity();
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('SERVICE ERROR: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Devuelve "Día X de Y · Z días restantes" (o "¡Día final!" / "X días de retraso")
  String _buildHospedajeDayLabel() {
    final startStr  = _booking?['startDate'] as String?;
    final endStr    = _booking?['endDate']   as String?;
    final totalDays = _booking?['totalDays'] as int?;
    if (startStr == null) return '${_elapsed.inHours}h en curso';

    final start = DateTime.tryParse(startStr);
    final end   = endStr != null ? DateTime.tryParse(endStr) : null;
    if (start == null) return '${_elapsed.inHours}h en curso';

    final now     = DateTime.now();
    final today   = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(start.year, start.month, start.day);
    final daysSinceStart = today.difference(startDay).inDays + 1; // día 1 = día de inicio

    if (end != null) {
      final endDay = DateTime(end.year, end.month, end.day);
      final daysLeft = endDay.difference(today).inDays;
      if (daysLeft < 0) {
        return 'Día ${daysSinceStart} · ${(-daysLeft)} día${(-daysLeft) == 1 ? '' : 's'} de retraso ⚠️';
      }
      if (daysLeft == 0) return 'Día $daysSinceStart de ${totalDays ?? daysSinceStart} · ¡Último día!';
      return 'Día $daysSinceStart de ${totalDays ?? (daysSinceStart + daysLeft)} · $daysLeft día${daysLeft == 1 ? '' : 's'} restante${daysLeft == 1 ? '' : 's'}';
    }

    return 'Día $daysSinceStart${totalDays != null ? ' de $totalDays' : ''}';
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

  Future<void> _loadGpsInfo() async {
    if (!mounted) return;
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/track'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (!mounted) return;
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final pts = (data['data'] as List? ?? []);
        if (pts.isEmpty) return;
        final lastTs = pts.last['timestamp'] as String?;
        setState(() {
          _gpsHasSignal = true;
          _gpsLastPoint = lastTs != null ? DateTime.tryParse(lastTs) : null;
        });
      }
    } catch (_) {}
  }

  String _buildGpsStatusText() {
    if (!_gpsHasSignal) return 'El cuidador aún no ha compartido su ubicación';
    if (_gpsLastPoint == null) return 'Ubicación en vivo disponible';
    final diff = DateTime.now().difference(_gpsLastPoint!);
    final ago = diff.inSeconds < 60
        ? 'hace ${diff.inSeconds}s'
        : diff.inMinutes < 60
            ? 'hace ${diff.inMinutes} min'
            : 'hace ${diff.inHours}h';
    return 'Ubicación actualizada $ago';
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

  /// Recalcula `_elapsed` desde cero a partir de los timestamps del server en
  /// vez de simplemente sumar 1s por tick — esto es lo que hace que el timer
  /// respete la pausa por emergencia (_isServicePaused) y sea robusto a que
  /// la app haya estado en background durante toda o parte de la pausa (un
  /// `+= 1s` en un Timer.periodic no corre en background, así que al volver
  /// igual habría que resincronizar; recalcular desde el server evita ambos
  /// problemas de una vez).
  ///
  /// Fórmula: tiempo transcurrido desde el inicio del servicio, menos el
  /// tiempo ya pausado por emergencias resueltas (totalPausedMinutes), menos
  /// el tiempo de la pausa activa en curso (si la hay) — para esto último el
  /// "reloj de pared" se congela en pausedAt en vez de seguir hasta ahora.
  Duration _computeElapsedNow() {
    final bk = _booking;
    if (bk == null) return _elapsed;
    final startedAtStr = bk['serviceStartedAt'] as String?;
    final startTime = startedAtStr != null ? DateTime.tryParse(startedAtStr) : null;
    if (startTime == null) return _elapsed;

    final totalPausedMin = (bk['totalPausedMinutes'] as num?)?.toInt() ?? 0;
    final pausedAtStr = bk['pausedAt'] as String?;
    final pausedAt = pausedAtStr != null ? DateTime.tryParse(pausedAtStr) : null;
    final clientMarkedEndAtStr = bk['clientMarkedEndAt'] as String?;
    final clientMarkedEndAt = clientMarkedEndAtStr != null ? DateTime.tryParse(clientMarkedEndAtStr) : null;

    // El reloj de pared se congela en el primero que ocurra entre: una
    // emergencia activa (pausedAt) o el dueño marcando el servicio como
    // terminado mientras se espera la confirmación del cuidador
    // (clientMarkedEndAt) — ninguno de los dos debe seguir sumando tiempo
    // visualmente aunque el reloj real siga corriendo.
    DateTime? freezeAt = pausedAt;
    if (clientMarkedEndAt != null && (freezeAt == null || clientMarkedEndAt.isBefore(freezeAt))) {
      freezeAt = clientMarkedEndAt;
    }
    final wallClockEnd = freezeAt ?? DateTime.now();
    var elapsed = wallClockEnd.difference(startTime) - Duration(minutes: totalPausedMin);
    if (elapsed.isNegative) elapsed = Duration.zero;
    return elapsed;
  }

  void _startTimer() {
    _serviceTimer?.cancel();
    final startedAt = _booking?['serviceStartedAt'] as String?;
    final startTime = startedAt != null ? DateTime.tryParse(startedAt) : null;
    _elapsed = _computeElapsedNow();

    // Launch Live Activity / Android notification on first timer start
    _startLiveActivity(startTime ?? DateTime.now());

    _serviceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsed = _computeElapsedNow());
        // Update Live Activity timer every 10 s (stays within iOS budget)
        if (_elapsed.inSeconds % 10 == 0) {
          GardenLiveActivity.instance.updateTimer(_elapsed);
        }
        // Photo reminders every 30s — no tiene sentido recordarlas mientras
        // el servicio está pausado por emergencia.
        if (_elapsed.inSeconds % 30 == 0 && widget.role == 'CAREGIVER' && !_isServicePaused) {
          _checkPhotoReminders();
        }
      }
    });
  }

  void _startLiveActivity(DateTime startTime) {
    final bk = _booking;
    if (bk == null) return;
    GardenLiveActivity.instance.startActivity(
      petName: bk['petName'] as String? ?? bk['petNames']?.toString() ?? 'Mascota',
      caregiverName: bk['caregiverName'] as String? ?? '',
      ownerName: bk['clientName'] as String? ?? bk['ownerName'] as String? ?? '',
      serviceType: bk['serviceType'] as String? ?? 'PASEO',
      role: widget.role,
      bookingId: widget.bookingId,
      startTime: startTime,
      totalPaidDurationMinutes: _computeTotalPaidDurationMinutes(bk),
    );
  }

  /// Total paid duration in minutes — original booked duration plus any
  /// already-approved & paid extension. Feeds the Live Activity's progress
  /// bar goal (see [GardenLiveActivity.startActivity] /
  /// [GardenLiveActivity.updateTotalPaidDuration]).
  ///
  /// PASEO / GUARDERIA are booked directly in minutes (`booking['duration']`,
  /// already mutated server-side on extension confirm). HOSPEDAJE is booked
  /// in nights — derived from `startDate`/`endDate` when available (accounts
  /// for confirmed extensions extending `endDate`), falling back to
  /// `totalDays × 24h`.
  int _computeTotalPaidDurationMinutes([Map<String, dynamic>? booking]) {
    final bk = booking ?? _booking;
    if (bk == null) return 60;
    final serviceType = bk['serviceType'] as String? ?? 'PASEO';
    if (serviceType == 'HOSPEDAJE') {
      final startStr = bk['startDate'] as String?;
      final endStr = bk['endDate'] as String?;
      final start = startStr != null ? DateTime.tryParse(startStr) : null;
      final end = endStr != null ? DateTime.tryParse(endStr) : null;
      if (start != null && end != null && end.isAfter(start)) {
        return end.difference(start).inMinutes;
      }
      final totalDays = (bk['totalDays'] as num?)?.toInt() ?? 1;
      return totalDays * 24 * 60;
    }
    // PASEO / GUARDERIA: booked duration is expressed directly in minutes.
    return (bk['duration'] as num?)?.toInt() ?? 60;
  }

  /// true cuando el tiempo total pagado del servicio (reserva + extensiones
  /// aprobadas) ya se cumplió — es decir, `DateTime.now()` superó
  /// `serviceStartedAt + duración total pagada + tiempo pausado` (tanto el ya
  /// acumulado de emergencias resueltas como el de una pausa activa en curso,
  /// si la hay). Se usa para gatear el botón "Marcar servicio como terminado"
  /// del dueño (punto 2) y para bloquear "Resolver emergencia" cuando el
  /// tiempo ya se agotó con una emergencia sin resolver (punto 4).
  bool get _isPaidServiceTimeUp {
    final bk = _booking;
    if (bk == null) return false;
    final startedAtStr = bk['serviceStartedAt'] as String?;
    final startTime = startedAtStr != null ? DateTime.tryParse(startedAtStr) : null;
    if (startTime == null) return false;

    final totalPaidMin = _computeTotalPaidDurationMinutes();
    final totalPausedMin = (bk['totalPausedMinutes'] as num?)?.toInt() ?? 0;
    final pausedAtStr = bk['pausedAt'] as String?;
    final pausedAt = pausedAtStr != null ? DateTime.tryParse(pausedAtStr) : null;
    final activePauseMin = pausedAt != null ? DateTime.now().difference(pausedAt).inMinutes : 0;

    final deadline = startTime.add(Duration(minutes: totalPaidMin + totalPausedMin + activePauseMin));
    return DateTime.now().isAfter(deadline);
  }

  /// Botón de "volver"/"cerrar" de la pantalla — usa `context.pop()` cuando
  /// hay algo que popear en el Navigator (llegamos con context.push o
  /// Navigator.push, típico al abrir desde una lista con un tap), pero cae a
  /// una ruta explícita con context.go cuando no lo hay (llegamos con
  /// context.go directo — desde el splash reanudando un servicio activo, o
  /// desde una notificación push, ambos casos reemplazan el stack). Antes
  /// siempre usaba context.pop() a secas, que no hacía nada visible en el
  /// segundo caso — el botón de volver quedaba "roto" en la práctica.
  void _exitServiceScreen() {
    if (Navigator.of(context).canPop()) {
      context.pop();
    } else {
      context.go(widget.role == 'CAREGIVER' ? '/caregiver/home' : '/my-bookings-tab');
    }
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
            body: const Center(child: GardenLoadingIndicator(color: GardenColors.primary)),
          );
        }

        final status = _booking?['status'] ?? '';

        return Scaffold(
          backgroundColor: bg,
          appBar: kIsWeb ? null : AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.close_rounded, color: textColor),
              onPressed: _exitServiceScreen,
            ),
            title: Text(
              _getAppBarTitle(status),
              style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          body: kIsWeb
              ? Column(children: [
                  Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
                      border: Border(bottom: BorderSide(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(children: [
                      IconButton(icon: Icon(Icons.close_rounded, color: textColor, size: 18), onPressed: _exitServiceScreen),
                      const SizedBox(width: 6),
                      Text(_getAppBarTitle(status), style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  Expanded(child: Center(child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: _buildBody(status),
                  ))),
                ])
              : _buildBody(status),
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
    if (status == 'CONFIRMED' && widget.role == 'CLIENT') {
      return _buildClientWaitingView();
    }
    if (status == 'IN_PROGRESS') {
      return _buildInProgressView();
    }
    if (status == 'COMPLETED') {
      if (widget.role == 'CLIENT' && !_alreadyRated) {
        return _buildSatisfactionSurvey();
      }
      if (widget.role == 'CAREGIVER' && _booking?['caregiverRated'] != true) {
        return _buildCaregiverRatingSurvey();
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
    final isPaseo = _booking?['serviceType'] == 'PASEO';
    final heroColors = isPaseo
        ? [GardenColors.forest, const Color(0xFF0B5C2E)]
        : [GardenColors.primaryDark, GardenColors.primary];

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          // ── Hero header ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Stack(
              children: [
                Container(
                  height: 260,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: heroColors,
                    ),
                  ),
                ),
                // Subtle pattern overlay
                Container(
                  height: 260,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.15)],
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 260,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                  ),
                                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 17),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: GardenColors.polygon.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(GardenRadius.full),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6, height: 6,
                                      decoration: const BoxDecoration(color: Color(0xFFAA84F5), shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('⬡ Escrow listo',
                                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Service type chip
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(GardenRadius.full),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(isPaseo ? '🦮' : '🏠', style: const TextStyle(fontSize: 13)),
                                const SizedBox(width: 6),
                                Text(
                                  isPaseo ? 'Paseo confirmado' : 'Hospedaje confirmado',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _booking?['petName'] as String? ?? 'Tu mascota',
                                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, height: 1.05),
                                    ),
                                    const SizedBox(height: 3),
                                    if ((_booking?['petBreed'] as String? ?? '').isNotEmpty)
                                      Text(
                                        _booking!['petBreed'] as String,
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(GardenRadius.lg),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _booking?['startTime'] ?? _booking?['timeSlot'] ?? '—',
                                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                    ),
                                    Text('hora de inicio',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 10)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Card: Dueño ──────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(GardenRadius.xl),
                      border: Border.all(color: borderColor),
                      boxShadow: GardenShadows.card,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            GardenAvatar(
                              imageUrl: null,
                              size: 56,
                              initials: (_booking?['clientName'] as String? ?? 'C')[0],
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _booking?['clientName'] as String? ?? 'Cliente',
                                    style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Dueño de ${_booking?['petName'] ?? 'la mascota'}',
                                    style: TextStyle(color: subtextColor, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: GardenColors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(GardenRadius.md),
                                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Bs ${_booking?['totalAmount'] ?? '—'}',
                                    style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w900, fontSize: 16)),
                                  Text('total', style: TextStyle(color: subtextColor, fontSize: 10)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_booking?['specialNeeds'] != null && (_booking!['specialNeeds'] as String).isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: GardenColors.warning.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(GardenRadius.md),
                              border: Border.all(color: GardenColors.warning.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.priority_high_rounded, size: 15, color: GardenColors.warning),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _booking!['specialNeeds'] as String,
                                    style: const TextStyle(color: GardenColors.warning, fontSize: 12, height: 1.4, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Dirección del dueño (PASEO) ──────────────────────────────
                  if (isPaseo && widget.role == 'CAREGIVER') ...[
                    _buildClientAddressCard(textColor, subtextColor, surface, borderColor),
                    const SizedBox(height: 14),
                  ],

                  // ── Meet & Greet (HOSPEDAJE) ─────────────────────────────────
                  if (_booking?['serviceType'] == 'HOSPEDAJE') ...[
                    _buildMeetAndGreetCard(),
                    const SizedBox(height: 14),
                  ],

                  // ── GPS (PASEO) ──────────────────────────────────────────────
                  if (isPaseo) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: GardenColors.secondary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(GardenRadius.lg),
                        border: Border.all(color: GardenColors.secondary.withValues(alpha: 0.22)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: GardenColors.secondary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(GardenRadius.sm),
                            ),
                            child: const Icon(Icons.map_rounded, color: GardenColors.secondary, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Comparte tu GPS durante el paseo',
                                  style: TextStyle(
                                    color: isDark ? GardenColors.darkTextPrimary : GardenColors.secondary,
                                    fontWeight: FontWeight.w700, fontSize: 13,
                                  )),
                                const SizedBox(height: 3),
                                Text(
                                  'Una vez iniciado, abre "Mapa GPS" en Acciones para que el dueño te vea en tiempo real.',
                                  style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ── Checklist ────────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(GardenRadius.xl),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: GardenColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(GardenRadius.sm),
                              ),
                              child: const Icon(Icons.checklist_rounded, color: GardenColors.primary, size: 16),
                            ),
                            const SizedBox(width: 10),
                            Text('Antes de iniciar',
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 14)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _checkItem('Confirma la identidad del dueño', textColor, subtextColor),
                        _checkItem('Verifica el estado de la mascota', textColor, subtextColor),
                        _checkItem('Revisa las necesidades especiales', textColor, subtextColor),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 20),
        decoration: BoxDecoration(
          color: surface,
          border: Border(top: BorderSide(color: borderColor)),
          boxShadow: GardenShadows.elevated,
        ),
        child: Builder(
          builder: (context) {
            final blockReason = _getStartServiceBlockReason();
            final isBlocked = blockReason != null;
            final isWebNonPro = kIsWeb && !_caregiverIsProfessional;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isBlocked) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: isWebNonPro
                          ? GardenColors.primary.withValues(alpha: 0.10)
                          : GardenColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isWebNonPro
                            ? GardenColors.primary.withValues(alpha: 0.3)
                            : GardenColors.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(children: [
                      Icon(
                        isWebNonPro ? Icons.phone_android_rounded : Icons.info_outline_rounded,
                        size: 16,
                        color: isWebNonPro ? GardenColors.primary : GardenColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        blockReason,
                        style: TextStyle(
                          fontSize: 12,
                          color: isWebNonPro ? GardenColors.primary : GardenColors.warning,
                          fontWeight: FontWeight.w500,
                        ),
                      )),
                    ]),
                  ),
                ],
                GardenButton(
                  label: _isProcessing ? 'Iniciando...' : (isPaseo ? '🦮  Iniciar paseo' : '🏠  Iniciar hospedaje'),
                  loading: _isProcessing,
                  color: isBlocked
                      ? (isDark ? GardenColors.darkBorder : GardenColors.lightBorder)
                      : (isPaseo ? GardenColors.forest : GardenColors.primary),
                  onPressed: isBlocked ? () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(blockReason),
                      backgroundColor: isWebNonPro ? GardenColors.primary : GardenColors.warning,
                      duration: const Duration(seconds: 4),
                    ));
                  } : _startService,
                ),
                const SizedBox(height: 8),
                Text(
                  isBlocked && !isWebNonPro
                      ? blockReason
                      : 'El pago en escrow se liberará al finalizar',
                  style: TextStyle(color: subtextColor, fontSize: 11),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _checkItem(String text, Color textColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: GardenColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: GardenColors.success.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.check_rounded, size: 14, color: GardenColors.success),
          ),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildClientAddressCard(
    Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final clientAddress = _booking?['clientAddress'] as Map<String, dynamic>?;
    final lat = (clientAddress?['lat'] as num?)?.toDouble();
    final lng = (clientAddress?['lng'] as num?)?.toDouble();
    final street = clientAddress?['street'] as String?;
    final number = clientAddress?['number'] as String?;
    final zone = clientAddress?['zone'] as String?;
    final apartment = clientAddress?['apartment'] as String?;
    final condominio = clientAddress?['condominio'] as String?;
    final reference = clientAddress?['reference'] as String?;
    final full = clientAddress?['full'] as String?;

    final displayAddress = [
      if (street != null && street.isNotEmpty) street,
      if (number != null && number.isNotEmpty) 'N° $number',
      if (apartment != null && apartment.isNotEmpty) 'Dpto. $apartment',
      if (condominio != null && condominio.isNotEmpty) condominio,
      if (zone != null && zone.isNotEmpty) zone,
    ].join(', ');

    final addressText = displayAddress.isNotEmpty ? displayAddress : (full ?? 'Dirección no disponible');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        border: Border.all(color: borderColor),
        boxShadow: GardenShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.location_on_outlined, color: GardenColors.primary, size: 18),
            const SizedBox(width: 8),
            Text('Dirección del dueño',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          const SizedBox(height: 4),
          Text(
            'Aquí debes recoger a ${_booking?['petName'] ?? 'la mascota'} antes del paseo.',
            style: TextStyle(color: subtextColor, fontSize: 11),
          ),
          const SizedBox(height: 12),
          if (reference != null && reference.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: subtextColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(reference,
                      style: TextStyle(color: subtextColor, fontSize: 12, fontStyle: FontStyle.italic)),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 16, color: GardenColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  addressText,
                  style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          if (lat != null && lng != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.directions_rounded, size: 18),
                label: const Text('Navegar al domicilio'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GardenColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.md)),
                ),
                onPressed: () => _launchMaps(lat, lng, addressText),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _launchMaps(double lat, double lng, String label) async {
    final encoded = Uri.encodeComponent(label);
    // Intenta Google Maps primero, luego Apple Maps como fallback
    final urls = [
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
      'maps://?q=$lat,$lng',
      'geo:$lat,$lng?q=$lat,$lng($encoded)',
    ];
    for (final rawUrl in urls) {
      final uri = Uri.parse(rawUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la aplicación de mapas')),
      );
    }
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

  Future<void> _loadHospedajeExtensionAvailability() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/hospedaje-extension-availability'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _allowedExtensionDays = (data['data']['availableDays'] as num?)?.toInt() ?? 0;
            _hospedajePricePerDay = (data['data']['pricePerDay'] as num?)?.toDouble() ?? 0;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _requestHospedajeExtensionPayment(int days, String method) async {
    setState(() => _loadingExtension = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/request-hospedaje-extension-payment'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'additionalDays': days, 'method': method}),
      );

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
              additionalMinutes: days,
              additionalLabel: '$days noche${days == 1 ? '' : 's'}',
              confirmPath: 'confirm-hospedaje-extension-qr',
              extraAmount: (payData['extraAmount'] as num).toDouble(),
              qrImageUrl: payData['qrImageUrl'] as String?,
              qrExpiresAt: payData['qrExpiresAt'] as String?,
              method: method,
              onConfirmed: () async {
                await _loadBooking();
                await _loadHospedajeExtensionAvailability();
                // Extension confirmed & paid — update the Live Activity's
                // progress-bar goal right away.
                await GardenLiveActivity.instance
                    .updateTotalPaidDuration(_computeTotalPaidDurationMinutes());
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

  void _showExtendHospedajeSheet() {
    int selectedDays = 1;
    String selectedMethod = 'qr';

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

          Widget dayChip(int days) {
            final isSelected = selectedDays == days;
            final cost = (_hospedajePricePerDay * days).ceil();
            final label = days == 1 ? '1 noche' : '$days noches';
            return Expanded(
              child: GestureDetector(
                onTap: () => setSheetState(() => selectedDays = days),
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
                      Text('+$label', style: TextStyle(color: isSelected ? Colors.white : textColor, fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('Bs $cost', style: TextStyle(color: isSelected ? Colors.white70 : subtextColor, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            );
          }

          Widget methodChip(String method, String label, IconData icon, {bool enabled = true}) {
            final isSelected = selectedMethod == method;
            final chip = AnimatedContainer(
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
            );
            return Expanded(
              child: Opacity(
                opacity: enabled ? 1.0 : 0.42,
                child: AbsorbPointer(
                  absorbing: !enabled,
                  child: GestureDetector(
                    onTap: () => setSheetState(() => selectedMethod = method),
                    child: chip,
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
                Text('Ampliar hospedaje', style: GardenText.h4.copyWith(color: textColor)),
                const SizedBox(height: 4),
                Text('Selecciona cuántas noches adicionales necesitas.', style: GardenText.metadata.copyWith(color: subtextColor)),
                const SizedBox(height: 20),
                Row(children: [dayChip(1), dayChip(2), dayChip(3)]),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: GardenColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Costo adicional', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                      Text('Bs ${(_hospedajePricePerDay * selectedDays).ceil()}', style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w900, fontSize: 18)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Método de pago', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                Row(children: [
                  methodChip('qr', 'QR', Icons.qr_code_rounded),
                  methodChip('manual', 'Transferencia', Icons.account_balance_rounded),
                  methodChip('card', 'Tarjeta', Icons.credit_card_rounded, enabled: _cardPaymentEnabled),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: GardenButton(
                    label: 'Ir a pagar',
                    onPressed: () {
                      // El cobro con tarjeta todavía no está conectado a una
                      // pasarela real — comunicarlo claro en vez de intentar
                      // iniciar un pago que no existe de verdad.
                      if (selectedMethod == 'card') {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('El pago con tarjeta aún no está disponible. Elige QR o transferencia.'),
                          backgroundColor: Colors.orange,
                        ));
                        return;
                      }
                      Navigator.pop(ctx);
                      _requestHospedajeExtensionPayment(selectedDays, selectedMethod);
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
                // Extension confirmed & paid — update the Live Activity's
                // progress-bar goal right away.
                await GardenLiveActivity.instance
                    .updateTotalPaidDuration(_computeTotalPaidDurationMinutes());
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

          Widget methodChip(String method, String label, IconData icon, {bool enabled = true}) {
            final isSelected = selectedMethod == method;
            final chip = AnimatedContainer(
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
            );
            return Expanded(
              child: Opacity(
                opacity: enabled ? 1.0 : 0.42,
                child: AbsorbPointer(
                  absorbing: !enabled,
                  child: GestureDetector(
                    onTap: () => setSheetState(() => selectedMethod = method),
                    child: chip,
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
                    methodChip('card', 'Tarjeta', Icons.credit_card_rounded, enabled: _cardPaymentEnabled),
                  ]),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: GardenButton(
                      label: 'Ir a pagar',
                      onPressed: selectedMinutes == 0 ? null : () {
                        // El cobro con tarjeta todavía no está conectado a una
                        // pasarela real — comunicarlo claro en vez de intentar
                        // iniciar un pago que no existe de verdad.
                        if (selectedMethod == 'card') {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text('El pago con tarjeta aún no está disponible. Elige QR o transferencia.'),
                            backgroundColor: Colors.orange,
                          ));
                          return;
                        }
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

  // --- VISTA: CLIENT WAITING FOR CAREGIVER TO START ---
  Widget _buildClientWaitingView() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final isPaseo = _booking?['serviceType'] == 'PASEO';
    final isGuarderia = _booking?['serviceType'] == 'GUARDERIA';
    final heroColors = isPaseo
        ? [GardenColors.forest, const Color(0xFF0B5C2E)]
        : [GardenColors.primaryDark, GardenColors.primary];

    final caregiverName = _booking?['caregiverName'] as String? ?? 'Tu cuidador';
    final caregiverPhoto = _booking?['caregiverPhoto'] as String?;
    final caregiverRating = _booking?['caregiverRating'];
    final petName = _booking?['petName'] as String? ?? 'Tu mascota';

    String serviceLabel;
    String serviceEmoji;
    if (isPaseo) {
      serviceLabel = 'Paseo confirmado';
      serviceEmoji = '🦮';
    } else if (isGuarderia) {
      serviceLabel = 'Guardería confirmada';
      serviceEmoji = '🏡';
    } else {
      serviceLabel = 'Hospedaje confirmado';
      serviceEmoji = '🏠';
    }

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                Container(
                  height: 240,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: heroColors,
                    ),
                  ),
                ),
                Container(
                  height: 240,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.15)],
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 240,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 17),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(GardenRadius.full),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(serviceEmoji, style: const TextStyle(fontSize: 13)),
                                const SizedBox(width: 6),
                                Text(serviceLabel, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            petName,
                            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, height: 1.05),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tu cuidador ya está listo',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Caregiver card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: borderColor, width: 2),
                          ),
                          child: ClipOval(
                            child: caregiverPhoto != null && caregiverPhoto.isNotEmpty
                                ? Image.network(
                                    fixImageUrl(caregiverPhoto),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: GardenColors.primary.withValues(alpha: 0.1),
                                      child: const Icon(Icons.person_rounded, color: GardenColors.primary, size: 28),
                                    ),
                                  )
                                : Container(
                                    color: GardenColors.primary.withValues(alpha: 0.1),
                                    child: const Icon(Icons.person_rounded, color: GardenColors.primary, size: 28),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(caregiverName, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              if (caregiverRating != null)
                                Row(children: [
                                  const Icon(Icons.star_rounded, color: GardenColors.star, size: 14),
                                  const SizedBox(width: 3),
                                  Text(
                                    (caregiverRating as num).toStringAsFixed(1),
                                    style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ])
                              else
                                Text('Cuidador verificado', style: TextStyle(color: subtextColor, fontSize: 13)),
                            ],
                          ),
                        ),
                        if (_caregiverPhone != null && _caregiverPhone!.isNotEmpty)
                          GestureDetector(
                            onTap: () => launchUrl(Uri.parse('tel:$_caregiverPhone')),
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: GardenColors.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.phone_rounded, color: GardenColors.primary, size: 20),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Status card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: GardenColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: GardenColors.primary.withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      children: [
                        const _PulsingDot(color: GardenColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Esperando inicio del servicio',
                                style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Tu cuidador iniciará el servicio cuando llegue. Recibirás una notificación.',
                                style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Tips
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('¿Qué pasa ahora?', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        ...[
                          if (isPaseo) ...[
                            ('📍', 'Podrás ver la ubicación de tu mascota en tiempo real.'),
                            ('📸', 'Tu cuidador subirá fotos durante el paseo.'),
                            ('🔔', 'Te avisamos cuando el paseo termine.'),
                          ] else ...[
                            ('🏠', 'Tu mascota estará cuidada en un ambiente seguro.'),
                            ('📸', 'Recibirás fotos y actualizaciones del servicio.'),
                            ('🔔', 'Te avisamos si hay cualquier novedad.'),
                          ],
                        ].map((t) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.$1, style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 10),
                              Expanded(child: Text(t.$2, style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4))),
                            ],
                          ),
                        )).toList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
    final serviceType = _booking?['serviceType'] as String? ?? 'PASEO';
    final isPaseo = serviceType == 'PASEO';
    final isHospedaje = serviceType == 'HOSPEDAJE';
    final isGuarderia = serviceType == 'GUARDERIA';
    // ── Acento visual por tipo de servicio ──────────────────────────────────
    // Cada servicio ancla su propio color de acento dentro de la paleta
    // GARDEN ya existente (nunca un color nuevo) — sutil, no un rediseño:
    //   PASEO      → forest (verde bosque) — aire libre / caminata
    //   HOSPEDAJE  → orange (naranja cálido) — hogar acogedor / noches
    //   GUARDERIA  → info (azul brillante) — día soleado / guardería
    // Antes HOSPEDAJE y GUARDERIA compartían el mismo tratamiento visual
    // (incluso un tono café fuera de paleta, 0xFF8C5200) — ahora cada uno
    // tiene su propio anclaje coherente con la marca.
    final serviceAccent = isPaseo
        ? GardenColors.forest
        : isHospedaje
            ? GardenColors.orange
            : GardenColors.info;
    final serviceEmoji = isPaseo ? '🦮' : (isHospedaje ? '🏠' : '🏡');
    final serviceTypeLabel = isPaseo ? 'Paseo' : (isHospedaje ? 'Hospedaje' : 'Guardería');
    final timerStr = (isPaseo || isGuarderia)
        ? '${_elapsed.inHours.toString().padLeft(2,'0')}:${(_elapsed.inMinutes%60).toString().padLeft(2,'0')}:${(_elapsed.inSeconds%60).toString().padLeft(2,'0')}'
        : _buildHospedajeDayLabel();
    final incidents = (_booking?['serviceEvents'] as List<dynamic>? ?? [])
        .where((e) => e['type'] == 'INCIDENT' || e['type'] == 'ACCIDENT').toList();
    final lastPhoto = _serviceEvents.isNotEmpty ? _serviceEvents.last : null;
    final heroColors = isPaseo
        ? [GardenColors.forest, const Color(0xFF0B5C2E)]
        : isHospedaje
            ? [GardenColors.orange, GardenColors.orangeDark]
            : [GardenColors.info, GardenColors.infoDark];

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          // ── Hero inmersivo ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Stack(
              children: [
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: heroColors,
                    ),
                  ),
                ),
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.2)],
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 300,
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, _) => Transform.translate(
                            offset: Offset(0, _pulseController.value * -6),
                            child: isPaseo
                                ? _WalkIllustration(petName: _booking?['petName'] ?? '')
                                : _StayIllustration(petName: _booking?['petName'] ?? ''),
                          ),
                        ),
                        const Spacer(),
                        // Live timer badge
                        Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(GardenRadius.full),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PulsingDot(size: 8),
                              const SizedBox(width: 10),
                              Text(
                                isPaseo ? 'EN VIVO  $timerStr' : 'EN CURSO  $timerStr',
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Nav buttons
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10, left: 12,
                  child: GestureDetector(
                    onTap: () {
                      if (widget.role == 'CLIENT') {
                        context.go('/my-bookings-tab');
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 17),
                    ),
                  ),
                ),
                if (widget.role == 'CLIENT')
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 10, right: 12,
                    child: GestureDetector(
                      onTap: () => context.go('/marketplace'),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.28),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Alerta incidente ───────────────────────────────────────
                  if (incidents.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: GardenColors.warning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(GardenRadius.lg),
                        border: Border.all(color: GardenColors.warning.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: GardenColors.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(GardenRadius.sm),
                            ),
                            child: const Icon(Icons.warning_amber_rounded, color: GardenColors.warning, size: 17),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Incidente reportado',
                                  style: TextStyle(color: GardenColors.warning, fontSize: 13, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text(
                                  incidents.last['description']?.toString() ?? '',
                                  style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Botón de llamada de emergencia al cuidador ────────────
                    if (_caregiverPhone != null && _caregiverPhone!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => launchUrl(Uri.parse('tel:$_caregiverPhone')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GardenColors.error,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.md)),
                          ),
                          icon: const Icon(Icons.phone_rounded, size: 18),
                          label: const Text('Llamar al cuidador', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                  ],

                  // ── Trip card: cuidador + mascota unificados ────────────────
                  // Antes eran dos cajas separadas con bordes propios — mismo
                  // peso visual para info del cuidador y de la mascota, sin
                  // ninguna jerarquía clara. Unificadas en una sola tarjeta con
                  // sombra suave (menos "cajas apiladas", más estilo
                  // Airbnb/Uber: una fila principal tappable + un divisor fino
                  // + una fila secundaria de detalle).
                  Container(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(GardenRadius.xl),
                      boxShadow: GardenShadows.card,
                    ),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _showServiceInfoSheet,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
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
                                      Text(
                                        _booking?['caregiverName'] as String? ?? 'Cuidador',
                                        style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.star_rounded, color: GardenColors.star, size: 13),
                                          const SizedBox(width: 3),
                                          Text(
                                            _booking?['caregiverRating'] != null
                                                ? '${(_booking!['caregiverRating'] as num).toStringAsFixed(1)} · Tu cuidador'
                                                : 'Nuevo · Tu cuidador',
                                            style: TextStyle(color: subtextColor, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: GardenColors.success.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(GardenRadius.full),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _PulsingDot(size: 6, color: GardenColors.success),
                                      const SizedBox(width: 5),
                                      const Text('Activo',
                                        style: TextStyle(color: GardenColors.success, fontSize: 11, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.chevron_right_rounded, color: subtextColor, size: 18),
                              ],
                            ),
                          ),
                        ),
                        Divider(height: 1, thickness: 1, color: borderColor, indent: 16, endIndent: 16),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          child: Row(
                            children: [
                              const Text('🐾', style: TextStyle(fontSize: 16)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(color: subtextColor, fontSize: 12.5),
                                    children: [
                                      TextSpan(
                                        text: _booking?['petName'] as String? ?? '—',
                                        style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
                                      ),
                                      if ((_booking?['petBreed'] as String? ?? '').isNotEmpty)
                                        TextSpan(text: ' · ${_booking!['petBreed']}'),
                                    ],
                                  ),
                                ),
                              ),
                              Icon(Icons.shield_outlined, color: GardenColors.polygon, size: 13),
                              const SizedBox(width: 4),
                              Text('Pago en escrow',
                                style: TextStyle(color: GardenColors.polygon, fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Progreso del servicio (barra de tiempo por tipo) ────────
                  // Mismo concepto de "estado del viaje" estilo Airbnb, pero el
                  // dato que llena la barra cambia según el servicio: minutos
                  // transcurridos/pagados en Paseo, ventana de horario en
                  // Guardería (mismo día), noche actual/total en Hospedaje.
                  // Usa _computeTotalPaidDurationMinutes(), la misma fuente que
                  // ya gatea "marcar como terminado" — el progreso mostrado
                  // siempre coincide con la lógica real de fin de servicio
                  // (incluye extensiones ya aprobadas).
                  Builder(builder: (context) {
                    final elapsedMin = _elapsed.inMinutes;
                    final totalPaidMin = _computeTotalPaidDurationMinutes();
                    final progress = totalPaidMin > 0
                        ? (elapsedMin / totalPaidMin).clamp(0.0, 1.0)
                        : 0.0;

                    String progressLabel;
                    String progressCaption;
                    if (isHospedaje) {
                      progressLabel = _buildHospedajeDayLabel();
                      progressCaption = '${(progress * 100).round()}% de la estadía completada';
                    } else if (isGuarderia) {
                      final startedAtStr = _booking?['serviceStartedAt'] as String?;
                      final startedAt = startedAtStr != null ? DateTime.tryParse(startedAtStr) : null;
                      if (startedAt != null) {
                        final pickupEstimate = startedAt.add(Duration(minutes: totalPaidMin));
                        progressLabel = 'Desde las ${_formatClockTime(startedAt)}';
                        progressCaption = 'Recogida estimada ${_formatClockTime(pickupEstimate)}';
                      } else {
                        progressLabel = 'En guardería';
                        progressCaption = '$elapsedMin min transcurridos';
                      }
                    } else {
                      progressLabel = '$elapsedMin min de $totalPaidMin min';
                      progressCaption = '${(progress * 100).round()}% del paseo completado';
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: serviceAccent.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(GardenRadius.xl),
                        border: Border.all(color: serviceAccent.withValues(alpha: 0.18)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(serviceEmoji, style: const TextStyle(fontSize: 15)),
                              const SizedBox(width: 8),
                              Text(
                                serviceTypeLabel.toUpperCase(),
                                style: TextStyle(color: serviceAccent, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                              ),
                              const Spacer(),
                              Text(
                                progressLabel,
                                style: TextStyle(color: textColor, fontSize: 12.5, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(GardenRadius.full),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor: serviceAccent.withValues(alpha: 0.12),
                              valueColor: AlwaysStoppedAnimation<Color>(serviceAccent),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(progressCaption, style: TextStyle(color: subtextColor, fontSize: 11.5)),
                        ],
                      ),
                    );
                  }),

                  // ── Acciones GPS/Extensión (PASEO) ──────────────────────────
                  if (_booking?['serviceType'] == 'PASEO' || _booking?['serviceType'] == 'HOSPEDAJE')
                    _sectionHeader('Seguimiento en vivo', Icons.sensors_rounded, textColor, subtextColor),
                  if (_booking?['serviceType'] == 'PASEO') ...[
                    // ── Card GPS en vivo ──────────────────────────────────────
                    GestureDetector(
                      onTap: () => Navigator.push(
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
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              GardenColors.forest.withValues(alpha: 0.92),
                              GardenColors.forest.withValues(alpha: 0.75),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(GardenRadius.xl),
                          boxShadow: [
                            BoxShadow(
                              color: GardenColors.forest.withValues(alpha: 0.25),
                              blurRadius: 12, offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(GardenRadius.md),
                              ),
                              child: const Icon(Icons.map_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _GpsPulsingDot(active: _gpsHasSignal),
                                      const SizedBox(width: 6),
                                      Text(
                                        _gpsHasSignal ? 'GPS en vivo' : 'Esperando GPS...',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _buildGpsStatusText(),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.82),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _loadingExtension ? null : _showExtendTimeSheet,
                      icon: _loadingExtension
                          ? const GardenLoadingIndicator(size: 16, color: GardenColors.primary)
                          : const Icon(Icons.add_alarm_rounded, size: 18),
                      label: Text(
                        _allowedExtensionMinutes == 0
                            ? 'Ampliar tiempo del paseo'
                            : 'Ampliar tiempo (hasta $_allowedExtensionMinutes min)',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GardenColors.primary,
                        side: const BorderSide(color: GardenColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.md)),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Extensión de hospedaje ───────────────────────────────────
                  if (_booking?['serviceType'] == 'HOSPEDAJE') ...[
                    OutlinedButton.icon(
                      onPressed: _loadingExtension ? null : _showExtendHospedajeSheet,
                      icon: _loadingExtension
                          ? const GardenLoadingIndicator(size: 16, color: GardenColors.primary)
                          : const Icon(Icons.nightlight_round, size: 18),
                      label: const Text('Agregar noches al hospedaje', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GardenColors.primary,
                        side: const BorderSide(color: GardenColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.md)),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Actualizaciones del servicio (fotos y videos) ───────────
                  if (_serviceEvents.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionHeader('Actualizaciones del servicio', Icons.photo_camera_back_outlined, textColor, subtextColor),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: GardenColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(GardenRadius.full),
                          ),
                          child: Text(
                            '${_serviceEvents.length}',
                            style: const TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 220,
                      child: PageView.builder(
                        itemCount: _serviceEvents.length,
                        itemBuilder: (ctx, i) {
                          final photo = _serviceEvents[i];
                          return GestureDetector(
                            onTap: () => _openEventMedia(photo),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(GardenRadius.xl),
                                child: Stack(
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      height: 220,
                                      child: _eventMediaPreview(photo, height: 220),
                                    ),
                                    Positioned(
                                      bottom: 0, left: 0, right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(14, 40, 14, 14),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.access_time_rounded, color: Colors.white, size: 12),
                                                const SizedBox(width: 4),
                                                Text(_formatEventTime(photo['timestamp'] as String? ?? ''),
                                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                            if (_serviceEvents.length > 1)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withValues(alpha: 0.45),
                                                  borderRadius: BorderRadius.circular(GardenRadius.full),
                                                ),
                                                child: Text('${i + 1}/${_serviceEvents.length}',
                                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                              ),
                                          ],
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
                    const SizedBox(height: 20),
                  ],

                  // ── Sin fotos aún ───────────────────────────────────────────
                  if (lastPhoto == null) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: GardenColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(GardenRadius.xl),
                        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: GardenColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(GardenRadius.md),
                            ),
                            child: const Center(child: Text('📸', style: TextStyle(fontSize: 22))),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Esperando fotos',
                                  style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
                                const SizedBox(height: 3),
                                Text('El cuidador te enviará fotos durante el servicio',
                                  style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Marcar servicio como terminado (dueño) ──────────────────
                  // Al final de la columna (prioridad más baja) — gateado por
                  // tiempo: solo aparece cuando el tiempo total pagado
                  // (reserva + extensiones) ya se cumplió, antes de eso no
                  // tiene sentido que el dueño lo marque como terminado.
                  if (_booking?['clientMarkedEndAt'] == null && !_isPaidServiceTimeUp) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: (isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated),
                        borderRadius: BorderRadius.circular(GardenRadius.md),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.schedule_rounded, color: subtextColor, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Podrás marcar el servicio como terminado cuando se cumpla el tiempo contratado.',
                              style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_booking?['clientMarkedEndAt'] == null) ...[
                    OutlinedButton.icon(
                      onPressed: _markingEnd ? null : _confirmMarkServiceEnded,
                      icon: _markingEnd
                          ? const GardenLoadingIndicator(size: 16, color: GardenColors.success)
                          : const Icon(Icons.check_circle_outline_rounded, size: 18),
                      label: const Text('Marcar servicio como terminado', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GardenColors.success,
                        side: const BorderSide(color: GardenColors.success),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.md)),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: GardenColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(GardenRadius.md),
                        border: Border.all(color: GardenColors.success.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: GardenColors.success, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Marcaste el servicio como terminado. Esperando que el cuidador suba sus fotos finales.',
                              style: TextStyle(color: textColor, fontSize: 12.5, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Bottom action bar ──────────────────────────────────────────────────
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 14),
        decoration: BoxDecoration(
          color: surface,
          border: Border(top: BorderSide(color: borderColor)),
          boxShadow: GardenShadows.elevated,
        ),
        child: Row(
          children: [
            _BottomActionBtn(
              icon: Icons.info_outline_rounded,
              label: 'Info',
              onTap: _showServiceInfoSheet,
              color: textColor,
              bg: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
            ),
            const SizedBox(width: 8),
            _BottomActionBtn(
              icon: Icons.camera_alt_rounded,
              label: 'Pedir foto',
              onTap: _requestPhotoFromCaregiver,
              color: Colors.white,
              bg: GardenColors.primary,
            ),
            const SizedBox(width: 8),
            _BottomActionBtn(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Chat',
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ChatScreen(
                  bookingId: widget.bookingId,
                  otherPersonName: _booking?['caregiverName'] ?? 'Cuidador',
                  token: _token,
                ),
              )),
              color: Colors.white,
              bg: GardenColors.forest,
            ),
            const SizedBox(width: 8),
            _BottomActionBtn(
              icon: Icons.sos_rounded,
              label: 'SOS',
              onTap: _showSosDialog,
              color: Colors.white,
              bg: GardenColors.error,
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
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final isHospedaje = _booking?['serviceType'] == 'HOSPEDAJE';
    final isPaseo = _booking?['serviceType'] == 'PASEO';
    final timerStr = isHospedaje
        ? _buildHospedajeDayLabel()
        : '${_elapsed.inHours.toString().padLeft(2,'0')}:${(_elapsed.inMinutes%60).toString().padLeft(2,'0')}:${(_elapsed.inSeconds%60).toString().padLeft(2,'0')}';
    final minPhotos = isPaseo ? 2 : 3;
    final photoCount = _serviceEvents.length;
    final isPhotoMet = photoCount >= minPhotos;
    final photoProgress = (photoCount / minPhotos).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // ── Header inmersivo ──────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isHospedaje
                    ? [const Color(0xFF7A3200), GardenColors.primaryDark]
                    : [GardenColors.forest, const Color(0xFF0B5C2E)],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: back + escrow
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: GardenColors.polygon.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(GardenRadius.full),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6, height: 6,
                                decoration: const BoxDecoration(color: Color(0xFFAA84F5), shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              const Text('⬡ Escrow activo',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Pet name + timer
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _PulsingDot(size: 8),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _booking?['petName'] as String? ?? 'Servicio activo',
                                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, height: 1.1),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Dueño: ${_booking?['clientName'] ?? '—'}',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: _isServicePaused
                                ? GardenColors.error.withValues(alpha: 0.35)
                                : Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(GardenRadius.lg),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                timerStr,
                                style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w900,
                                  fontSize: isHospedaje ? 16 : 17, letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                _isServicePaused ? 'pausado' : (isHospedaje ? 'cuidando' : 'en curso'),
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Contenido scrollable ──────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Emergencia activa: tiempo pausado ────────────────────
                  if (_isServicePaused) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: GardenColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(GardenRadius.md),
                        border: Border.all(color: GardenColors.error, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.pause_circle_filled_rounded, color: GardenColors.error, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Emergencia activa — el tiempo del servicio está pausado',
                                  style: TextStyle(color: textColor, fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Si ya se pasó el tiempo pagado del servicio Y la
                          // emergencia sigue sin resolver, ya no se puede
                          // "solucionar" desde la app — hace falta que un
                          // admin intervenga. El chat sigue disponible siempre
                          // (no se deshabilita por esto, ver Row de Acciones).
                          if (_isPaidServiceTimeUp) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(GardenRadius.sm),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.support_agent_rounded, color: GardenColors.error, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'El tiempo del servicio ya se cumplió con la emergencia sin resolver. Contacta a soporte de GARDEN para que un administrador la resuelva — puedes seguir usando el chat mientras tanto.',
                                      style: TextStyle(color: subtextColor, fontSize: 11.5, height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error, foregroundColor: Colors.white),
                                onPressed: _resolveIncidentCaregiver,
                                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                label: const Text('Resolver emergencia'),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  // ── Aviso: el dueño ya marcó el servicio como terminado ──
                  if (_booking?['clientMarkedEndAt'] != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: GardenColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(GardenRadius.md),
                        border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active_rounded, color: GardenColors.warning, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'El dueño marcó que el servicio ya terminó. Sube tus fotos finales y concluye para cobrar.',
                              style: TextStyle(color: textColor, fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  // ── Progreso fotos (barra compacta arriba) ──────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(GardenRadius.lg),
                      border: Border.all(color: isPhotoMet
                          ? GardenColors.success.withValues(alpha: 0.3)
                          : borderColor),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Fotos del servicio',
                                    style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
                                  Text(
                                    '$photoCount / $minPhotos',
                                    style: TextStyle(
                                      color: isPhotoMet ? GardenColors.success : GardenColors.warning,
                                      fontWeight: FontWeight.w800, fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(GardenRadius.full),
                                child: LinearProgressIndicator(
                                  value: photoProgress,
                                  minHeight: 5,
                                  backgroundColor: isDark ? GardenColors.darkBorder : GardenColors.lightBorder,
                                  valueColor: AlwaysStoppedAnimation(
                                    isPhotoMet ? GardenColors.success : GardenColors.warning,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isPhotoMet
                                    ? '✓ Requisito cumplido — puedes finalizar'
                                    : 'Faltan ${minPhotos - photoCount} foto${minPhotos - photoCount > 1 ? 's' : ''} para finalizar',
                                style: TextStyle(
                                  color: isPhotoMet ? GardenColors.success : subtextColor,
                                  fontSize: 11,
                                  fontWeight: isPhotoMet ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Grid de acciones ─────────────────────────────────────
                  Text('Acciones', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 12),
                  // Row 1: Foto + Video
                  Row(
                    children: [
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.camera_alt_rounded,
                          label: _isSendingPhoto ? 'Enviando...' : 'Foto',
                          sublabel: 'Obligatorio',
                          color: GardenColors.primary,
                          onTap: _isSendingPhoto ? () {} : _sendServicePhoto,
                          isDark: isDark,
                          loading: _isSendingPhoto,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.videocam_rounded,
                          label: _isSendingVideo ? 'Enviando...' : 'Video',
                          sublabel: 'Opcional',
                          color: const Color(0xFF7C4DFF),
                          onTap: _isSendingVideo ? () {} : _sendServiceVideo,
                          isDark: isDark,
                          loading: _isSendingVideo,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Row 2: Chat + Emergencia
                  Row(
                    children: [
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.chat_bubble_rounded,
                          label: 'Chat',
                          sublabel: 'Con el dueño',
                          color: GardenColors.forest,
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              bookingId: widget.bookingId,
                              otherPersonName: _booking?['clientName'] ?? 'Dueño',
                              token: _token,
                            ),
                          )),
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.emergency_rounded,
                          label: 'Emergencia',
                          sublabel: 'Reportar',
                          color: GardenColors.error,
                          onTap: _showReportDialog,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  // Row 3: Mapa GPS (solo PASEO)
                  if (isPaseo) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionTile(
                            icon: Icons.map_rounded,
                            label: 'Mapa GPS',
                            sublabel: 'Compartir ruta',
                            color: GardenColors.secondary,
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => GpsTrackingScreen(
                                bookingId: widget.bookingId,
                                role: 'CAREGIVER',
                                petName: _booking?['petName'] as String? ?? '',
                                token: _token,
                                petPhoto: _booking?['petPhoto'] as String?,
                              ),
                            )),
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  const SizedBox(height: 6),

                  // ── Botón deslizante: Finalizar servicio ─────────────────
                  // No se puede finalizar mientras haya una emergencia activa sin
                  // resolver (_isServicePaused) — hay que resolverla primero.
                  // Movido a después del bloque de Acciones (pedido explícito) para
                  // que el cuidador no lo toque por error antes de revisar las acciones.
                  SlideToConfirmButton(
                    label: _isServicePaused
                        ? 'Resuelve la emergencia activa primero'
                        : isPhotoMet
                            ? 'Desliza para finalizar servicio'
                            : 'Necesitas ${minPhotos - photoCount} foto${minPhotos - photoCount == 1 ? '' : 's'} más',
                    color: _isServicePaused
                        ? GardenColors.error
                        : (isPhotoMet ? GardenColors.success : GardenColors.warning),
                    icon: Icons.check_circle_rounded,
                    height: 58,
                    onConfirmed: (isPhotoMet && !_isServicePaused) ? _showFinishConfirmation : null,
                  ),
                  const SizedBox(height: 20),

                  // ── Fotos enviadas ───────────────────────────────────────
                  if (_serviceEvents.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Fotos enviadas',
                          style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: GardenColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(GardenRadius.full),
                          ),
                          child: Text('${_serviceEvents.length}',
                            style: const TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 110,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _serviceEvents.length,
                        itemBuilder: (_, i) {
                          final e = _serviceEvents[_serviceEvents.length - 1 - i];
                          final url = _eventMediaUrl(e) ?? '';
                          if (url.isEmpty) return const SizedBox();
                          return GestureDetector(
                            onTap: () => _openEventMedia(e),
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 110,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(GardenRadius.lg),
                                boxShadow: GardenShadows.card,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(GardenRadius.lg),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    _eventMediaPreview(e, height: 110),
                                    Positioned(
                                      bottom: 0, left: 0, right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                                          ),
                                        ),
                                        child: Text(_formatEventTime(e['timestamp'] as String? ?? ''),
                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
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

                  // ── Incidentes reportados ────────────────────────────────
                  Builder(builder: (_) {
                    final incidents = (_booking?['serviceEvents'] as List<dynamic>? ?? [])
                        .where((e) => e['type'] == 'INCIDENT').toList();
                    if (incidents.isEmpty) return const SizedBox();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Incidentes reportados',
                          style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 10),
                        ...incidents.map((inc) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: GardenColors.warning.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(GardenRadius.md),
                            border: Border.all(color: GardenColors.warning.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: GardenColors.warning, size: 15),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(inc['description'] as String? ?? '—',
                                      style: TextStyle(color: textColor, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text(_formatEventTime(inc['timestamp'] as String? ?? ''),
                                      style: TextStyle(color: subtextColor, fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    );
                  }),

                  // ── Extensiones confirmadas (PASEO y HOSPEDAJE) ──────────
                  Builder(builder: (_) {
                    final exts = (_booking?['serviceEvents'] as List<dynamic>? ?? [])
                        .where((e) => e['type'] == 'EXTENSION_CONFIRMED')
                        .toList();
                    if (exts.isEmpty) return const SizedBox();
                    final isHospedaje = _booking?['serviceType'] == 'HOSPEDAJE';
                    final totalMins = isHospedaje ? 0 : exts.fold<int>(0, (s, e) =>
                        s + ((e['additionalMinutes'] as num?)?.toInt() ?? 0));
                    final totalDays = isHospedaje ? exts.fold<int>(0, (s, e) =>
                        s + ((e['additionalDays'] as num?)?.toInt() ?? 0)) : 0;
                    final summaryLabel = isHospedaje
                        ? '+$totalDays noche${totalDays == 1 ? '' : 's'} total'
                        : '+$totalMins min total';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text(isHospedaje ? 'Noches añadidas' : 'Tiempo ampliado',
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: GardenColors.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(GardenRadius.full),
                              ),
                              child: Text(summaryLabel,
                                style: const TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...exts.map((ext) {
                          final mins = (ext['additionalMinutes'] as num?)?.toInt();
                          final days = (ext['additionalDays'] as num?)?.toInt();
                          final amount = (ext['extraAmount'] as num?)?.toDouble();
                          final time = _formatEventTime(ext['timestamp'] as String? ?? '');
                          final extLabel = days != null
                              ? '+$days noche${days == 1 ? '' : 's'}'
                              : (mins != null ? '+$mins min' : 'Extensión');
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: GardenColors.primary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(GardenRadius.md),
                              border: Border.all(color: GardenColors.primary.withValues(alpha: 0.15)),
                            ),
                            child: Row(
                              children: [
                                Icon(isHospedaje ? Icons.nightlight_round : Icons.add_alarm_rounded,
                                  size: 14, color: GardenColors.primary),
                                const SizedBox(width: 8),
                                Text(extLabel, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                if (amount != null) ...[
                                  const SizedBox(width: 6),
                                  Text('· Bs ${amount.toStringAsFixed(0)}',
                                    style: TextStyle(color: subtextColor, fontSize: 12)),
                                ],
                                const Spacer(),
                                Text(time, style: TextStyle(color: subtextColor, fontSize: 11)),
                              ],
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
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

  /// Reproductor de video en pantalla completa — antes esto no existía en
  /// ningún lado de la app: el cuidador podía enviar un video, pero no había
  /// forma de verlo (la galería solo sabía renderizar photoUrl como imagen,
  /// y un evento de solo-video sin photoUrl podía incluso crashear la
  /// pantalla al forzar el cast a String no-nulo).
  void _showVideoFullscreen(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(child: _FullscreenVideoPlayer(url: fixImageUrl(url))),
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

  bool _isVideoEvent(Map<String, dynamic> e) => (e['videoUrl'] as String?)?.isNotEmpty == true;
  String? _eventMediaUrl(Map<String, dynamic> e) =>
      _isVideoEvent(e) ? e['videoUrl'] as String? : e['photoUrl'] as String?;

  void _openEventMedia(Map<String, dynamic> e) {
    final url = _eventMediaUrl(e);
    if (url == null || url.isEmpty) return;
    _isVideoEvent(e) ? _showVideoFullscreen(url) : _showPhotoFullscreen(url);
  }

  /// Capa de imagen/video para una miniatura de la galería. Para video usamos
  /// un placeholder estático (fondo oscuro + ícono de play) en vez de un
  /// VideoPlayerController real — inicializar un controller por cada
  /// miniatura en una lista/carrusel sería costoso y no hace falta, el
  /// video real recién se decodifica al abrir en pantalla completa.
  Widget _eventMediaPreview(Map<String, dynamic> e, {required double height}) {
    if (_isVideoEvent(e)) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Container(color: const Color(0xFF1A1A1A)),
          const Center(
            child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 46),
          ),
          Positioned(
            top: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(GardenRadius.full),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.videocam_rounded, color: Colors.white, size: 11),
                SizedBox(width: 3),
                Text('VIDEO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
              ]),
            ),
          ),
        ],
      );
    }
    final url = e['photoUrl'] as String? ?? '';
    return Image.network(
      fixImageUrl(url),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: GardenColors.primary.withValues(alpha: 0.08),
        child: const Center(child: Icon(Icons.image_outlined, color: GardenColors.primary, size: 32)),
      ),
    );
  }

  /// Encabezado de sección estilo Airbnb/Uber — un ícono chico + label en
  /// mayúsculas espaciadas, para agrupar visualmente bloques de contenido
  /// relacionado sin necesitar otra caja/borde.
  Widget _sectionHeader(String label, IconData icon, Color textColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: subtextColor, size: 15),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(color: subtextColor, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }

  /// Formatea una hora local como "HH:MM" — usado por la barra de progreso
  /// de Guardería (ventana de horario entre-vivo → recogida estimada).
  String _formatClockTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final isCaregiver = widget.role == 'CAREGIVER';

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 40),
          child: Column(
            children: [
              // ── Ilustración de éxito ───────────────────────────────────
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.elasticOut,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [GardenColors.success.withValues(alpha: 0.15), GardenColors.primary.withValues(alpha: 0.08)],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: GardenColors.success.withValues(alpha: 0.3), width: 2),
                  ),
                  child: const Center(child: Text('🏆', style: TextStyle(fontSize: 52))),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                '¡Servicio Completado!',
                style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                isCaregiver
                    ? 'Excelente trabajo. El pago será liberado automáticamente.'
                    : 'Gracias por confiar en GARDEN. ¡Tu mascota fue cuidada con amor!',
                textAlign: TextAlign.center,
                style: TextStyle(color: subtextColor, fontSize: 14, height: 1.55),
              ),
              const SizedBox(height: 32),

              // ── Resumen del servicio ───────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(GardenRadius.xl),
                  border: Border.all(color: borderColor),
                  boxShadow: GardenShadows.card,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resumen',
                      style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                    const SizedBox(height: 14),
                    _InfoRow('Mascota', _booking?['petName'] as String? ?? '—', textColor, subtextColor),
                    _InfoRow('Servicio', _booking?['serviceType'] == 'PASEO' ? '🦮 Paseo' : '🏠 Hospedaje', textColor, subtextColor),
                    _InfoRow('Total', 'Bs ${_booking?['totalAmount'] ?? '—'}', textColor, subtextColor),
                    if (_booking?['serviceType'] == 'PASEO') ...[
                      Builder(builder: (_) {
                        final rawDist = _booking?['gpsDistance'];
                        if (rawDist == null) return const SizedBox.shrink();
                        final distM = (rawDist as num).toDouble();
                        final distStr = distM < 1000
                            ? '${distM.toStringAsFixed(0)} m'
                            : '${(distM / 1000).toStringAsFixed(2)} km';
                        return _InfoRow('📍 Recorrido', distStr, textColor, subtextColor);
                      }),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: GardenColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(GardenRadius.full),
                        border: Border.all(color: GardenColors.success.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 13, color: GardenColors.success),
                          const SizedBox(width: 6),
                          const Text('Servicio verificado por GARDEN',
                            style: TextStyle(color: GardenColors.success, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Escrow badge ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: GardenColors.polygon.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(GardenRadius.lg),
                  border: Border.all(color: GardenColors.polygon.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Text('⬡', style: TextStyle(fontSize: 20, color: GardenColors.polygon)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Pago en Polygon Amoy',
                            style: TextStyle(color: GardenColors.polygon, fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            isCaregiver
                                ? 'Los fondos se liberarán a tu billetera automáticamente.'
                                : 'El smart contract procesó el pago de forma segura.',
                            style: TextStyle(color: subtextColor, fontSize: 11, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              GardenButton(
                label: isCaregiver ? 'Volver al panel' : 'Volver a Mis Reservas',
                onPressed: () => context.go(
                  isCaregiver ? '/caregiver/home' : '/marketplace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- RESTRICCIONES PARA INICIAR SERVICIO ---

  /// Devuelve true si el cuidador es profesional.
  /// Lee isProfessional del booking.caregiver o de SharedPreferences como fallback.
  bool get _caregiverIsProfessional {
    // Intentar leer desde los datos de la reserva (caregiver profile embebido)
    final caregiverData = _booking?['caregiver'] as Map<String, dynamic>?;
    if (caregiverData != null && caregiverData.containsKey('isProfessional')) {
      return caregiverData['isProfessional'] == true;
    }
    // Fallback: leer del nivel superior del booking si viene aplanado
    return _booking?['isProfessional'] == true;
  }

  /// Retorna null si se puede iniciar, o un mensaje de error si no.
  String? _getStartServiceBlockReason() {
    // 1. Web + no profesional
    if (kIsWeb && !_caregiverIsProfessional) {
      return 'Para iniciar el servicio ve a tu teléfono';
    }

    final now = DateTime.now();

    // 2. Verificar que la fecha de hoy coincida con la fecha de la reserva
    final serviceType = _booking?['serviceType'] as String? ?? '';
    DateTime? bookingDate;
    if (serviceType == 'PASEO') {
      final walkDateStr = _booking?['walkDate'] as String?;
      if (walkDateStr != null) {
        bookingDate = DateTime.tryParse(walkDateStr);
      }
    } else {
      // HOSPEDAJE: usar startDate
      final startDateStr = _booking?['startDate'] as String?;
      if (startDateStr != null) {
        bookingDate = DateTime.tryParse(startDateStr);
      }
    }

    if (bookingDate != null) {
      final today = DateTime(now.year, now.month, now.day);
      final bookingDay = DateTime(bookingDate.year, bookingDate.month, bookingDate.day);
      if (today != bookingDay) {
        final diff = bookingDay.difference(today).inDays;
        if (diff > 0) {
          return 'El servicio es en $diff día${diff == 1 ? '' : 's'}. Podrás iniciarlo el día del servicio.';
        } else {
          return 'La fecha del servicio ya pasó. Contacta a soporte.';
        }
      }
    }

    // 3. Verificar ventana de ±30 minutos de la hora configurada (solo PASEO)
    if (serviceType == 'PASEO') {
      // Intentar leer la hora exacta configurada por el cuidador (HH:MM)
      final startTimeStr = _booking?['startTime'] as String?;
      DateTime? scheduledTime;

      if (startTimeStr != null && startTimeStr.contains(':')) {
        final parts = startTimeStr.split(':');
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) {
          scheduledTime = DateTime(now.year, now.month, now.day, h, m);
        }
      }

      // Fallback: usar hora fija del turno si no hay startTime
      if (scheduledTime == null) {
        final timeSlot = _booking?['timeSlot'] as String?;
        if (timeSlot != null) {
          int? slotHour;
          switch (timeSlot) {
            case 'MANANA': slotHour = 8; break;
            case 'TARDE':  slotHour = 14; break;
            case 'NOCHE':  slotHour = 19; break;
          }
          if (slotHour != null) {
            scheduledTime = DateTime(now.year, now.month, now.day, slotHour, 0);
          }
        }
      }

      if (scheduledTime != null) {
        final windowStart = scheduledTime.subtract(const Duration(minutes: 30));
        final windowEnd   = scheduledTime.add(const Duration(minutes: 30));
        final timeLabel   = '${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}';
        if (now.isBefore(windowStart)) {
          final minutesLeft = windowStart.difference(now).inMinutes;
          return 'Podrás iniciar en $minutesLeft min. La ventana abre a las ${windowStart.hour.toString().padLeft(2, '0')}:${windowStart.minute.toString().padLeft(2, '0')} (±30 min de las $timeLabel).';
        }
        if (now.isAfter(windowEnd)) {
          return 'La ventana de inicio para las $timeLabel ya cerró. Contacta a soporte si el servicio aún debe realizarse.';
        }
      }
    }

    return null; // Sin restricciones
  }

  // --- LOGICA DE ACCIONES ---
  Future<void> _startService() async {
    // iOS mata la ubicación en segundo plano si el cuidador cierra la app
    // por completo (restricción de la plataforma, no un bug nuestro) — avisar
    // antes de iniciar para que no lo descubra a mitad de un paseo.
    if (!kIsWeb && Platform.isIOS && mounted) {
      final understood = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.info_outline_rounded, color: GardenColors.primary, size: 32),
          title: const Text('No cierres la app durante el servicio'),
          content: const Text(
            'En iPhone, si cierras la app por completo (deslizándola desde el '
            'multitarea) se detiene el seguimiento GPS y el dueño deja de ver tu '
            'ubicación en vivo. Podés minimizarla o usar otras apps con normalidad, '
            'solo evitá cerrarla del todo hasta terminar el servicio.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Entendido', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (understood != true) return;
    }
    // Para paseos en móvil, verificar permiso de ubicación antes de iniciar
    if (!kIsWeb && _booking?['serviceType'] == 'PASEO') {
      LocationPermission permission = await Geolocator.checkPermission();
      // Divulgación destacada, DENTRO de la app, mostrada antes del diálogo
      // del sistema operativo — requisito de Google Play para apps que piden
      // ubicación en segundo plano (Política de Permisos de Ubicación). Solo
      // se muestra la primera vez (permiso aún "denied" = nunca se decidió),
      // no en cada paseo una vez que el cuidador ya lo concedió.
      if (permission == LocationPermission.denied && mounted) {
        final understood = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.location_on_rounded, color: GardenColors.primary, size: 32),
            title: const Text('Ubicación en tiempo real durante el paseo'),
            content: const Text(
              'Garden usa tu ubicación GPS mientras un paseo está en curso — incluso '
              'con la pantalla bloqueada o la app minimizada — para que el dueño de '
              'la mascota pueda ver el recorrido en vivo en el mapa, igual que el '
              '"modo conductor" de una app de transporte. Esta transmisión ocurre '
              'solo durante el paseo activo y se detiene automáticamente al '
              'finalizar el servicio. En la siguiente pantalla, elegí "Permitir '
              'todo el tiempo" para que el seguimiento no se corte.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Entendido, continuar', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (understood != true) return;
      }
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
    // El backend exige una foto de inicio (serviceStartPhoto) — pedirla y
    // subirla ANTES de llamar a /start, si no el servicio nunca puede
    // iniciarse (no hay otra forma de conseguir esa foto una vez arrancado).
    // Va directo a cámara (sin elegir cámara/galería) — debe ser una foto
    // real del momento, no una vieja de la galería. Aviso de "que se vea la
    // mascota" una sola vez por cuidador (persistido), no en cada servicio.
    final prefs = await SharedPreferences.getInstance();
    if (mounted && prefs.getBool('seen_start_photo_pet_reminder') != true) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.pets_rounded, color: GardenColors.primary, size: 32),
          title: const Text('Que se vea la mascota'),
          content: const Text(
            'Antes de iniciar, toma una foto donde se vea claramente a la '
            'mascota — deja constancia de su estado inicial.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      await prefs.setBool('seen_start_photo_pet_reminder', true);
    }
    if (!mounted) return;
    const source = ImageSource.camera;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    if (!mounted) return;

    setState(() => _isProcessing = true);
    try {
      final bytes = await picked.readAsBytes();
      final fileName = picked.name.isEmpty ? 'start_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name;

      final uploadRequest = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/upload/service-photo'),
      );
      uploadRequest.headers['Authorization'] = 'Bearer $_token';
      uploadRequest.files.add(http.MultipartFile.fromBytes(
        'photo', bytes,
        filename: fileName,
        contentType: MediaType('image', 'jpeg'),
      ));
      final uploadStreamed = await uploadRequest.send();
      final uploadResponse = await http.Response.fromStream(uploadStreamed);
      final uploadData = jsonDecode(uploadResponse.body);
      if (uploadData['success'] != true) {
        throw Exception(uploadData['error']?['message'] ?? 'No se pudo subir la foto de inicio');
      }
      final photoUrl = uploadData['data']['url'] as String;

      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/start'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'photo': photoUrl}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadBooking();
        if (!mounted) return;
        // Arranca el tracking GPS en background (independiente de la pantalla)
        // apenas el servicio pasa a IN_PROGRESS. Solo aplica a PASEO — el
        // backend (trackServiceLocation) rechaza el resto de todos modos.
        if (_booking?['serviceType'] == 'PASEO') {
          GpsTrackingSession.instance.start(bookingId: widget.bookingId, token: _token);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Servicio iniciado! El escrow blockchain está activo.'), backgroundColor: GardenColors.success),
        );
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      if (!mounted) return;
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

  // ── SOS del dueño ──────────────────────────────────────────────────────
  // El cuidador NUNCA se entera de este reporte — pensado para el caso en
  // que el cuidador sea la parte cuestionada (posible robo/retención
  // indebida de la mascota). Solo el equipo de Garden lo recibe.
  static const _sosTypes = [
    {'icon': '📵', 'label': 'No puedo contactar al cuidador'},
    {'icon': '🐾', 'label': 'Sospecho que algo le pasó a mi mascota'},
    {'icon': '🏠', 'label': 'El cuidador no está donde dijo que estaría'},
    {'icon': '⚠️', 'label': 'Otra emergencia'},
  ];

  Future<void> _reportSos(String label) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/sos'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'description': label, 'incidentType': label}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('🆘 Alerta enviada al equipo de Garden'),
          backgroundColor: GardenColors.error,
          duration: Duration(seconds: 4),
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['error']?['message'] ?? 'Error al enviar la alerta'),
          backgroundColor: GardenColors.error,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error de conexión'),
          backgroundColor: GardenColors.error,
        ));
      }
    }
  }

  void _showSosDialog() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(ctx).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: subtextColor.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: GardenColors.error.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.sos_rounded, color: GardenColors.error, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🆘 Reportar un problema', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w900)),
                  Text('Esto alerta de inmediato al equipo de Garden.\nEl cuidador no se entera de este reporte.',
                      style: TextStyle(color: subtextColor, fontSize: 12, height: 1.3)),
                ],
              )),
            ]),
            const SizedBox(height: 20),
            Text('¿Qué está pasando?', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 12),
            ..._sosTypes.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _reportSos(item['label'] as String);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: GardenColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GardenColors.error.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    Text(item['icon'] as String, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item['label'] as String, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
            )),
            Center(child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar', style: TextStyle(color: subtextColor)),
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmMarkServiceEnded() async {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.xl)),
        title: Text('¿Ya terminó el servicio?', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
        content: Text(
          'Esto avisa al cuidador que puede subir sus fotos finales y cerrar el servicio. Úsalo solo si el servicio realmente ya terminó.',
          style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, ya terminó')),
        ],
      ),
    );
    if (confirmed != true) return;

    // Segunda confirmación — el dueño no tiene la barra de "deslizar para
    // confirmar" que sí tiene el cuidador, así que agregamos un segundo paso
    // explícito acá para evitar toques accidentales (pedido explícito: el
    // cuidador NO necesita esta fricción extra, solo el dueño).
    final doubleConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.xl)),
        title: Text('¿Estás completamente seguro?', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
        content: Text(
          'Esta acción no se puede deshacer. Confirmá solo si el servicio realmente ya terminó.',
          style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, confirmar', style: TextStyle(color: GardenColors.success, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (doubleConfirmed != true) return;
    await _markServiceEnded();
  }

  Future<void> _markServiceEnded() async {
    setState(() => _markingEnd = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/mark-ended'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (data['success'] == true) {
        setState(() => _booking = data['data']);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Avisamos al cuidador que el servicio terminó'), backgroundColor: GardenColors.success),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'No se pudo marcar el servicio'), backgroundColor: GardenColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión'), backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _markingEnd = false);
    }
  }

  void _showFinishConfirmation() {
    final minPhotos = _booking?['serviceType'] == 'PASEO' ? 2 : 3;
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
      // Punto de ubicación final — best-effort, nunca bloquea el cierre del
      // servicio si el permiso fue denegado o falla el GPS. Para Hospedaje/
      // Guardería es el único punto "de cierre" que queda registrado, dado
      // que esos servicios no tienen tracking continuo como Paseo.
      Map<String, dynamic> conclusionBody = {};
      try {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
            .timeout(const Duration(seconds: 8));
        conclusionBody = {'lat': pos.latitude, 'lng': pos.longitude};
      } catch (_) {
        // Sin ubicación disponible — se concluye igual, sin punto final.
      }
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/conclude'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode(conclusionBody),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        // El servicio pasó a COMPLETED — cortar el tracking GPS en background
        // acá, no en _markServiceEnded (esa acción del dueño solo congela el
        // reloj de overtime, no termina el booking realmente).
        if (_booking?['serviceType'] == 'PASEO') {
          GpsTrackingSession.instance.stop();
        }
        await _loadBooking();
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Photo / Video helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _sendServiceVideo() async {
    if (_isSendingVideo) return;
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 2));
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _isSendingVideo = true);
    try {
      final bytes = await picked.readAsBytes();
      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final uri = Uri.parse('$_baseUrl/bookings/${widget.bookingId}/event');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_token';
      request.fields['type'] = 'PHOTO';
      request.fields['description'] = 'Video del servicio';
      request.files.add(http.MultipartFile.fromBytes(
        'photo', bytes,
        filename: fileName,
        contentType: MediaType('video', 'mp4'),
      ));
      // Un video de hasta 2 min puede pesar varias decenas de MB — sin timeout
      // explícito, una red lenta puede colgar el request indefinidamente hasta
      // que el OS lo corte solo (apareciendo como "connection abort" en vez de
      // un timeout claro). Le damos 3 minutos de margen para la subida.
      final streamed = await request.send().timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw Exception('La subida tardó demasiado. Verifica tu conexión e intenta de nuevo.'),
      );
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadBooking();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🎥 Video enviado al dueño'), backgroundColor: GardenColors.success),
          );
        }
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al enviar el video');
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('errno 103') || e.toString().toLowerCase().contains('connection abort')
            ? 'Se cortó la conexión al enviar el video. Revisa tu conexión a internet e intenta de nuevo con un video más corto.'
            : 'No se pudo enviar el video: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingVideo = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Photo reminder system
  // ─────────────────────────────────────────────────────────────────────────

  void _checkPhotoReminders() {
    if (_booking?['status'] != 'IN_PROGRESS') return;
    final isPaseo = _booking?['serviceType'] == 'PASEO';
    final durationMin = int.tryParse(_booking?['duration']?.toString() ?? '0') ?? 0;
    final elapsedMin = _elapsed.inMinutes;
    final photoCount = _serviceEvents.length;
    final minPhotos = isPaseo ? 2 : 3;

    // Wait until flags are loaded from SharedPreferences to avoid false triggers on boot
    if (!_remindersLoaded) return;

    // Reminder 1: first photo
    if (!_reminder1Shown && photoCount == 0) {
      final threshold = isPaseo ? 5 : 15;
      if (elapsedMin >= threshold) {
        _reminder1Shown = true;
        _persistReminderFlag(1);
        _showPhotoReminderBanner(
          '📸 ¡Envía la primera foto!',
          isPaseo ? 'Han pasado 5 minutos. El dueño espera ver a su mascota.' : 'Han pasado 15 minutos sin fotos.',
        );
      }
    }

    // Reminder 2: mid-service (not for PASEO)
    if (!isPaseo && !_reminder2Shown && photoCount < 2 && durationMin > 0 && elapsedMin >= durationMin ~/ 2) {
      _reminder2Shown = true;
      _persistReminderFlag(2);
      _showPhotoReminderBanner('📸 ¡Foto de mitad del servicio!', 'Ya vas por la mitad del servicio.');
    }

    // Reminder 3: before end
    if (!_reminder3Shown && photoCount < minPhotos - 1 && durationMin > 0) {
      final endThreshold = isPaseo ? (durationMin - 10) : (durationMin - 15);
      if (endThreshold > 0 && elapsedMin >= endThreshold) {
        _reminder3Shown = true;
        _persistReminderFlag(3);
        _showPhotoReminderBanner(
          '📸 ¡Última foto antes de finalizar!',
          isPaseo ? 'Quedan ~10 minutos. Envía la foto final.' : 'Quedan ~15 minutos. Envía la foto final.',
        );
      }
    }
  }

  void _showPhotoReminderBanner(String title, String subtitle) {
    if (!mounted) return;
    final isDark = themeNotifier.isDark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? GardenColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: GardenColors.warning.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt_rounded, color: GardenColors.warning, size: 28),
            ),
            const SizedBox(height: 14),
            Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary,
                fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary,
                fontSize: 13)),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: GardenColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _sendServicePhoto();
            },
            child: const Text('Enviar foto ahora', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Recordar después',
              style: TextStyle(color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Emergency incident report — multi-step flow
  // ─────────────────────────────────────────────────────────────────────────

  static const _incidentTypes = [
    {'icon': '🐾', 'label': 'Pelea con otro animal', 'type': 'ACCIDENT', 'color': 0xFFE53935},
    {'icon': '🤕', 'label': 'Mascota lesionada', 'type': 'ACCIDENT', 'color': 0xFFE53935},
    {'icon': '🤢', 'label': 'Vómito / Malestar', 'type': 'ILLNESS', 'color': 0xFFFF8F00},
    {'icon': '🚗', 'label': 'Accidente de tráfico', 'type': 'ACCIDENT', 'color': 0xFFE53935},
    {'icon': '😰', 'label': 'Mascota perdida', 'type': 'INCIDENT', 'color': 0xFFFF8F00},
    {'icon': '⚡', 'label': 'Otra emergencia', 'type': 'INCIDENT', 'color': 0xFFE53935},
  ];

  Future<void> _reportIncident(String incidentLabel, String eventType) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/event'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': eventType,
          'description': incidentLabel,
          'incidentType': incidentLabel,
        }),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('🚨 Emergencia reportada. El dueño fue notificado.'),
          backgroundColor: GardenColors.error,
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (_) {}
  }

  bool get _isServicePaused => _booking?['pausedAt'] != null;

  /// Muestra el diálogo bloqueante de confirmación al cuidador cuando el
  /// dueño marcó el servicio como terminado (clientMarkedEndAt) y el cuidador
  /// todavía no respondió a esta marca específica — usamos el timestamp como
  /// clave en `_respondedEndMarks` para no repetir el diálogo en loop en cada
  /// refresco (cada 10s, ver _caregiverRefreshTimer) ni volver a mostrarlo si
  /// el cuidador ya respondió, pero sí mostrarlo de nuevo si el dueño lo marca
  /// una segunda vez tras un rechazo anterior (nuevo timestamp).
  void _maybeShowEndConfirmDialog() {
    final markedAt = _booking?['clientMarkedEndAt'] as String?;
    if (markedAt == null) return;
    if (_respondedEndMarks.contains(markedAt)) return;
    if (_endConfirmDialogShowing) return;
    _showEndConfirmDialog(markedAt);
  }

  void _showEndConfirmDialog(String markedAt) {
    _endConfirmDialogShowing = true;
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.xl)),
            title: Text('¿Finalizamos el servicio?', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
            content: Text(
              'El dueño marcó que el servicio ya terminó. ¿Estás de acuerdo? Si dices que no, el servicio sigue en curso con normalidad.',
              style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: _isRespondingToEndConfirm
                    ? null
                    : () async {
                        setDialogState(() {});
                        await _respondToEndConfirm(markedAt, false, ctx);
                      },
                child: const Text('No, todavía no'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: GardenColors.success, foregroundColor: Colors.white),
                onPressed: _isRespondingToEndConfirm
                    ? null
                    : () async {
                        setDialogState(() {});
                        await _respondToEndConfirm(markedAt, true, ctx);
                      },
                child: const Text('Sí, finalizamos'),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _endConfirmDialogShowing = false);
  }

  Future<void> _respondToEndConfirm(String markedAt, bool accepted, BuildContext dialogContext) async {
    setState(() => _isRespondingToEndConfirm = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/confirm-end'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'accepted': accepted}),
      );
      final data = jsonDecode(res.body);
      _respondedEndMarks.add(markedAt);
      if (data['success'] == true && mounted) {
        setState(() {
          _booking = data['data'] as Map<String, dynamic>;
          _elapsed = _computeElapsedNow();
        });
      }
    } catch (_) {
      // Si falla la request, igual cerramos el diálogo — el cuidador puede
      // seguir usando la pantalla con normalidad y el próximo refresco (10s)
      // volverá a mostrar el diálogo si clientMarkedEndAt sigue activo, sin
      // marcar esta respuesta como ya atendida.
    } finally {
      if (mounted) setState(() => _isRespondingToEndConfirm = false);
      if (dialogContext.mounted) Navigator.pop(dialogContext);
    }
  }

  Future<void> _resolveIncidentCaregiver() async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/event'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        // description es obligatoria server-side para todo evento (auditoría) —
        // antes esta request no la mandaba y siempre fallaba con
        // VALIDATION_ERROR (silenciado por el catch de abajo), así que
        // "Resolver emergencia" nunca funcionaba de verdad.
        body: jsonEncode({'type': 'INCIDENT_RESOLVED', 'description': 'Emergencia resuelta por el cuidador'}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        // Usar la respuesta completa del server (no solo poner pausedAt en
        // null a mano) — así totalPausedMinutes también queda actualizado de
        // inmediato y el timer no "salta" al recalcularse (ver _computeElapsedNow).
        setState(() {
          if (data['data'] != null) {
            _booking = data['data'] as Map<String, dynamic>;
          } else if (_booking != null) {
            _booking!['pausedAt'] = null;
          }
          _elapsed = _computeElapsedNow();
        });
        _showResolvedChoiceDialog();
      }
    } catch (_) {}
  }

  void _showResolvedChoiceDialog() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Emergencia resuelta', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text('El tiempo del servicio se reanudó. ¿Deseas continuar con el servicio o terminar la reserva ahora?',
            style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continuar servicio'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _showFinishConfirmation();
            },
            child: const Text('Terminar reserva'),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchNearestVets() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final res = await http.get(
        Uri.parse('$_baseUrl/vets/nearest?lat=${pos.latitude}&lng=${pos.longitude}'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        return List<Map<String, dynamic>>.from(data['data'] as List);
      }
    } catch (_) {}
    return [];
  }

  void _showReportDialog() {
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
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(
                width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: subtextColor.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: GardenColors.error.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.emergency_rounded, color: GardenColors.error, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🚨 Emergencia', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w900)),
                    Text('El dueño será notificado al instante', style: TextStyle(color: subtextColor, fontSize: 12)),
                  ],
                )),
              ]),
              const SizedBox(height: 20),
              Text('¿Qué está pasando?', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 12),
              // Incident type grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.8,
                children: _incidentTypes.map((item) {
                  final color = Color(item['color'] as int);
                  return GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      final label = item['label'] as String;
                      final type = item['type'] as String;
                      await _reportIncident(label, type);
                      if (mounted) _showEmergencyResources(label);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(item['icon'] as String, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Flexible(child: Text(item['label'] as String, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Center(child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancelar', style: TextStyle(color: subtextColor)),
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _showEmergencyResources(String incidentLabel) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) {
          List<Map<String, dynamic>> nearestVets = [];
          bool loadingVets = true;

          // Load vets on first build
          Future.microtask(() async {
            final vets = await _fetchNearestVets();
            setSt(() { nearestVets = vets; loadingVets = false; });
          });

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollCtrl) => SingleChildScrollView(
              controller: scrollCtrl,
              padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(ctx).padding.bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(
                    width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: subtextColor.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2)),
                  )),
                  // Header
                  Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: GardenColors.error.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: const Icon(Icons.crisis_alert_rounded, color: GardenColors.error, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recursos de emergencia', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w900)),
                        Text(incidentLabel, style: TextStyle(color: GardenColors.error, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    )),
                  ]),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: GardenColors.error.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle_rounded, color: GardenColors.success, size: 14),
                      const SizedBox(width: 8),
                      Text('El dueño ya fue notificado', style: TextStyle(color: GardenColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // ── Sección: Veterinarias cercanas ──
                  Text('🏥 Veterinarias cercanas', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  if (loadingVets)
                    const Center(child: Padding(padding: EdgeInsets.all(16), child: GardenLoadingIndicator()))
                  else if (nearestVets.isEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00897B).withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF00897B).withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.info_outline_rounded, color: Color(0xFF00897B), size: 16),
                            const SizedBox(width: 8),
                            Text('Sin veterinarias geo-registradas aún', style: TextStyle(color: const Color(0xFF00897B), fontSize: 12, fontWeight: FontWeight.w700)),
                          ]),
                          const SizedBox(height: 10),
                          Text('Clínicas veterinarias de referencia — Bolivia:', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          ...[
                            {'name': 'VetBol Santa Cruz', 'number': '+591 3 3449900'},
                            {'name': 'Clínica Veterinaria Central', 'number': '+591 3 3337700'},
                            {'name': 'VetLapaz 24h', 'number': '+591 2 2790090'},
                          ].map((v) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(v['name']!, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
                                  Text(v['number']!, style: TextStyle(color: subtextColor, fontSize: 11)),
                                ],
                              )),
                              GestureDetector(
                                onTap: () => launchUrl(Uri.parse('tel:${v['number']!.replaceAll(' ', '')}')),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: const Color(0xFF00897B).withValues(alpha: 0.1), shape: BoxShape.circle),
                                  child: const Icon(Icons.phone_rounded, color: Color(0xFF00897B), size: 16),
                                ),
                              ),
                            ]),
                          )).toList(),
                        ],
                      ),
                    )
                  else
                    ...nearestVets.map((vet) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                      ),
                      child: Row(children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(color: const Color(0xFF00897B).withValues(alpha: 0.12), shape: BoxShape.circle),
                          child: const Icon(Icons.local_hospital_rounded, color: Color(0xFF00897B), size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(vet['name'] as String, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
                            if ((vet['address'] ?? '').toString().isNotEmpty)
                              Text(vet['address'] as String, style: TextStyle(color: subtextColor, fontSize: 11)),
                            Text(
                              '${((vet['distanceKm'] ?? 0) as num).toStringAsFixed(1)} km',
                              style: const TextStyle(color: Color(0xFF00897B), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        )),
                        GestureDetector(
                          onTap: () => launchUrl(Uri.parse('tel:${vet['phone']}')),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: const Color(0xFF00897B).withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.phone_rounded, color: Color(0xFF00897B), size: 18),
                          ),
                        ),
                      ]),
                    )).toList(),

                  const SizedBox(height: 20),
                  // ── Sección: Emergencias nacionales ──
                  Text('📞 Emergencias nacionales', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  ...[
                    {'label': '🚔 Policía Bolivia', 'number': '110'},
                    {'label': '🚒 Bomberos', 'number': '119'},
                    {'label': '🚑 Ambulancia', 'number': '118'},
                  ].map((e) => _EmergencyCallTile(
                    label: e['label']!, number: e['number']!,
                    isDark: isDark, textColor: textColor, subtextColor: subtextColor,
                  )).toList(),

                  const SizedBox(height: 20),
                  // ── Sección: GARDEN ──
                  Text('🌿 Soporte GARDEN', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  _EmergencyCallTile(
                    label: '🌿 Emergencias GARDEN',
                    number: '+59175933133',
                    numberDisplay: '+591 75933133',
                    isDark: isDark, textColor: textColor, subtextColor: subtextColor,
                    highlight: true,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? GardenColors.darkSurfaceElevated : const Color(0xFFF5F5F5),
                        foregroundColor: subtextColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(ctx2),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
    final ratingLabels = ['', 'Terrible', 'Malo', 'Regular', 'Bueno', '¡Excelente!'];
    final starColor = _surveyRating >= 4
        ? GardenColors.star
        : _surveyRating >= 3
            ? GardenColors.warning
            : GardenColors.error;

    return Scaffold(
      backgroundColor: bg,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 24, 24, 48),
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    GardenColors.primary.withValues(alpha: 0.08),
                    GardenColors.lime.withValues(alpha: 0.25),
                  ],
                ),
                borderRadius: BorderRadius.circular(GardenRadius.xl),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.14)),
              ),
              child: Column(
                children: [
                  const Text('🐾', style: TextStyle(fontSize: 52)),
                  const SizedBox(height: 16),
                  Text(
                    '¿Qué tal estuvo el servicio?',
                    style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w900, height: 1.2),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tu calificación activa el smart contract para liberar el pago al cuidador.',
                    style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Selector de estrellas ──────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final ratingValue = index + 1;
                final isSelected = ratingValue <= _surveyRating;
                return GestureDetector(
                  onTap: () => setState(() => _surveyRating = ratingValue),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1.0, end: isSelected ? 1.22 : 1.0),
                    duration: const Duration(milliseconds: 180),
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Icon(
                            isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: isSelected ? GardenColors.star : borderColor,
                            size: 54,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
            ),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _surveyRating > 0
                  ? Padding(
                      key: ValueKey(_surveyRating),
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        ratingLabels[_surveyRating],
                        style: TextStyle(color: starColor, fontWeight: FontWeight.w800, fontSize: 17),
                      ),
                    )
                  : const SizedBox(height: 12),
            ),
            const SizedBox(height: 28),

            // ── Comentario ─────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(GardenRadius.xl),
                border: Border.all(
                  color: _surveyCommentController.text.trim().isNotEmpty
                      ? GardenColors.primary.withValues(alpha: 0.4)
                      : borderColor,
                ),
                boxShadow: GardenShadows.card,
              ),
              child: TextField(
                controller: _surveyCommentController,
                maxLines: 4,
                style: TextStyle(color: textColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Cuéntanos tu experiencia... (requerido)',
                  hintStyle: TextStyle(color: subtextColor.withValues(alpha: 0.5), fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(18),
                ),
              ),
            ),
            if (_surveyShowValidationError && _surveyCommentController.text.trim().isEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: GardenColors.error, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'El comentario es obligatorio para calificar al cuidador',
                      style: const TextStyle(color: GardenColors.error, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            if (_surveyShowValidationError && _surveyRating == 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: GardenColors.error, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Selecciona una calificación de estrellas',
                      style: const TextStyle(color: GardenColors.error, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),

            // ── Cualidades del cuidador (opcional, selección múltiple) ──
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '¿Qué destacarías del cuidador? (opcional)',
                style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _caregiverSkillOptions.map((opt) {
                final isSel = _surveySkillTags.contains(opt);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (isSel) {
                      _surveySkillTags.remove(opt);
                    } else {
                      _surveySkillTags.add(opt);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? GardenColors.primary.withValues(alpha: 0.12) : surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSel ? GardenColors.primary : borderColor,
                        width: isSel ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSel) ...[
                          const Icon(Icons.check_rounded, color: GardenColors.primary, size: 14),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          opt,
                          style: TextStyle(
                            color: isSel ? GardenColors.primary : subtextColor,
                            fontSize: 13,
                            fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),

            // ── Feedback Smart Contract ────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _surveyRating > 0
                  ? Container(
                      key: ValueKey('sc_$_surveyRating'),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: (_surveyRating >= 3 ? GardenColors.success : GardenColors.error).withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(GardenRadius.lg),
                        border: Border.all(
                          color: (_surveyRating >= 3 ? GardenColors.success : GardenColors.error).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _surveyRating >= 3 ? Icons.lock_open_rounded : Icons.lock_clock_rounded,
                            color: _surveyRating >= 3 ? GardenColors.success : GardenColors.error,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _surveyRating >= 3
                                  ? 'El smart contract liberará el pago automáticamente al cuidador.'
                                  : 'El pago quedará retenido y un administrador revisará el caso.',
                              style: TextStyle(
                                color: _surveyRating >= 3 ? GardenColors.success : GardenColors.error,
                                fontSize: 12, fontWeight: FontWeight.w600, height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            const SizedBox(height: 32),
            GestureDetector(
              // Cuando el botón está deshabilitado, GardenButton ignora el tap
              // internamente — este detector envuelve para poder mostrar el
              // motivo en vez de fallar en silencio.
              onTap: canSubmit
                  ? null
                  : () {
                      setState(() => _surveyShowValidationError = true);
                      final reason = _surveyRating == 0
                          ? 'Selecciona una calificación de estrellas'
                          : 'El comentario es obligatorio para calificar al cuidador';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(reason), backgroundColor: GardenColors.error),
                      );
                    },
              child: AbsorbPointer(
                absorbing: !canSubmit,
                child: GardenButton(
                  label: _isProcessing ? 'Procesando en Blockchain...' : 'Confirmar calificación',
                  loading: _isProcessing,
                  onPressed: canSubmit
                      ? () => _submitRating(_surveyRating, _surveyCommentController.text, _surveySkillTags)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('⬡ ', style: TextStyle(color: GardenColors.polygon, fontSize: 12)),
                Text('Polygon Amoy Network',
                  style: TextStyle(color: subtextColor, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitRating(int rating, String comment, [List<String>? skillTags]) async {
    debugPrint('SERVICE: _submitRating starting for ${widget.bookingId} with rating $rating. Comment: $comment');
    setState(() => _isProcessing = true);
    try {
      debugPrint('SERVICE: Sending confirmation to ${widget.bookingId} with rating $rating...');
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/confirm-receipt'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'rating': rating, 'comment': comment, 'skillTags': skillTags ?? []}),
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
                  color: (rating >= 3 ? GardenColors.success : GardenColors.warning).withValues(alpha: 0.1),
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

  // ── Cuidador califica al dueño ──────────────────────────────────────────────

  Widget _buildCaregiverRatingSurvey() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final ratingLabels = ['', 'Complicado', 'Difícil', 'Normal', 'Bueno', '¡Excelente dueño!'];
    final starColor = _caregiverSurveyRating >= 4
        ? GardenColors.star
        : _caregiverSurveyRating >= 3
            ? GardenColors.warning
            : GardenColors.error;
    final petName = _booking?['petName'] ?? 'la mascota';

    return Scaffold(
      backgroundColor: bg,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 24, 24, 48),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    GardenColors.primary.withValues(alpha: 0.08),
                    GardenColors.lime.withValues(alpha: 0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(GardenRadius.xl),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.14)),
              ),
              child: Column(
                children: [
                  const Text('🐾', style: TextStyle(fontSize: 52)),
                  const SizedBox(height: 16),
                  Text(
                    '¿Cómo fue el dueño de $petName?',
                    style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w900, height: 1.2),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tu opinión es voluntaria y ayuda a mejorar la comunidad GARDEN.',
                    style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final val = i + 1;
                final selected = val <= _caregiverSurveyRating;
                return GestureDetector(
                  onTap: () => setState(() => _caregiverSurveyRating = val),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1.0, end: selected ? 1.2 : 1.0),
                    duration: const Duration(milliseconds: 180),
                    builder: (_, s, child) => Transform.scale(scale: s, child: child),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Icon(
                        selected ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: selected ? GardenColors.star : borderColor,
                        size: 52,
                      ),
                    ),
                  ),
                );
              }),
            ),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _caregiverSurveyRating > 0
                  ? Padding(
                      key: ValueKey(_caregiverSurveyRating),
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        ratingLabels[_caregiverSurveyRating],
                        style: TextStyle(color: starColor, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    )
                  : const SizedBox(height: 10),
            ),

            const SizedBox(height: 28),

            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(GardenRadius.lg),
                border: Border.all(color: borderColor),
              ),
              child: TextField(
                controller: _caregiverCommentController,
                maxLines: 3,
                maxLength: 500,
                style: TextStyle(color: textColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Comentario opcional (instrucciones claras, puntualidad, etc.)',
                  hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                  contentPadding: const EdgeInsets.all(16),
                  border: InputBorder.none,
                  counterStyle: TextStyle(color: subtextColor, fontSize: 11),
                ),
              ),
            ),

            if (_caregiverSurveyShowValidationError && _caregiverSurveyRating == 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: GardenColors.error, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Selecciona una calificación de estrellas para enviar',
                      style: const TextStyle(color: GardenColors.error, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 32),

            GestureDetector(
              onTap: (_caregiverSurveyRating > 0 && !_isSubmittingCaregiverRating)
                  ? null
                  : () {
                      if (_isSubmittingCaregiverRating) return;
                      setState(() => _caregiverSurveyShowValidationError = true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Selecciona una calificación de estrellas para enviar'), backgroundColor: GardenColors.error),
                      );
                    },
              child: AbsorbPointer(
                absorbing: !(_caregiverSurveyRating > 0 && !_isSubmittingCaregiverRating),
                child: GardenButton(
                  label: _isSubmittingCaregiverRating ? 'Enviando...' : 'Enviar calificación',
                  icon: Icons.star_rounded,
                  loading: _isSubmittingCaregiverRating,
                  onPressed: _caregiverSurveyRating > 0 && !_isSubmittingCaregiverRating
                      ? _submitCaregiverRating
                      : null,
                ),
              ),
            ),

            const SizedBox(height: 12),
            TextButton(
              onPressed: _isSubmittingCaregiverRating ? null : _skipCaregiverRating,
              child: Text(
                'Omitir por ahora',
                style: TextStyle(color: subtextColor, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitCaregiverRating() async {
    setState(() => _isSubmittingCaregiverRating = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/rate-owner'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'rating': _caregiverSurveyRating,
          'comment': _caregiverCommentController.text.trim().isEmpty
              ? null
              : _caregiverCommentController.text.trim(),
        }),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (data['success'] == true) {
        // Actualizar el flag localmente de inmediato en vez de depender de
        // _loadBooking() (una carrera contra el rebuild de _buildBody podía
        // dejar la encuesta visible aunque la calificación ya se había
        // enviado) — mismo patrón que _skipCaregiverRating, que sí funciona.
        setState(() {
          if (data['data'] != null) {
            _booking = data['data'] as Map<String, dynamic>;
          }
          if (_booking != null) _booking!['caregiverRated'] = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error']?['message'] ?? 'Error al enviar calificación'),
            backgroundColor: GardenColors.error,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión'), backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingCaregiverRating = false);
    }
  }

  Future<void> _skipCaregiverRating() async {
    setState(() {
      if (_booking != null) _booking!['caregiverRated'] = true;
    });
  }

}

// --- HELPERS LOCALES PARA EL DISEÑO ---

/// Reproductor de video simple: autoplay + loop, tap para pausar/reanudar.
/// Sin controles de scrubbing a propósito — son videos cortos de servicio,
/// no contenido largo que necesite avanzar/retroceder.
class _FullscreenVideoPlayer extends StatefulWidget {
  final String url;
  const _FullscreenVideoPlayer({required this.url});

  @override
  State<_FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<_FullscreenVideoPlayer> {
  late final VideoPlayerController _controller;
  bool _initError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.setLooping(true);
        _controller.play();
      }).catchError((_) {
        if (mounted) setState(() => _initError = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.white54, size: 40),
            SizedBox(height: 12),
            Text('No se pudo cargar el video', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    if (!_controller.value.isInitialized) {
      return const GardenLoadingIndicator(color: Colors.white);
    }
    return GestureDetector(
      onTap: () => setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play()),
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller),
            AnimatedOpacity(
              opacity: _controller.value.isPlaying ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 64, height: 64,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: const Center(child: Text('🦮', style: TextStyle(fontSize: 48))),
        ),
        const SizedBox(height: 10),
        Text(
          petName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: 0.2),
        ),
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
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: const Center(child: Text('🏠', style: TextStyle(fontSize: 48))),
        ),
        const SizedBox(height: 10),
        Text(
          petName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: 0.2),
        ),
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
      child: AnimatedOpacity(
        opacity: loading ? 0.65 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(GardenRadius.xl),
            border: Border.all(color: color.withValues(alpha: 0.18)),
            boxShadow: GardenShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(GardenRadius.md),
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(9),
                        child: GardenLoadingIndicator(color: color),
                      )
                    : Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 10),
              Text(label,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 1),
              Text(sublabel,
                style: TextStyle(color: subtextColor, fontSize: 11, height: 1.2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color bg;
  const _BottomActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    required this.bg,
  });
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(GardenRadius.lg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(label,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
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
  final String extensionId;
  final int additionalMinutes;
  final String? additionalLabel; // override display (e.g. '2 noches')
  final String confirmPath;      // endpoint suffix for QR confirmation
  final double extraAmount;
  final String? qrImageUrl;
  final String? qrExpiresAt;
  final String method;
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
    this.additionalLabel,
    this.confirmPath = 'confirm-extension-qr',
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

  Widget _buildQrImage(String url, double size) {
    const fallback = Center(child: Icon(Icons.qr_code_rounded, size: 90, color: GardenColors.primary));
    if (url.startsWith('data:image/')) {
      try {
        final comma = url.indexOf(',');
        final bytes = base64Decode(url.substring(comma + 1));
        return Image.memory(bytes, width: size, height: size, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => SizedBox(width: size, height: size, child: fallback));
      } catch (_) {
        return SizedBox(width: size, height: size, child: fallback);
      }
    }
    return Image.network(url, width: size, height: size, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => SizedBox(width: size, height: size, child: fallback));
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
                  Text('Adicional', style: TextStyle(color: subtextColor, fontSize: 14)),
                  Text(widget.additionalLabel ?? '+${widget.additionalMinutes} min', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
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
                ? _buildQrImage(widget.qrImageUrl!, 230)
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
                    Text('Adicional', style: TextStyle(color: subtextColor, fontSize: 14)),
                    Text(widget.additionalLabel ?? '+${widget.additionalMinutes} min', style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
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
            const GardenLoadingIndicator(size: 28, color: GardenColors.primary),
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

// ── Emergency call tile ───────────────────────────────────────────────────────

class _EmergencyCallTile extends StatelessWidget {
  final String label;
  final String number;
  final String? numberDisplay;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final bool highlight;

  const _EmergencyCallTile({
    required this.label,
    required this.number,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    this.numberDisplay,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = highlight
        ? GardenColors.primary.withValues(alpha: 0.08)
        : (isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated);
    final borderColor = highlight
        ? GardenColors.primary.withValues(alpha: 0.3)
        : (isDark ? GardenColors.darkBorder : GardenColors.lightBorder);
    final accentColor = highlight ? GardenColors.primary : GardenColors.error;

    return GestureDetector(
      onTap: () => launchUrl(Uri.parse('tel:$number')),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.phone_rounded, color: accentColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    numberDisplay ?? number,
                    style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(GardenRadius.full),
              ),
              child: const Text('Llamar', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

}

// Widget punto pulsante para el indicador GPS del cliente
class _GpsPulsingDot extends StatefulWidget {
  final bool active;
  const _GpsPulsingDot({this.active = true});
  @override
  _GpsPulsingDotState createState() => _GpsPulsingDotState();
}

class _GpsPulsingDotState extends State<_GpsPulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final color = widget.active ? GardenColors.success : Colors.white54;
    if (!widget.active) {
      return Container(
        width: 7, height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 7, height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

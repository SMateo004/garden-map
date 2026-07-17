import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show ChangeNotifier, TargetPlatform, defaultTargetPlatform, kIsWeb, debugPrint;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../screens/service/gps_location.dart';
import 'gps_task_handler.dart';

/// Singleton que mantiene vivo el tracking GPS de un paseo (PASEO) —
/// captura + envío al backend cada 5s exactos — de forma INDEPENDIENTE de
/// qué pantalla esté visible en la app, y (en Android) también mientras la
/// app está minimizada o la pantalla bloqueada, gracias a un foreground
/// service con notificación persistente (mismo patrón que usa Uber en su
/// "modo conductor").
///
/// ── CÓMO INVOCAR DESDE OTRAS PANTALLAS ──────────────────────────────────
/// `service_execution_screen.dart` ya llama:
///   1. `GpsTrackingSession.instance.start(bookingId: ..., token: ...)`
///      cuando el cuidador confirma "iniciar servicio" (booking → IN_PROGRESS).
///   2. `GpsTrackingSession.instance.stop()` cuando el cuidador concluye el
///      servicio (booking → COMPLETED).
///
/// ── COMPORTAMIENTO POR PLATAFORMA ───────────────────────────────────────
/// - **Android**: además del stream de Geolocator en el isolate principal
///   (que solo alimenta la UI del mapa mientras la app está en pantalla),
///   arranca un foreground service (`flutter_foreground_task`) cuyo
///   `TaskHandler` (`GpsTaskHandler`, isolate separado que Android NO mata
///   mientras el servicio esté activo) es el único responsable de mandar los
///   puntos al backend cada 5s — así se evita duplicar envíos y se garantiza
///   que el envío sobrevive a que el cuidador minimice la app o bloquee la
///   pantalla. El cuidador ve una notificación persistente ("Paseo en
///   curso...") mientras esto corre — no se puede ocultar, es requisito de
///   Android para foreground services, y le deja claro al cuidador que su
///   ubicación se sigue compartiendo.
/// - **iOS**: no existe un mecanismo equivalente a un foreground service.
///   En su lugar, usamos `Geolocator` con `AppleSettings(allowBackgroundLocationUpdates: true,
///   pauseLocationUpdatesAutomatically: false, showBackgroundLocationIndicator: true)`
///   + `UIBackgroundModes: location` en Info.plist — iOS entrega
///   actualizaciones de ubicación en background de forma nativa a cualquier
///   app con esa combinación de permiso "Always" + background mode, sin
///   necesitar un isolate separado. El mismo timer de 5s del isolate
///   principal sigue corriendo y mandando los puntos.
/// - **Web**: sin cambios — solo tracking en foreground (no hay concepto de
///   "background" real en una pestaña de navegador).
class GpsTrackingSession extends ChangeNotifier {
  GpsTrackingSession._();
  static final GpsTrackingSession instance = GpsTrackingSession._();

  String? _bookingId;
  String? _token;
  bool _running = false;
  bool _permissionDenied = false;
  bool _isSendingTrack = false; // evita requests paralelos (race condition fix)
  bool _androidForegroundInitDone = false;

  StreamSubscription<Map<String, double>>? _gpsSub;
  Timer? _sendTimer;

  LatLng? _currentPos;
  double? _lastAccuracy;
  final List<LatLng> track = [];

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  String get _baseUrl =>
      const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  bool get isRunning => _running;
  bool get permissionDenied => _permissionDenied;
  String? get bookingId => _bookingId;
  LatLng? get currentPos => _currentPos;

  /// Arranca (o continúa) el tracking para [bookingId]. Idempotente: si ya
  /// está corriendo para el mismo booking, no hace nada.
  Future<void> start({required String bookingId, required String token}) async {
    if (_running && _bookingId == bookingId) return;
    if (_running) await stop(); // sesión de otro booking activa: cortarla primero

    _bookingId = bookingId;
    _token = token;
    _permissionDenied = false;
    notifyListeners();

    if (kIsWeb) {
      _gpsSub = watchGpsPosition().listen(
        (pos) => _onLocation(pos['lat']!, pos['lng']!, pos['accuracy'] ?? 0),
        onError: (_) {
          _permissionDenied = true;
          notifyListeners();
        },
      );
    } else {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _permissionDenied = true;
        notifyListeners();
        return;
      }
      // iOS: con solo "Mientras se usa" (whileInUse), el stream se corta apenas
      // la app pasa a background. Pedimos la actualización a "Siempre" acá —
      // justo cuando arranca el paseo, momento en que el pedido tiene contexto
      // claro para el usuario (mejor práctica de Apple vs. pedirlo al abrir la app).
      if (_isIOS && permission == LocationPermission.whileInUse) {
        permission = await Geolocator.requestPermission();
      }

      final settings = _isIOS
          // iOS: pedimos actualizaciones en background de forma nativa — sin
          // esto, el stream se corta apenas la app pasa a background.
          ? AppleSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
              pauseLocationUpdatesAutomatically: false,
              showBackgroundLocationIndicator: true,
              allowBackgroundLocationUpdates: true,
              activityType: ActivityType.fitness,
            )
          : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);

      _gpsSub = Geolocator.getPositionStream(locationSettings: settings)
          .map((p) => {'lat': p.latitude, 'lng': p.longitude, 'accuracy': p.accuracy})
          .listen(
        (pos) => _onLocation(pos['lat']!, pos['lng']!, pos['accuracy'] ?? 0),
        onError: (_) {
          _permissionDenied = true;
          notifyListeners();
        },
      );
    }

    _running = true;

    if (_isAndroid) {
      // Android: el envío al backend queda a cargo del foreground service
      // (GpsTaskHandler) — sobrevive a que la app se minimice o la pantalla
      // se bloquee. El stream de arriba en este isolate solo alimenta la UI.
      await _startAndroidForegroundService(bookingId: bookingId, token: token);
    } else {
      // iOS / web: cadencia EXACTA de 5s en el isolate principal, sin
      // importar si hubo movimiento o no — toma la última posición conocida
      // (mantenida fresca por el stream de arriba) y la envía.
      _sendTimer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
    }
    notifyListeners();
  }

  Future<void> _startAndroidForegroundService({required String bookingId, required String token}) async {
    if (!_androidForegroundInitDone) {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'gps_tracking_service',
          channelName: 'Ubicación en vivo del paseo',
          channelDescription: 'Se muestra mientras compartís tu ubicación en vivo durante un paseo activo.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(5000), // cadencia exacta de 5s
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      _androidForegroundInitDone = true;
    }

    FlutterForegroundTask.addTaskDataCallback(_onTaskData);

    final running = await FlutterForegroundTask.isRunningService;
    if (running) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 3000,
        notificationTitle: 'Paseo en curso',
        notificationText: 'Compartiendo tu ubicación en vivo con el dueño de la mascota',
        callback: gpsForegroundStartCallback,
      );
    }
    // Le pasamos bookingId/token al TaskHandler — corre en su propio isolate,
    // no comparte memoria con esta clase.
    FlutterForegroundTask.sendDataToTask({'bookingId': bookingId, 'token': token});
  }

  /// Datos que manda `GpsTaskHandler` (isolate del foreground service) cada
  /// vez que captura un punto — solo para reflejarlo en la UI del mapa si la
  /// app está en foreground en ese momento.
  void _onTaskData(Object data) {
    if (data is! Map) return;
    final lat = data['lat'];
    final lng = data['lng'];
    if (lat is num && lng is num) {
      _currentPos = LatLng(lat.toDouble(), lng.toDouble());
      track.add(_currentPos!);
      notifyListeners();
    }
  }

  void _onLocation(double lat, double lng, double accuracy) {
    if (accuracy > 50) {
      debugPrint('GpsTrackingSession: precisión baja ($accuracy m), ignorando punto');
      return;
    }
    _currentPos = LatLng(lat, lng);
    _lastAccuracy = accuracy;
    notifyListeners();
  }

  Future<void> _tick() async {
    if (_isSendingTrack) return; // request anterior sin terminar: no solaparse
    final pos = _currentPos;
    final booking = _bookingId;
    final token = _token;
    if (pos == null || booking == null || token == null) return;

    _isSendingTrack = true;
    try {
      track.add(pos);
      notifyListeners();
      await http.post(
        Uri.parse('$_baseUrl/bookings/$booking/track'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'lat': pos.latitude, 'lng': pos.longitude, 'accuracy': _lastAccuracy ?? 0}),
      );
    } catch (e) {
      debugPrint('GpsTrackingSession: envío error: $e');
    } finally {
      _isSendingTrack = false;
    }
  }

  /// Detiene el tracking por completo. Se debe invocar cuando el servicio
  /// termina (booking pasa a COMPLETED o CANCELLED).
  Future<void> stop() async {
    await _gpsSub?.cancel();
    _gpsSub = null;
    _sendTimer?.cancel();
    _sendTimer = null;
    if (_isAndroid) {
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    }
    _running = false;
    _bookingId = null;
    _token = null;
    _isSendingTrack = false;
    notifyListeners();
  }
}

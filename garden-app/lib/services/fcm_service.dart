import 'dart:convert';
import 'dart:io' show Platform;
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'local_notification_service.dart';
import 'secure_storage_service.dart';
import 'auth_state.dart';

/// Background message handler — must be top-level function (FCM requirement).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // FCM muestra la notificación del sistema automáticamente en background/terminated.
  if (kDebugMode) debugPrint('[FCM] Background message: ${message.messageId}');
}

class FcmService {
  static final _fcm = FirebaseMessaging.instance;
  static GoRouter? _router;

  static String get _baseUrl => const String.fromEnvironment(
        'API_URL',
        defaultValue: 'https://api.gardenbo.com/api',
      );

  /// Inyectar el router para poder navegar al abrir una notificación.
  static void setRouter(GoRouter router) => _router = router;

  /// Call once at app startup (after Firebase.initializeApp).
  static Future<void> init() async {
    if (kIsWeb) return;

    // Background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Permisos (Android 13+ / iOS)
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // iOS foreground
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    // Notificación local cuando la app está en primer plano
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        LocalNotificationService.show(
          title: notification.title ?? 'GARDEN',
          body: notification.body ?? '',
        );
      }
      if (message.data['type'] == 'SERVICE_INCIDENT_URGENT') {
        _playEmergencyAlertSound();
      }
    });

    // Tap en notificación con app en segundo plano
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Tap en notificación con app terminada
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial);

    // Registrar token con reintentos
    await _registerTokenWithRetry();

    // Renovar token si cambia (reinstalación, etc.)
    _fcm.onTokenRefresh.listen((t) => _saveTokenToBackend(t));
  }

  /// Alarma sonora adicional para emergencias urgentes (incidente reportado
  /// por un cuidador) — suena aunque el admin tenga la app abierta y no vea
  /// la notificación del sistema. Silencioso si falta el asset.
  static Future<void> _playEmergencyAlertSound() async {
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('sounds/emergency_alert.mp3'));
      player.onPlayerComplete.first.then((_) => player.dispose());
    } catch (_) {}
  }

  /// Navega a la pantalla correcta según el payload de la notificación.
  ///
  /// Antes casi ninguna notificación llevaba a ningún lado: la mayoría de
  /// los `sendPushToUser(...)` en el backend nunca mandaban el `data` con
  /// `type`/`bookingId` (solo título y cuerpo), así que `type` siempre daba
  /// `null` acá y caía al `default` sin navegar — reportado explícitamente
  /// como bug por el dueño del negocio. Además, el ÚNICO caso que sí tenía
  /// navegación (INCIDENT/ACCIDENT) armaba una URL
  /// (`/service/$bookingId/CLIENT`) que no coincidía con la ruta real
  /// registrada en el router (`/service/:bookingId`, con el rol pasado por
  /// `extra`, no como segmento de la URL) — tampoco funcionaba.
  ///
  /// Para las pantallas que distinguen CLIENT/CAREGIVER (`/service/:id`) se
  /// usa el rol actual de la sesión (`AuthState.effectiveRole`) en vez de
  /// que el backend intente adivinarlo — es más robusto porque el rol
  /// correcto siempre es el de quien está mirando el teléfono en este momento.
  static void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] as String?;
    final bookingId = data['bookingId'] as String?;

    if (_router == null) return;

    final role = AuthState.effectiveRole.isNotEmpty ? AuthState.effectiveRole : 'CLIENT';
    final isCaregiver = role == 'CAREGIVER';

    switch (type) {
      case 'BOOKING_CONFIRMED':
      case 'BOOKING_CANCELLED':
      case 'BOOKING_PAYMENT':
      case 'BOOKING_ACCEPTED':
      case 'BOOKING_REJECTED':
        // Reservas del dueño — la lista ya muestra el estado y las acciones
        // disponibles para cada una (no hay pantalla de detalle separada).
        _router!.go('/my-bookings-tab');
        break;
      case 'BOOKING_WAITING_APPROVAL':
        // Nueva solicitud de reserva esperando que el cuidador acepte o
        // rechace — la pantalla de inicio del cuidador ya muestra esta
        // reserva de forma prominente con los botones Aceptar/Rechazar.
        _router!.go('/caregiver/home');
        break;
      case 'CHAT_MESSAGE':
        if (bookingId != null) {
          _router!.go('/chat/$bookingId');
        }
        break;
      case 'SLOT_CONFLICT':
        if (bookingId != null) {
          _router!.go('/slot-conflict/$bookingId');
        }
        break;
      case 'INCIDENT':
      case 'ACCIDENT':
      case 'SERVICE_STARTED':
      case 'SERVICE_COMPLETED':
      case 'SERVICE_EXTENSION':
      case 'SERVICE_MARKED_ENDED':
        // Todo lo que pasa durante un servicio activo (emergencia, inicio,
        // fin, extensión de tiempo/hospedaje, confirmación de fin) lleva
        // directo a esa pantalla — es donde está la acción que corresponde
        // tomar (calificar, subir fotos, confirmar, etc.).
        if (bookingId != null) {
          _router!.go('/service/$bookingId', extra: {'role': isCaregiver ? 'CAREGIVER' : 'CLIENT'});
        }
        break;
      case 'MEET_AND_GREET':
        if (bookingId != null) {
          _router!.go('/meet-and-greet/$bookingId', extra: {'role': isCaregiver ? 'CAREGIVER' : 'CLIENT'});
        }
        break;
      case 'WALLET':
        _router!.go('/wallet');
        break;
      default:
        // Sin navegación específica — el usuario ve la notificación en el drawer
        break;
    }
  }

  /// Obtiene el token FCM con hasta 3 reintentos ante fallos de red.
  static Future<void> _registerTokenWithRetry({int retries = 3}) async {
    // On iOS, FCM requires an APNS token. Simulators don't have APNS, so
    // skip registration gracefully instead of retrying 3 times and logging.
    if (!kIsWeb && Platform.isIOS) {
      try {
        final apnsToken = await _fcm.getAPNSToken();
        if (apnsToken == null) {
          if (kDebugMode) debugPrint('[FCM] Sin APNS token (simulador) — omitiendo registro');
          return;
        }
      } catch (_) {
        if (kDebugMode) debugPrint('[FCM] APNS no disponible — omitiendo registro');
        return;
      }
    }
    for (int i = 0; i < retries; i++) {
      try {
        final token = await _fcm.getToken();
        if (token != null) {
          // Only log token hint in debug builds — never expose in release logs
          if (kDebugMode) debugPrint('[FCM] Token obtenido (debug only)');
          await _saveTokenToBackend(token);
          return;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[FCM] Intento ${i + 1}/$retries falló: $e');
        if (i < retries - 1) {
          await Future.delayed(Duration(seconds: (i + 1) * 2));
        }
      }
    }
    if (kDebugMode) debugPrint('[FCM] No se pudo registrar el token después de $retries intentos');
  }

  /// Envía el token FCM al backend para recibir notificaciones push.
  /// Lee el access token desde el almacenamiento seguro (Keychain / EncryptedSharedPreferences).
  static Future<void> _saveTokenToBackend(String token) async {
    try {
      final authToken = await SecureStorageService.getAccessToken() ?? '';
      if (authToken.isEmpty) return; // Aún no autenticado — se llamará después del login

      final res = await http.put(
        Uri.parse('$_baseUrl/auth/fcm-token'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fcmToken': token}),
      );
      if (kDebugMode) {
        debugPrint(res.statusCode == 200
            ? '[FCM] Token registrado en el backend'
            : '[FCM] Backend rechazó el token: ${res.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] Error al guardar token en backend: $e');
    }
  }

  /// Llama tras un login exitoso para asegurar que el token esté actualizado.
  static Future<void> registerAfterLogin() async {
    if (kIsWeb) return;
    await _registerTokenWithRetry();
  }

  /// Reporta un error crítico al backend para que el admin reciba una notificación push.
  /// Se llama desde los handlers globales de error en main.dart.
  // Set via --dart-define=APP_SECRET=xxx at build time
  static const _appSecret = String.fromEnvironment('APP_SECRET');

  static Future<void> reportErrorToAdmin(String error, String stackTrace) async {
    if (kDebugMode) return; // Solo en producción
    try {
      final authToken = await SecureStorageService.getAccessToken() ?? '';

      await http.post(
        Uri.parse('$_baseUrl/app/error-report'),
        headers: {
          if (authToken.isNotEmpty) 'Authorization': 'Bearer $authToken',
          if (_appSecret.isNotEmpty) 'X-App-Secret': _appSecret,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'error': error.length > 500 ? error.substring(0, 500) : error,
          'stackTrace': stackTrace.length > 1000
              ? stackTrace.substring(0, 1000)
              : stackTrace,
          'platform': kIsWeb ? 'web' : 'mobile',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Silencioso — no lanzar otro error desde el handler de errores
    }
  }
}

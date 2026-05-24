import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'local_notification_service.dart';

/// Background message handler — must be top-level function (FCM requirement).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // FCM muestra la notificación del sistema automáticamente en background/terminated.
  debugPrint('[FCM] Background message: ${message.messageId}');
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

  /// Navega a la pantalla correcta según el payload de la notificación.
  static void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] as String?;
    final bookingId = data['bookingId'] as String?;

    if (_router == null) return;

    switch (type) {
      case 'BOOKING_CONFIRMED':
      case 'BOOKING_CANCELLED':
      case 'BOOKING_PAYMENT':
        if (bookingId != null) {
          _router!.go('/my-bookings-tab');
        }
        break;
      case 'CHAT_MESSAGE':
        if (bookingId != null) {
          _router!.go('/chat/$bookingId');
        }
        break;
      case 'INCIDENT':
      case 'ACCIDENT':
        if (bookingId != null) {
          _router!.go('/service/$bookingId/CLIENT');
        }
        break;
      default:
        // Sin navegación específica — el usuario ve la notificación en el drawer
        break;
    }
  }

  /// Obtiene el token FCM con hasta 3 reintentos ante fallos de red.
  static Future<void> _registerTokenWithRetry({int retries = 3}) async {
    for (int i = 0; i < retries; i++) {
      try {
        final token = await _fcm.getToken();
        if (token != null) {
          debugPrint('[FCM] Token obtenido: ${token.substring(0, 20)}...');
          await _saveTokenToBackend(token);
          return;
        }
      } catch (e) {
        debugPrint('[FCM] Intento ${i + 1}/$retries falló: $e');
        if (i < retries - 1) {
          await Future.delayed(Duration(seconds: (i + 1) * 2));
        }
      }
    }
    debugPrint('[FCM] No se pudo registrar el token después de $retries intentos');
  }

  /// Envía el token FCM al backend para recibir notificaciones push.
  static Future<void> _saveTokenToBackend(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('access_token') ?? '';
      if (authToken.isEmpty) return; // Aún no autenticado — se llamará después del login

      final res = await http.put(
        Uri.parse('$_baseUrl/auth/fcm-token'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fcmToken': token}),
      );
      if (res.statusCode == 200) {
        debugPrint('[FCM] Token registrado en el backend correctamente');
      } else {
        debugPrint('[FCM] Backend rechazó el token: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('[FCM] Error al guardar token en backend: $e');
    }
  }

  /// Llama tras un login exitoso para asegurar que el token esté actualizado.
  static Future<void> registerAfterLogin() async {
    if (kIsWeb) return;
    await _registerTokenWithRetry();
  }

  /// Reporta un error crítico al backend para que el admin reciba una notificación push.
  /// Se llama desde los handlers globales de error en main.dart.
  static Future<void> reportErrorToAdmin(String error, String stackTrace) async {
    if (kDebugMode) return; // Solo en producción
    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('access_token') ?? '';

      await http.post(
        Uri.parse('$_baseUrl/admin/error-report'),
        headers: {
          if (authToken.isNotEmpty) 'Authorization': 'Bearer $authToken',
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

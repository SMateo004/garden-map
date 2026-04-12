import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'local_notification_service.dart';

/// Background message handler — must be top-level function (FCM requirement).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // FCM shows the system notification automatically when the app is in background/terminated.
  // Nothing extra needed here for Android — the notification is displayed by the OS.
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class FcmService {
  static final _fcm = FirebaseMessaging.instance;

  static String get _baseUrl => const String.fromEnvironment(
        'API_URL',
        defaultValue: 'https://garden-api-1ldd.onrender.com/api',
      );

  /// Call once at app startup (after Firebase.initializeApp).
  static Future<void> init() async {
    if (kIsWeb) return;

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permission (Android 13+ / iOS)
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Configure foreground notification behavior on iOS
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Show local notification when a message arrives while app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        LocalNotificationService.show(
          title: notification.title ?? 'GARDEN',
          body: notification.body ?? '',
        );
      }
    });

    // Get and send the token
    await _registerToken();

    // Refresh token when it changes (e.g. after app reinstall)
    _fcm.onTokenRefresh.listen((newToken) => _saveTokenToBackend(newToken));
  }

  /// Gets the FCM token and sends it to the backend.
  static Future<void> _registerToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        debugPrint('[FCM] Token: ${token.substring(0, 20)}...');
        await _saveTokenToBackend(token);
      }
    } catch (e) {
      debugPrint('[FCM] Could not get token: $e');
    }
  }

  /// Sends the FCM token to the backend so the server can push to this device.
  static Future<void> _saveTokenToBackend(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('access_token') ?? '';
      if (authToken.isEmpty) return; // Not logged in yet — will be called again after login

      await http.put(
        Uri.parse('$_baseUrl/auth/fcm-token'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fcmToken': token}),
      );
      debugPrint('[FCM] Token registered with backend');
    } catch (e) {
      debugPrint('[FCM] Failed to save token to backend: $e');
    }
  }

  /// Call this after a successful login so the token is always fresh on the server.
  static Future<void> registerAfterLogin() async {
    if (kIsWeb) return;
    await _registerToken();
  }
}

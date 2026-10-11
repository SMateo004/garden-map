import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Qué hacer al tocar un aviso local (lo registra FcmService con la misma
  /// navegación que una notificación push). Antes tocarlo solo abría la app.
  static void Function(Map<String, dynamic> data)? onTap;

  static const _androidChannel = AndroidNotificationDetails(
    'garden_main',
    'Garden',
    channelDescription: 'Notificaciones de Garden',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );

  static Future<void> init() async {
    if (_initialized || kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          onTap?.call(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        } catch (_) {}
      },
    );
    _initialized = true;
  }

  static Future<void> requestPermission() async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  /// [data] viaja con el aviso (tipo y reserva) para que al tocarlo se
  /// abra lo que corresponde.
  static Future<void> show({required String title, required String body, Map<String, dynamic>? data}) async {
    if (!_initialized || kIsWeb) return;
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      const NotificationDetails(
        android: _androidChannel,
        iOS: DarwinNotificationDetails(),
      ),
      payload: data == null || data.isEmpty ? null : jsonEncode(data),
    );
  }
}

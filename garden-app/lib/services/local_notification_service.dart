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

  /// Sonido de GARDEN: tres roces de hojas, de suave a fuerte (un perro que
  /// pasa entre los arbustos). Sintetizado para GARDEN, sin derechos de terceros.
  /// Android: res/raw/garden_arbusto.wav · iOS: Runner/garden_arbusto.wav. El
  /// backend pide el mismo sonido y canal en cada push (firebase.service.ts).
  static const sound = 'garden_arbusto';

  /// Android no deja cambiar el sonido de un canal ya creado: el sonido va en
  /// un canal nuevo. El viejo ('garden_main', sonido del sistema) se borra.
  static const channelId = 'garden_avisos';
  static const _oldChannelId = 'garden_main';

  static const _androidChannel = AndroidNotificationDetails(
    channelId,
    'Avisos de Garden',
    channelDescription: 'Reservas, pagos, mensajes y servicios',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_stat_garden',
    sound: RawResourceAndroidNotificationSound(sound),
  );

  static Future<void> init() async {
    if (_initialized || kIsWeb) return;
    // Silueta monocroma para la barra de estado (el ícono a color salía como un cuadrado).
    const android = AndroidInitializationSettings('ic_stat_garden');
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
    // Crear el canal ya al arrancar (antes se creaba recién con el primer
    // aviso con la app abierta): así las push que llegan con la app cerrada
    // también usan el sonido.
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      try {
        await androidImpl.createNotificationChannel(const AndroidNotificationChannel(
          channelId,
          'Avisos de Garden',
          description: 'Reservas, pagos, mensajes y servicios',
          importance: Importance.high,
          sound: RawResourceAndroidNotificationSound(sound),
        ));
        await androidImpl.deleteNotificationChannel(_oldChannelId);
      } catch (_) {}
    }
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
        iOS: DarwinNotificationDetails(sound: '$sound.wav'),
      ),
      payload: data == null || data.isEmpty ? null : jsonEncode(data),
    );
  }
}

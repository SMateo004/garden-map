import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Manages Live Activities (iOS 16.2+) and the home-screen widget + persistent
/// foreground notification (Android) during an active pet service (PASEO /
/// GUARDERIA / HOSPEDAJE). See ios/GardenActivityWidget/ for the iOS widget
/// and android/app/src/main/kotlin/com/garden/bolivia/widget/ for the
/// Android one — same visual language (tarjeta oscura, barra de progreso,
/// cronómetro), driven from the exact same call sites in this class.
class GardenLiveActivity {
  GardenLiveActivity._();
  static final GardenLiveActivity instance = GardenLiveActivity._();

  static const _iosChannel = MethodChannel('com.gardenbo.app/live_activity');
  static const _androidWidgetChannel = MethodChannel('com.gardenbo.app/android_widget');
  static const _androidNotifId = 888;
  static const _androidChannelId = 'garden_service_active';

  // iOS activity ID returned by native side
  String? _activityId;

  // Android
  final _notifications = FlutterLocalNotificationsPlugin();
  bool _androidReady = false;

  // Cache — reenviado completo en cada heartbeat porque, a diferencia de
  // ActivityKit en iOS, el widget de Android (Glance) no tiene un cronómetro
  // que corra solo: cada refresco recalcula "tiempo transcurrido" desde
  // startedAtMs en el momento en que Android vuelve a dibujar el widget, así
  // que necesita los mismos datos de arranque en cada llamada, no solo un
  // heartbeat vacío.
  String _petName = '';
  String _subtitle = '';
  String _serviceType = 'PASEO';
  String _role = 'CLIENT';
  String _bookingId = '';
  int _serviceStartMs = 0;
  int _totalPaidSeconds = 3600;

  // ── iOS ────────────────────────────────────────────────────────────────────

  /// [totalPaidDurationMinutes] is the "goal" the lock-screen/Dynamic-Island
  /// progress bar walks towards: the original booked duration + any
  /// already-approved & paid extension, in minutes (PASEO/GUARDERIA: minutes
  /// booked; HOSPEDAJE: nights × 24h). Recompute and re-send it (via
  /// [updateTotalPaidDuration]) every time an extension is confirmed so the
  /// widget's goal updates immediately.
  Future<void> startActivity({
    required String petName,
    required String caregiverName,
    required String ownerName,
    required String serviceType,
    required String role,
    required String bookingId,
    required DateTime startTime,
    required int totalPaidDurationMinutes,
  }) async {
    if (kIsWeb) return;

    final emoji = serviceType == 'PASEO'
        ? '🐾'
        : serviceType == 'GUARDERIA'
            ? '🏡'
            : '🏠';
    final serviceLabel = serviceType == 'PASEO'
        ? 'paseo'
        : serviceType == 'GUARDERIA'
            ? 'guardería'
            : 'hospedaje';

    if (Platform.isIOS) {
      try {
        _activityId = await _iosChannel.invokeMethod<String>('startActivity', {
          'petName': petName,
          'caregiverName': caregiverName,
          'ownerName': ownerName,
          'serviceType': serviceType,
          'role': role,
          'bookingId': bookingId,
          'startTimeMs': startTime.millisecondsSinceEpoch,
          'totalPaidSeconds': totalPaidDurationMinutes * 60,
        });
        debugPrint('[LiveActivity] Started: $_activityId');
      } catch (e) {
        // ActivityKit not available on this device (iOS < 16.2 or simulator)
        debugPrint('[LiveActivity] start error: $e');
      }
      return;
    }

    if (Platform.isAndroid) {
      _petName = petName;
      _serviceType = serviceType;
      _role = role;
      _bookingId = bookingId;
      _serviceStartMs = startTime.millisecondsSinceEpoch;
      _totalPaidSeconds = totalPaidDurationMinutes * 60;
      _subtitle = role == 'CLIENT' ? 'Con $caregiverName' : 'Dueño: $ownerName';
      _lastTitle = role == 'CLIENT'
          ? '$emoji $petName está de $serviceLabel'
          : '$emoji Paseando a $petName';
      _lastBody = '$_subtitle · Garden';
      await _initAndroid();
      await _showAndroidNotification();
      await _updateAndroidWidget(status: 'IN_PROGRESS');
    }
  }

  // Cache for Android notification refresh
  String _lastTitle = '';
  String _lastBody = '';

  /// Call every N seconds from the service timer (suggested: every 10s for iOS,
  /// every 10s for Android too — el widget de Android no tiene reloj propio,
  /// necesita este heartbeat para que el "tiempo transcurrido" se vea al día).
  Future<void> updateTimer(Duration elapsed) async {
    if (kIsWeb) return;

    if (Platform.isIOS && _activityId != null) {
      try {
        await _iosChannel.invokeMethod('updateActivity', {
          'id': _activityId!,
          'status': 'IN_PROGRESS',
        });
      } catch (e) {
        debugPrint('[LiveActivity] update error: $e');
      }
      return;
    }

    if (Platform.isAndroid) {
      await _updateAndroidWidget(status: 'IN_PROGRESS');
    }
  }

  /// Call whenever a paid time/night extension is confirmed, with the new
  /// total (original + all approved extensions so far) in minutes. Moves the
  /// Live Activity's / Android widget's progress-bar goal immediately.
  Future<void> updateTotalPaidDuration(int totalPaidDurationMinutes) async {
    if (kIsWeb) return;
    if (Platform.isIOS && _activityId != null) {
      try {
        await _iosChannel.invokeMethod('updateTotalPaidSeconds', {
          'id': _activityId!,
          'totalPaidSeconds': totalPaidDurationMinutes * 60,
        });
        debugPrint('[LiveActivity] Updated goal: ${totalPaidDurationMinutes}min');
      } catch (e) {
        debugPrint('[LiveActivity] updateTotalPaidDuration error: $e');
      }
      return;
    }

    if (Platform.isAndroid) {
      _totalPaidSeconds = totalPaidDurationMinutes * 60;
      await _updateAndroidWidget(status: 'IN_PROGRESS');
    }
  }

  /// Empuja un snapshot de mapa (PNG, ya bajado por el caller — ver
  /// service_execution_screen.dart._updateMapSnapshot) al widget nativo.
  /// Solo tiene sentido durante un PASEO — el caller ya filtra por tipo de
  /// servicio antes de llamar acá. Se manda en base64 dentro del payload del
  /// MethodChannel (no hay forma de pasar bytes binarios crudos de forma
  /// nativa en un Map de argumentos estándar de Flutter).
  Future<void> updateMapSnapshot(Uint8List pngBytes) async {
    if (kIsWeb) return;
    final b64 = base64Encode(pngBytes);

    if (Platform.isIOS) {
      if (_activityId == null) return;
      try {
        await _iosChannel.invokeMethod('updateMapSnapshot', {
          'id': _activityId!,
          'mapSnapshotBase64': b64,
        });
      } catch (e) {
        debugPrint('[LiveActivity] updateMapSnapshot iOS error: $e');
      }
      return;
    }

    if (Platform.isAndroid) {
      if (_bookingId.isEmpty) return;
      try {
        await _androidWidgetChannel.invokeMethod('updateMapSnapshot', {
          'mapSnapshotBase64': b64,
        });
      } catch (e) {
        debugPrint('[LiveActivity] updateMapSnapshot Android error: $e');
      }
    }
  }

  Future<void> endActivity() async {
    if (kIsWeb) return;

    if (Platform.isIOS) {
      if (_activityId != null) {
        try {
          await _iosChannel.invokeMethod('endActivity', {'id': _activityId!});
          debugPrint('[LiveActivity] Ended: $_activityId');
        } catch (e) {
          debugPrint('[LiveActivity] end error: $e');
        }
        _activityId = null;
      }
      return;
    }

    if (Platform.isAndroid) {
      await _notifications.cancel(_androidNotifId);
      try {
        await _androidWidgetChannel.invokeMethod('endActiveService');
      } catch (e) {
        debugPrint('[LiveActivity] Android endActiveService error: $e');
      }
    }
  }

  // ── Android ────────────────────────────────────────────────────────────────

  Future<void> _updateAndroidWidget({required String status}) async {
    if (_bookingId.isEmpty) return; // no hay servicio arrancado todavía
    try {
      await _androidWidgetChannel.invokeMethod('updateActiveService', {
        'petName': _petName,
        'subtitle': _subtitle,
        'serviceType': _serviceType,
        'status': status,
        'startedAtMs': _serviceStartMs,
        'totalPaidSeconds': _totalPaidSeconds,
        'bookingId': _bookingId,
        'role': _role,
      });
    } catch (e) {
      debugPrint('[LiveActivity] Android widget update error: $e');
    }
  }

  Future<void> _initAndroid() async {
    if (_androidReady) return;
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(init);
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _androidChannelId,
            'Servicio Activo',
            description: 'Se muestra mientras hay un servicio en curso',
            importance: Importance.low,
            enableVibration: false,
            playSound: false,
          ),
        );
    _androidReady = true;
  }

  Future<void> _showAndroidNotification() async {
    final details = AndroidNotificationDetails(
      _androidChannelId,
      'Servicio Activo',
      channelDescription: 'Se muestra mientras hay un servicio en curso',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: _serviceStartMs > 0,
      when: _serviceStartMs > 0 ? _serviceStartMs : null,
      usesChronometer: _serviceStartMs > 0,
      chronometerCountDown: false,
      color: const Color(0xFF778C43),
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );
    await _notifications.show(
      _androidNotifId,
      _lastTitle,
      _lastBody,
      NotificationDetails(android: details),
    );
  }
}

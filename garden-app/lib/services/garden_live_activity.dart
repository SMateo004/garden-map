import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Manages Live Activities (iOS 16.2+) and persistent foreground notifications
/// (Android) during an active pet service (PASEO / HOSPEDAJE).
class GardenLiveActivity {
  GardenLiveActivity._();
  static final GardenLiveActivity instance = GardenLiveActivity._();

  static const _iosChannel = MethodChannel('com.gardenbo.app/live_activity');
  static const _androidNotifId = 888;
  static const _androidChannelId = 'garden_service_active';

  // iOS activity ID returned by native side
  String? _activityId;

  // Android
  final _notifications = FlutterLocalNotificationsPlugin();
  bool _androidReady = false;

  // Cache for Android notification refresh
  String _lastTitle = '';
  String _lastBody = '';
  int _serviceStartMs = 0;

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
      _serviceStartMs = startTime.millisecondsSinceEpoch;
      _lastTitle = role == 'CLIENT'
          ? '$emoji $petName está de $serviceLabel'
          : '$emoji Paseando a $petName';
      _lastBody = role == 'CLIENT'
          ? 'Con $caregiverName · Garden'
          : 'Dueño: $ownerName · Garden';
      await _initAndroid();
      await _showAndroidNotification();
    }
  }

  /// Call every N seconds from the service timer (suggested: every 10s for iOS,
  /// every 30s for Android to stay within OS rate limits). The elapsed-time
  /// digits and the progress-bar animation are computed on-device by the
  /// widget itself (from the `startedAt`/`totalPaidSeconds` it already has),
  /// so this is just a lightweight status heartbeat — it does not need to
  /// carry a formatted timer string.
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
    }
    // Android: chronometer counts from startTime automatically — no update needed
  }

  /// Call whenever a paid time/night extension is confirmed, with the new
  /// total (original + all approved extensions so far) in minutes. Moves the
  /// Live Activity's progress-bar goal immediately — this is a real native
  /// push, but it only happens on the rare extension-confirmation event, so
  /// it stays well within ActivityKit's update budget.
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
    }
    // Android notification doesn't show a paid-duration goal today — no-op.
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
    }
  }

  // ── Android ────────────────────────────────────────────────────────────────

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

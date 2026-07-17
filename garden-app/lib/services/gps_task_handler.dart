import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Entry point del isolate del foreground service Android — SIEMPRE debe ser
/// una función top-level (no un método de clase), lo exige el plugin.
@pragma('vm:entry-point')
void gpsForegroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(GpsTaskHandler());
}

/// `TaskHandler` que corre en el isolate del foreground service de Android —
/// SOBREVIVE a que el cuidador minimice la app, bloquee la pantalla o navegue
/// a otra app, mientras un paseo (PASEO) esté activo. Es el equivalente al
/// "modo conductor" de apps como Uber: notificación persistente + servicio en
/// primer plano que Android no mata mientras esté visible.
///
/// SOLO se usa en Android. En iOS la continuidad en background se logra de
/// forma nativa con `Geolocator` + `AppleSettings(allowBackgroundLocationUpdates: true)`
/// + `UIBackgroundModes: location` en Info.plist — no hace falta este handler
/// ahí (ver `GpsTrackingSession`).
///
/// Recibe `bookingId`/`token` vía `FlutterForegroundTask.sendDataToTask(...)`
/// justo después de `startService(...)` (ver `GpsTrackingSession.start`).
/// Cada 5s (cadencia fijada por `ForegroundTaskEventAction.repeat(5000)` en
/// `GpsTrackingSession._initForegroundTaskAndroid`) toma una posición fresca y
/// la manda al backend, y también se la reenvía al isolate principal
/// (`FlutterForegroundTask.sendDataToMain`) para que la UI (mapa) se actualice
/// si la app está en foreground en ese momento.
class GpsTaskHandler extends TaskHandler {
  String? _bookingId;
  String? _token;

  String get _baseUrl =>
      const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('GpsTaskHandler: iniciado (starter: ${starter.name})');
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      final bookingId = data['bookingId'];
      final token = data['token'];
      if (bookingId is String) _bookingId = bookingId;
      if (token is String) _token = token;
      debugPrint('GpsTaskHandler: datos recibidos, bookingId=$_bookingId');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // No usamos `timestamp` para el envío — pedimos una posición fresca en
    // cada tick en vez de mantener un stream vivo dentro del isolate del
    // servicio (más simple y robusto para un TaskHandler de background).
    _captureAndSend();
  }

  Future<void> _captureAndSend() async {
    final bookingId = _bookingId;
    final token = _token;
    if (bookingId == null || token == null) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (pos.accuracy > 50) return; // precisión baja, descartar el punto

      await http.post(
        Uri.parse('$_baseUrl/bookings/$bookingId/track'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'lat': pos.latitude, 'lng': pos.longitude, 'accuracy': pos.accuracy}),
      );

      FlutterForegroundTask.sendDataToMain({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
      });
    } catch (e) {
      debugPrint('GpsTaskHandler: error capturando/enviando posición: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('GpsTaskHandler: destruido (timeout: $isTimeout)');
  }
}

import 'dart:async';
import 'dart:html' as html;

Stream<Map<String, double>> watchGpsPosition() {
  final ctrl = StreamController<Map<String, double>>.broadcast();
  html.window.navigator.geolocation
      .watchPosition(enableHighAccuracy: true, maximumAge: const Duration(seconds: 5))
      .listen(
        (pos) => ctrl.add({
          'lat': pos.coords!.latitude!.toDouble(),
          'lng': pos.coords!.longitude!.toDouble(),
          'accuracy': pos.coords!.accuracy?.toDouble() ?? 0,
        }),
        onError: (e) => ctrl.addError(e),
      );
  return ctrl.stream;
}

Future<Map<String, double>?> getCurrentGpsPosition() async {
  try {
    final pos = await html.window.navigator.geolocation.getCurrentPosition(enableHighAccuracy: true);
    return {
      'lat': pos.coords!.latitude!.toDouble(),
      'lng': pos.coords!.longitude!.toDouble(),
      'accuracy': pos.coords!.accuracy?.toDouble() ?? 0,
    };
  } catch (_) {
    return null;
  }
}
